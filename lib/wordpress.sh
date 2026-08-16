#!/usr/bin/env bash
set -Eeuo pipefail

wordpress_help() { echo "toolkitctl wp list|health DOMAIN|permissions DOMAIN|clone SOURCE TARGET|staging DOMAIN"; }

wordpress_install() {
  require_root
  package_install rsync unzip curl mariadb-client 2>/dev/null || package_install rsync unzip curl mariadb
  if ! command -v wp >/dev/null; then
    run curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp
    run chmod 0755 /usr/local/bin/wp
  fi
}

wordpress_docroot() {
  local domain="$1"
  for path in "/home/$domain/public_html" /home/*/"$domain"/public_html; do
    [[ -f "$path/wp-config.php" ]] && { realpath "$path"; return 0; }
  done
  return 1
}

wordpress_list() {
  find /home -xdev -type f -name wp-config.php -path '*/public_html/*' -o -path '*/public_html/wp-config.php' 2>/dev/null | sed 's#/wp-config.php$##' | sort -u
}

wordpress_health() {
  local domain="${1:?domain}" root
  root=$(wordpress_docroot "$domain") || die "WordPress not found: $domain"
  wp --allow-root --path="$root" core verify-checksums
  wp --allow-root --path="$root" plugin status
  wp --allow-root --path="$root" option get siteurl
}

wordpress_permissions() {
  require_root
  local domain="${1:?domain}" root owner
  root=$(wordpress_docroot "$domain") || die "WordPress not found"
  owner=$(stat -c '%U:%G' "$root")
  info "Applying safe WordPress permissions root=$root owner=$owner"
  run find "$root" -xdev -type d -exec chmod 0755 {} +
  run find "$root" -xdev -type f -exec chmod 0644 {} +
  [[ -f "$root/wp-config.php" ]] && run chmod 0640 "$root/wp-config.php"
  run chown -R "$owner" "$root"
}

wordpress_clone() {
  require_root
  local source_domain="${1:?source}" target_domain="${2:?target}" source_root target_root
  source_root=$(wordpress_docroot "$source_domain") || die "Source not found"
  target_root=$(wordpress_docroot "$target_domain") || die "Create target website in CyberPanel first"
  [[ "$source_root" != "$target_root" ]] || die "Source and target are identical"
  confirm "Clone $source_domain to $target_domain and overwrite target files/database?" || die "Cancelled"
  "$TOOLKIT_ROOT/toolkitctl" backup run production || die "Pre-clone backup failed"
  local source_url target_url source_db target_db dump="$STATE_DIR/jobs/clone-$RUN_ID.sql"
  source_url=$(wp --allow-root --path="$source_root" option get home)
  target_url=$(wp --allow-root --path="$target_root" option get home)
  source_db=$(wp --allow-root --path="$source_root" config get DB_NAME)
  target_db=$(wp --allow-root --path="$target_root" config get DB_NAME)
  mariadb-dump --single-transaction "$source_db" >"$dump"
  rsync -aHAX --delete --exclude wp-config.php "$source_root/" "$target_root/"
  mariadb "$target_db" <"$dump"
  wp --allow-root --path="$target_root" search-replace "$source_url" "$target_url" --all-tables --precise --skip-columns=guid
  wp --allow-root --path="$target_root" option update blog_public 0
  wordpress_permissions "$target_domain"
  rm -f "$dump"
}

wordpress_staging() {
  local domain="${1:?domain}" staging="${2:-staging.$domain}"
  wordpress_clone "$domain" "$staging"
}
