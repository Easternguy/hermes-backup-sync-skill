---
name: hermes-backup-sync
version: 1.1.0
description: Daily backup of Hermes config, skills, memory, and settings to a private GitHub repo. Pure shell script, no LLM overhead. Includes cache/strip logic for minimal repo size, secret templating, and a public-repo safety check.
tags: [backup, github, cron, devops, hermes, sync]
---

# Hermes Backup Sync

Backup your Hermes Agent config, skills, memory, and settings to a private GitHub repository. Uses a pure bash script (`no_agent: true`) — no LLM tokens burned on backups.

## How It Works

A daily cron job runs a bash script that:

1. Clones (or pulls) the backup repo
2. Copies top-level config files (`config.yaml`, `SOUL.md`, etc.)
3. Creates **stripped templates** of `.env` and `auth.json` (secrets removed)
4. Syncs Hermes directories via `tar` with exclusions for runtime caches
5. Cleans up lock files, pycache, and other artifacts
6. Commits and pushes

**Runtime:** ~5–30 seconds unless your Hermes data directory is exceptionally large.

## Files

- **`sync-hermes-backup.sh`** — the backup script (standalone, all config via env vars)
- **`SKILL.md`** — this documentation

## Setup

### 1. Prerequisites
- A GitHub account with a [Personal Access Token (classic)](https://github.com/settings/tokens) with `repo` scope
- A **private** GitHub repo to push backups to (e.g., `hermes-backup`)
- Your Hermes data directory (typically `$HOME` or wherever your Hermes session runs)

### 2. Set environment variables
Add to your Hermes `.env` file or export before running:

```bash
GITHUB_TOKEN=ghp_your_token_here
GITHUB_USER=your-github-username
HERMES_DATA=/path/to/hermes/data
BACKUP_REPO=https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/hermes-backup.git
```

### 3. Configure the script
The script has sensible defaults but you should review two sections:

**`home/` selective copy** — edit the `for sub in ...` list to match the dotfiles your Hermes instance uses:
```bash
for sub in .hermes .profile; do
```
⚠️ **Never add `.ssh` or other private-key material to this list.** Private keys must not be pushed to ANY remote — even a private repo. If you need key backups, encrypt them first (`age`, `git-crypt`) and back up the encrypted file. Also review what's inside each dotfile you add — config files sometimes embed tokens.

**Excludes array** — add/remove runtime directories that don't need backing up:
```bash
EXCLUDES=(--exclude=.cache --exclude=.npm ...)
```

### 4. Create the cron job in Hermes
```bash
# Copy script to cron's lookup path (adjust to wherever your Hermes
# instance looks up cron scripts, e.g. $HERMES_DATA/cron/scripts/)
cp sync-hermes-backup.sh "$HERMES_DATA/cron/scripts/"

# Create the cron entry
cronjob action=create \
  name=hermes-backup-sync \
  schedule="0 16 * * *" \
  script="sync-hermes-backup.sh" \
  no_agent=true \
  deliver=local
```

## Running Manually

```bash
export HERMES_DATA=/path/to/hermes/data
bash sync-hermes-backup.sh
```

## Customization

- **Add directories** — edit the `for dir in ...` loop
- **Exclude more files** — add patterns to the `EXCLUDES` array
- **Change repo** — set `BACKUP_REPO` env var or default in the script
- **Change git identity** — set `GIT_EMAIL` and `GIT_USERNAME` env vars
- **Change destination** — set `BACKUP_DIR` env var (default: `/tmp/hermes-backup-sync`)

## Troubleshooting

### Script times out
- Check for large new runtime caches in your Hermes data directory
- Add them to the `EXCLUDES` array or the `home/` selective list
- GitHub has a 100MB file size limit — check for oversized files:
  ```bash
  find /tmp/hermes-backup-sync -size +90M -exec ls -lh {} \;
  ```

### Push fails
- Verify `GITHUB_TOKEN` is still valid and has `repo` scope
- Check for any files exceeding 100MB
- Ensure the remote repo exists and is accessible

### Clone state is dirty
- Manually reset: `rm -rf /tmp/hermes-backup-sync` then re-run

## Security Notes

- **The script refuses to push to a public repo.** It checks the target repo's visibility via the GitHub API before every sync and aborts if the repo is public. Keep the backup repo private, always.
- **No private keys, ever.** The default dotfile list deliberately excludes `.ssh`. Encrypt first if you must back up key material.
- **Session history is off by default.** `.hermes_history` can contain sensitive commands and prompts; its copy line ships commented out — enable it only if you accept that.
- **The token lands in the clone's `.git/config`** (it's part of the remote URL). The script `chmod 700`s the backup working directory to keep other local users out. On shared machines, set `BACKUP_DIR` somewhere under your home instead of `/tmp`.
- **Use a fine-grained PAT if you can** — scoped to just the backup repo with Contents read/write, instead of a classic `repo`-scope token.
- **Secrets are templated, not copied.** `.env.template` and `auth.json.template` preserve structure with values stripped — verify this on your first push by reading both files in the repo.

## Restoring From a Backup

1. Clone the backup repo onto the new machine.
2. Copy the directories (`skills/`, `memories/`, `cron/`, …) and top-level config files into your new Hermes data directory.
3. Recreate `.env` from `.env.template` — fill in each value from your password manager.
4. Recreate `auth.json` from `auth.json.template` the same way (every string was redacted).
5. Restore dotfiles from `home/` into the Hermes home directory.
6. Start Hermes and verify: skills load, cron jobs listed, memory queries return results.

## Design Decisions

- **`no_agent: true`** — backups don't need an LLM. Saves tokens and avoids failure modes from agent loops.
- **Exclude at copy time** — never copy 12GB of caches just to delete them. Use `tar --exclude` to skip large cruft during the archive phase.
- **Selective `home/` copy** — the home directory is often the largest. Only sync known-useful dotfiles rather than trying to exclude everything.
- **Template files for secrets** — `.env.template` and `auth.json.template` commit the *structure* of your config without exposing values, so a restore knows what files to create.