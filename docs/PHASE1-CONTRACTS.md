# Phase 1 — parallel workstream contracts

- **Started:** 2026-10-29, after Phase 0 retest
- **Owner/integrator:** manager (this session)
- **Agents:** A (character & weapon art), B (entry UX & network resilience), C (combat, perf, bots)
- **Merge order:** B → C → A (A touches the most visual surface last)

## User decisions (locked)

| Decision | Value |
|---|---|
| Character pack | **KayKit Adventurers 2.0 free tier** + **Character Animations 1.1 `Rig_Medium`** (CC0) |
| Character count | **5 different characters**, each with the full animation set |
| Head hurtbox | **Keep the current sphere** (0.72 m, r 0.115); do not change hit feel |
| Mesh strategy | **Merge the 9 character meshes to one skinned mesh** per character and **disable character shadows** |
| Rifle | **Quaternius CC0 M4** confirmed (Poly Pizza `/m/Bgvuu4CUMV`) |
| Bullet visual | Long thin tracer: trail ~2.2 m, rim ~2.4 m, core length ~0.36 m; radial thickness only 5 % (core ~0.018 m, trail ~0.006 m, rim ~0.026 m); grows out of the muzzle |
| Bot roster | Bots draw from the same five-character pool; no separate subset |
| Paid content | **No** purchases |
| Remote aim pose | Keep the rifle-ready pose; **no protocol change** for now |
| Textures | Local 512×512, remotes 256×256 (recommended) |

## File ownership (hard rule)

| Area | Owner | Must not touch |
|---|---|---|
| `assets/kaykit/**`, `assets/weapons/rifle/**`, `scenes/characters/player.tscn` visual subtree, `scripts/player/character_visual.gd`, character visual tests | **A** | `player_controller.gd`, `weapon_controller.gd`, `game_manager.gd`, networking |
| `scripts/game/main.gd`, `scripts/networking/network_manager.gd`, `web/` shell/template, `tools/serve.py`, `tools/dev.sh`, menu/loading scenes | **B** | `game_manager.gd`, `player_controller.gd`, combat, characters |
| `scripts/game/server_combat.gd`, `scripts/weapons/projectile.gd`, `bullet_field.gd`, `bullet_visual.gd`, `scripts/ui/hud.gd`, soak/perf tests | **C** | `game_manager.gd` (request changes through the manager), characters, entry UI |
| `scripts/game/game_manager.gd`, `player_controller.gd`, `net_protocol.gd`, merge resolution | **Manager** | — |

If a change genuinely needs an unowned file, stop and report it. Do not edit across the line.

## Frozen interfaces

- `Msg.EVENT` schema and event ids.
- `NetProtocol.AnimState { STILL=0, WALK=1, SPRINT=2, AIR=3 }`.
- `PlayerController` public API: `net_role`, `net_id`, `view_yaw`, `aiming`, `aim_hold_until_msec`, `simulate_tick`, `server_step`, `accept_server_state`, `set_dead`, `respawn_at`, `reset_remote_smoothing`.
- Gun contract: `WeaponController` resolves `muzzle_path` (`../Visual/GunMount/Muzzle`) at `_ready`; the visual layer may reparent `GunMount` but must keep a `Marker3D` named `Muzzle` under it and preserve `GunMount` world scale (1.0).
- `CharacterVisual` public/semi-public fields used elsewhere: `force_anim`, `_gun_attached` (tests), `animation_player` (tests), `_hold_player` (tests), `_shot_player`.
- `GameManager` signals: `server_hit`, `server_death`, `server_respawn`, `server_shot`.
- `NetworkManager`: `start_client(host, port)`, `last_error`, `connection_failed`, `mode`, `stop()`.

## Worktrees & ports

Each agent works in its own worktree:

- A: `/srv/opencode/workspace/mis/ballofduty-wt-a` (branch `phase1-a`)
- B: `/srv/opencode/workspace/mis/ballofduty-wt-b` (branch `phase1-b`)
- C: `/srv/opencode/workspace/mis/ballofduty-wt-c` (branch `phase1-c`)

Live ports `9180`/`8099` belong to the manager. Agents must use ephemeral ports (`92xx`/`82xx`) and must not run `tools/dev.sh up/down` against the live server.

## Test protocol

Each agent must:

1. Run `./tools/godot --headless --path . --import`.
2. Run the targeted suites it touches, then `./tools/check.sh --skip-export` if practical.
3. Add/extend tests for the new surface.
4. Commit to its branch with a clear message and report the commit hash, files changed, test output, and open risks.
5. Never merge into `main`; the manager merges and runs the full pipeline + live browser match.

## Acceptance gates

- **A:** 5 KayKit characters at 0.82 m, one skinned mesh each, shadows off, full animation map (idle/walk/run/strafe/backpedal/jump/land/aim/shoot/reload/hit/death); gun and muzzle still follow the hand; `test_rig` green; draw calls ≤ 150 with 5 characters + map.
- **B:** page opens to a menu (name/host/port/join/solo); loading animation; one-origin static+WS proxy so only one port is needed; unreachable server shows a clear error and retry; no silent cosmetic-only state.
- **C:** 8 clients + 4 bots for 10 minutes at 30 Hz; no tick collapse, CPU measured, bots tuned with reaction/spread; shot/hit telemetry remains readable; projectile expiry/hit counters consistent.
