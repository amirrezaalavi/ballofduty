#!/usr/bin/env bash
# Fast parse/type gate for edited GDScript files: ~2 s per file instead of a
# full import. Exits non-zero on the first script that fails to parse.
#
#   tools/gdcheck.sh scripts/game/game_manager.gd
#   tools/gdcheck.sh                 # every changed/untracked .gd file
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
GODOT="./tools/godot"

files=("$@")
if [[ ${#files[@]} -eq 0 ]]; then
  mapfile -t files < <(
    { git diff --name-only --diff-filter=ACMR HEAD -- '*.gd'
      git ls-files --others --exclude-standard -- '*.gd'
    } | sort -u
  )
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "gdcheck: no changed .gd files"
  exit 0
fi

failed=0
for file in "${files[@]}"; do
  rel="${file#./}"
  rel="${rel#res://}"
  case "$rel" in
    addons/*) continue ;;
  esac
  output=$("$GODOT" --headless --path . --check-only --script "res://$rel" 2>&1) || {
    echo "FAIL $rel" >&2
    echo "$output" | grep -vE '^Godot Engine|^$' >&2
    failed=1
    continue
  }
  echo "ok   $rel"
done

exit "$failed"
