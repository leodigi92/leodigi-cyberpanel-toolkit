#!/usr/bin/env bash
set -Eeuo pipefail

backup_help() {
  cat <<'EOF'
toolkitctl backup configure
toolkitctl backup remote add|list|test NAME
toolkitctl backup run [PROFILE]
toolkitctl backup list [PROFILE]
toolkitctl backup check [PROFILE]
toolkitctl backup restore PROFILE SNAPSHOT TARGET
EOF
}

backup_install() {
  require_root
  package_install restic rclone mariadb-client 2>/dev/null || package_install restic rclone mariadb
  install -D -m 0644 "$TOOLKIT_ROOT/systemd/leodigi-cpt-backup.service" /etc/systemd/system/leodigi-cpt-backup.service
  install -D -m 0644 "$TOOLKIT_ROOT/systemd/leodigi-cpt-backup.timer" /etc/systemd/system/leodigi-cpt-backup.timer
  run systemctl daemon-reload
  run systemctl enable --now leodigi-cpt-backup.timer
  info "Backup module installed. Configure with: toolkitctl backup configure"
}

backup_configure() {
  require_root; ensure_layout
  local profile remote path password_file
  read -r -p "Profile name [production]: " profile; profile=${profile:-production}
  read -r -p "Rclone remote name or backend URL: " remote
  read -r -p "Repository path [CyberPanel-Backups/$(hostname -s)]: " path; path=${path:-CyberPanel-Backups/$(hostname -s)}
  password_file="$SECRETS_DIR/restic-${profile}.password"
  if [[ ! -s "$password_file" ]]; then
    umask 077
    tr -dc 'A-Za-z0-9_@%+=-' </dev/urandom | head -c 48 >"$password_file" || true
    printf '\n' >>"$password_file"
  fi
  local repository
  if [[ "$remote" == *:* ]]; then repository="$remote/$path"; else repository="rclone:${remote}:${path}"; fi
  cat >"$CONFIG_DIR/backup-${profile}.env" <<EOF
BACKUP_PROFILE=$profile
RESTIC_REPOSITORY=$repository
RESTIC_PASSWORD_FILE=$password_file
RCLONE_CONFIG=$SECRETS_DIR/rclone.conf
BACKUP_SOURCES=/home,/etc,/usr/local/lsws/conf,/usr/local/CyberCP
EOF
  chmod 0640 "$CONFIG_DIR/backup-${profile}.env"
  info "Profile saved: $profile. Run remote test, then initialize repository."
}

backup_remote() {
  local action="${1:-list}" name="${2:-}"
  install -d -m 0700 "$SECRETS_DIR"
  export RCLONE_CONFIG="$SECRETS_DIR/rclone.conf"
  case "$action" in
    add)
      cat <<'EOF'
Rclone connection wizard supports:
  drive     Google Drive / Shared Drive (use your own OAuth Client ID)
  onedrive  OneDrive Personal/Business and SharePoint document libraries
  s3        S3, MinIO, Wasabi and compatible providers
  sftp      Remote SSH/SFTP
On a headless VPS choose remote authorization and run `rclone authorize` on a PC.
Never paste tokens into issue trackers or commit rclone.conf to Git.
EOF
      rclone config
      chmod 0600 "$RCLONE_CONFIG"
      ;;
    list) rclone listremotes ;;
    test) [[ -n "$name" ]] || die "Remote name required"; rclone lsd "${name%:}:" --max-depth 1 ;;
    *) die "Usage: toolkitctl backup remote add|list|test NAME" ;;
  esac
}

backup_load_profile() {
  local profile file
  profile="${1:-production}"
  file="$CONFIG_DIR/backup-${profile}.env"
  [[ -r "$file" ]] || die "Backup profile not configured: $profile"
  source "$file"
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE RCLONE_CONFIG RESTIC_CACHE_DIR
  [[ -s "$RESTIC_PASSWORD_FILE" ]] || die "Restic password file missing"
}

backup_dump_databases() {
  local dump_dir="$1" db
  install -d -m 0700 "$dump_dir"
  command -v mariadb >/dev/null || return 0
  while IFS= read -r db; do
    [[ -n "$db" && "$db" != information_schema && "$db" != performance_schema && "$db" != mysql && "$db" != sys ]] || continue
    info "Dumping database: $db"
    mariadb-dump --single-transaction --routines --events --triggers --databases "$db" | gzip -c >"$dump_dir/$db.sql.gz"
  done < <(mariadb --batch --skip-column-names -e 'SHOW DATABASES' 2>/dev/null || true)
}

backup_run() {
  require_root; acquire_lock
  local profile="${1:-production}" stage="$STATE_DIR/jobs/backup-$RUN_ID"
  backup_load_profile "$profile"
  install -d -m 0700 "$stage/database"
  trap 'rm -rf "$stage"' RETURN
  backup_dump_databases "$stage/database"
  printf '{"run_id":"%s","hostname":"%s","created":"%s"}\n' "$RUN_ID" "$(hostname -f)" "$(date -u +%FT%TZ)" >"$stage/manifest.json"
  if ! restic snapshots --json >/dev/null 2>&1; then
    info "Initializing encrypted repository"
    restic init
  fi
  IFS=',' read -r -a sources <<<"${BACKUP_SOURCES:-/home,/etc}"
  restic backup "${sources[@]}" "$stage" --tag "profile:$profile" --tag cyberpanel --host "$(hostname -s)" --exclude-caches
  restic forget --prune --keep-daily "${BACKUP_RETENTION_DAILY:-7}" --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" --keep-monthly "${BACKUP_RETENTION_MONTHLY:-6}" --keep-yearly "${BACKUP_RETENTION_YEARLY:-1}"
  printf '%s\n' "$(date -u +%FT%TZ) profile=$profile status=PASS" >"$STATE_DIR/last-backup"
  info "Backup completed: $profile"
}

backup_list() { backup_load_profile "${1:-production}"; restic snapshots; }
backup_check() { backup_load_profile "${1:-production}"; restic check --read-data-subset="${RESTIC_CHECK_SUBSET:-5%}"; }

backup_restore() {
  require_root
  local profile="${1:?profile}" snapshot="${2:?snapshot}" target="${3:?target}"
  backup_load_profile "$profile"
  [[ "$target" == /* && "$target" != / ]] || die "Target must be an absolute non-root path"
  install -d -m 0700 "$target"
  confirm "Restore snapshot $snapshot into $target?" || die "Cancelled"
  restic restore "$snapshot" --target "$target"
  info "Files restored to $target. Database dumps are not auto-imported."
}

backup_replica() {
  local source_profile="${1:?source profile}" destination_profile="${2:?destination profile}"
  backup_load_profile "$source_profile"
  local from_repo=$RESTIC_REPOSITORY from_pass=$RESTIC_PASSWORD_FILE from_rclone=$RCLONE_CONFIG
  backup_load_profile "$destination_profile"
  restic copy --from-repo "$from_repo" --from-password-file "$from_pass" --repo "$RESTIC_REPOSITORY" --password-file "$RESTIC_PASSWORD_FILE"
}
