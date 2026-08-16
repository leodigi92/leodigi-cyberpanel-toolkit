#!/usr/bin/env bash
set -Eeuo pipefail

backup_help() {
  cat <<'EOF'
toolkitctl backup configure
toolkitctl backup configure-noninteractive PROFILE REMOTE PATH RETENTION_DAYS
toolkitctl backup configure-selection PROFILE all|selected SITE_ROOTS DATABASES
toolkitctl backup inventory
toolkitctl backup remote add|list|test NAME
toolkitctl backup remote dirs NAME [PATH]
toolkitctl backup schedule PROFILE daily|twice-daily|weekly|monthly|hourly [HH:MM]
toolkitctl backup unschedule PROFILE
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
  run systemctl disable --now leodigi-cpt-backup.timer
  info "Backup module installed. Configure a profile and schedule before enabling automatic backup."
}

backup_configure() {
  require_root; ensure_layout
  local profile remote path retention
  read -r -p "Profile name [production]: " profile; profile=${profile:-production}
  read -r -p "Rclone remote name or backend URL: " remote
  read -r -p "Repository path [CyberPanel-Backups/$(hostname -s)]: " path; path=${path:-CyberPanel-Backups/$(hostname -s)}
  read -r -p "Retention days, 0 = unlimited [30]: " retention; retention=${retention:-30}
  backup_configure_noninteractive "$profile" "$remote" "$path" "$retention"
}

backup_configure_noninteractive() {
  require_root; ensure_layout
  local profile="${1:?profile}" remote="${2:?remote}" path="${3:?path}" retention="${4:-30}" password_file
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid backup profile name"
  [[ "$remote" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || die "Invalid Rclone remote name"
  [[ "$retention" =~ ^[0-9]{1,5}$ ]] || die "Retention days must be 0-99999"
  ((retention <= 99999)) || die "Retention days must be 0-99999"
  [[ -n "$path" && "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *:* ]] || die "Invalid repository path"
  path="${path#/}"; path="${path%/}"
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
BACKUP_RETENTION_DAYS=$retention
BACKUP_SCOPE=all
BACKUP_SITE_ROOTS=
BACKUP_DATABASES=
EOF
  chmod 0640 "$CONFIG_DIR/backup-${profile}.env"
  info "Profile saved: $profile. Run remote test, then initialize repository."
}

backup_configure_selection() {
  require_root; ensure_layout
  local profile="${1:?profile}" scope="${2:?scope}" roots="${3:-}" databases="${4:-}" file
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid backup profile name"
  [[ "$scope" == all || "$scope" == selected ]] || die "Backup scope must be all or selected"
  file="$CONFIG_DIR/backup-${profile}.env"
  [[ -f "$file" ]] || die "Backup profile not configured: $profile"
  [[ "$roots" != *$'\n'* && "$roots" != *$'\r'* ]] || die "Invalid site roots"
  [[ "$databases" != *$'\n'* && "$databases" != *$'\r'* ]] || die "Invalid databases"
  local value root db normalized_roots="" normalized_databases=""
  if [[ "$scope" == selected ]]; then
    IFS=',' read -r -a values <<<"$roots"
    for value in "${values[@]}"; do
      root="${value%/}"
      [[ "$root" =~ ^/home/[A-Za-z0-9._-]+(/public_html)?$ ]] || die "Invalid website root: $root"
      [[ -d "$root" && ! -L "$root" ]] || die "Website root not found: $root"
      normalized_roots+="${normalized_roots:+,}$root"
    done
    [[ -n "$normalized_roots" ]] || die "Select at least one website"
    IFS=',' read -r -a values <<<"$databases"
    for value in "${values[@]}"; do
      db="$value"
      [[ "$db" =~ ^[A-Za-z0-9_$-]{1,64}$ ]] || die "Invalid database: $db"
      normalized_databases+="${normalized_databases:+,}$db"
    done
  fi
  sed -i '/^BACKUP_SCOPE=/d;/^BACKUP_SITE_ROOTS=/d;/^BACKUP_DATABASES=/d' "$file"
  cat >>"$file" <<EOF
BACKUP_SCOPE=$scope
BACKUP_SITE_ROOTS=$normalized_roots
BACKUP_DATABASES=$normalized_databases
EOF
  info "Backup selection saved: profile=$profile scope=$scope sites=${normalized_roots:-all} databases=${normalized_databases:-all}"
}

backup_inventory() {
  require_root
  local first=1 domain root owner db wp
  printf '{"sites":['
  for root in /home/*/public_html; do
    [[ -d "$root" && ! -L "$root" ]] || continue
    domain="$(basename "$(dirname "$root")")"
    [[ "$domain" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    owner="$(stat -c '%U' "$root" 2>/dev/null || printf unknown)"
    db=""
    wp="$root/wp-config.php"
    if [[ -r "$wp" ]]; then
      db="$(sed -nE "s/^[[:space:]]*define[[:space:]]*\([[:space:]]*['\"]DB_NAME['\"][[:space:]]*,[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "$wp" | head -n1)"
      [[ "$db" =~ ^[A-Za-z0-9_$-]{1,64}$ ]] || db=""
    fi
    ((first)) || printf ','; first=0
    printf '{"domain":"%s","owner":"%s","root":"%s","suggested_database":"%s"}' "$domain" "$owner" "$root" "$db"
  done
  printf '],"databases":['; first=1
  while IFS= read -r db; do
    [[ "$db" =~ ^[A-Za-z0-9_$-]{1,64}$ ]] || continue
    case "$db" in information_schema|performance_schema|mysql|sys) continue ;; esac
    ((first)) || printf ','; first=0; printf '"%s"' "$db"
  done < <(backup_mariadb --batch --skip-column-names -e 'SHOW DATABASES' 2>/dev/null || true)
  printf ']}\n'
}

backup_remote() {
  local action="${1:-list}" name="${2:-}" path="${3:-}"
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
    dirs)
      [[ "$name" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || die "Invalid remote name"
      [[ "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *:* ]] || die "Invalid remote path"
      rclone lsf "${name%:}:${path#/}" --dirs-only --max-depth 1
      ;;
    *) die "Usage: toolkitctl backup remote add|list|test|dirs NAME [PATH]" ;;
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

backup_mariadb() {
  if [[ -s /etc/cyberpanel/mysqlPassword ]]; then
    MYSQL_PWD="$(< /etc/cyberpanel/mysqlPassword)" mariadb -u root "$@"
  else
    mariadb "$@"
  fi
}

backup_mariadb_dump() {
  if [[ -s /etc/cyberpanel/mysqlPassword ]]; then
    MYSQL_PWD="$(< /etc/cyberpanel/mysqlPassword)" mariadb-dump -u root "$@"
  else
    mariadb-dump "$@"
  fi
}

backup_dump_databases() {
  local dump_dir="$1" selection="${2:-}" db
  install -d -m 0700 "$dump_dir"
  command -v mariadb >/dev/null || return 0
  while IFS= read -r db; do
    [[ -n "$db" && "$db" != information_schema && "$db" != performance_schema && "$db" != mysql && "$db" != sys ]] || continue
    info "Dumping database: $db"
    backup_mariadb_dump --single-transaction --routines --events --triggers --databases "$db" | gzip -c >"$dump_dir/$db.sql.gz"
  done < <(if [[ -n "$selection" ]]; then tr ',' '\n' <<<"$selection"; else backup_mariadb --batch --skip-column-names -e 'SHOW DATABASES' 2>/dev/null || true; fi)
}

backup_run() {
  require_root; acquire_lock
  local profile="${1:-production}" stage="$STATE_DIR/jobs/backup-$RUN_ID"
  backup_load_profile "$profile"
  install -d -m 0700 "$stage/database"
  trap 'rm -rf "$stage"' RETURN
  local scope="${BACKUP_SCOPE:-all}" selected_databases="${BACKUP_DATABASES:-}"
  backup_dump_databases "$stage/database" "$([[ "$scope" == selected ]] && printf %s "$selected_databases")"
  printf '{"run_id":"%s","hostname":"%s","created":"%s","scope":"%s","site_roots":"%s","databases":"%s"}\n' \
    "$RUN_ID" "$(hostname -f)" "$(date -u +%FT%TZ)" "$scope" "${BACKUP_SITE_ROOTS:-all}" "${BACKUP_DATABASES:-all}" >"$stage/manifest.json"
  if ! restic snapshots --json >/dev/null 2>&1; then
    info "Initializing encrypted repository"
    restic init
  fi
  if [[ "$scope" == selected ]]; then
    [[ -n "${BACKUP_SITE_ROOTS:-}" ]] || die "Selected backup has no website roots"
    IFS=',' read -r -a sources <<<"$BACKUP_SITE_ROOTS"
    sources+=(/etc /usr/local/lsws/conf /usr/local/CyberCP)
  else
    IFS=',' read -r -a sources <<<"${BACKUP_SOURCES:-/home,/etc}"
  fi
  restic backup "${sources[@]}" "$stage" --tag "profile:$profile" --tag cyberpanel --host "$(hostname -s)" --exclude-caches
  if [[ -n "${BACKUP_RETENTION_DAYS:-}" ]]; then
    if ((BACKUP_RETENTION_DAYS > 0)); then restic forget --prune --keep-within "${BACKUP_RETENTION_DAYS}d"; fi
  else
    restic forget --prune --keep-daily "${BACKUP_RETENTION_DAILY:-7}" --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" --keep-monthly "${BACKUP_RETENTION_MONTHLY:-6}" --keep-yearly "${BACKUP_RETENTION_YEARLY:-1}"
  fi
  printf '%s\n' "$(date -u +%FT%TZ) profile=$profile status=PASS" >"$STATE_DIR/last-backup"
  info "Backup completed: $profile"
}

backup_list() { backup_load_profile "${1:-production}"; restic snapshots; }
backup_check() { backup_load_profile "${1:-production}"; restic check --read-data-subset="${RESTIC_CHECK_SUBSET:-5%}"; }

backup_schedule() {
  require_root
  local profile="${1:?profile}" frequency="${2:?frequency}" at="${3:-02:30}" calendar service timer second_hour
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid profile"
  [[ "$at" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || die "Time must be HH:MM"
  case "$frequency" in
    hourly) calendar="hourly" ;;
    daily) calendar="*-*-* ${at}:00" ;;
    twice-daily)
      second_hour=$(((10#${at%%:*} + 12) % 24))
      printf -v second_hour '%02d' "$second_hour"
      calendar="*-*-* ${at%%:*},${second_hour}:${at##*:}:00"
      ;;
    weekly) calendar="Mon *-*-* ${at}:00" ;;
    monthly) calendar="*-*-01 ${at}:00" ;;
    *) die "Frequency must be hourly, daily, twice-daily, weekly or monthly" ;;
  esac
  service="/etc/systemd/system/leodigi-cpt-backup-${profile}.service"
  timer="/etc/systemd/system/leodigi-cpt-backup-${profile}.timer"
  cat >"$service" <<EOF
[Unit]
Description=LeoDigi CyberPanel Toolkit backup ($profile)
After=network-online.target mariadb.service
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/toolkitctl backup run $profile
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF
  cat >"$timer" <<EOF
[Unit]
Description=LeoDigi backup schedule ($profile)
[Timer]
OnCalendar=$calendar
RandomizedDelaySec=10m
Persistent=true
[Install]
WantedBy=timers.target
EOF
  chmod 0644 "$service" "$timer"
  systemctl daemon-reload
  systemctl enable --now "leodigi-cpt-backup-${profile}.timer"
  info "Schedule saved: profile=$profile frequency=$frequency calendar=$calendar"
}

backup_unschedule() {
  require_root
  local profile="${1:?profile}"
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid profile"
  systemctl disable --now "leodigi-cpt-backup-${profile}.timer" 2>/dev/null || true
  rm -f "/etc/systemd/system/leodigi-cpt-backup-${profile}.timer" "/etc/systemd/system/leodigi-cpt-backup-${profile}.service"
  systemctl daemon-reload
  info "Schedule removed: $profile (backup profile and repository were preserved)"
}

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
