#!/usr/bin/env bash
# Deterministic screenshot of the web build, written into the repo (the
# Playwright MCP writes relative to its own cwd, which is not the project).
#
#   tools/capture.sh "http://127.0.0.1:8080/?join=1&host=127.0.0.1&port=9180&name=Shot" docs/development/evidence/shot.png
#   tools/capture.sh <url> <out.png> [wait_ms]
#
# Start the build with tools/dev.sh up first.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
URL="${1:?usage: tools/capture.sh <url> <out.png> [wait_ms]}"
OUT="${2:?usage: tools/capture.sh <url> <out.png> [wait_ms]}"
WAIT_MS="${3:-4000}"

# The sandbox keeps Playwright browsers outside the default cache.
if [[ -d /srv/opencode/pkg/playwright ]]; then
  export PLAYWRIGHT_BROWSERS_PATH=/srv/opencode/pkg/playwright
fi

mkdir -p "$(dirname "$OUT")"
npx --yes playwright screenshot \
  --viewport-size="1280,720" \
  --wait-for-timeout="$WAIT_MS" \
  "$URL" "$OUT"
echo "captured $OUT"
