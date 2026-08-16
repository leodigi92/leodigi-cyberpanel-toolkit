#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/lib/common.sh"
source "$SOURCE_DIR/lib/core.sh"

usage() {
  cat <<'EOF'
Usage: sudo bash install.sh [options]
  --apply             Apply changes (default is preview/dry-run)
  --yes               Non-interactive confirmation
  --profile NAME      minimal|standard|full
  --dashboard         Install dashboard service
  --no-dashboard      Do not install dashboard
  --dashboard-public  Listen on 0.0.0.0 and open the dashboard TCP port
  --dashboard-port N  Dashboard port (default: 9443)
  --dashboard-https   Serve Dashboard with TLS (requires --dashboard-domain)
  --dashboard-domain  Domain in the TLS certificate, for example toolkit.example.com
  --dashboard-cert    TLS full-chain path (default: /etc/letsencrypt/live/DOMAIN/fullchain.pem)
  --dashboard-key     TLS private-key path (default: /etc/letsencrypt/live/DOMAIN/privkey.pem)
EOF
}

PROFILE=standard
INSTALL_DASHBOARD=auto
DASHBOARD_PUBLIC=no
DASHBOARD_PORT_OPTION=9443
DASHBOARD_HTTPS=no
DASHBOARD_DOMAIN_OPTION=
DASHBOARD_CERT_OPTION=
DASHBOARD_KEY_OPTION=
while (($#)); do
  case "$1" in
    --apply) APPLY_CHANGES=yes ;;
    --yes|-y) ASSUME_YES=yes ;;
    --profile) PROFILE="${2:?}"; shift ;;
    --dashboard) INSTALL_DASHBOARD=yes ;;
    --no-dashboard) INSTALL_DASHBOARD=no ;;
    --dashboard-public) DASHBOARD_PUBLIC=yes; INSTALL_DASHBOARD=yes ;;
    --dashboard-port) DASHBOARD_PORT_OPTION="${2:?}"; shift ;;
    --dashboard-https) DASHBOARD_HTTPS=yes; DASHBOARD_PUBLIC=yes; INSTALL_DASHBOARD=yes ;;
    --dashboard-domain) DASHBOARD_DOMAIN_OPTION="${2:?}"; shift ;;
    --dashboard-cert) DASHBOARD_CERT_OPTION="${2:?}"; shift ;;
    --dashboard-key) DASHBOARD_KEY_OPTION="${2:?}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

[[ "$DASHBOARD_PORT_OPTION" =~ ^[0-9]+$ ]] &&
  ((DASHBOARD_PORT_OPTION >= 1 && DASHBOARD_PORT_OPTION <= 65535)) ||
  die "--dashboard-port must be between 1 and 65535"

if [[ "$DASHBOARD_HTTPS" == yes ]]; then
  [[ -n "$DASHBOARD_DOMAIN_OPTION" ]] || die "--dashboard-https requires --dashboard-domain"
  DASHBOARD_CERT_OPTION=${DASHBOARD_CERT_OPTION:-/etc/letsencrypt/live/${DASHBOARD_DOMAIN_OPTION}/fullchain.pem}
  DASHBOARD_KEY_OPTION=${DASHBOARD_KEY_OPTION:-/etc/letsencrypt/live/${DASHBOARD_DOMAIN_OPTION}/privkey.pem}
fi

require_root
if [[ "$APPLY_CHANGES" != yes ]]; then
  LOG_DIR=/tmp/leodigi-cyberpanel-toolkit
  LOG_FILE="$LOG_DIR/preflight-$RUN_ID.log"
fi
core_preflight || warn "Preflight has warnings; review before --apply."

if [[ "$APPLY_CHANGES" != yes ]]; then
  info "Preview complete. Re-run with --apply after review."
  exit 0
fi

if [[ "$DASHBOARD_HTTPS" == yes ]]; then
  [[ -r "$DASHBOARD_CERT_OPTION" ]] || die "TLS certificate not readable: $DASHBOARD_CERT_OPTION"
  [[ -r "$DASHBOARD_KEY_OPTION" ]] || die "TLS private key not readable: $DASHBOARD_KEY_OPTION"
fi

acquire_lock
ensure_layout
confirm "Install $TOOLKIT_NAME profile=$PROFILE?" || die "Cancelled"
backup_file /etc/systemd/system/leodigi-cpt-dashboard.service
install -d -m 0755 "$INSTALL_DIR"
cp -a "$SOURCE_DIR/." "$INSTALL_DIR/"
chmod 0755 "$INSTALL_DIR/bin/dashboard-server"
install -m 0755 "$INSTALL_DIR/toolkitctl" /usr/local/sbin/toolkitctl

if [[ ! -f "$CONFIG_FILE" ]]; then
  install -D -m 0640 "$INSTALL_DIR/config/default.env" "$CONFIG_FILE"
  sed -i 's/^APPLY_CHANGES=no/APPLY_CHANGES=yes/' "$CONFIG_FILE"
fi
ensure_layout

set_config_value() {
  local key="$1" value="$2"
  if grep -q "^${key}=" "$CONFIG_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >>"$CONFIG_FILE"
  fi
}

set_config_value DASHBOARD_PORT "$DASHBOARD_PORT_OPTION"
if [[ "$DASHBOARD_PUBLIC" == yes ]]; then
  set_config_value DASHBOARD_BIND 0.0.0.0
  warn "Dashboard will be reachable from the network on TCP $DASHBOARD_PORT_OPTION."
fi
if [[ "$DASHBOARD_HTTPS" == yes ]]; then
  [[ -r "$DASHBOARD_CERT_OPTION" ]] || die "TLS certificate not readable: $DASHBOARD_CERT_OPTION"
  [[ -r "$DASHBOARD_KEY_OPTION" ]] || die "TLS private key not readable: $DASHBOARD_KEY_OPTION"
  set_config_value DASHBOARD_TLS yes
  set_config_value DASHBOARD_DOMAIN "$DASHBOARD_DOMAIN_OPTION"
  set_config_value DASHBOARD_CERT_FILE "$DASHBOARD_CERT_OPTION"
  set_config_value DASHBOARD_KEY_FILE "$DASHBOARD_KEY_OPTION"
fi

case "$PROFILE" in
  minimal) modules=(core) ;;
  standard) modules=(backup wordpress security ssl monitoring) ;;
  full) modules=(backup wordpress security mail ssl monitoring dashboard) ;;
  *) die "Unknown profile: $PROFILE" ;;
esac

if [[ "$INSTALL_DASHBOARD" == yes ]] && [[ " ${modules[*]} " != *" dashboard "* ]]; then
  modules+=(dashboard)
elif [[ "$INSTALL_DASHBOARD" == no ]]; then
  filtered_modules=()
  for module in "${modules[@]}"; do
    [[ "$module" == dashboard ]] || filtered_modules+=("$module")
  done
  modules=("${filtered_modules[@]}")
fi

for module in "${modules[@]}"; do
  [[ "$module" == core ]] && continue
  info "Installing module: $module"
  "$INSTALL_DIR/toolkitctl" module install "$module" --yes || warn "Module $module needs manual configuration; see log."
done

if [[ "$DASHBOARD_PUBLIC" == yes ]]; then
  source "$INSTALL_DIR/lib/security.sh"
  security_firewall_open "$DASHBOARD_PORT_OPTION/tcp"
  systemctl restart leodigi-cpt-dashboard
  service_active leodigi-cpt-dashboard || die "Dashboard failed after public access configuration"
  if [[ "$DASHBOARD_HTTPS" == yes ]]; then
    info "Dashboard URL: https://$DASHBOARD_DOMAIN_OPTION:$DASHBOARD_PORT_OPTION"
  else
    info "Dashboard URL: http://SERVER_IP:$DASHBOARD_PORT_OPTION"
  fi
fi

systemctl daemon-reload
info "$TOOLKIT_NAME installed. Run: toolkitctl doctor"
