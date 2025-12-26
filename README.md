# ILoF IaC — Provisioning Scripts 🚀

**Short description:** A small collection of shell scripts to provision a Linux host with a user, basic security hardening, an Nginx Docker site (optionally HTTPS), and a memory-logging cron job. The scripts are designed to be run on Debian/Ubuntu-like systems and can be executed individually or orchestrated with `ilof_run_all.sh`.

---

## Table of Contents

- **Prerequisites** ✅
- **Quick start** ⚡️
- **Scripts overview** 🔧
- **Examples & Flags** 🧭
- **Logs & Artifacts** 📁
- **Security & Safety notes** ⚠️
- **Troubleshooting** 🔍
- **Project layout** 📂
- **Contributing / License** ✍️

---

## Prerequisites ✅

- A Debian/Ubuntu based system (or compatible) with `apt` and `systemd` available.
- Root privileges (scripts require `sudo` or running as `root`) except when using `--dry-run`.
- Internet access (to install packages and Docker if missing).
- Recommended to test inside a VM/container before running on production.

> Note: These scripts are POSIX/bash shell scripts intended for Linux hosts — they will not run on Windows without a Linux environment (WSL, VM, etc.).

---

## Quick start ⚡️

1. Preview what would run (safe):

```bash
sudo ./ilof_run_all.sh --dry-run
```

2. Run the full provisioning (all scripts in default order):

```bash
sudo ./ilof_run_all.sh
```

3. Run a single script (example: create user):

```bash
sudo ./ilof_createuser.sh -u deploy_admin --dry-run
sudo ./ilof_createuser.sh -u deploy_admin
```

---

## Scripts overview 🔧

- `ilof_run_all.sh` — Orchestrates the other scripts sequentially and prints a summary table. Options:
  - `--dry-run` — show what would run without making changes
  - `--stop-on-failure` — stop when a step fails
  - `--scripts <csv>` — run only the named scripts (relative or absolute paths)

- `ilof_createuser.sh` — Updates packages, creates a user and configures a passwordless sudoers file for that user.
  - `-u <username>` — set username (default `deploy_admin`)
  - `--dry-run`
  - Validates `visudo -cf` after writing the sudoers file

- `ilof_security_hardening.sh` — Installs/ensures OpenSSH, adjusts `sshd_config` (port, disables root login), creates a backup (`sshd_config.bak`), and configures UFW firewall rules.
  - `--ssh-port <port>` — change SSH listen port (default in script: 22 or value passed)
  - `--sshd-config <path>` — alternate sshd config location
  - `--dry-run`

- `ilof_nginx_docker.sh` — Installs Docker if missing, prepares `./srv/ilof_nginx_html/` and runs an `nginx` container named `ilof_nginx`. If `--https` is passed it will create a self-signed cert and an HTTPS-enabled nginx config.
  - `--https` — enable HTTPS and mount certs and config
  - `--dry-run`

- `ilof_memory_cron.sh` — Ensures `cron` is installed, creates `/usr/local/bin/ilof_log_memory.sh` (helper script to log memory usage to `var/log/memory_usage.log`) and installs a root cron job.
  - `--interval <minutes>` — cron frequency (default 10)
  - `--dry-run`

---

## Examples & Flags 🧭

- Dry-run full flow:
  - `sudo ./ilof_run_all.sh --dry-run`

- Run only specific scripts (from repo directory):
  - `sudo ./ilof_run_all.sh --scripts ilof_createuser.sh,ilof_security_hardening.sh`

- Run Nginx with HTTPS (generates a self-signed cert in `srv/ilof_nginx_html/certs`):
  - `sudo ./ilof_nginx_docker.sh --https`

- Install memory cron to run every 5 minutes (dry-run first):
  - `sudo ./ilof_memory_cron.sh --interval 5 --dry-run`

---

## Logs & Artifacts 📁

- Orchestration logs: `var/log/ilof_run/*.log` (one per script when run by `ilof_run_all.sh`).
- Memory log: `var/log/memory_usage.log` (written by `/usr/local/bin/ilof_log_memory.sh`).
- Nginx web root: `srv/ilof_nginx_html/` (contains `index.html`, `default.conf`, and `certs/` when HTTPS used).

---

## Security & Safety notes ⚠️

> - **Caution:** Changing SSH port or firewall rules may lock you out. Test in a safe environment and ensure you have console/other access.
> - Running these scripts will modify system packages and services as `root`; **do not** run on systems you cannot afford to change without testing.
> - `--dry-run` exists on all scripts to preview actions safely.

---

## Troubleshooting 🔍

- If a step fails when run via `ilof_run_all.sh`, check the corresponding log in `var/log/ilof_run/`.
- For `nginx`/Docker issues: run `docker logs ilof_nginx` and `docker ps -a`.
- For SSH issues: inspect `/etc/ssh/sshd_config` and the backup file (`.bak`). Use `sshd -t` to validate config.

---

## Project layout 📂

```
./
├─ ilof_run_all.sh
├─ ilof_createuser.sh
├─ ilof_security_hardening.sh
├─ ilof_nginx_docker.sh
├─ ilof_memory_cron.sh
└─ srv/
   ├─ default.conf
   └─ ilof_nginx_html/
      ├─ default.conf
      ├─ index.html
      └─ certs/
```

---

## Contributing / License ✍️

- Author / Maintainer: Eduardo
- If you'd like changes to tone, examples, or to add CI checks / unit tests / a VM test harness, open an issue or request edits here and I'll update the README.

---

If you'd like, I can:
- Add more examples (step-by-step),
- Add a `CHECKLIST.md` for manual pre-run checks, or
- Add GitHub Actions to run basic shellcheck/lint checks.

Tell me which you'd prefer and I will update the README.
