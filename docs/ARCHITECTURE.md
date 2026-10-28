# Architecture

## Authority model

| Concern | Authority | Client behavior |
|---|---|---|
| Movement | Server (from CP4b) | Predict locally, reconcile on snapshot |
| Aim/camera | Client | Sent with input frame; server sanity-checks |
| Fire rate / ammo | Server | Predict FX only; server rejects invalid shots |
| Projectile path & hits | Server | Draw predicted cosmetic tracer; confirm on event |
| Damage / death / score | Server | Render events only (HUD, effects) |
| Spawn point / protection | Server | Countdown UI only |
| Match state / timer | Server | Display only |
| Cosmetics / audio | Client | Purely local |

Hard rule: **no client script may write health, kills, or score.** Before CP4 these live behind the same
`CombatResolver` / `GameState` API that the server will call, so enabling authority is a wiring change,
not a rewrite.

## Tick & network model

- Physics/simulation tick: **30 Hz** (`physics/common/physics_ticks_per_second=30`).
- Input frames are produced once per tick: `{seq, move_x, move_z, jump, sprint, scope, aim_yaw, aim_pitch}`.
- Snapshots are sent once per tick at 30 Hz and carry `{tick, seq, acked_input_seq, players[], events[]}`.
- Remote players render with a **100 ms interpolation buffer**; stale snapshots are dropped, never queued.
- Local player: fixed-tick prediction, replay of unacked inputs, visual correction smoothed over 100 ms.
- Maximum packet target: **1 KB** snapshot at 8 players; downstream ≤ 10 KB/s/client.

## Collision layers

Defined in `project.godot` under `layer_names/3d_physics`:

| Bit | Value | Name | Used by |
|---|---|---|---|
| 1 | 1 | `world` | Static geometry, terrain, walls |
| 2 | 2 | `player` | Local/remote player bodies |
| 3 | 4 | `enemy` | Bot bodies (CP4c) |
| 4 | 8 | `hurtbox` | Head/body `Area3D` hit volumes |
| 5 | 16 | `projectile` | Projectile bodies (if not raycast) |
| 6 | 32 | `camera` | Future camera-blocking volumes |
| 7 | 64 | `trigger` | Pickups, kill planes, spawn zones |

Rules:
- Player `collision_mask` = world + player (+ enemy from CP4c).
- SpringArm `collision_mask` = world only.
- Hurtboxes `collision_layer` = hurtbox, `monitoring` = false; hit detection is a query, not an overlap callback.
- Projectile hit queries mask world + hurtbox. Never query player bodies for damage.

## Events (EventBus)

Only cross-system events go on the bus. Component-internal communication stays parent↔child signals.

```gdscript
# scripts/autoload/event_bus.gd
signal health_changed(entity_id: int, current: int, maximum: int)
signal damage_dealt(target_id: int, source_id: int, amount: int, hitbox: StringName, position: Vector3)
signal died(entity_id: int, source_id: int, position: Vector3)
signal kill_credited(killer_id: int, victim_id: int, weapon_id: StringName)
signal shot_fired(shooter_id: int, origin: Vector3, direction: Vector3, weapon_id: StringName)
signal match_state_changed(state: StringName, seconds_left: float)
signal score_changed(player_id: int, kills: int, deaths: int)
```

Conventions:
- IDs are server-assigned peer ids; `0` = local/solo.
- Events carrying truth (`damage_dealt`, `died`, `kill_credited`) are emitted **only by authority**.
- Cosmetic-only signals are prefixed `fx_` and may be emitted locally.
- Payloads must be serializable primitives; no node references.

## Components & scenes

```text
Player.tscn (CharacterBody3D)
├── CollisionShape3D
├── Mesh (presentation only)
├── BodyHurtbox / HeadHurtbox   (Area3D, layer hurtbox)
├── HealthComponent             (CP3)
├── LocomotionComponent         (CP4b, shared with server)
├── WeaponController            (CP3)
├── CameraRig (Node3D → SpringArm3D → Camera3D)
└── NetworkInterpolator         (CP4a, remote variant only)
```

- `InputHandler` exists only for the locally controlled player.
- The headless server instantiates `Player.tscn` without camera/HUD and with `LocomotionComponent` driven
  by received input frames.
- Visuals never drive gameplay: mesh scale/animation is presentation.

## Directory conventions

- `snake_case` for all files and folders; `PascalCase` for node names and `class_name`s.
- Scenes in `scenes/`; scripts in `scripts/` mirroring the scene domain.
- Tuning data in `.tres` text resources under `resources/`; no gameplay magic numbers in scripts.
- Third-party assets in `assets/` with an entry in `assets/CREDITS.md` **before** commit.
- Autoloads limited to `EventBus`, `GameManager`, `Settings`, `AudioManager`.

## Web constraints

- Compatibility renderer only; no SSAO/SSIL/volumetric fog/TAA.
- Single-threaded export; no `SharedArrayBuffer`/COOP/COEP requirement.
- WSS terminated at Caddy/Nginx in front of the headless server; static build served from the same origin.
- Audio unlocked on first pointer gesture; pointer lock re-acquired after focus loss.
- Export must load with all resources packed; no runtime file access.
