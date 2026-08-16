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
EOF
}

PROFILE=standard
INSTALL_DASHBOARD=auto
while (($#)); do
  case "$1" in
    --apply) APPLY_CHANGES=yes ;;
    --yes|-y) ASSUME_YES=yes ;;
    --profile) PROFILE="${2:?}"; shift ;;
    --dashboard) INSTALL_DASHBOARD=yes ;;
    --no-dashboard) INSTALL_DASHBOARD=no ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
  shift
done

require_root
acquire_lock
ensure_layout
core_preflight || warn "Preflight has warnings; review before --apply."

if [[ "$APPLY_CHANGES" != yes ]]; then
  info "Preview complete. Re-run with --apply after review."
  exit 0
fi

confirm "Install $TOOLKIT_NAME profile=$PROFILE?" || die "Cancelled"
backup_file /etc/systemd/system/leodigi-cpt-dashboard.service
install -d -m 0755 "$INSTALL_DIR"
cp -a "$SOURCE_DIR/." "$INSTALL_DIR/"
install -m 0755 "$INSTALL_DIR/toolkitctl" /usr/local/sbin/toolkitctl

if [[ ! -f "$CONFIG_FILE" ]]; then
  install -D -m 0640 "$INSTALL_DIR/config/default.env" "$CONFIG_FILE"
  sed -i 's/^APPLY_CHANGES=no/APPLY_CHANGES=yes/' "$CONFIG_FILE"
fi
ensure_layout

case "$PROFILE" in
  minimal) modules=(core) ;;
  standard) modules=(backup wordpress security ssl monitoring) ;;
  full) modules=(backup wordpress security mail ssl monitoring dashboard) ;;
  *) die "Unknown profile: $PROFILE" ;;
esac

for module in "${modules[@]}"; do
  [[ "$module" == core ]] && continue
  info "Installing module: $module"
  "$INSTALL_DIR/toolkitctl" module install "$module" --yes || warn "Module $module needs manual configuration; see log."
done

systemctl daemon-reload
info "$TOOLKIT_NAME installed. Run: toolkitctl doctor"
