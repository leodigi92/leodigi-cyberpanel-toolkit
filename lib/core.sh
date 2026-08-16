#!/usr/bin/env bash
set -Eeuo pipefail

core_preflight() {
  require_root
  detect_os
  ensure_layout
  local failures=0
  [[ -d /usr/local/CyberCP ]] || { warn "CyberPanel directory not detected."; failures=$((failures+1)); }
  [[ -d /usr/local/lsws ]] || { warn "OpenLiteSpeed directory not detected."; failures=$((failures+1)); }
  command -v systemctl >/dev/null || { error "systemd is required"; failures=$((failures+1)); }
  local free_mb
  free_mb=$(df -Pm / | awk 'NR==2 {print $4}')
  (( free_mb >= 2048 )) || { warn "Less than 2 GB free disk space."; failures=$((failures+1)); }
  info "OS=$OS_ID $OS_VERSION free_disk=${free_mb}MB cyberpanel=$([[ -d /usr/local/CyberCP ]] && echo yes || echo no)"
  (( failures == 0 )) || return 2
}

core_health() {
  local failed=0 service state
  printf '%-22s %-8s %s\n' COMPONENT STATUS DETAIL
  printf '%-22s %-8s %s\n' CyberPanel "$([[ -d /usr/local/CyberCP ]] && echo PASS || echo WARN)" /usr/local/CyberCP
  for service in lscpd lsws mariadb postfix dovecot rspamd redis netdata leodigi-cpt-dashboard; do
    service_exists "$service" || continue
    state=$(systemctl is-active "$service" 2>/dev/null || true)
    if [[ "$state" == active ]]; then
      printf '%-22s %-8s %s\n' "$service" PASS "$state"
    else
      printf '%-22s %-8s %s\n' "$service" FAIL "$state"
      failed=$((failed+1))
    fi
  done
  if command -v restic >/dev/null && [[ -r "$CONFIG_DIR/backup.env" ]]; then
    printf '%-22s %-8s %s\n' Restic PASS "installed"
  fi
  return "$failed"
}

core_restore_points() {
  find "$STATE_DIR/restore-points" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -r
}

core_rollback() {
  local point="${1:?restore point required}" root="$STATE_DIR/restore-points/$point"
  [[ -d "$root" ]] || die "Restore point not found: $point"
  confirm "Restore configuration from $point?" || die "Cancelled"
  while IFS= read -r -d '' file; do
    local relative="${file#$root}"
    [[ "$relative" == /* ]] || continue
    run install -D -m "$(stat -c %a "$file")" "$file" "$relative"
  done < <(find "$root" -type f -print0)
  info "Rollback completed. Review and restart affected services."
}

core_doctor() {
  core_preflight || true
  core_health || true
  command -v restic >/dev/null && info "restic=$(restic version | head -1)" || warn "restic not installed"
  command -v rclone >/dev/null && info "rclone=$(rclone version | head -1)" || warn "rclone not installed"
  command -v wp >/dev/null && info "wp=$(wp --version --allow-root 2>/dev/null)" || warn "WP-CLI not installed"
  ss -lntup 2>/dev/null | grep -E ':(22|80|443|7080|8090|9443)\b' || true
}
