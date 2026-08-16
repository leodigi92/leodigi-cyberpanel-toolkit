#!/usr/bin/env bash
set -Eeuo pipefail

# Backup CLI contract v1.5.1: keep Dashboard actions and toolkitctl dispatch in sync.

backup_help() {
  cat <<'EOF'
toolkitctl backup configure
toolkitctl backup configure-noninteractive PROFILE REMOTE PATH RETENTION_DAYS [archive|restic]
toolkitctl backup configure-selection PROFILE all|selected SITE_ROOTS DATABASES
toolkitctl backup inventory
toolkitctl backup remote add|list|test NAME
toolkitctl backup remote dirs NAME [PATH]
toolkitctl backup schedule PROFILE daily|twice-daily|weekly|monthly|hourly [HH:MM]
toolkitctl backup unschedule PROFILE
toolkitctl backup run [PROFILE]
toolkitctl backup start|cancel|status [PROFILE]
toolkitctl backup list [PROFILE]
toolkitctl backup snapshots-json [PROFILE]
toolkitctl backup archives-json [PROFILE]
toolkitctl backup check [PROFILE]
toolkitctl backup restore PROFILE SNAPSHOT TARGET
toolkitctl backup export PROFILE SNAPSHOT
toolkitctl backup export-start PROFILE SNAPSHOT
EOF
}

backup_install() {
  require_root
  package_install restic rclone zip mariadb-client 2>/dev/null || package_install restic rclone zip mariadb
  install -D -m 0644 "$TOOLKIT_ROOT/systemd/leodigi-cpt-backup.service" /etc/systemd/system/leodigi-cpt-backup.service
  install -D -m 0644 "$TOOLKIT_ROOT/systemd/leodigi-cpt-backup.timer" /etc/systemd/system/leodigi-cpt-backup.timer
  run systemctl daemon-reload
  run systemctl disable --now leodigi-cpt-backup.timer
  info "Backup module installed. Configure a profile and schedule before enabling automatic backup."
}

backup_configure() {
  require_root; ensure_layout
  local profile remote path retention format
  read -r -p "Profile name [production]: " profile; profile=${profile:-production}
  read -r -p "Rclone remote name or backend URL: " remote
  read -r -p "Repository path [CyberPanel-Backups/$(hostname -s)]: " path; path=${path:-CyberPanel-Backups/$(hostname -s)}
  read -r -p "Retention days, 0 = unlimited [30]: " retention; retention=${retention:-30}
  read -r -p "Backup format, archive or restic [archive]: " format; format=${format:-archive}
  backup_configure_noninteractive "$profile" "$remote" "$path" "$retention" "$format"
}

backup_configure_noninteractive() {
  require_root; ensure_layout
  local profile="${1:?profile}" remote="${2:?remote}" path="${3:?path}" retention="${4:-30}" format="${5:-archive}" password_file
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid backup profile name"
  [[ "$remote" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || die "Invalid Rclone remote name"
  [[ "$retention" =~ ^[0-9]{1,5}$ ]] || die "Retention days must be 0-99999"
  ((retention <= 99999)) || die "Retention days must be 0-99999"
  [[ "$format" == archive || "$format" == restic ]] || die "Backup format must be archive or restic"
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
BACKUP_FORMAT=$format
BACKUP_REMOTE=$remote
BACKUP_REMOTE_PATH=$path
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
  info "Profile saved: $profile format=$format. Run remote test before the first backup."
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
  BACKUP_FORMAT="${BACKUP_FORMAT:-restic}"
  export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE RCLONE_CONFIG RESTIC_CACHE_DIR BACKUP_FORMAT BACKUP_REMOTE BACKUP_REMOTE_PATH
  if [[ "$BACKUP_FORMAT" == restic ]]; then
    [[ -s "$RESTIC_PASSWORD_FILE" ]] || die "Restic password file missing"
  fi
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

backup_job_dir() { printf '%s/backup-jobs' "$STATE_DIR"; }

backup_job_state() {
  local profile="$1" status="$2" phase="$3" message="${4:-}" dir tmp
  dir="$(backup_job_dir)"; install -d -m 0750 "$dir"
  tmp="$dir/${profile}.state.json.tmp"
  PROFILE="$profile" STATUS="$status" PHASE="$phase" MESSAGE="$message" PID_VALUE="$$" \
    python3 - "$tmp" <<'PY'
import json, os, sys
from datetime import datetime, timezone
data = {"profile": os.environ["PROFILE"], "status": os.environ["STATUS"],
        "phase": os.environ["PHASE"], "message": os.environ.get("MESSAGE", ""),
        "pid": int(os.environ["PID_VALUE"]), "updated": datetime.now(timezone.utc).isoformat()}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False)
PY
  mv -f "$tmp" "$dir/${profile}.state.json"
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

backup_archive_progress() {
  local progress="$1" done="$2" total="$3" bytes="$4" current="${5:-}" percent
  percent="$(awk -v done="$done" -v total="$total" 'BEGIN { if (total < 1) print 0; else printf "%.6f", done / total }')"
  printf '{"message_type":"status","percent_done":%s,"files_done":%s,"total_files":%s,"bytes_done":%s,"current_files":["%s"]}\n' \
    "$percent" "$done" "$total" "$bytes" "${current//\"/}" >>"$progress"
}

backup_archive_upload() {
  local local_file="$1" remote_file="$2" bytes
  bytes="$(stat -c '%s' "$local_file")"
  sha256sum "$local_file" >"${local_file}.sha256"
  rclone copyto "$local_file" "$remote_file" --config "$RCLONE_CONFIG" --retries 3 --low-level-retries 10
  rclone copyto "${local_file}.sha256" "${remote_file}.sha256" --config "$RCLONE_CONFIG" --retries 3 --low-level-retries 10
  rm -f "$local_file" "${local_file}.sha256"
  printf '%s' "$bytes"
}

backup_run_archive() {
  local profile="$1" stage="$STATE_DIR/jobs/archive-$RUN_ID" job_dir progress scope selected_databases
  local remote path archive_root batch remote_batch root name artifact db item_bytes total_bytes=0 done=0 total=1 success=no
  local -a site_roots databases
  job_dir="$(backup_job_dir)"; install -d -m 0750 "$job_dir"
  progress="$job_dir/${profile}.progress.ndjson"; : >"$progress"
  install -d -m 0700 "$stage/websites" "$stage/databases"
  trap 'rc=$?; if [[ "$success" == yes ]]; then rm -rf "$stage"; else backup_job_state "$profile" failed failed "Archive backup thất bại; dữ liệu tạm còn tại $stage"; fi; exit "$rc"' EXIT
  remote="${BACKUP_REMOTE:-}"; path="${BACKUP_REMOTE_PATH:-}"
  if [[ -z "$remote" && "${RESTIC_REPOSITORY:-}" == rclone:* ]]; then
    remote="${RESTIC_REPOSITORY#rclone:}"; path="${remote#*:}"; remote="${remote%%:*}"
  fi
  [[ "$remote" =~ ^[A-Za-z0-9._-]{1,128}$ ]] || die "Archive profile has no valid Rclone remote"
  path="${path#/}"; path="${path%/}"
  archive_root="${path:+$path/}archives/$(hostname -s)/$profile"
  batch="$(date -u +%Y-%m-%d_%H-%M-%S)-${RUN_ID##*-}"
  remote_batch="${remote}:${archive_root}/${batch}"
  scope="${BACKUP_SCOPE:-all}"; selected_databases="${BACKUP_DATABASES:-}"
  if [[ "$scope" == selected ]]; then
    IFS=',' read -r -a site_roots <<<"${BACKUP_SITE_ROOTS:-}"
    IFS=',' read -r -a databases <<<"$selected_databases"
  else
    for root in /home/*/public_html; do [[ -d "$root" && ! -L "$root" ]] && site_roots+=("$root"); done
    while IFS= read -r db; do
      case "$db" in ""|information_schema|performance_schema|mysql|sys) continue ;; esac
      databases+=("$db")
    done < <(backup_mariadb --batch --skip-column-names -e 'SHOW DATABASES')
  fi
  total=$((${#site_roots[@]} + ${#databases[@]} + 1))
  backup_job_state "$profile" running archive "Đang nén website thành ZIP"
  backup_archive_progress "$progress" 0 "$total" 0 "preparing"
  for root in "${site_roots[@]}"; do
    [[ -d "$root" && ! -L "$root" ]] || die "Website root not found: $root"
    name="$(basename "$(dirname "$root")")"; [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid website name: $name"
    artifact="$stage/websites/${name}.zip"
    backup_job_state "$profile" running archive "Đang nén website: $name"
    (cd "$root" && zip -q -r -y "$artifact" .)
    backup_job_state "$profile" running upload "Đang tải website lên Drive: ${name}.zip"
    item_bytes="$(backup_archive_upload "$artifact" "$remote_batch/websites/${name}.zip")"
    total_bytes=$((total_bytes + item_bytes)); done=$((done + 1))
    backup_archive_progress "$progress" "$done" "$total" "$total_bytes" "websites/${name}.zip"
  done
  for db in "${databases[@]}"; do
    [[ "$db" =~ ^[A-Za-z0-9_$-]{1,64}$ ]] || die "Invalid database: $db"
    artifact="$stage/databases/${db}.sql.gz"
    backup_job_state "$profile" running database "Đang xuất database: $db"
    backup_mariadb_dump --single-transaction --routines --events --triggers --databases "$db" | gzip -c >"$artifact"
    backup_job_state "$profile" running upload "Đang tải database lên Drive: ${db}.sql.gz"
    item_bytes="$(backup_archive_upload "$artifact" "$remote_batch/databases/${db}.sql.gz")"
    total_bytes=$((total_bytes + item_bytes)); done=$((done + 1))
    backup_archive_progress "$progress" "$done" "$total" "$total_bytes" "databases/${db}.sql.gz"
  done
  printf '{"profile":"%s","format":"archive","hostname":"%s","created":"%s","scope":"%s","websites":%s,"databases":%s}\n' \
    "$profile" "$(hostname -f)" "$(date -u +%FT%TZ)" "$scope" "${#site_roots[@]}" "${#databases[@]}" >"$stage/manifest.json"
  item_bytes="$(backup_archive_upload "$stage/manifest.json" "$remote_batch/manifest.json")"
  total_bytes=$((total_bytes + item_bytes)); done=$((done + 1))
  printf '%s\n' "completed $(date -u +%FT%TZ)" >"$stage/_SUCCESS"
  rclone copyto "$stage/_SUCCESS" "$remote_batch/_SUCCESS" --config "$RCLONE_CONFIG" --retries 3
  rm -f "$stage/_SUCCESS"
  backup_archive_progress "$progress" "$done" "$total" "$total_bytes" "_SUCCESS"
  if [[ "${BACKUP_RETENTION_DAYS:-0}" =~ ^[0-9]+$ ]] && ((BACKUP_RETENTION_DAYS > 0)); then
    backup_job_state "$profile" running retention "Đang dọn archive cũ trên Drive"
    rclone delete "${remote}:${archive_root}" --config "$RCLONE_CONFIG" --min-age "${BACKUP_RETENTION_DAYS}d" --retries 3
    rclone rmdirs "${remote}:${archive_root}" --config "$RCLONE_CONFIG" --leave-root 2>/dev/null || true
  fi
  printf '%s\n' "$(date -u +%FT%TZ) profile=$profile format=archive status=PASS remote=$remote_batch" >"$STATE_DIR/last-backup"
  backup_job_state "$profile" completed completed "Backup ZIP + SQL hoàn tất: $remote_batch"
  success=yes
  info "Archive backup completed: $remote_batch"
}

backup_run_restic() {
  local profile="${1:-production}" stage="$STATE_DIR/jobs/backup-$RUN_ID" job_dir progress rc=0
  job_dir="$(backup_job_dir)"; install -d -m 0750 "$job_dir"
  progress="$job_dir/${profile}.progress.ndjson"; : >"$progress"
  backup_job_state "$profile" running preparing "Đang chuẩn bị backup"
  install -d -m 0700 "$stage/database"
  trap 'exit_code=$?; rm -rf "$stage"; if ((exit_code != 0)); then backup_job_state "$profile" failed failed "Backup dừng hoặc thất bại (exit $exit_code)"; fi' EXIT
  local scope="${BACKUP_SCOPE:-all}" selected_databases="${BACKUP_DATABASES:-}"
  backup_job_state "$profile" running database "Đang dump database"
  backup_dump_databases "$stage/database" "$([[ "$scope" == selected ]] && printf %s "$selected_databases")"
  printf '{"run_id":"%s","hostname":"%s","created":"%s","scope":"%s","site_roots":"%s","databases":"%s"}\n' \
    "$RUN_ID" "$(hostname -f)" "$(date -u +%FT%TZ)" "$scope" "${BACKUP_SITE_ROOTS:-all}" "${BACKUP_DATABASES:-all}" >"$stage/manifest.json"
  if ! restic snapshots --json >/dev/null 2>&1; then
    backup_job_state "$profile" running initialize "Đang khởi tạo repository mã hóa"
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
  backup_job_state "$profile" running upload "Đang mã hóa và tải dữ liệu lên cloud"
  set +e
  restic backup "${sources[@]}" "$stage" --tag "profile:$profile" --tag cyberpanel --host "$(hostname -s)" --exclude-caches --json 2>&1 | tee -a "$progress"
  rc=${PIPESTATUS[0]}
  set -e
  ((rc == 0)) || return "$rc"
  backup_job_state "$profile" running retention "Đang áp dụng chính sách lưu trữ"
  if [[ -n "${BACKUP_RETENTION_DAYS:-}" ]]; then
    if ((BACKUP_RETENTION_DAYS > 0)); then restic forget --prune --keep-within "${BACKUP_RETENTION_DAYS}d"; fi
  else
    restic forget --prune --keep-daily "${BACKUP_RETENTION_DAILY:-7}" --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" --keep-monthly "${BACKUP_RETENTION_MONTHLY:-6}" --keep-yearly "${BACKUP_RETENTION_YEARLY:-1}"
  fi
  printf '%s\n' "$(date -u +%FT%TZ) profile=$profile status=PASS" >"$STATE_DIR/last-backup"
  backup_job_state "$profile" completed completed "Backup hoàn tất"
  info "Backup completed: $profile"
}

backup_run() {
  require_root; acquire_lock
  local profile="${1:-production}"
  backup_load_profile "$profile"
  if [[ "$BACKUP_FORMAT" == archive ]]; then backup_run_archive "$profile"; else backup_run_restic "$profile"; fi
}

backup_archive_location() {
  local remote="${BACKUP_REMOTE:-}" path="${BACKUP_REMOTE_PATH:-}" value
  if [[ -z "$remote" && "${RESTIC_REPOSITORY:-}" == rclone:* ]]; then
    value="${RESTIC_REPOSITORY#rclone:}"; remote="${value%%:*}"; path="${value#*:}"
  fi
  printf '%s:%sarchives/%s/%s' "$remote" "${path:+${path%/}/}" "$(hostname -s)" "$BACKUP_PROFILE"
}

backup_archives_json() {
  backup_load_profile "${1:-production}"
  local location; location="$(backup_archive_location)"
  LOCATION="$location" RCLONE_CONFIG="$RCLONE_CONFIG" python3 - <<'PY'
import json, os, subprocess
p = subprocess.run(["rclone", "lsf", os.environ["LOCATION"], "--config", os.environ["RCLONE_CONFIG"],
                    "--dirs-only", "--max-depth", "1"], text=True, capture_output=True)
if p.returncode: raise SystemExit(p.returncode)
items=[]
for raw in p.stdout.splitlines():
    name=raw.rstrip("/")
    if name: items.append({"id":name,"short_id":name,"time":name,"hostname":"archive","paths":["websites/*.zip", "databases/*.sql.gz"]})
print(json.dumps(items, ensure_ascii=False))
PY
}

backup_list() {
  backup_load_profile "${1:-production}"
  if [[ "$BACKUP_FORMAT" == archive ]]; then rclone lsf "$(backup_archive_location)" --config "$RCLONE_CONFIG" --dirs-only; else restic snapshots; fi
}
backup_snapshots_json() {
  backup_load_profile "${1:-production}"
  if [[ "$BACKUP_FORMAT" == archive ]]; then backup_archives_json "$BACKUP_PROFILE"; else restic snapshots --json 2>/dev/null; fi
}
backup_check() {
  backup_load_profile "${1:-production}"
  if [[ "$BACKUP_FORMAT" == archive ]]; then
    local location latest
    location="$(backup_archive_location)"
    latest="$(rclone lsf "$location" --config "$RCLONE_CONFIG" --dirs-only | sort | tail -n1)"
    [[ -n "$latest" ]] || die "No archive backup found"
    rclone lsf "$location/${latest%/}/_SUCCESS" --config "$RCLONE_CONFIG" >/dev/null
    info "Latest archive is complete: ${latest%/}"
  else
    restic check --read-data-subset="${RESTIC_CHECK_SUBSET:-5%}"
  fi
}

backup_start() {
  require_root
  local profile="${1:-production}" unit="leodigi-cpt-backup-now-${1:-production}"
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid profile"
  backup_load_profile "$profile"
  if systemctl is-active --quiet "$unit.service" || systemctl is-active --quiet "leodigi-cpt-backup-${profile}.service"; then
    die "Backup is already running: $profile"
  fi
  backup_job_state "$profile" queued queued "Đang chờ systemd khởi chạy"
  systemd-run --unit="$unit" --collect --no-block --property=Nice=10 \
    --property=IOSchedulingClass=best-effort --property=IOSchedulingPriority=7 \
    /usr/local/sbin/toolkitctl backup run "$profile"
  info "Backup queued in background: $profile"
}

backup_cancel() {
  require_root
  local profile="${1:-production}" stopped=0
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid profile"
  for unit in "leodigi-cpt-backup-now-${profile}.service" "leodigi-cpt-backup-${profile}.service"; do
    if systemctl is-active --quiet "$unit"; then systemctl stop "$unit"; stopped=1; fi
  done
  ((stopped)) || die "No running backup for profile: $profile"
  backup_job_state "$profile" cancelled cancelled "Backup đã được dừng theo yêu cầu"
}

backup_status() {
  local profile="${1:-production}" dir state progress
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid profile"
  dir="$(backup_job_dir)"; state="$dir/${profile}.state.json"; progress="$dir/${profile}.progress.ndjson"
  PROFILE="$profile" STATE_FILE="$state" PROGRESS_FILE="$progress" python3 - <<'PY'
import json, os
state = {"profile": os.environ["PROFILE"], "status": "idle", "phase": "idle", "message": "Chưa chạy"}
try:
    with open(os.environ["STATE_FILE"], encoding="utf-8") as f: state.update(json.load(f))
except (OSError, ValueError): pass
last = None
try:
    with open(os.environ["PROGRESS_FILE"], encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                item=json.loads(line)
                if item.get("message_type") in ("status", "summary"): last=item
            except ValueError: pass
except OSError: pass
if last: state["progress"] = last
print(json.dumps(state, ensure_ascii=False))
PY
}

backup_export() {
  require_root
  local profile="${1:?profile}" snapshot="${2:?snapshot}" export_dir archive estimated available required
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid profile"
  [[ "$snapshot" =~ ^[A-Fa-f0-9]{6,64}$ || "$snapshot" == latest ]] || die "Invalid snapshot"
  backup_load_profile "$profile"
  export_dir="$STATE_DIR/exports/${profile}-${snapshot}"
  archive="$STATE_DIR/exports/${profile}-${snapshot}.tar.gz"
  install -d -m 0750 "$STATE_DIR/exports"
  find "$STATE_DIR/exports" -maxdepth 1 -type f -name '*.tar.gz' -mmin +1440 -delete
  rm -rf "$export_dir"; rm -f "$archive"
  estimated="$(restic stats "$snapshot" --mode raw-data --json 2>/dev/null | python3 -c 'import json,sys; print(int(json.load(sys.stdin).get("total_size",0)))')"
  available="$(df -PB1 "$STATE_DIR" | awk 'NR==2 {print $4}')"
  required=$((estimated * 2 + 1073741824))
  ((available >= required)) || die "Not enough disk for export: need $required bytes, available $available bytes"
  backup_job_state "$profile" running restore "Đang khôi phục snapshot vào vùng tạm"
  restic restore "$snapshot" --target "$export_dir"
  backup_job_state "$profile" running archive "Đang đóng gói file tải xuống"
  tar -C "$export_dir" -czf "$archive" .
  rm -rf "$export_dir"; chmod 0640 "$archive"
  backup_job_state "$profile" completed export "Đã tạo gói tải xuống: $(basename "$archive")"
  printf '%s\n' "$archive"
}

backup_export_start() {
  require_root
  local profile="${1:?profile}" snapshot="${2:?snapshot}" unit
  [[ "$profile" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "Invalid profile"
  [[ "$snapshot" =~ ^[A-Fa-f0-9]{6,64}$ || "$snapshot" == latest ]] || die "Invalid snapshot"
  unit="leodigi-cpt-export-${profile}-${snapshot:0:12}"
  systemctl is-active --quiet "$unit.service" && die "Export is already running"
  systemd-run --unit="$unit" --collect --no-block /usr/local/sbin/toolkitctl backup export "$profile" "$snapshot"
  info "Snapshot export queued: profile=$profile snapshot=$snapshot"
}

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
