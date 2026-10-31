#!/usr/bin/env bash
# Serve the exported web build with correct MIME types (Python 3.11+ serves
# application/wasm). Production uses precompressed Brotli + WSS behind Caddy.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
PORT="${1:-8080}"
DIR="$PWD/build/web"

if [[ ! -f "$DIR/index.html" ]]; then
  echo "Web build missing. Run tools/check.sh first." >&2
  exit 1
fi

echo "Ball of Duty web build: http://127.0.0.1:${PORT}/"
cd "$DIR"
exec python3 -m http.server "$PORT" --bind 127.0.0.1
