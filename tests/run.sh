#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
required=(README.md README.vi.md LICENSE VERSION install.sh uninstall.sh update.sh toolkitctl bin/dashboard-server lib/common.sh lib/core.sh lib/backup.sh lib/wordpress.sh lib/security.sh lib/mail.sh lib/ssl.sh lib/monitoring.sh lib/dashboard.sh dashboard/app.py)
for file in "${required[@]}"; do [[ -s "$ROOT/$file" ]] || { echo "MISSING $file"; fail=1; }; done
while IFS= read -r file; do bash -n "$file" || fail=1; done < <(find "$ROOT" -type f -name '*.sh' -o -name toolkitctl)
python3 -m py_compile "$ROOT/dashboard/app.py"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
CPT_CONFIG="$tmp/missing.env" TOOLKIT_ROOT="$ROOT" "$ROOT/toolkitctl" version | grep -Fx "$(<"$ROOT/VERSION")"
CPT_CONFIG="$tmp/missing.env" TOOLKIT_ROOT="$ROOT" "$ROOT/toolkitctl" help | grep -q 'CyberPanel Toolkit'
for function in backup_inventory backup_remote backup_schedule backup_unschedule backup_start backup_cancel backup_status backup_snapshots_json backup_export backup_export_start; do
  grep -q "^${function}()" "$ROOT/lib/backup.sh" || { echo "MISSING backup action: $function"; fail=1; }
done
if grep -RIE '(ghp_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|client_secret[[:space:]]*=[[:space:]]*[^<])' "$ROOT" --exclude-dir=.git --exclude=run.sh; then
  echo "Possible committed secret detected"; fail=1
fi
((fail == 0)) && echo "All tests passed"
exit "$fail"
