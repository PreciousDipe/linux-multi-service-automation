# Linux Multi-Service Environment Automation

Modular Bash provisioning for a hardened multi-service Linux host: **Nginx reverse
proxy → Flask/Gunicorn backend**, locked down with **UFW**, **fail2ban**, a
**dedicated non-root service user**, a **hardened systemd unit**, **logrotate**,
plus bonus **self-signed TLS**, **cron health monitoring**, and **verified backups**.

- **Target OS:** Ubuntu 22.04 / 24.04 (Debian-based, `apt`)
- **Entry point:** `sudo ./provision.sh` (one command provisions everything)
- **Log:** every run is timestamped to `/var/log/provision.log`

---

## Quick start

```bash
git clone <your-repo-url> && cd linux-multi-service-automation

# Basic run (HTTP only)
sudo ./provision.sh

# With bonus TLS (self-signed cert on :443, HTTP→HTTPS redirect)
sudo ./provision.sh --with-tls --domain myapp.local

# Skip the bonus cron jobs if you don't want them
sudo ./provision.sh --skip-monitoring --skip-backup
```

> No real DNS for your domain yet? `echo "127.0.0.1 myapp.local" >> /etc/hosts`
> satisfies both the provisioning DNS check and the TLS certificate CN.

Full option list: `sudo ./provision.sh --help`

---

## Architecture

```javascript
                            INTERNET
                               │
                ┌──────────────▼──────────────┐
                │   UFW FIREWALL              │   only 22 (SSH), 80, 443 open
                └──────────────┬──────────────┘
                               │
                ┌──────────────▼──────────────┐
                │   NGINX :80 / :443          │   reverse proxy (site: backend)
                │   upstream "backend_app"    │   X-Real-IP / X-Forwarded-For
                └──────────────┬──────────────┘
                               │ proxy_pass
                      ┌────────▼─────────┐
                      │  GUNICORN        │   127.0.0.1:3000 (localhost only —
                      │  Flask app       │   never exposed to the network)
                      │  user: appsvc    │   non-root, nologin shell
                      └────────┬─────────┘
                               │ writes
        ┌──────────────────────┼───────────────────────┐
        │                      │                       │
  ┌─────▼──────┐        ┌──────▼───────┐        ┌──────▼───────┐
  │ /var/log/  │        │ systemd      │        │ cron         │
  │ myapp/     │        │ Restart=     │        │ every 5 min: │
  │ nginx/     │        │ on-failure + │        │ health check │
  │ +logrotate │        │ sandboxing   │        │ daily: backup│
  └────────────┘        └──────────────┘        └──────────────┘

  fail2ban (journald backend) watches sshd + nginx logs → bans via UFW
```

### Provisioning control flow

```javascript
provision.sh [flags]
   │  sources scripts/config.sh (log/die/guard helpers)
   ├─► 01 system-setup.sh        packages + DNS preflight
   ├─► 02 create-user.sh         dedicated user "appsvc"
   ├─► 03 install-backend.sh     venv (owned by appsvc) + app deploy
   ├─► 04 configure-logrotate.sh rotation policy for all three log families
   ├─► 05 systemd unit           enable + start backend-app.service
   ├─► 06 configure-nginx.sh     reverse proxy :80 → 127.0.0.1:3000
   ├─► 07 configure-tls.sh       self-signed cert + :443 (only with --with-tls)
   ├─► 08 configure-firewall.sh  UFW minimal ports
   ├─► 09 configure-fail2ban.sh  sshd + nginx jails
   ├─► 10 configure-monitoring.sh cron health check      [bonus]
   ├─► 11 configure-backup.sh     cron daily backup      [bonus]
   └─► 12 verify.sh              self-check gate — fails the run if anything is down
```

Every arrow is a separate file under `scripts/`. `provision.sh` itself contains no
setup logic — it only parses flags and calls module functions in dependency order.

---

## Repository layout

```javascript
├── provision.sh              # orchestrator: flags, ordering, ERR trap
├── app/
│   ├── app.py                # Flask app: / and JSON /health endpoint
│   └── requirements.txt      # flask + gunicorn (pinned)
├── scripts/
│   ├── config.sh             # log/die/require_root/apt_install_if_missing/verify_dns
│   ├── system-setup.sh       # apt packages + DNS preflight
│   ├── create-user.sh        # service user
│   ├── install-backend.sh    # venv + deploy
│   ├── configure-logrotate.sh
│   ├── configure-nginx.sh
│   ├── configure-tls.sh      # + configure-cert.sh (keypair generation)
│   ├── configure-firewall.sh
│   ├── configure-fail2ban.sh
│   ├── configure-monitoring.sh
│   ├── configure-backup.sh
│   └── verify.sh             # post-provision correctness gate
├── systemd/backend.service   # unit file (hardened)
├── nginx/                    # backend.conf, upstream.conf, +tls variants
├── fail2ban/jail.local
├── logrotate/backend-app     # three stanzas: app, nginx, monitor/backup logs
├── monitoring/health-check.sh
└── backup/backup.sh
```

Every module is also **standalone-executable** (`./scripts/create-user.sh`) —
the `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard at the bottom of each module
means it can be sourced (by the orchestrator) *or* run directly, and it behaves
correctly either way.

---

## Design decisions

This table is the heart of the documentation — each entry is a deliberate
choice with a rationale, not a default.

| # | Decision | Rationale |
| --- | --- | --- |
| 1 | **Modular functions sourced into one shell**, rather than independent sub-scripts executed in sequence | Shared shell state (config vars, log file handle, helper functions) with zero re-parsing; strict execution order enforced by `main()`; each module still independently runnable (see the `BASH_SOURCE[0]` guard) |
| 2 | **`readonly PROJECT_ROOT` in the orchestrator** | Sourced modules compute their own directory via `BASH_SOURCE[0]`, which overwrites any normal variable they share a name with. A `readonly` variable with a unique name survives sourcing untouched — this was a real bug during development (`scripts/scripts/...` paths) and the fix is structural, not incidental |
| 3 | **`set -euo pipefail` in every script** | Fail fast on command errors, unset variables, and failures anywhere inside a pipeline — a half-configured state is worse than an aborted run |
| 4 | **Idempotency via existence guards, not state tracking** | `dpkg -s` for packages, `id` for the user, `-d` for the venv, `ufw allow` (self-skips duplicates), `[[ -f cert ]]` for TLS, `*.orig` backup only created once. No state files to corrupt — re-running is always safe |
| 5 | **Dedicated user `appsvc`: `--system` + `nologin` shell** | Least privilege: the app never runs as root; the account can never hold an interactive login even if compromised |
| 6 | **Venv created and pip-run *as* `appsvc` (`sudo -u`)** | Every file in `/opt/backend-app` is owned by the service user from birth — no root-owned files inside the app tree that could break later reinstalls |
| 7 | **Gunicorn bound to `127.0.0.1:3000`, never `0.0.0.0`** | The backend is unreachable from the network by construction. All traffic must enter through Nginx — one entry point means one place for headers, TLS, rate limiting, and logging |
| 8 | **systemd hardening: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`, explicit `ReadWritePaths`** | Defense in depth beyond "runs as non-root": the service cannot gain new privileges, see other users' tmp files, or write anywhere except the two paths it needs |
| 9 | **`Restart=on-failure` + `RestartSec=5`** | Automatic recovery from crashes without masking genuine startup errors (a service that can never start would loop forever under `Restart=always`) |
| 10 | **Nginx `upstream` block + dedicated `/health` location with `access_log off`** | Upstream decouples the socket decision from the vhost; health polls every 5 minutes from cron would otherwise flood the access log, so that one location opts out of logging |
| 11 | **Logrotate uses `postrotate` reload instead of `copytruncate`** | `copytruncate` has a race window where log lines written between copy and truncate are lost. Reloading the service reopens file descriptors cleanly — correctness over convenience |
| 12 | **Logrotate creates rotated files with correct ownership (`create 0640 appsvc appsvc` / `www-data adm`)** | Rotation must not silently change who can write or read the logs — three stanzas cover the three distinct log families (app, nginx, monitor/backup) |
| 13 | **fail2ban `backend = systemd` (journald)** | Modern Ubuntu logs SSH to the journal, not `/var/log/auth.log`; the journald backend is reliable regardless of rsyslog configuration, and `%(sshd_log)s` resolves correctly against it |
| 14 | **Nginx jails watch the *app-specific* logs** (`backend-access.log`, `backend-error.log`) | fail2ban only sees traffic for this service, not unrelated vhosts — tighter signal, fewer false positives |
| 15 | **Backup verifies itself (`tar -tzf`) before declaring success** | A backup that fails at restore time is worthless; the archive is integrity-tested at creation, corrupt files are deleted rather than kept, and rotation is age-based (`-mtime +7`) |
| 16 | **DNS preflight with three-tool fallback (`getent` → `host` → `nslookup`)** | Fails fast with a clear message before any network-dependent step, instead of mid-`apt-get`; tolerates whichever resolver tools happen to be installed |
| 17 | **Timestamped dual-output logging (`tee -a`)** | One line on screen for the operator, one line in `/var/log/provision.log` for the audit trail — same format, single writer function |
| 18 | **`verify.sh` as a hard gate at the end of provisioning** | Provisioning only reports success after independently confirming nginx, backend-app, fail2ban, UFW are active *and* the health endpoint responds through the proxy — not merely that commands exited 0 |
| 19 | **Backup excludes `venv/`, `__pycache__`, `*.pyc`** | Dependencies are reproducible from `requirements.txt`; archiving them would triple the archive size for zero recoverable value |

## Security notes

- Open ports: **22, 80, 443 only**. Port 3000 is bound to localhost and invisible to `nmap` from outside.
- App runs as `appsvc` under a sandboxed systemd unit (see decision #8).
- fail2ban bans SSH and Nginx abusers at the firewall level (1h ban, 5 strikes / 10 min).
- Existing config files are backed up to `*.orig` before being overwritten.
- TLS private key is generated with `chmod 600` semantics via OpenSSL defaults and lives in `/etc/nginx/ssl/`.
- **Out of scope by design:** SSH daemon hardening (`PasswordAuthentication no`, etc.) is left to the base image/operator — fail2ban complements it but does not replace it.

---

## Idempotency proof

Requirement: *running twice produces the same result without errors.*

```bash
$ sudo ./provision.sh            # run 1 — full install
...
$ sudo ./provision.sh            # run 2 — must exit 0
...
$ echo $?                        # -> 0
```

Expected evidence in the run-2 log (`/var/log/provision.log`) — every expensive or
destructive step is guarded and reports itself as skipped rather than failing:

```javascript
[...] [INFO] Package 'ufw' already installed, skipping.
[...] [INFO] Package 'fail2ban' already installed, skipping.
[...] [INFO] User 'appsvc' already exists, skipping creation.
[...] [INFO] Virtualenv already exists at /opt/backend-app/venv, skipping creation.
[...] [INFO] DNS resolution is OK for google.com.
[...] [INFO] All verification checks passed.
[...] [INFO] ===== Provisioning completed successfully =====
```

Where each guard lives:

| Step | Guard |
| --- | --- |
| apt packages | `dpkg -s` check in `apt_install_if_missing` (`scripts/config.sh`) |
| service user | `id "$APP_USER"` in `scripts/create-user.sh` |
| virtualenv | `[[ -d "$VENV_DIR" ]]` in `scripts/install-backend.sh` |
| UFW rules | `ufw allow` skips exact duplicates by design |
| TLS certificate | `[[ -f ... ]]` check in `scripts/configure-cert.sh` (skipped entirely without `--with-tls`) |
| original configs | `backup_file_if_exists` only copies to `*.orig` once |
| cron jobs | cron file content is rewritten idempotently, never duplicated |

---

## Verification checklist

Run order is enforced by `provision.sh`; `verify.sh` executes the ✅ checks
marked **(auto)** automatically at the end of every provisioning run.

| Check | Command | Expected |
| --- | --- | --- |
| Backend service active, running as non-root **(auto)** | `systemctl status backend-app` | `active (running)`, `Main PID` owned by `appsvc` |
| Backend health direct | `curl http://127.0.0.1:3000/health` | `{"status":"ok","service":"myapp",...}` |
| Reverse proxy works **(auto)** | `curl http://localhost/health` | same JSON, served via nginx (:80) |
| Real client IP is forwarded | `tail /var/log/myapp/app.log` from an external client | log lines show the *client's* IP, not `127.0.0.1` |
| nginx active **(auto)** | `systemctl is-active nginx` | `active` |
| Firewall minimal **(auto)** | `sudo ufw status verbose` | `22, 80, 443` only; `Status: active` |
| fail2ban active **(auto)** | `sudo fail2ban-client status` | sshd, nginx-http-auth, nginx-botsearch listed |
| fail2ban SSH jail | `sudo fail2ban-client status sshd` | jail running, `Currently banned: 0` (or list) |
| Health monitor logging (bonus) | `sudo cat /var/log/backend-health.log` (after ~5 min) | `[timestamp] OK - {"status":"ok",...}` lines |
| Log rotation dry-run | `sudo logrotate -d /etc/logrotate.d/backend-app` | no errors, rotation plan shown |
| TLS (bonus, if enabled) | `curl -k https://<domain>/health` | JSON response; `http://` redirects to `https://` |
| Backup (bonus) | `sudo backup-app` or wait for daily cron | `/var/backups/backend-app/backend-app-<ts>.tar.gz`, verified in `/var/log/backend-backup.log` |
| Provisioning log | `sudo less /var/log/provision.log` | complete timestamped audit trail |
| **Full gate** **(auto)** | end of `sudo ./provision.sh` | `All verification checks passed.` |

---

## Bonus features

| Feature | Files | How it runs |
| --- | --- | --- |
| Self-signed TLS + HTTP→HTTPS redirect | `scripts/configure-cert.sh`, `scripts/configure-tls.sh`, `nginx/backend-tls.conf`, `nginx/backend-redirect.conf` | `--with-tls [--domain name]`; cert valid 365 days, regenerated only if missing |
| Health monitoring | `monitoring/health-check.sh`, `scripts/configure-monitoring.sh` | cron every 5 min → `/var/log/backend-health.log` |
| Verified, rotated backups | `backup/backup.sh`, `scripts/configure-backup.sh` | cron daily; `tar -tzf` integrity check, 7-day retention |

---

## Known limitations

- The TLS certificate is **self-signed**, so browsers show a warning — expected
and acceptable for this assignment; swap in a real CA-issued cert by replacing
the files in `/etc/nginx/ssl/`.
- `provision.sh` targets Debian/Ubuntu (`apt`); porting to RHEL-family would
mean swapping `apt_install_if_missing` for a `dnf` equivalent — the module
structure keeps that change to one function.