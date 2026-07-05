# hermes-backup-sync

**A [Hermes agent](https://github.com/NousResearch/hermes-agent) skill that backs up your agent's brain (skills, memories, cron jobs, and config) to a private GitHub repo, every day, with zero LLM cost.**

Your Hermes instance accumulates real value over time: custom skills, memory files, cron schedules, tuned config. One disk failure and it's gone. This skill gives you a daily, versioned, off-machine backup using a pure bash script (`no_agent: true`, no tokens burned on backups) that you can restore from in minutes.

## What it does

Every day, a cron job:

1. Clones (or pulls) your private backup repo
2. Copies top-level config (`config.yaml`, `SOUL.md`, …)
3. Writes **secret-free templates** of `.env` and `auth.json` (structure preserved, every value stripped) so a restore knows what to recreate without your secrets ever leaving the machine
4. Syncs `skills/`, `memories/`, `cron/`, `platforms/`, `plans/`, `skins/`, `hooks/`, and a hand-picked set of dotfiles, with runtime caches, lockfiles, and `__pycache__` excluded at copy time
5. Commits and pushes (skips the push when nothing changed)

**Runtime:** ~5–30 seconds. **Safety built in:** the script checks the target repo's visibility via the GitHub API and **refuses to push if the repo is public**.

## Requirements

| Dependency | Notes |
|---|---|
| [Hermes agent](https://github.com/NousResearch/hermes-agent) | with its cron system |
| A **private** GitHub repo | e.g. `hermes-backup`: create it empty; first run populates it |
| GitHub token | fine-grained PAT scoped to the backup repo (Contents: read/write) recommended; classic `repo`-scope PAT also works |
| `git`, `curl`, `python3`, `tar` | present on any normal Linux box |

## Setup

```bash
# 1. Set environment (in your Hermes .env or exported)
GITHUB_TOKEN=ghp_your_token_here
GITHUB_USER=your-github-username
HERMES_DATA=/path/to/hermes/data

# 2. Review the script's two customization points:
#    - the dotfile list (for sub in .hermes .profile; ...)
#    - the EXCLUDES array
# See SKILL.md for details.

# 3. Install the cron job (see SKILL.md "Setup" for the cronjob command)
```

Manual run any time:

```bash
export HERMES_DATA=/path/to/hermes/data
bash sync-hermes-backup.sh
```

## Restoring

Clone the backup repo on the new machine, copy the directories back into your Hermes data directory, recreate `.env` and `auth.json` from their `.template` files (fill values from your password manager), and start Hermes. Full steps in [SKILL.md](SKILL.md#restoring-from-a-backup).

## Security model: read this before first run

- **Backups go to a private repo only**: the script enforces it and aborts on a public target.
- **Secrets never leave the machine.** `.env` and `auth.json` are templated (values stripped). Verify both `.template` files after your first push.
- **Private SSH keys are deliberately NOT backed up.** Don't add `.ssh` to the dotfile list. If you need key backups, push encrypted archives (`age`, `git-crypt`) instead.
- **Session history is off by default** (it can contain sensitive prompts/commands). Enable its commented line only if you accept that.
- The backup working directory is `chmod 700` because the git remote URL embeds your token; on shared machines set `BACKUP_DIR` under your home.

Full details: [SKILL.md → Security Notes](SKILL.md#security-notes).

## Support

If this skill saved your Hermes setup (or just your peace of mind), you can [buy me a coffee](https://buymeacoffee.com/Hessamsh) ☕

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?logo=buymeacoffee)](https://buymeacoffee.com/Hessamsh)

## License

[MIT](LICENSE)

---

## 🇮🇷 راهنمای فارسی

<div dir="rtl">

### این ابزار چیست؟

یک اسکیل برای ایجنت «هرمس» (Hermes) که هر روز به‌صورت خودکار از مغز ایجنت شما (اسکیل‌ها، حافظه‌ها، زمان‌بندی‌های کرون و فایل‌های تنظیمات) در یک مخزن **خصوصی** گیت‌هاب نسخهٔ پشتیبان می‌گیرد. اسکریپت کاملاً bash است و هیچ توکن LLM مصرف نمی‌کند. اگر دیسک شما بسوزد یا سرور از دست برود، کل تنظیمات هرمس در چند دقیقه قابل بازیابی است.

### پیش‌نیازها

- ایجنت هرمس همراه با سیستم کرون آن
- یک مخزن خصوصی در گیت‌هاب (مثلاً `hermes-backup`)؛ خالی بسازید، اجرای اول پرش می‌کند
- توکن گیت‌هاب (ترجیحاً Fine-grained و محدود به همان مخزن)
- ابزارهای معمول لینوکس: `git`، `curl`، `python3`، `tar`

### نصب و راه‌اندازی

۱. متغیرهای محیطی را در فایل `env.` هرمس یا محیط شل تنظیم کنید: `GITHUB_TOKEN`، `GITHUB_USER` و `HERMES_DATA`.

۲. دو بخش قابل شخصی‌سازی اسکریپت را بازبینی کنید: فهرست دات‌فایل‌ها و آرایهٔ `EXCLUDES` (جزئیات در فایل SKILL.md).

۳. کرون‌جاب روزانه را طبق بخش Setup در فایل SKILL.md بسازید.

اجرای دستی برای آزمایش:

</div>

```bash
export HERMES_DATA=/path/to/hermes/data
bash sync-hermes-backup.sh
```

<div dir="rtl">

### بازیابی

مخزن پشتیبان را روی ماشین جدید کلون کنید، پوشه‌ها را به مسیر دادهٔ هرمس برگردانید، فایل‌های `env.` و `auth.json` را از روی نسخه‌های `template.` بازسازی کنید (مقادیر را از مدیر رمز عبور خود وارد کنید) و هرمس را اجرا کنید.

### نکات امنیتی مهم

- پشتیبان فقط باید به مخزن **خصوصی** برود: اسکریپت خودش این را بررسی می‌کند و اگر مخزن عمومی باشد، اجرا را متوقف می‌کند.
- مقادیر محرمانه (توکن‌ها و کلیدهای API) هرگز آپلود نمی‌شوند؛ فقط ساختار فایل‌ها به‌صورت template ذخیره می‌شود. بعد از اولین اجرا، هر دو فایل template را بررسی کنید.
- کلید خصوصی SSH را **هرگز** به فهرست پشتیبان اضافه نکنید، حتی در مخزن خصوصی. اگر لازم دارید، اول با ابزاری مثل `age` رمزنگاری کنید.
- تاریخچهٔ جلسات به‌صورت پیش‌فرض غیرفعال است، چون ممکن است حاوی دستورات حساس باشد.

### حمایت

اگر این ابزار به کارتان آمد، می‌توانید <a href="https://buymeacoffee.com/Hessamsh">یک قهوه مهمانم کنید</a> ☕

</div>
