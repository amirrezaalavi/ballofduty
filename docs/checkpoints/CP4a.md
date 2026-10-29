# CP4a — Transport & replication

- **Date:** 2026-10-29
- **Status:** implementation complete — **awaiting two-player feel test**
- **Engine:** Godot 4.7.2, Compatibility, 30 Hz physics / 30 Hz snapshots
- **Screenshots:** [`cp4a-two-clients.png`](./cp4a-two-clients.png), [`cp4a-browser-join.png`](./cp4a-browser-join.png)

## What landed

- **Transport** (`scripts/networking/network_manager.gd`): `WebSocketMultiplayerPeer` polled manually
  every frame. Client connect, server listen, `--server --port`, `--connect HOST`, `--name`, plus
  browser URL params `?join=1&host=…&port=…&name=…`. Simulated latency via
  `--sim-latency MS --sim-jitter MS` or `?sim=100,20`.
- **Binary protocol** (`scripts/networking/net_protocol.gd`): hand-packed little-endian messages.
  Snapshot header 6 B + 15 B/player → **126 B at 8 players**; input frame 12 B → ~360 B/s upstream.
  Every decoder validates length, count, and enum ranges; malformed packets are rejected and counted.
- **Session** (`scripts/game/game_manager.gd`): join/leave, per-player ids, sanitized names, roster
  broadcast, spawn-slot assignment, server-side simulation, snapshot fan-out.
- **Interpolation** (`scripts/networking/network_interpolator.gd`): 12-sample tick buffer,
  newest-wins (stale ticks dropped), render at `newest − 2 ticks` with a jitter tick, extrapolation
  capped at 1 tick, then hold.
- **Roles** (`scripts/player/player_controller.gd`): `LOCAL` (input + camera), `REMOTE` (posed from
  snapshots, no collision), `SERVER` (authority sim, visuals disabled).
- **Animation replication**: snapshot state byte (still/walk/sprint/air) selects the clip on ghosts.
- **Dev panel** (bottom-right, `F6`): host/port/name, connect/disconnect, and live
  `id / remotes / rtt / snapshot bytes / processed / dropped`.

## Bugs found during this checkpoint (server-side)

| Bug | Symptom | Fix |
|---|---|---|
| Spawn mismatch | Server spawned players at a marker (22 m out); the client stayed at the origin, so every other player saw them 22 m away | `JOIN_OK` now carries the authoritative spawn position + yaw; the client adopts it. Verified gap **0.000 m** (was 22.0) |
| Spawn yaw inverted | Players spawned facing the perimeter wall | `atan2(pos.x, pos.z)` instead of the negated form; forward · to-centre = **1.000** |
| Yaw stomp | `server_step` wrote `frame.yaw` every tick, and an empty frame defaults to 0, so spawn yaw snapped to 0 and packet loss would spin players | Yaw only applied after the first real input frame (`has_input`) |
| Self-ghost | A snapshot arriving before `JOIN_OK` could spawn a ghost of yourself | Ghosts are never created for `local_id`; an existing one is removed on accept |
| Broadcast to pending peers | Snapshots/rosters went to half-open connections | Fan-out and roster broadcast iterate the joined roster only |
| Deny race | Server closed the socket immediately after sending "server full" | 0.3 s flush window before disconnect |
| Join timeout too early | Timer started at `create_client`, so a throttled/background tab was killed before its socket opened | Timer starts when `JOIN_REQ` is actually sent |
| WebSocket close noise | `close()` on an already-dropped socket logged `ready_state != STATE_OPEN` | Only close when status ≠ DISCONNECTED |
| Remote T-pose | Ghosts shared `_state` with the local state machine, so the forced clip was skipped while the player was stopped | Compare against `current_animation`; ghosts start in forced mode |

## Automated evidence

| Suite | Result |
|---|---|
| `net_protocol_test.gd` | **27 checks, 0 failures** — roundtrips, quantization, malformed/oversized/truncated rejection |
| `net_loopback_test.gd` | **23 checks, 0 failures** — real sockets, 2 clients, spawn parity, yaw persistence, ghost convergence, no teleports, leave cleanup, malformed traffic |
| `net_client_probe.gd` | **5 checks, 0 failures** — separate OS process against a live server, 900–1200 snapshots, `remotes=1` |
| `smoke_test.gd` | 100 checks, 0 failures |
| `movement_test.gd` / `combat_test.gd` | 14 / 204 checks, 0 failures |
| `arena_stats.gd` | 50 draw calls, 32,544 tris, 0 blocked spawns |

Measured live values:

- 8-player snapshot: **126 B** (budget 300 B)
- 2-player snapshot in browser: **36 B**
- Browser ↔ native round trip on loopback: **61–64 ms** (30 Hz ping)
- Web payload: **11,301 KB gzip**

## Acceptance criteria

| Criterion | Status |
|---|---|
| 2 browser clients + 1 desktop client join; all see each other move | **Partial** — verified with 1 browser + 1 native client (2 clients). Two browser tabs cannot both run simultaneously: Chromium freezes background tabs, so only the focused tab simulates. Cross-tab testing needs two windows/profiles — deferred to the CP5 browser matrix with your hardware |
| Remote movement smooth at 60/144 FPS, no teleporting | **Pass** in loopback (successive ghost steps < 0.5 m; buffer holds 12 samples) |
| Snapshot ≤ 300 B at 8 players; ≤ 10 KB/s | **Pass** — 126 B; 30 Hz × 126 B ≈ 3.8 KB/s |
| Server runs with no display; CPU < 25 % idle with 8 | **Partial** — headless boots clean; 8-client CPU not yet measured (needs the soak harness, CP4d) |
| Newest snapshot wins, counters logged | **Pass** — stale ticks increment `snapshots_dropped`; panel shows in/dropped |
| Join mid-match spawns; leave removes within 1 s | **Pass** — loopback leave check passes within the roster update |
| Malformed/oversized packets rejected without stalling | **Pass** — 3 malformed packets rejected, server keeps serving |
| 100 ms RTT + 20 ms jitter smooth, ≤ 1 tick extrapolation | **Pass** — median ghost gap 0.560 m, no snap-back; local input lag expected until CP4b |
| **Your sign-off** | Pending |

## How to test

```bash
# terminal 1 — authoritative server
tools/godot --headless --path . -- --server --port 9180

# terminal 2 — static build
tools/check.sh && tools/serve.sh 8099
# then open http://127.0.0.1:8099/?join=1&host=127.0.0.1&port=9180&name=You

# optional second player (separate process, walks toward the first)
tools/godot --headless --path . --script tests/headless/net_client_probe.gd \
  -- --host 127.0.0.1 --port 9180 --name Bot --seconds 30 --walk-to 22,0
```

Latency test: add `?sim=100,20` to the URL (100 ms each way, ±20 ms jitter).

## Known gaps carried into CP4b

- No client prediction/reconciliation yet: the local player is simulated locally and the server
  simulates independently. Input lag and divergence are expected; movement correction lands in 4b.
- Two browser tabs cannot be tested at once because of background-tab throttling. A window-level
  test is part of the CP5 matrix.
- Server CPU with 8 clients is unmeasured; the soak harness is CP4d work.
- Combat is still local (CP3); damage authority moves in 4c.
- The connect panel is a developer convenience, not final UI (CP5).
