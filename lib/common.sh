#!/usr/bin/env bash
set -Eeuo pipefail

TOOLKIT_NAME="LeoDigi CyberPanel Toolkit"
TOOLKIT_VENDOR="LeoDigi"
TOOLKIT_WEBSITE="https://leodigi.dev"
TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEFAULT_CONFIG="${TOOLKIT_ROOT}/config/default.env"
CONFIG_FILE="${CPT_CONFIG:-/etc/leodigi-cyberpanel-toolkit/toolkit.env}"

[[ -r "$DEFAULT_CONFIG" ]] && source "$DEFAULT_CONFIG"
[[ -r "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

INSTALL_DIR="${INSTALL_DIR:-/opt/leodigi-cyberpanel-toolkit}"
CONFIG_DIR="${CONFIG_DIR:-/etc/leodigi-cyberpanel-toolkit}"
STATE_DIR="${STATE_DIR:-/var/lib/leodigi-cyberpanel-toolkit}"
LOG_DIR="${LOG_DIR:-/var/log/leodigi-cyberpanel-toolkit}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/leodigi-cyberpanel-toolkit}"
SECRETS_DIR="${SECRETS_DIR:-${CONFIG_DIR}/secrets}"
LOCK_FILE="${LOCK_FILE:-/run/lock/leodigi-cyberpanel-toolkit.lock}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/toolkit-${RUN_ID}.log}"
DRY_RUN="${DRY_RUN:-no}"

color() { [[ -t 2 ]] && printf '\033[%sm' "$1" || true; }
reset_color() { [[ -t 2 ]] && printf '\033[0m' || true; }
timestamp() { date '+%Y-%m-%d %H:%M:%S%z'; }

log() {
  local level="$1"; shift
  local line="[$(timestamp)] [$level] $*"
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s\n' "$line" | tee -a "$LOG_FILE" >&2
}
info() { log INFO "$*"; }
warn() { log WARN "$*"; }
error() { log ERROR "$*"; }
die() { error "$*"; exit 1; }

require_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root (sudo)."; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

run() {
  if [[ "$DRY_RUN" == yes || "${APPLY_CHANGES:-no}" != yes ]]; then
    info "DRY-RUN: $(printf '%q ' "$@")"
    return 0
  fi
  info "RUN: $(printf '%q ' "$@")"
  "$@"
}

confirm() {
  local prompt="$1"
  [[ "${ASSUME_YES:-no}" == yes ]] && return 0
  [[ -t 0 ]] || return 1
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

ensure_layout() {
  install -d -m 0750 "$CONFIG_DIR" "$STATE_DIR" "$LOG_DIR" "$BACKUP_DIR"
  install -d -m 0700 "$SECRETS_DIR"
  install -d -m 0750 "$STATE_DIR/reports" "$STATE_DIR/restore-points" "$STATE_DIR/jobs"
  install -d -m 0750 "${RESTIC_CACHE_DIR:-/var/cache/leodigi-cyberpanel-toolkit}"
}

acquire_lock() {
  require_command flock
  mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "Another toolkit process is running."
}

detect_os() {
  [[ -r /etc/os-release ]] || die "Cannot detect operating system."
  source /etc/os-release
  OS_ID="${ID,,}"
  OS_VERSION="${VERSION_ID:-unknown}"
  case "$OS_ID" in
    ubuntu) PKG_MANAGER=apt-get ;;
    almalinux|rocky|rhel) PKG_MANAGER=dnf ;;
    *) die "Unsupported OS: $OS_ID $OS_VERSION" ;;
  esac
  export OS_ID OS_VERSION PKG_MANAGER
}

package_install() {
  detect_os
  if [[ "$PKG_MANAGER" == apt-get ]]; then
    run apt-get update
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
  else
    run dnf install -y "$@"
  fi
}

service_exists() { systemctl list-unit-files "$1.service" --no-legend 2>/dev/null | grep -q "$1.service"; }
service_active() { systemctl is-active --quiet "$1"; }
safe_restart() {
  local service="$1" check_command="${2:-}"
  [[ -n "$check_command" ]] && bash -c "$check_command" || true
  run systemctl restart "$service"
  [[ "$DRY_RUN" == yes || "${APPLY_CHANGES:-no}" != yes ]] || service_active "$service" || die "$service failed after restart"
}

backup_file() {
  local source="$1" point="${2:-$RUN_ID}"
  [[ -e "$source" ]] || return 0
  local target="${STATE_DIR}/restore-points/${point}${source}"
  mkdir -p "$(dirname "$target")"
  cp -a "$source" "$target"
  info "Saved restore copy: $source"
}

atomic_write() {
  local target="$1" mode="${2:-0640}" tmp
  tmp="$(mktemp "${target##*/}.XXXXXX")"
  cat >"$tmp"
  install -D -m "$mode" "$tmp" "$target"
  rm -f "$tmp"
}

json_escape() {
  local s=${1//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; printf '%s' "$s"
}

on_error() {
  local code=$? line=${BASH_LINENO[0]:-unknown}
  error "Command failed at line $line (exit $code). See $LOG_FILE"
  exit "$code"
}
trap on_error ERR
