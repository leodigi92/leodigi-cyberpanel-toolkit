#!/usr/bin/env bash
set -Eeuo pipefail

ssl_install() {
  require_root
  if [[ ! -x /root/.acme.sh/acme.sh ]]; then
    run sh -c "curl -fsSL https://get.acme.sh | sh -s email='${ALERT_EMAIL:-admin@$(hostname -f)}'"
  fi
}
ssl_check() {
  local target=${1:-$(hostname -f)} port=${2:-443}
  echo | openssl s_client -servername "$target" -connect "$target:$port" 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256
}
ssl_issue() {
  require_root
  local domain="${1:?domain}" webroot="${2:-/home/$domain/public_html}"
  /root/.acme.sh/acme.sh --issue -d "$domain" -w "$webroot"
}
ssl_wildcard() {
  require_root
  local domain="${1:?domain}" provider="${2:?dns provider, e.g. dns_cf}"
  [[ -r "$SECRETS_DIR/dns-api.env" ]] || die "Create $SECRETS_DIR/dns-api.env with provider credentials (chmod 600)"
  set -a; source "$SECRETS_DIR/dns-api.env"; set +a
  /root/.acme.sh/acme.sh --issue --dns "$provider" -d "$domain" -d "*.$domain"
}
ssl_renew() { require_root; /root/.acme.sh/acme.sh --cron --home /root/.acme.sh; }
