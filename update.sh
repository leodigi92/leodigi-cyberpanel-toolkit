#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT/lib/common.sh"
require_root; acquire_lock; ensure_layout

PACKAGE="${1:-}"
[[ -n "$PACKAGE" && -f "$PACKAGE" ]] || die "Usage: toolkitctl update /absolute/path/cyberpanel-toolkit-VERSION.tar.gz"
[[ "$PACKAGE" == /* ]] || die "Package must be an absolute path"

CHECKSUM_FILE="${PACKAGE}.sha256"
if [[ -f "$CHECKSUM_FILE" ]]; then
  (cd "$(dirname "$PACKAGE")" && sha256sum -c "$(basename "$CHECKSUM_FILE")") || die "Checksum verification failed"
else
  die "Checksum file missing: $CHECKSUM_FILE"
fi

point="update-$RUN_ID"
backup_file "$INSTALL_DIR" "$point"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$PACKAGE" -C "$work"
source_dir=$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -1)
[[ -x "$source_dir/toolkitctl" && -r "$source_dir/VERSION" ]] || die "Invalid toolkit package"
bash -n "$source_dir/toolkitctl" "$source_dir/install.sh"
new_version=$(<"$source_dir/VERSION"); old_version=$(<"$ROOT/VERSION")
info "Updating $old_version -> $new_version"
confirm "Install verified update?" || die "Cancelled"
cp -a "$source_dir/." "$INSTALL_DIR/"
install -m 0755 "$INSTALL_DIR/toolkitctl" /usr/local/sbin/toolkitctl
systemctl daemon-reload
toolkitctl health || { warn "Health check failed; use toolkitctl rollback $point"; exit 2; }
info "Update completed"
