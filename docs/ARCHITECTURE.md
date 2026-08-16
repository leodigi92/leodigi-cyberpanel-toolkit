# Architecture

The toolkit deliberately stays outside CyberPanel's Django source tree. `toolkitctl` calls modular Bash libraries, systemd invokes the same CLI, and the dashboard can invoke only a small read-only allowlist. This avoids patching CyberPanel templates or routes and reduces breakage during panel updates.

Configuration lives in `/etc/leodigi-cyberpanel-toolkit`, runtime state in `/var/lib/leodigi-cyberpanel-toolkit`, logs in `/var/log/leodigi-cyberpanel-toolkit`, local safety copies in `/var/backups/leodigi-cyberpanel-toolkit`, and program code in `/opt/leodigi-cyberpanel-toolkit`.

Restic provides encrypted snapshots. Rclone provides cloud transports. Database dumps are staged immediately before the Restic snapshot and removed afterward. Cloud OAuth tokens and Restic keys never enter the repository.
