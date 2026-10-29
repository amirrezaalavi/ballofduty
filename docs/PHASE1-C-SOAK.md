# Phase 1 C — soak, combat telemetry and bot feel

## Soak harness

`tools/soak.sh` boots one authoritative server in-process with real WebSocket
clients on an ephemeral `92xx` port and optional server bots. It never touches
the live `9180` / `8099` services.

```bash
# Short gate (2 minutes): 4 clients + 4 bots, the largest mixed match allowed
# by the current 8-player roster cap.
tools/soak.sh

# 10-minute Phase 1 gate.
tools/soak.sh --full

# Explicit load / future 12-actor match once MAX_PLAYERS is raised.
tools/soak.sh --clients 8 --bots 4 --seconds 600

# CI guard: fail if the requested client+bot count exceeds the roster cap.
tools/soak.sh --clients 8 --bots 4 --require-full
```

Reports are machine readable (`SOAK ...` lines) and are also written to
`.cache/soak-<port>.log`. Exit code is non-zero if tick rate, frame period, CPU,
memory, node count, client liveness or projectile accounting fail.

What is measured each second:

| Metric | Source |
|---|---|
| tick rate | `GameManager._server_tick` delta / wall second |
| frame period | 1 / tick rate (30 Hz target = 33.3 ms) |
| CPU / RSS | `/proc/self/stat`, `/proc/self/status` (server + in-process clients) |
| nodes | `Performance.OBJECT_NODE_COUNT` |
| snapshot bytes | each client's `NetworkManager.last_snapshot_bytes` |
| ack / starve / frozen / dropped | `GameManager.server_player_stats(id)` |
| shots / hits / world impacts / expiry / deaths | `ServerCombat` counters |

### Roster cap (action for the manager)

`NetProtocol.MAX_PLAYERS` is **8** (frozen, manager owned). `8 clients + 4 bots`
is therefore impossible today: bots consume the first four ids, so only four
clients can join. The harness clamps to the largest feasible mixed match and
prints `SOAK_CAP`; `--require-full` fails until the cap is raised.

To run the literal 8 + 4 gate the manager must:

1. Raise `NetProtocol.MAX_PLAYERS` to 12. The snapshot is then
   `6 + 12 * 22 = 270 B`, still under the 300 B budget; no schema change.
2. Add four spawn markers (`Spawn09`–`Spawn12`) to `arena_nature.tscn`.
   `_claim_slot()` returns `-1` after the 8th spawn and extra actors would stack
   at the origin.

## Bot feel (data in `game_manager.gd`)

| Constant | Value | Effect |
|---|---|---|
| `BOT_REACTION_MIN_SEC` / `MAX_SEC` | 0.24 / 0.55 | first shot after acquiring a target |
| `BOT_REACQUIRE_SCALE` | 0.7 | shorter delay after cover breaks line of sight |
| `BOT_AIM_TURN_RATE` | 9.0 rad/s | view cannot snap instantly |
| `BOT_AIM_ERROR_BASE_DEG` | 1.1° | persistent angular error |
| `BOT_AIM_ERROR_MOVING_DEG` | +1.2° | wider while strafing/sprinting |
| `BOT_AIM_ERROR_FAR_DEG` | +1.4° | wider beyond 12 m |
| `BOT_AIM_ERROR_RESAMPLE_SEC` | 0.32 s | error is resampled, not jittered per tick |
| `BOT_AIM_ERROR_PITCH_SCALE` | 0.65 | vertical error is tighter |
| `BOT_BURST_SHOTS` / `PAUSE_SEC` | 6 / 0.35 s | burst fire instead of a laser |
| `BOT_FIRE_RANGE` | 20 m | same engagement envelope as before |
| `BOT_TARGET_STICKY_RANGE` | 26 m | target memory; reaction is not reset every tick |

Regression: `test_bot_feel.gd` checks the reaction delay, bounded aim error and
that four bots still land damage on flat ground.

## Bullet visual

- Core `0.018 × 0.36 m`, trail `0.006 × 2.2 m`, rim `0.026 × 2.4 m`, impact
  flash ≈ 3 cm.
- The trail/rim length is `min(distance_travelled, max_length)`, so at spawn it
  is invisible and grows out of the muzzle at render rate. It can never extend
  behind the gun towards the camera.
- 64 visual bullets + 24 impacts, all pre-built; 500-round test
  (`test_bullet_pool.gd`) asserts the node count and material count stay fixed.

## Measured short runs (this worktree)

2-minute mixed match, 4 clients + 4 bots (8-player cap):

```
tick 30.01 Hz (min 28.80)                      frame period 33.32 ms avg / 34.48 p95
CPU 27.2% of one core (server+4 clients)       RSS 127.3 → 127.9 MB (+0.5%)
nodes 1550 → 1546                              snapshot 182 B, ~21.3 KiB/s uplink
clients 4/4, dropped snaps 0, starved 0, frozen 0, ack lag max 5
shots 2521 · player hits 544 · world 1970 · expired 3 · active 4 · deaths 70
hit ratio 21.6%, rejections cd/rl/ammo = 6640/701/46
```

2-minute, 8 clients + 0 bots (8-player cap):

```
tick 30.01 Hz (min 28.86)                      frame period 33.32 ms avg / 34.42 p95
CPU 45.7% of one core (server+8 clients)       RSS 134.9 → 135.5 MB (+0.4%)
nodes 2486 → 2498                              snapshot 182 B, ~42.7 KiB/s uplink
clients 8/8, dropped snaps 0, starved 0, frozen 0
shots 2806 · player hits 503 · world 2286 · expired 9 · deaths 42
```
