#!/usr/bin/env bash
set -Eeuo pipefail

security_install() {
  require_root
  detect_os
  if [[ "$OS_ID" == ubuntu ]]; then package_install clamav clamav-daemon ufw; else package_install clamav clamav-update firewalld; fi
  install -D -m 0644 "$TOOLKIT_ROOT/systemd/leodigi-cpt-malware.service" /etc/systemd/system/leodigi-cpt-malware.service
  install -D -m 0644 "$TOOLKIT_ROOT/systemd/leodigi-cpt-malware.timer" /etc/systemd/system/leodigi-cpt-malware.timer
  run systemctl daemon-reload
  run systemctl enable --now leodigi-cpt-malware.timer
}

security_malware_help() { echo "toolkitctl malware scan DOMAIN|scan-all|report|quarantine|restore FILE"; }
security_malware_scan() {
  local domain="${1:?domain}" root report="$STATE_DIR/reports/malware-$RUN_ID.log"
  root=$(wordpress_docroot "$domain") || die "Website not found"
  command -v clamscan >/dev/null || die "ClamAV not installed"
  info "Scanning $root"
  set +e
  clamscan -ri --infected --log="$report" --exclude-dir='/(cache|backups?|quarantine|\.git)/' "$root"
  local rc=$?; set -e
  [[ $rc -le 1 ]] || die "Scanner error ($rc)"
  info "Report: $report"
  return "$rc"
}
security_malware_scan_all() {
  local root report="$STATE_DIR/reports/malware-$RUN_ID.log"
  command -v clamscan >/dev/null || die "ClamAV not installed"
  set +e; clamscan -ri --infected --log="$report" --exclude-dir='/(cache|backups?|quarantine|\.git)/' /home; local rc=$?; set -e
  [[ $rc -le 1 ]] || die "Scanner error ($rc)"
  return "$rc"
}
security_malware_report() { find "$STATE_DIR/reports" -name 'malware-*.log' -printf '%T@ %p\n' | sort -rn | head -10 | cut -d' ' -f2-; }
security_malware_quarantine() { warn "Automatic quarantine is disabled by design; review the report and use a full path."; }
security_malware_restore() { die "Restore must be performed from a verified Restic snapshot."; }

security_firewall_status() {
  if command -v firewall-cmd >/dev/null; then firewall-cmd --state; firewall-cmd --list-all; elif command -v ufw >/dev/null; then ufw status verbose; else nft list ruleset; fi
}
security_firewall_apply() {
  require_root
  [[ "${FIREWALL_MANAGE:-no}" == yes ]] || die "Set FIREWALL_MANAGE=yes after reviewing ports"
  local ssh_port="${FIREWALL_SSH_PORT:-22}" ports=("$ssh_port/tcp" 80/tcp 443/tcp 8090/tcp 25/tcp 465/tcp 587/tcp 143/tcp 993/tcp)
  confirm "Apply firewall baseline and preserve SSH port $ssh_port?" || die "Cancelled"
  if command -v firewall-cmd >/dev/null; then
    run systemctl enable --now firewalld
    for port in "${ports[@]}"; do run firewall-cmd --permanent --add-port="$port"; done
    run firewall-cmd --reload
  elif command -v ufw >/dev/null; then
    run ufw default deny incoming; run ufw default allow outgoing
    for port in "${ports[@]}"; do run ufw allow "$port"; done
    run ufw --force enable
  else die "No supported firewall frontend"; fi
}
security_firewall_open() { local port="${1:?port/protocol}"; command -v firewall-cmd >/dev/null && run firewall-cmd --permanent --add-port="$port" && run firewall-cmd --reload || run ufw allow "$port"; }
security_firewall_close() { local port="${1:?port/protocol}"; command -v firewall-cmd >/dev/null && run firewall-cmd --permanent --remove-port="$port" && run firewall-cmd --reload || run ufw delete allow "$port"; }
