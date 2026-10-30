# Testing & dev tooling

All automated checks run headless on the pinned Godot **4.7.2** binary. The suite is
[gdUnit4 **6.2.2**](https://github.com/godot-gdunit-labs/gdUnit4) (MIT), vendored under
`addons/gdUnit4/` and excluded from both exports.

## Run

```bash
tools/check.sh                            # import → content → tests → arena budget → boots → exports → size
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
| `tests/gdunit/test_movement.gd` | 8 | 21 | travel, diagonal parity, sprint, L1 jump apex/derivation/asymmetric fall/terminal, coyote/buffer, settings persistence |
| `tests/gdunit/test_combat.gd` | 5 | 164 | weapon data, 20/20 body hits at 5/15/30 m, fire rate, reload |
| `tests/gdunit/test_net_protocol.gd` | 12 | 72 | roundtrips, 1 cm / ±327.68 m positions, golden 28 B layout, 182 B snapshot budget, velocity/ground roundtrip, malformed/oversized rejection |
| `tests/gdunit/test_net_loopback.gd` | 1 | 39 | two real clients, spawn parity, prediction p95, divergence recovery, input ordering/dedupe/rate limit, bounded starvation, leave cleanup |
| `tests/gdunit/test_prediction.gd` | 3 | 13 | deterministic replay, divergent correction + visual decay, stale ack rejection |
| `tests/gdunit/test_turning.gd` | 4 | 12 | camera-relative movement, body facing, aim strafe, deterministic 180° |
| `tests/gdunit/test_phase0.gd` | 5 | 18 | speed/projectile tuning, turn-then-shoot gate, virtual-clock interpolation, connection timeout, death pose + red marker |
| `tests/gdunit/test_world_geometry.gd` | 2 | 59 | nature arena: every tree has a collider; camera never enters the cliff |
| `tests/gdunit/test_quarry_arena.gd` | 9 | — | quarry loads, 9 chunks, mesh/heightmap parity, 8 spawns, cave clearance, hero colliders, walkable ramps, boundary, camera wall, main wiring |
| `tests/gdunit/test_rig.gd` | 2 | 16 | gun follows the hand; filtered Pistol_Shoot overlay |
| `tests/gdunit/test_server_combat.gd` | 4 | 21 | canonical muzzle, body damage, rate/ammo/reload, protection, kill attribution |
| `tests/gdunit/test_loopback_combat.gd` | 1 | 22 | fire intent through the socket, hit/death/respawn, spoofed damage rejection |
| `tests/gdunit/test_bots.gd` | 1 | 9 | four bots move, fire, damage each other, stay in the roster, id index |
| `tests/gdunit/test_kaykit.gd` | 5 | 0 | five variants, one shadowless skinned surface, scale/yaw, clip set, gun/muzzle, budget |
| `tests/gdunit/test_menu.gd` | 8 | 0 | menu fields/state, direct vs one-origin config, loading overlay, endpoint/URL selection |
| `tests/gdunit/test_quick_menu.gd` | 3 | 0 | phase-aware actions, signals, Esc close, settings placeholder |
| `tests/gdunit/test_hud.gd` | 9 | 0 | dirty-flag redraws, transient timers, state setters, death/respawn, debug refresh |
| `tests/gdunit/test_content_catalog.gd` | 8 | 0 | core manifest, catalog-backed weapons, ids/paths/types, wire ids, budgets, dependency cycles, disabled entries |
| `tests/gdunit/test_menu_network.gd` | 4 | 0 | initial timeout, bounded backoff, dropped-socket grace, real drop/rejoin |
| `tests/gdunit/test_proxy.gd` | 5 | 0 | shell placeholders, static serving/injection, WS handshake/tunnel, real client through proxy |
| `tests/gdunit/test_bullet_pool.gd` | 5 | 0 | prewarm before first shot, 500-round no-growth, shared materials, muzzle-grown streak, impact pool |
| `tests/gdunit/test_combat_telemetry.gd` | 4 | 0 | hit/world/expiry/rejection accounting |
| `tests/gdunit/test_bot_feel.gd` | 3 | 0 | reaction delay, bounded spread, 4-bot lethality, staggered target LOS |
| `tests/gdunit/test_class_weapons.gd` | 7 | 0 | five profiles, per-class damage, three-hit TTK, charge/burst/heat, bot classes |
| `tests/gdunit/test_projectile_effects.gd` | 5 | 0 | flat flight, pierce, splash, knockback/slow |
| `tests/gdunit/test_class_picker.gd` | 4 | 0 | five-card picker, class URL, solo class, selection state |
| `tests/gdunit/test_class_weapon_visual.gd` | 4 | 0 | class→variant, five weapon/muzzle attachments, animation map, HUD state |
| `tests/gdunit/test_sanity.gd` | 2 | 2 | toolchain canary: runner + scene instantiation |
| `tests/gdunit/test_respawn.gd` | 1 | 0 | distance-first spawn ranking, top-2 raycast bound, clustered deaths |

**141 test cases · ~1,030 assertions** in the optimization batch, plus **35 walkthrough sections** and the 4-bot match. The current worktree also contains two map-picker tests from the map session (**143** total).
Quarry budget: 49 draw calls, 192,842 triangles; web export 44,768 KB raw / 14,244 KB gzip.
Walkthrough: 536.5 m, 0 fall-through, 0 camera clips, 0 stuck episodes over 1.5 s.

`test_net_loopback` stays one integration test: the value is the real socket path and shared tick, and re-establishing three peers per assertion would triple runtime.
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
- `tests/headless/arena_stats.gd` — draw calls / triangles / collider budget report for the nature and quarry arenas.
- `tests/headless/quarry_walk.gd` — 35-section real-physics walkthrough on the quarry (chunks, cave aprons/bore, ramps, bridge, tower, lookout, spawns, edges, falls). Fails on fall-through, >1.5 s stuck, unreachable spawn, cave camera clipping or boundary escape.
- `tests/headless/quarry_match.gd` — 45 s four-bot headless match on the quarry (spawn, movement, shots, hits, deaths).

`tools/check.sh` runs both arena harnesses after the gdUnit suite and arena budget.

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
