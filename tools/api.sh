#!/usr/bin/env bash
# Version-exact Godot API reference, generated from the running engine.
#
#   tools/api.sh                              # usage + class count
#   tools/api.sh WebSocketMultiplayerPeer     # print the class XML
#   tools/api.sh WebSocketMultiplayerPeer get_peer   # grep a member
#   tools/api.sh get_packet_peers             # search every class
#
# The cache lives in .cache/api (git-ignored). Generation takes a few seconds
# and needs an existing directory, which is why we create it first.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
CACHE="${BOD_API_CACHE:-.cache/api}"
GODOT="./tools/godot"

if [[ ! -d "$CACHE/doc/classes" ]]; then
  echo "generating API reference in $CACHE …" >&2
  mkdir -p "$CACHE"
  "$GODOT" --headless --doctool "$CACHE" >/dev/null 2>&1 || {
    echo "api: --doctool failed" >&2
    exit 1
  }
fi

if [[ $# -eq 0 ]]; then
  echo "usage: tools/api.sh <Class|pattern> [member]"
  echo "classes: $(find "$CACHE" -name '*.xml' | wc -l) · cache: $CACHE"
  exit 0
fi

if [[ $# -eq 1 ]]; then
  file=$(find "$CACHE" -name "$1.xml" | head -1)
  if [[ -n "$file" ]]; then
    cat "$file"
    exit 0
  fi
  grep -rn --include='*.xml' -i -- "$1" "$CACHE" | head -40
  exit 0
fi

file=$(find "$CACHE" -name "$1.xml" | head -1)
if [[ -z "$file" ]]; then
  echo "api: class not found: $1" >&2
  exit 1
fi
grep -n -i -- "$2" "$file"
