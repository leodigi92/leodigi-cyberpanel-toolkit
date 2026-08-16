#!/usr/bin/env bash
set -Eeuo pipefail

monitoring_install() {
  require_root
  if [[ "${NETDATA_INSTALL:-no}" == yes ]]; then
    run sh -c 'curl -fsSL https://get.netdata.cloud/kickstart.sh > /tmp/netdata-kickstart.sh'
    run sh /tmp/netdata-kickstart.sh --non-interactive --stable-channel
  fi
  install -D -m 0644 "$TOOLKIT_ROOT/systemd/leodigi-cpt-health.service" /etc/systemd/system/leodigi-cpt-health.service
  install -D -m 0644 "$TOOLKIT_ROOT/systemd/leodigi-cpt-health.timer" /etc/systemd/system/leodigi-cpt-health.timer
  run systemctl daemon-reload
  run systemctl enable --now leodigi-cpt-health.timer
}
monitoring_status() { core_health; df -h /; df -i /; free -h; uptime; }
monitoring_collect() {
  local report="$STATE_DIR/reports/health-$(date -u +%Y%m%dT%H%M%SZ).txt" rc=0
  core_health >"$report" || rc=$?
  df -h >>"$report"; df -i >>"$report"; free -h >>"$report"
  ((rc == 0)) || monitoring_alert "CyberPanel health check failed on $(hostname -f). Report: $report"
}
monitoring_alert() {
  local message="$*"
  if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
    curl -fsS --max-time 10 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=$message" >/dev/null || true
  fi
  if [[ -n "${ALERT_EMAIL:-}" ]] && command -v mail >/dev/null; then printf '%s\n' "$message" | mail -s "CyberPanel Toolkit alert" "$ALERT_EMAIL" || true; fi
}
monitoring_test_alert() { monitoring_alert "Test alert from $(hostname -f) at $(date -u +%FT%TZ)"; }
