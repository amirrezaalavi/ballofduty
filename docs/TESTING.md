# Testing & dev tooling

All automated checks run headless on the pinned Godot **4.7.2** binary. The suite is
[gdUnit4 **6.2.2**](https://github.com/godot-gdunit-labs/gdUnit4) (MIT), vendored under
`addons/gdUnit4/` and excluded from both exports.

## Run

```bash
tools/check.sh                            # import → tests → arena budget → boots → exports → size
tools/check.sh --skip-export              # tests + boots only

# tests only (writes reports/report_N/results.xml + index.html)
tools/godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a tests/gdunit -c --ignoreHeadlessMode

# one suite
tools/godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a tests/gdunit/test_net_loopback.gd -c --ignoreHeadlessMode
```

`--ignoreHeadlessMode` is required because gdUnit4 otherwise refuses to run without a display.
The suite deliberately does **not** use Godot `InputEvent` simulation: input events are not
transported in headless mode. Tests drive `PlayerInputFrame`s and physics frames directly.

Exit codes: `0` green, `100` test failure. `check.sh` relies on both the exit code and
`Exit code: 0` in the log, so a crashed runner cannot be mistaken for a pass.

## Suites

| File | Test cases | Assertions | Covers |
|---|---|---|---|
| `tests/gdunit/test_smoke.gd` | 7 | 100 | settings, autoloads, input map, scenes, spawn spacing, player rig, greybox ramp |
| `tests/gdunit/test_movement.gd` | 6 | 15 | travel distance, diagonal parity, sprint, jump apex, coyote/buffer, settings persistence |
| `tests/gdunit/test_combat.gd` | 5 | 204 | weapon data, 20/20 headshots at 5/15/30 m, body damage, fire rate, reload |
| `tests/gdunit/test_net_protocol.gd` | 8 | 45 | roundtrips, quantization, 182 B snapshot budget, velocity/ground roundtrip, malformed rejection |
| `tests/gdunit/test_net_loopback.gd` | 1 | 39 | two real clients, spawn parity, prediction p95, divergence recovery, input ordering/dedupe/rate limit, bounded starvation, leave cleanup |
| `tests/gdunit/test_prediction.gd` | 3 | 13 | deterministic replay, divergent correction + visual decay, stale ack rejection |
| `tests/gdunit/test_turning.gd` | 4 | 12 | camera-relative movement, body facing, aim strafe, deterministic 180° |
| `tests/gdunit/test_phase0.gd` | 5 | 18 | speed/projectile tuning, turn-then-shoot gate, virtual-clock interpolation, connection timeout, death pose + red marker |
| `tests/gdunit/test_world_geometry.gd` | 2 | 59 | every tree has a collider; camera never enters the cliff |
| `tests/gdunit/test_rig.gd` | 2 | 16 | gun follows the hand; filtered Pistol_Shoot overlay |
| `tests/gdunit/test_server_combat.gd` | 5 | 25 | canonical muzzle, body/head damage, rate/ammo/reload, protection, kill attribution |
| `tests/gdunit/test_loopback_combat.gd` | 1 | 22 | fire intent through the socket, hit/death/respawn, spoofed damage rejection |
| `tests/gdunit/test_bots.gd` | 1 | 7 | four bots move, fire, damage each other, stay in the roster |
| `tests/gdunit/test_kaykit.gd` | 5 | 0 | five variants, one shadowless skinned surface, scale/yaw, clip set, gun/muzzle, budget |
| `tests/gdunit/test_menu.gd` | 8 | 0 | menu fields/state, direct vs one-origin config, loading overlay, endpoint/URL selection |
| `tests/gdunit/test_menu_network.gd` | 4 | 0 | initial timeout, bounded backoff, dropped-socket grace, real drop/rejoin |
| `tests/gdunit/test_proxy.gd` | 5 | 0 | shell placeholders, static serving/injection, WS handshake/tunnel, real client through proxy |
| `tests/gdunit/test_bullet_pool.gd` | 4 | 0 | 500-round no-growth, shared materials, muzzle-grown streak, impact pool |
| `tests/gdunit/test_combat_telemetry.gd` | 4 | 0 | hit/world/expiry/rejection accounting |
| `tests/gdunit/test_bot_feel.gd` | 2 | 0 | reaction delay, bounded spread, 4-bot lethality |
| `tests/gdunit/test_sanity.gd` | 2 | 2 | toolchain canary: runner + scene instantiation |

**84 test cases · ~765 assertions.** `test_net_loopback` stays one integration test: the value is the
real socket path and shared tick, and re-establishing three peers per assertion would triple runtime.
Loopback tests disable the local `_physics_process` and drive `simulate_tick()` explicitly, so the
prediction path is identical to real input without competing sequences.

`tests/gdunit/bod_test_suite.gd` is the shared base (`class BodTestSuite extends GdUnitTestSuite`).
It provides `expect(condition, label)` and `wait_for(predicate, frames)` so failures keep a
human-readable label without duplicating assertion plumbing. Prefer `expect()` for boolean checks
and native `assert_*` when a value diff is more useful.

Not in gdUnit4:

- `tests/headless/net_client_probe.gd` — cross-process client against a live server (probe mode).
- `tools/soak.sh` / `tests/headless/soak_runner.gd` — 30 Hz soak with real WS clients and bots,
  metrics for tick/frame/CPU/RSS/nodes/snapshot/ack/combat. `--full` is the 10-minute gate.
- `tests/headless/arena_stats.gd` — draw calls / triangles / collider budget report.

## Tooling

| Command | Purpose |
|---|---|
| `tools/api.sh Class [member]` | Version-exact Godot class reference generated by `--doctool` into `.cache/api` (1,076 classes). Grep before guessing an API. |
| `tools/gdcheck.sh [files…]` | `--check-only` parse gate, ~2 s per file; defaults to changed/untracked `.gd` files |
| `tools/dev.sh up\|down\|status` | Pidfile supervisor for server `:9180` and web `:8099`; refuses a port held by another process |
| `tools/capture.sh URL OUT [wait_ms]` | Deterministic 1280×720 Playwright screenshot written inside the repo |

Typical visual check:

```bash
tools/check.sh && tools/dev.sh up
tools/capture.sh "http://127.0.0.1:8099/?join=1&host=127.0.0.1&port=9180&name=Shot" \
  docs/checkpoints/shot.png 6000
tools/dev.sh down
```

## Migration note

CP0–CP4a evidence files name the original SceneTree harnesses (`smoke_test.gd`,
`movement_test.gd`, `combat_test.gd`, `net_protocol_test.gd`, `net_loopback_test.gd`). Those were
migrated verbatim to the suites above; the measured numbers in the checkpoint docs are unchanged.
The duplicate truncated-snapshot assertion in the old protocol test was removed (26 meaningful
checks). CI already runs `tools/check.sh`, so it inherits the new runner.
