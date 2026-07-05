#!/bin/bash
# Auto-sync Hermes config to GitHub backup repo
# Configure: HERMES_DATA, GITHUB_TOKEN in .env, GITHUB_USER, BACKUP_REPO
#
# Usage:
#   export HERMES_DATA="/path/to/hermes/data"
#   export GITHUB_USER="your-username"
#   export BACKUP_REPO="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/hermes-backup.git"
#   bash sync-hermes-backup.sh

set -euo pipefail

# --- Configuration (override via env vars) ---
SRC="${HERMES_DATA:-/opt/data}"
DST="${BACKUP_DIR:-/tmp/hermes-backup-sync}"
TOKEN_FILE="${SRC}/.env"
TOKEN=$(grep "^GITHUB_TOKEN=" "$TOKEN_FILE" | head -1 | cut -d= -f2 | tr -d '\n\r')
GITHUB_USER="${GITHUB_USER:-your-username}"
BACKUP_REPO="${BACKUP_REPO:-https://${TOKEN}@github.com/${GITHUB_USER}/hermes-backup.git}"

# --- Clone or pull ---
if [ -d "$DST/.git" ]; then
    cd "$DST"
    git fetch origin main
    git reset --hard origin/main
else
    rm -rf "$DST" 2>/dev/null || true
    git clone "$BACKUP_REPO" "$DST"
    cd "$DST"
fi

# --- Copy config and settings ---
cp "$SRC/config.yaml" .
cp "$SRC/SOUL.md" .
cp "$SRC/channel_directory.json" .
cp "$SRC/.hermes_history" .

# --- Create templates (no secrets) ---
grep -E "^[A-Z_]+=" "$SRC/.env" | sed 's/=.*$/=/' > .env.template
python3 -c "
import json
with open('$SRC/auth.json') as f:
    data = json.load(f)

def strip_values(obj):
    if isinstance(obj, dict):
        return {k: strip_values(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [strip_values(i) for i in obj]
    elif isinstance(obj, str):
        return '***REDACTED***'
    else:
        return obj

with open('auth.json.template', 'w') as f:
    json.dump(strip_values(data), f, indent=2)
" 2>/dev/null || true

# --- Exclude patterns: large runtime caches and binaries ---
EXCLUDES=(
    --exclude=.cache
    --exclude=.npm
    --exclude=.pki
    --exclude=node_modules
    --exclude=.local/bin
    --exclude=.local/lib
    --exclude=.local/include
    --exclude=.agent-browser
    --exclude=.config/google-chrome-for-testing
    --exclude=.config/browseruse
    --exclude=.bun
)

# --- Sync directories ---
for dir in skills memories cron platforms plans skins hooks home; do
    if [ -d "$SRC/$dir" ]; then
        if [ "$dir" = "home" ]; then
            # home/ is typically the largest — select only useful dotfiles
            # Customize this list for your instance
            rm -rf "home" 2>/dev/null || true
            mkdir -p "home"
            for sub in .hermes .ssh .profile; do
                if [ -e "$SRC/home/$sub" ]; then
                    cp -a "$SRC/home/$sub" "home/$sub" 2>/dev/null || true
                fi
            done
        else
            rm -rf "$dir" 2>/dev/null || true
            tar -cf - -C "$SRC" "$dir" --dereference --ignore-failed-read \
                "${EXCLUDES[@]}" 2>/dev/null | tar -xf - 2>/dev/null || true
        fi

        # Clean up unnecessary artifacts
        find "$dir" -name "*.lock" -delete 2>/dev/null || true
        find "$dir" -name ".tick.lock" -delete 2>/dev/null || true
        find "$dir" -name ".usage.json" -delete 2>/dev/null || true
        find "$dir" -name ".usage.json.lock" -delete 2>/dev/null || true
        find "$dir" -name ".curator_state" -delete 2>/dev/null || true
        find "$dir" -name "request_dump_*" -delete 2>/dev/null || true
        find "$dir" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
        find "$dir" -name "*.pyc" -delete 2>/dev/null || true
    fi
done

# --- Commit and push ---
git config user.email "${GIT_EMAIL:-user@example.com}"
git config user.name "${GIT_USERNAME:-GitHub User}"
git add -A

if git diff --cached --quiet; then
    echo "No changes to sync."
    exit 0
fi

git commit -m "Auto-sync: $(date -u '+%Y-%m-%d %H:%M UTC')"
git push origin main
echo "Synced at $(date -u '+%Y-%m-%d %H:%M UTC')"