#!/usr/bin/env bash
set -Eeuo pipefail

mail_install() { info "Mail diagnostics available. Rspamd is opt-in: toolkitctl mail install-rspamd --apply"; }
mail_status() {
  local service
  for service in postfix dovecot rspamd redis; do
    service_exists "$service" && printf '%-12s %s\n' "$service" "$(systemctl is-active "$service" 2>/dev/null || true)"
  done
  mail_queue
}
mail_queue() { command -v postqueue >/dev/null && postqueue -p || warn "postqueue unavailable"; }
mail_check() {
  local hostname_fqdn=${1:-$(hostname -f)}
  postfix check
  doveconf -n >/dev/null
  getent ahosts "$hostname_fqdn" || true
  command -v dig >/dev/null && { dig +short MX "$hostname_fqdn"; dig +short TXT "$hostname_fqdn"; } || true
  openssl s_client -starttls smtp -connect "127.0.0.1:25" -servername "$hostname_fqdn" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates || true
}
mail_install_rspamd() {
  require_root
  service_exists postfix || die "Postfix is required"
  backup_file /etc/postfix/main.cf
  backup_file /etc/rspamd
  detect_os
  if [[ "$OS_ID" == ubuntu ]]; then package_install rspamd redis-server; else package_install rspamd redis; fi
  install -d -m 0755 /etc/rspamd/local.d
  cat >/etc/rspamd/local.d/actions.conf <<'EOF'
reject = 15;
add_header = 6;
greylist = 4;
EOF
  cat >/etc/rspamd/local.d/redis.conf <<'EOF'
servers = "127.0.0.1";
EOF
  postconf -e 'smtpd_milters=inet:127.0.0.1:11332'
  postconf -e 'non_smtpd_milters=inet:127.0.0.1:11332'
  postconf -e 'milter_default_action=accept'
  postconf -e 'milter_protocol=6'
  rspamadm configtest
  postfix check
  run systemctl enable --now redis rspamd
  safe_restart postfix "postfix check"
}
