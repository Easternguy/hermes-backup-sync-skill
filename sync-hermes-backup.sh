#!/bin/bash
# Auto-sync Hermes config to a PRIVATE GitHub backup repo
# Configure via env vars: HERMES_DATA, GITHUB_TOKEN (or in $HERMES_DATA/.env),
#                         GITHUB_USER, BACKUP_REPO, GIT_EMAIL, GIT_USERNAME
#
# Usage:
#   export HERMES_DATA="/path/to/hermes/data"
#   export GITHUB_USER="your-username"
#   bash sync-hermes-backup.sh

set -euo pipefail

# --- Configuration (override via env vars) ---
SRC="${HERMES_DATA:-/opt/data}"
DST="${BACKUP_DIR:-/tmp/hermes-backup-sync}"

# Token: prefer the environment, fall back to $SRC/.env
TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "$SRC/.env" ]; then
    TOKEN=$(grep "^GITHUB_TOKEN=" "$SRC/.env" | head -1 | cut -d= -f2- | tr -d '\n\r' || true)
fi
if [ -z "$TOKEN" ]; then
    echo "ERROR: GITHUB_TOKEN not set (export it or put it in $SRC/.env)" >&2
    exit 1
fi
GITHUB_USER="${GITHUB_USER:-your-username}"
BACKUP_REPO="${BACKUP_REPO:-https://${TOKEN}@github.com/${GITHUB_USER}/hermes-backup.git}"

# --- Safety: refuse to push a backup to a PUBLIC repo ---
REPO_PATH=$(echo "$BACKUP_REPO" | sed -E 's#.*github\.com/##; s#\.git$##')
VISIBILITY=$(curl -s -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/$REPO_PATH" | grep -o '"private": *\(true\|false\)' | head -1 || true)
if echo "$VISIBILITY" | grep -q "false"; then
    echo "ERROR: $REPO_PATH is PUBLIC. Backups contain your configuration — refusing to push." >&2
    echo "Make the repo private, or point BACKUP_REPO at a private repo." >&2
    exit 1
fi

# --- Clone or pull ---
if [ -d "$DST/.git" ]; then
    cd "$DST"
    git fetch origin main 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || true
else
    rm -rf "$DST" 2>/dev/null || true
    git clone "$BACKUP_REPO" "$DST"
    cd "$DST"
fi
# The clone's .git/config contains the token — keep the directory private
chmod 700 "$DST"
# Works for fresh/empty repos too (first-ever backup run)
git checkout -B main 2>/dev/null || git symbolic-ref HEAD refs/heads/main

# --- Copy config and settings (tolerant: skip files your instance doesn't have) ---
for f in config.yaml SOUL.md channel_directory.json; do
    if [ -f "$SRC/$f" ]; then cp "$SRC/$f" .; fi
done

# Session history often contains sensitive commands and prompts.
# Uncomment ONLY if you accept that risk:
# if [ -f "$SRC/.hermes_history" ]; then cp "$SRC/.hermes_history" .; fi

# --- Create templates (structure only, no secret values) ---
if [ -f "$SRC/.env" ]; then
    grep -E "^[A-Za-z_][A-Za-z0-9_]*=" "$SRC/.env" | sed 's/=.*$/=/' > .env.template || true
fi
if [ -f "$SRC/auth.json" ]; then
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
fi

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
            # home/ is typically the largest — select only useful dotfiles.
            # Customize this list for your instance.
            #
            # SECURITY: never add .ssh or any private-key material here.
            # Private keys must not be pushed to ANY remote, even a private
            # repo. If you need key backups, encrypt them first (age,
            # git-crypt) and back up the encrypted file instead.
            rm -rf "home" 2>/dev/null || true
            mkdir -p "home"
            for sub in .hermes .profile; do
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
