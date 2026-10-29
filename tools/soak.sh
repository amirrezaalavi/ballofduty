#!/usr/bin/env bash
# Phase 1 C soak: 30 Hz authoritative server + real WebSocket clients + bots.
#
#   tools/soak.sh                  # 2-minute short run (4 clients + 4 bots)
#   tools/soak.sh --full           # 10-minute run (the Phase 1 gate)
#   tools/soak.sh --clients 8 --bots 4 --seconds 600
#
# Always uses an ephemeral 92xx port. Never touches the live 9180/8099 server.
# The server roster is capped by NetProtocol.MAX_PLAYERS (frozen). When clients
# + bots exceed the cap the runner prints SOAK_CAP and soaks the largest feasible
# mixed match; --require-full turns that into a failure once the cap is raised.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
GODOT="./tools/godot"
CLIENTS=4
BOTS=4
SECONDS_RUN=120
REQUIRE_FULL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) SECONDS_RUN=600; shift ;;
    --short) SECONDS_RUN=120; shift ;;
    --seconds) SECONDS_RUN="${2:?seconds required}"; shift 2 ;;
    --clients) CLIENTS="${2:?clients required}"; shift 2 ;;
    --bots) BOTS="${2:?bots required}"; shift 2 ;;
    --require-full) REQUIRE_FULL=1; shift ;;
    -h|--help)
      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

pick_port() {
  python3 - <<'PY'
import socket
import random
random.seed()
for _ in range(200):
    port = random.randrange(9200, 9300)
    s = socket.socket()
    try:
        s.bind(("127.0.0.1", port))
        s.close()
        print(port)
        raise SystemExit(0)
    except OSError:
        s.close()
raise SystemExit(1)
PY
}

PORT="$(pick_port)" || { echo "no free 92xx port" >&2; exit 1; }
LOG_DIR=".cache"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/soak-$PORT.log"
ARGS=(--seconds "$SECONDS_RUN" --clients "$CLIENTS" --bots "$BOTS" --port "$PORT")
[[ "$REQUIRE_FULL" == "1" ]] && ARGS+=(--require-full)

echo "soak: port=$PORT clients=$CLIENTS bots=$BOTS seconds=$SECONDS_RUN log=$LOG"
set +e
timeout $((SECONDS_RUN + 180)) "$GODOT" --headless --path . \
  --script tests/headless/soak_runner.gd -- "${ARGS[@]}" 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

echo
echo "soak: report"
grep '^SOAK' "$LOG" || true
echo
if [[ "$STATUS" -ne 0 ]]; then
  echo "soak: FAILED (exit $STATUS); full log: $LOG" >&2
  exit "$STATUS"
fi
echo "soak: PASS (full log: $LOG)"
