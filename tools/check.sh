#!/usr/bin/env bash
# Full local pipeline check. Fails on any error.
# Usage: tools/check.sh [--skip-export]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
GODOT="./tools/godot"
SKIP_EXPORT=0
[[ "${1:-}" == "--skip-export" ]] && SKIP_EXPORT=1

log() { echo -e "\n\033[1;36m== $* ==\033[0m"; }

log "Engine"
"$GODOT" --version

log "Import"
"$GODOT" --headless --path . --import >/tmp/bod_import.log 2>&1 || {
  cat /tmp/bod_import.log
  exit 1
}
if grep -E "ERROR|SCRIPT ERROR|Parse Error" /tmp/bod_import.log; then
  echo "Import produced errors" >&2
  exit 1
fi

log "Headless client boot"
"$GODOT" --headless --path . --quit-after 5 2>&1 | tee /tmp/bod_client.log
! grep -E "ERROR|SCRIPT ERROR|Parse Error" /tmp/bod_client.log

log "Headless server boot"
"$GODOT" --headless --path . --quit-after 5 -- --server --port 9123 2>&1 | tee /tmp/bod_server.log
grep -q "BALL_OF_DUTY server" /tmp/bod_server.log
! grep -E "ERROR|SCRIPT ERROR|Parse Error" /tmp/bod_server.log

if [[ "$SKIP_EXPORT" == "1" ]]; then
  log "Exports skipped"
  exit 0
fi

TEMPLATES="${HOME}/.local/share/godot/export_templates/4.7.2.stable"
if [[ ! -d "$TEMPLATES" ]]; then
  echo "Export templates missing: $TEMPLATES" >&2
  echo "Install the 4.7.2 export templates before running exports." >&2
  exit 1
fi

log "Web export"
rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path . --export-release "Web" build/web/index.html 2>&1 | tee /tmp/bod_web.log
[[ -f build/web/index.html && -f build/web/index.wasm ]]

log "Linux server export"
rm -rf build/server && mkdir -p build/server
"$GODOT" --headless --path . --export-release "Linux Server" build/server/ballofduty-server.x86_64 2>&1 | tee /tmp/bod_server_export.log
[[ -x build/server/ballofduty-server.x86_64 ]]

log "Payload size (gzip)"
RAW=$(du -sk build/web | cut -f1)
GZ=$(find build/web -type f -print0 | xargs -0 gzip -c 2>/dev/null | wc -c)
echo "web raw: ${RAW} KB · gzip: $((GZ / 1024)) KB"

log "Server build smoke test"
timeout 10 build/server/ballofduty-server.x86_64 --headless --quit-after 5 -- --server --port 9124 2>&1 | tee /tmp/bod_server_bin.log
grep -q "BALL_OF_DUTY server" /tmp/bod_server_bin.log

log "OK"
