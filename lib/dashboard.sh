#!/usr/bin/env bash
set -Eeuo pipefail

dashboard_install() {
  require_root
  package_install python3 python3-venv
  python3 -m venv "$INSTALL_DIR/dashboard/.venv"
  "$INSTALL_DIR/dashboard/.venv/bin/pip" install --disable-pip-version-check -r "$INSTALL_DIR/dashboard/requirements.txt"
  install -D -m 0644 "$TOOLKIT_ROOT/systemd/leodigi-cpt-dashboard.service" /etc/systemd/system/leodigi-cpt-dashboard.service
  [[ -s "$SECRETS_DIR/dashboard.env" ]] || dashboard_reset_password
  run systemctl daemon-reload
  run systemctl enable --now leodigi-cpt-dashboard
}
dashboard_status() { systemctl status leodigi-cpt-dashboard --no-pager; }
dashboard_reset_password() {
  require_root; ensure_layout
  local password hash secret
  password=$(tr -dc 'A-Za-z0-9_@%+=-' </dev/urandom | head -c 24 || true)
  secret=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48 || true)
  hash=$(python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' "$password")
  cat >"$SECRETS_DIR/dashboard.env" <<EOF
CPT_DASHBOARD_USER=admin
CPT_DASHBOARD_PASSWORD_SHA256=$hash
CPT_DASHBOARD_SECRET=$secret
EOF
  chmod 0600 "$SECRETS_DIR/dashboard.env"
  printf 'Dashboard user: admin\nDashboard password: %s\nSave it now; only the hash is stored.\n' "$password"
}
