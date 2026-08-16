#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/common.sh"
require_root; acquire_lock
PURGE=no
[[ "${1:-}" == --purge-data ]] && PURGE=yes
confirm "Remove toolkit services and program files? Backups/config remain unless --purge-data is supplied." || die "Cancelled"
for unit in leodigi-cpt-backup.timer leodigi-cpt-malware.timer leodigi-cpt-health.timer leodigi-cpt-dashboard.service; do
  systemctl disable --now "$unit" 2>/dev/null || true
done
rm -f /etc/systemd/system/leodigi-cpt-*.service /etc/systemd/system/leodigi-cpt-*.timer /usr/local/sbin/toolkitctl
systemctl daemon-reload
rm -rf "$INSTALL_DIR"
if [[ "$PURGE" == yes ]]; then
  [[ "$CONFIG_DIR" == /etc/leodigi-cyberpanel-toolkit ]] && rm -rf "$CONFIG_DIR"
  [[ "$STATE_DIR" == /var/lib/leodigi-cyberpanel-toolkit ]] && rm -rf "$STATE_DIR"
  [[ "$LOG_DIR" == /var/log/leodigi-cyberpanel-toolkit ]] && rm -rf "$LOG_DIR"
fi
echo "Toolkit removed. Restic repositories and website data were not deleted."
