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

Hard rule: **no client script may write health, kills, or score.** CP3 keeps all damage behind
`CombatResolver`; CP4c moves the resolver's caller, projectile spawn, and hit resolution server-side.
That is a scoped refactor, not a one-file flip — plan for it.

## Tick & network model

- Physics/simulation tick: **30 Hz** (`physics/common/physics_ticks_per_second=30`).
- Input frames are produced once per tick: `{seq, move_x, move_z, jump, sprint, scope, aim_yaw, aim_pitch, buttons}`.
- Snapshots are sent once per tick at 30 Hz as a binary `PackedByteArray`:
  `{tick, seq, players:[{id, pos_q, yaw_q, state, hp, acked_input_seq}], events[]}`.
- Budget: **≤ 300 B** snapshot at 8 players → **≤ 10 KB/s** downstream per client (quantized, no dictionaries).
- Remote players render with a **2-interval (67 ms) buffer + jitter margin**, newest-wins; extrapolation is
  capped at **1 tick**, otherwise hold the last pose. Late packets never snap the pose backwards.
- Local player: fixed-tick prediction, replay of unacked inputs, visual correction smoothed over 100 ms.
- **Clock**: the client estimates server-tick offset from the first snapshot and minimum observed RTT,
  falling back to arrival time; it renders remote players at `estimated_server_tick - 2 - jitter_ticks`.
- **Transport reality**: WebSocket is TCP. Dropping stale snapshots prevents an unbounded backlog, but it
  cannot hide head-of-line retransmit stalls; a lost packet is a visible hitch of at least the RTO. Keep
  snapshots small and budget for it. Revisit WebTransport only if this is unacceptable.

## Wire protocol (CP4a)

All messages start with a 1-byte type (`NetProtocol.Msg`), little-endian, hand-packed; no dictionaries.

| Message | Size | Fields |
|---|---|---|
| `JOIN_REQ` | 2 + n | name length, up to 16 sanitized bytes |
| `JOIN_OK` | 14 | id, server tick, **spawn xyz (mm i16), spawn yaw (i16)** |
| `DENY` | 2 | reason |
| `ROSTER` | 2 + Σ(2+n) | count, then (id, name len, name) |
| `INPUT` | 12 | seq u32, move x/y i8, flags, yaw i16, pitch i16 |
| `SNAPSHOT` | 6 + 22n | tick u32, count, then (id, pos xyz i16 mm, yaw i16, state, vel xyz i16 cm/s, flags u8, hp, acked seq u32) |
| `PING`/`PONG` | 5 / 9 | client msec; pong adds server tick |

- Position quantization is millimetres over ±32.768 m (2 mm round-trip error in tests); velocity is
  centimetres per second. Flags bit 0 is `on_floor`.
- **Movement model (CP4b):** `view_yaw` is client-owned and independent of the body. WASD is
  camera-relative; the body turns toward the movement direction (14 rad/s) and only translates as its
  facing aligns, so turns read as turns. Aiming locks the body to the view and allows strafing. The
  `CameraPivot` is counter-rotated by `view_yaw - body_yaw`.
- **Camera:** the spring-arm pivot is centred inside the capsule; the shoulder offset lives on the
  `Camera3D` and collapses as the arm compresses. The cast is a 5 cm sphere (Godot's `cast_motion`
  ignores initial overlap, so a large sphere started inside walls). Camera occlusion by other
  players is still deferred (dither fade, CP5).
- **Weapon presentation:** the gun follows `DEF-hand.R` via an external `BoneAttachment3D`, with a
  filtered upper-body `Pistol_Aim_Neutral` hold overlay and a filtered `Pistol_Shoot` one-shot.
  Lower-body tracks stay with the main `AnimationPlayer`, so walking and shooting compose.
- **Web loop:** `Engine.max_physics_steps_per_frame = 4` and `physics_jitter_fix = 0` prevent
  background-tab catch-up bursts while still feeding 30 Hz down to ~7.5 FPS.
- **Starvation:** an empty input queue allows at most 2 extrapolated ticks, then freezes the actor.
  The ack stays pinned to the last received input; inventing an ack would have no client-side state
  to reconcile against.
- **Prediction & reconciliation (CP4b):** the client stores every locally simulated frame with its
  resulting state. A snapshot for the local id rewinds the body to the acked pose+velocity and
  replays all unacked inputs through `LocomotionComponent`. The collision body takes authority
  immediately; `Visual`/`CameraPivot` receive a decaying offset (~100 ms) so corrections are not
  visible. The first ack after join is a plain snap (spawn baseline). The server rejects a step
  whose horizontal travel exceeds `8.6 m/s × dt` and logs it.
- Every decoder rejects wrong lengths, counts above 8, and out-of-range values; the transport also caps
  packets at 2 KB and drains at most 64 per frame to prevent stalls.
- **Spawn authority:** the server owns the spawn pose and ships it in `JOIN_OK`; clients must adopt it
  or they will disagree with every other client about where they are standing.
- **Input authority:** the server consumes one queued input per tick, deduplicates by sequence and
  rate-limits at 90 frames/s. Repeating the last frame never advances the ack, so clients replay
  exactly the unacknowledged tail.
- **Yaw ownership:** the client owns aim yaw *after* its first input frame. Before that, the server keeps
  the spawn yaw so a missing packet can never spin a player to a default angle.
- Broadcasts go to joined roster peers only, never to half-open connections.
- **Hurtbox authority:** remote ghosts keep their hurtboxes so shots stop on the body, but
  `HurtboxComponent.damage_enabled = false` means clients can never apply damage to another player.
  Only the server applies damage, and the same flag carries CP4c spawn protection.

## Testing

- gdUnit4 suites live in `tests/gdunit/` and run through the vendored CLI runner (headless with
  `--ignoreHeadlessMode`); JUnit XML lands in `reports/` (git-ignored, uploaded by CI).
- Shared assertions/helpers live in `tests/gdunit/bod_test_suite.gd`; suites extend `BodTestSuite`.
- Headless runs do not transport `InputEvent`s, so tests feed `PlayerInputFrame`/physics frames
  directly instead of simulating mouse or keyboard.
- `tests/headless/` keeps the cross-process client probe and the arena budget report.
- The gdUnit4 addon is excluded from both exports; it must never ship in the PCK.

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
- Player `collision_mask` = **world only**. Players and bots do not block each other in V1, so client
  prediction never collides with 100 ms-old remote positions. Projectiles still hit hurtboxes.
- SpringArm `collision_mask` = world only.
- Hurtboxes `collision_layer` = hurtbox, `monitoring` = false; hit detection is a query, not an overlap callback.
- Projectile hit queries mask world + hurtbox. Never query player bodies for damage.

## Events (EventBus)

Only cross-system events go on the bus. Component-internal communication stays parent↔child signals.

```gdscript
# scripts/autoload/event_bus.gd
signal health_changed(entity_id: int, current: int, maximum: int)
signal damage_dealt(target_id: int, source_id: int, amount: int, hitbox: StringName, position: Vector3)
signal player_died(entity_id: int, source_id: int, position: Vector3)
signal kill_credited(killer_id: int, victim_id: int, weapon_id: StringName)
signal shot_fired(shooter_id: int, origin: Vector3, direction: Vector3, weapon_id: StringName)
signal match_state_changed(state: StringName, seconds_left: float)
signal score_changed(player_id: int, kills: int, deaths: int)
```

Conventions:
- IDs are server-assigned peer ids starting at **1**; `0` = local/solo/unassigned in offline dev.
- Events carrying truth (`damage_dealt`, `player_died`, `kill_credited`) are emitted **only by authority**.
- Cosmetic-only signals are prefixed `fx_` and may be emitted locally.
- Payloads must be serializable primitives; no node references.

## Components & scenes

```text
Player.tscn (CharacterBody3D) — roles: LOCAL (input/camera), REMOTE (snapshot-posed), SERVER (authority)
├── CollisionShape3D
├── Visual (Node3D) → Mesh/Face (presentation only)
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
- Autoloads limited to `EventBus`, `GameManager`, `Settings`, `AudioManager`; introduce them as the phase
  needs them (`Settings` in CP1, `EventBus` in CP3, `GameManager` in CP4a, `AudioManager` in CP3/CP5).

## Web constraints

- Compatibility renderer only; no SSAO/SSIL/volumetric fog/TAA.
- Single-threaded export; no `SharedArrayBuffer`/COOP/COEP requirement.
- WSS terminated at Caddy/Nginx in front of the headless server; static build served from the same origin.
- Audio unlocked on first pointer gesture; pointer lock is only requested from a click/key gesture
  (never at boot) and re-acquired on the next click after focus loss.
- Export must load with all resources packed; no runtime file access.

## Projectile hit rules (CP3+)

- Sweep from the previous tick's position to the new position each physics tick (ray/`ShapeCast3D`),
  never "move then overlap" — fast projectiles tunnel otherwise.
- Resolve **head hurtbox first**, then body, when both overlap on the same tick.
- Exclude the shooter's own hurtbox RIDs explicitly; a 3.6 m third-person camera starts the aim ray
  outside the shooter, so `hit_from_inside` is not sufficient.
- Spawn at the muzzle, but aim at the point under the crosshair (camera-center ray hit), so the
  third-person offset does not make shots miss the crosshair.
- Damage is recorded as a hit request, not applied by the projectile. `CombatResolver` is the only writer.
