# LeoDigi CyberPanel Toolkit

**Documentation:** [English](README.md) · [Tiếng Việt](README.vi.md)

**Developed by [LeoDigi](https://leodigi.dev)**

Production-oriented, modular operations toolkit for **CyberPanel Free + OpenLiteSpeed**. It adds encrypted cloud backup, WordPress staging/clone helpers, malware scanning, firewall guardrails, mail diagnostics/Rspamd, wildcard SSL automation, monitoring and a local-only dashboard without modifying CyberPanel core.

> Version 1.1.0 is intended for experienced Linux administrators. Test on a staging VPS first. A toolkit cannot compensate for compromised root credentials, unsupported operating systems or missing off-server backups.

## Features

| Module | Capabilities |
|---|---|
| Core | Preview-first installer, config/secrets separation, logs, locking, preflight, health, update, restore points, rollback and uninstall |
| Backup | Restic encryption/deduplication, Rclone remotes, MariaDB dumps, retention, integrity checks, restore and repository replication |
| Cloud destinations | Google Drive/Shared Drive, OneDrive Personal/Business, SharePoint libraries, S3/MinIO/Wasabi, SFTP and local storage |
| WordPress | Discovery, checksum health, safe permissions, clone and staging with pre-change backup |
| Security | ClamAV scanning, reports and guarded UFW/firewalld management that preserves SSH |
| Mail | Postfix/Dovecot diagnostics, queue inspection and opt-in Rspamd + Redis integration |
| SSL | acme.sh issuance, wildcard DNS-01, renew and certificate inspection |
| Monitoring | System/service/disk/inode checks, Netdata opt-in, email and Telegram alerts |
| Dashboard | Authenticated local FastAPI dashboard for read-only operational actions |

## Supported systems

- Ubuntu 22.04/24.04
- AlmaLinux 8/9
- Rocky Linux 8/9
- An existing CyberPanel installation under `/usr/local/CyberCP`
- OpenLiteSpeed under `/usr/local/lsws`
- Root/sudo access and systemd

Other distributions are rejected by preflight instead of being guessed.

## Installation

### 1. Download a versioned release

For this private repository, authenticate Git using GitHub CLI, a deploy key, or a fine-grained read-only token managed outside shell history. Never embed a token in an install URL.

```bash
git clone --depth 1 --branch main \
  https://github.com/leodigi92/leodigi-cyberpanel-toolkit.git
cd leodigi-cyberpanel-toolkit
```

### 2. Preview without changing the VPS

```bash
sudo bash install.sh --profile full
```

### 3. Apply after reviewing preflight output

```bash
sudo bash install.sh --profile full --apply
```

Profiles:

- `minimal`: Core only.
- `standard`: Core, Backup, WordPress, Security, SSL and Monitoring.
- `full`: All modules including Mail tooling and Dashboard.

The installer never installs Rspamd, manages firewall rules or installs Netdata merely because the full profile is selected. High-impact components remain opt-in in `/etc/leodigi-cyberpanel-toolkit/toolkit.env`.

### Direct Dashboard access

Install all modules and expose the Dashboard over HTTP on TCP 9443:

```bash
sudo bash install.sh --profile full --apply --yes \
  --dashboard-public \
  --dashboard-port 9443
```

This makes `http://SERVER_IP:9443` available and opens the firewall port. Use HTTP only on a private network or VPN.

To serve TLS directly, first point the domain to the VPS and obtain a valid certificate:

```bash
sudo bash install.sh --profile full --apply --yes \
  --dashboard-public \
  --dashboard-port 9443 \
  --dashboard-domain toolkit.example.com \
  --dashboard-https
```

The default certificate paths are `/etc/letsencrypt/live/DOMAIN/fullchain.pem` and `privkey.pem`. Override them with `--dashboard-cert` and `--dashboard-key` when necessary. The installer fails closed when TLS files are unreadable or the Dashboard cannot start. Port 8090 remains reserved for CyberPanel.

## First checks

```bash
sudo toolkitctl preflight
sudo toolkitctl health
sudo toolkitctl doctor
sudo toolkitctl module list
```

## Backup setup

Install the module and start the cloud connection wizard:

```bash
sudo toolkitctl module install backup --apply --yes
sudo toolkitctl backup remote add
sudo toolkitctl backup remote list
sudo toolkitctl backup remote test REMOTE_NAME
sudo toolkitctl backup configure
sudo toolkitctl backup run production
sudo toolkitctl backup list production
sudo toolkitctl backup check production
```

Rclone remote types:

- `drive`: Google Drive and Shared Drive. Use your own Google OAuth Client ID.
- `onedrive`: OneDrive Personal/Business and SharePoint document libraries.
- `s3`: Amazon S3, MinIO, Wasabi and compatible services.
- `sftp`: a remote SSH server.

For Microsoft 365 application authentication, prefer SharePoint `Sites.Selected` and grant access only to the backup site/library. Do not grant tenant-wide write access unless it is genuinely required.

Secrets are stored with mode `0600` in:

```text
/etc/leodigi-cyberpanel-toolkit/secrets/rclone.conf
/etc/leodigi-cyberpanel-toolkit/secrets/restic-PROFILE.password
```

Keep an offline copy of every Restic password. Without it, encrypted backups are unrecoverable.

Restore always targets a separate directory:

```bash
sudo toolkitctl backup restore production SNAPSHOT_ID /restore/cyberpanel-test
```

Database dumps are restored as files and are never automatically imported over a live database.

## WordPress

Create both source and destination websites/database assignments in CyberPanel first:

```bash
sudo toolkitctl wp list
sudo toolkitctl wp health example.com
sudo toolkitctl wp permissions example.com --apply
sudo toolkitctl wp clone example.com staging.example.com
sudo toolkitctl wp staging example.com staging.example.com
```

Clone/staging creates a Restic backup first. Production push is intentionally not exposed in v1.1.0 because file/database merge policy is application-specific; use a reviewed clone workflow or restore point.

## Malware and firewall

```bash
sudo toolkitctl module install security --apply --yes
sudo toolkitctl malware scan example.com
sudo toolkitctl malware scan-all
sudo toolkitctl malware report
```

The scanner reports infected files but does not automatically delete them. Restore known-good files from Restic after investigating the entry point.

Firewall management is disabled by default. Review SSH and service ports, then set:

```text
FIREWALL_MANAGE=yes
FIREWALL_SSH_PORT=22
```

Apply while keeping a second SSH session open:

```bash
sudo toolkitctl firewall status
sudo toolkitctl firewall apply --apply
```

## Mail and Rspamd

```bash
sudo toolkitctl mail status
sudo toolkitctl mail queue
sudo toolkitctl mail check mail.example.com
sudo toolkitctl mail install-rspamd --apply
```

Rspamd installation backs up Postfix/Rspamd configuration, validates both configurations and uses `milter_default_action=accept` so a Rspamd outage does not stop all mail. Tune thresholds after monitoring false positives.

## Wildcard SSL

```bash
sudo toolkitctl module install ssl --apply --yes
sudo install -m 600 /dev/null /etc/leodigi-cyberpanel-toolkit/secrets/dns-api.env
sudo editor /etc/leodigi-cyberpanel-toolkit/secrets/dns-api.env
sudo toolkitctl ssl wildcard example.com dns_cf
sudo toolkitctl ssl renew
sudo toolkitctl ssl check example.com
```

Use the variable names required by your acme.sh DNS provider. Restrict API tokens to DNS editing for the intended zone.

## Monitoring and alerts

Set `ALERT_EMAIL`, `TELEGRAM_CHAT_ID` and the secret `TELEGRAM_BOT_TOKEN` locally. The health timer runs every 15 minutes.

```bash
sudo toolkitctl monitoring status
sudo toolkitctl monitoring test-alert
systemctl list-timers 'leodigi-cpt-*'
```

Netdata is opt-in with `NETDATA_INSTALL=yes`. Do not expose Netdata directly; reverse proxy it with authentication.

## Dashboard

```bash
sudo toolkitctl module install dashboard --apply --yes
sudo toolkitctl dashboard reset-password
sudo toolkitctl dashboard status
```

The service listens on `127.0.0.1:9443`. Publish it only through an HTTPS OpenLiteSpeed reverse proxy with an additional IP allowlist or VPN. The dashboard intentionally cannot run restore, firewall mutation, malware deletion or WordPress clone.

## Update, rollback and removal

Versioned updates require a tarball and adjacent SHA-256 file:

```bash
sudo toolkitctl update /root/cyberpanel-toolkit-1.1.0.tar.gz
sudo toolkitctl restore-points
sudo toolkitctl rollback RESTORE_POINT_ID
sudo toolkitctl uninstall
```

`uninstall` preserves configuration, state and backup repositories. `uninstall --purge-data` removes local toolkit configuration/state after confirmation, but still does not delete remote Restic repositories or website data.

## Security model

- No credentials are committed to Git.
- Installer defaults to preview; mutation requires `--apply`.
- Dashboard binds to localhost and exposes only allowlisted read operations.
- Firewall management is opt-in and preserves the configured SSH port.
- Malware files are not auto-deleted.
- Database restores never overwrite live databases automatically.
- Service configuration is backed up before modification.
- Update packages require a checksum.

## Development and validation

```bash
bash tests/run.sh
```

The suite performs shell syntax checks, verifies executable permissions, checks required files, runs CLI help/version in an isolated temporary configuration and compiles the Python dashboard.

## Important limitations

- CyberPanel/OpenLiteSpeed internals can change; test after every CyberPanel update.
- Google Drive, OneDrive and SharePoint may throttle high-volume repositories. Prefer S3/MinIO as the primary target for large fleets and replicate snapshots to Drive/SharePoint.
- A successful backup is not proven until a restore test succeeds.
- The toolkit does not replace OS patching, least-privilege SSH, WAF rules, application updates or incident-response procedures.

## License

MIT. See [LICENSE](LICENSE).
