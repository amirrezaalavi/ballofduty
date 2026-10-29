#!/usr/bin/env bash
# Local server + web build supervisor with pidfiles, so tests never kill the
# wrong process again.
#
#   tools/dev.sh up        # server :9180 + one-origin web proxy :8099
#   tools/dev.sh down      # stop both
#   tools/dev.sh status    # show listeners and log tails
#
# Only the web port needs forwarding: tools/serve.py serves build/web and
# tunnels the browser's /ws upgrade to the game server on SERVER_PORT.
# Override ports with SERVER_PORT / WEB_PORT (agents: use ephemeral 92xx/82xx).
# Logs: .cache/server.log, .cache/web.log.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
SERVER_PORT="${SERVER_PORT:-9180}"
WEB_PORT="${WEB_PORT:-8099}"
WEB_BIND="${WEB_BIND:-127.0.0.1}"
WS_PATH="${WS_PATH:-/ws}"
PID_DIR=".cache/pids"
LOG_DIR=".cache"
SERVER_PID="$PID_DIR/server.pid"
WEB_PID="$PID_DIR/web.pid"
mkdir -p "$PID_DIR" "$LOG_DIR"

pid_of_port() {
  # `|| true` keeps `set -e` happy when the port is free (grep exits 1).
  ss -ltnp 2>/dev/null \
    | grep -E "[:.]$1 " \
    | sed -n 's/.*pid=\([0-9]*\).*/\1/p' \
    | head -1 || true
  return 0
}

running() {
  local pid_file="$1"
  [[ -f "$pid_file" ]] || return 1
  local pid
  pid=$(cat "$pid_file")
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

# Refuse to start on a port held by a process we do not own; otherwise the new
# process dies and the pidfile silently points at nothing.
check_port() {
  local name="$1" port="$2" pid_file="$3"
  local holder
  holder=$(pid_of_port "$port")
  [[ -z "$holder" ]] && return 0
  if running "$pid_file" && [[ "$holder" == "$(cat "$pid_file")" ]]; then
    return 0
  fi
  echo "$name: port $port is already in use by pid $holder (not started by dev.sh)" >&2
  return 1
}

wait_ready() {
  local name="$1" port="$2" pid_file="$3" log="$4"
  for _ in $(seq 1 50); do
    if [[ -n "$(pid_of_port "$port")" ]]; then
      echo "$name: up on :$port (pid $(cat "$pid_file"))"
      return 0
    fi
    if ! running "$pid_file"; then
      break
    fi
    sleep 0.1
  done
  echo "$name: failed to start; last log lines:" >&2
  tail -5 "$log" >&2 || true
  return 1
}

stop_one() {
  local name="$1" pid_file="$2"
  if running "$pid_file"; then
    local pid
    pid=$(cat "$pid_file")
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 30); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -9 "$pid" 2>/dev/null || true
    echo "stopped $name (pid $pid)"
  else
    echo "$name not running"
  fi
  rm -f "$pid_file"
}

start_server() {
  check_port server "$SERVER_PORT" "$SERVER_PID"
  if running "$SERVER_PID"; then
    echo "server already running (pid $(cat "$SERVER_PID"))"
    return
  fi
  ./tools/godot --headless --path . -- --server --port "$SERVER_PORT" --net-stats --bots "${BOTS:-4}" \
    > "$LOG_DIR/server.log" 2>&1 &
  echo $! > "$SERVER_PID"
  wait_ready server "$SERVER_PORT" "$SERVER_PID" "$LOG_DIR/server.log"
}

start_web() {
  [[ -f build/web/index.html ]] || {
    echo "web build missing: run tools/check.sh first" >&2
    return 1
  }
  check_port web "$WEB_PORT" "$WEB_PID"
  if running "$WEB_PID"; then
    echo "web already running (pid $(cat "$WEB_PID"))"
    return
  fi
  python3 tools/serve.py --root build/web --bind "$WEB_BIND" \
    --port "$WEB_PORT" --upstream "127.0.0.1:$SERVER_PORT" --ws-path "$WS_PATH" \
    > "$LOG_DIR/web.log" 2>&1 &
  echo $! > "$WEB_PID"
  wait_ready web "$WEB_PORT" "$WEB_PID" "$LOG_DIR/web.log"
}

case "${1:-}" in
  up)
    start_server
    start_web
    echo "one-origin: forward only web port $WEB_PORT; /ws tunnels to 127.0.0.1:$SERVER_PORT"
    ;;
  down)
    stop_one server "$SERVER_PID"
    stop_one web "$WEB_PID"
    ;;
  status)
    for spec in "server|$SERVER_PID|$SERVER_PORT" "web|$WEB_PID|$WEB_PORT"; do
      IFS='|' read -r name pid_file port <<< "$spec"
      if running "$pid_file"; then
        echo "$name: up (pid $(cat "$pid_file"), port $port)"
      else
        echo "$name: down"
      fi
    done
    ;;
  *)
    echo "usage: tools/dev.sh up|down|status" >&2
    exit 2
    ;;
esac
