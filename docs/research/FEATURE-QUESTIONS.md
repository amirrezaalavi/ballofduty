# Feature Research Questions — L2/L8, L9, L6

**Purpose:** one file to hand to the external research agent. L2/L8 and L9 are research-gated; L6 is implementation-only and needs no research.

**How to answer:** answer each question with a concrete decision, file-level migration notes, and a test that would fail if the answer is wrong. Prefer evidence from the worktree over generic Godot advice.

---

# L2/L8 — Character scale system & server parity

**Status:** research only (no gameplay, scene, resource or test changes)
**Worktree:** `ballofduty-wt-l2l8`, branch `feature/l2-l8`, base `develop@1bdb161`
**Date:** 2026-10-30
**Scope:** L2 = data-driven capsule/mesh/hurtbox/camera dimensions. L8 = client and server read the same body/camera/jump data.

This document inventories the dimensions that exist today, records who reads them, and turns the L2/L8 work into precise questions for an external research agent. Every value below was read from the worktree or measured with a temporary read-only headless probe (the probe was deleted before the commit).

---

## 1. Context that constrains the answer

- **Avatar:** 0.82 m tall, movement capsule `r 0.19 / h 0.82` at `y 0.41` (`scenes/characters/player.tscn:16-18,45-47`). The KayKit source rig is 2.543 m tall and is scaled by `0.32244` (`scripts/player/character_visual.gd:22,201`; `docs/research/kaykit-character.md:30-31,127-133`).
- **Five classes, one body:** Knight, Mage, Rogue, Rogue_Hooded, Barbarian all instantiate the same `player.tscn` and differ only by `class_id` → visual variant + weapon (`scripts/player/character_visual.gd:29-53,121-122,194-207`; `docs/PHASE2A-CONTRACTS.md:7-17`). There is no per-class size today.
- **Server authority at 30 Hz:** `project.godot:113` (`physics_ticks_per_second=30`). The server runs the same `Player.tscn` as a `SERVER` actor (`scripts/player/player_controller.gd:125-141`; `scripts/game/game_manager.gd:837-858`), steps `LocomotionComponent` from network frames (`player_controller.gd:206-207`), and broadcasts 18-byte snapshot rows (`scripts/networking/net_protocol.gd:22-28,188-224`).
- **Prediction/reconciliation:** the client replays unacked inputs through the same `LocomotionComponent` (`player_controller.gd:213-221,370-440`; `scripts/components/locomotion_component.gd:17-62`). Body dimensions affect `move_and_slide`, floor snap, step-up, spawn clearance and hit queries, so client and server must agree exactly.
- **Third-person camera:** pivot at `y 0.95`, spring arm `2.3 m`, shoulder `x 0.35`, FOV `75/48`, pitch clamp `-1.35..0.25` (`player.tscn:97-111`; `scripts/player/camera_rig.gd:8-17,28-31`). The camera yaw is counter-rotated against body yaw (`player_controller.gd:176-179`), so camera geometry is independent of body facing.
- **Web target:** Compatibility renderer, web export under 20 MB gzip / 60 fps (`project.godot:119-120`; `docs/PHASE2A-CONTRACTS.md:98`). Any solution must stay exportable as packed `.tres`/scene data and avoid runtime file access.
- **Already shared:** movement and jump values already live in `PlayerStats` and are read by both roles through `LocomotionComponent` (`scripts/components/player_stats.gd:6-30`; `resources/players/default_player.tres`; `player.tscn:49-51`; `locomotion_component.gd:7,17-62`). L8 must extend this pattern to body/camera/aim dimensions, not duplicate it.

---

## 2. Current dimension inventory

Values are current as of `1bdb161`. “Server reads” means an authoritative server code path reads the value, not merely that the node exists in the instantiated scene.

| # | Dimension | Current value | Authored at | Client reads? | Server reads? | Why it matters |
|---:|---|---|---|---|---|---|
| 1 | Movement capsule radius | `0.19 m` | `player.tscn:16-18` | yes (physics) | yes (same scene) | Body width, wall clearance, projectile exclusion, spawn validity. |
| 2 | Movement capsule height | `0.82 m` | `player.tscn:16-18` | yes | yes | Feet-to-head collision; must match visual height for readability. |
| 3 | Capsule node offset | `y 0.41 m` | `player.tscn:45-47` | yes | yes | Body origin is at the feet; capsule is centered 0.41 m up. Spawn offsets assume this. |
| 4 | Body hurtbox radius | `0.19 m` | `player.tscn:23-25` | yes (ghost shots stop here) | yes (projectile query) | Damage width; client-side ghost hit-stop must match server hit test. |
| 5 | Body hurtbox height | `0.80 m` | `player.tscn:23-25` | yes | yes | Vertical damage coverage; currently 2 cm shorter than the capsule. |
| 6 | Body hurtbox offset | `y 0.40 m` | `player.tscn:73-75` | yes | yes | Bottom at `0.00`, top at `0.80`; test asserts it stays inside the 0.82 m silhouette (`tests/gdunit/test_smoke.gd:105-114`). |
| 7 | Head hurtbox | none (single body capsule) | `test_smoke.gd:102` | n/a | n/a | No headshots today. `docs/ARCHITECTURE.md:159,207` still describes `HeadHurtbox`; documentation drift. |
| 8 | Visual uniform scale | `0.32244` | `character_visual.gd:22,201` | yes | no (server disables `Visual` processing at `player_controller.gd:139-141`) | Silhouette size. Not tied to the capsule by any runtime invariant. |
| 9 | Visual source height / result | `2.543 m → 0.820 m`; AABB `0.626 × 0.820 × 0.422 m` | `docs/research/kaykit-character.md:30-31,127-133` | yes (asset) | no | The 0.82 m capsule and the 0.82 m visual are two independent numbers that happen to agree. |
| 10 | Camera pivot height | `y 0.95 m` | `player.tscn:97-98`; duplicated as `CAMERA_PIVOT_HEIGHT` at `scripts/game/server_combat.gd:24` | yes | yes (aim ray origin) | Camera framing and server aim origin. |
| 11 | Spring arm length | `2.3 m` | `player.tscn:102`; duplicated as `CameraRig.spring_length` `camera_rig.gd:9,29` and `CAMERA_BACK` `server_combat.gd:26` | yes | yes (aim ray origin) | Third-person distance; changing it silently changes server aim if the constant is not updated. |
| 12 | Spring arm margin | `0.08 m` | `player.tscn:103` | yes | no | Camera clipping against walls. |
| 13 | Camera probe shape | `SphereShape3D r 0.05` | `player.tscn:20-21,105` | yes | no | Camera clipping; must be validated at every supported body size. |
| 14 | Camera shoulder offset | `x 0.35 m` | `player.tscn:108`; duplicated as `CameraRig.shoulder_offset` `camera_rig.gd:15,30,61` and `CAMERA_SHOULDER_X` `server_combat.gd:25` | yes | yes (aim ray origin) | Crosshair placement and aim ray origin. |
| 15 | Camera FOV / near plane | `75° / 48°`, `near 0.05` | `player.tscn:109-111`; `camera_rig.gd:10-12` | yes | no | Framing/zoom; not body data, but must stay valid if the camera height changes. |
| 16 | Eye/aim height | `0.62 m` | `server_combat.gd:19,424` | no direct counterpart | yes | Server muzzle height. The client has no equivalent “eye” value; it uses the actual hand muzzle. |
| 17 | Server shoulder muzzle offset | `(0.14, 0.0, -0.30) m` | `server_combat.gd:20,424` | no | yes | Canonical server shot origin. Not derived from the camera or the hand. |
| 18 | Client muzzle per class | `z -0.78 / -0.51 / -0.39 / -0.47 / -0.54` from the grip | `character_visual.gd:47-53,225-227` | yes | no | Visual tracer/flash origin. Differs by class and by animation pose. |
| 19 | Muzzle scene default | `(0, 0, -0.47)` | `player.tscn:88-89` | only before class swap | no | Dead/fallback authoring after `CharacterVisual._swap_weapon` runs. |
| 20 | GunMount rest offset | `(0.06, 0.56, -0.22)` | `player.tscn:83-84` | only until hand attachment | no | Fallback pose; `CharacterVisual` reparents the mount to the hand socket and zeroes its transform (`character_visual.gd:647-687`). |
| 21 | Hand socket / grip offset | bone `handslot.r`, `HAND_OFFSET (0, 0.02, 0)` | `character_visual.gd:23-26,647-687` | yes | no | Actual muzzle position follows the animated hand, not a fixed body offset. |
| 22 | Death marker size | disc `r 0.38`, shell capsule `r 0.24 / h 0.80` at `y 0.40` | `character_visual.gd:418-452` | yes | no | Cosmetic corpse marker that duplicates body/hurtbox dimensions. |
| 23 | Spawn foot offset | `+0.2 m` above the marker | `game_manager.gd:532,554,852` | client adopts `JOIN_OK` pose | yes | Spawn drop height; should scale/derive from the body if sizes change. |
| 24 | Bot aim / LOS heights | aim `+0.45`; LOS `+0.45` and `+0.6` | `game_manager.gd:639,726-727,777-778` | no | yes | Bot aim and visibility assume a human-sized torso/head. |
| 25 | Floor snap / max angle | `0.3 m`, `45°` | `player.tscn:41-42` | yes | yes | Step/ramp behavior; body-size dependent. |
| 26 | Training dummy body/hurtbox | capsule `r 0.35 / h 1.10` at `y 0.55`; hurtbox `r 0.36 / h 1.62` at `y 0.81` | `scenes/characters/training_dummy.tscn:8-10,55-58,112-117` | yes | yes | Target hit volume. Not a player, but a candidate for the same body-profile concept. |
| 27 | Crouch / height state | none | n/a | n/a | n/a | No crouch, slide or variable-height state exists today. |
| 28 | Class-specific body size | none; all five classes use the same scene/capsule | `character_visual.gd:121-122` | n/a | n/a | The five classes are visually different but physically identical. |

### Baseline that is already correct

`PlayerStats` already holds `move_speed`, sprint, acceleration, jump velocity, gravity, fall multiplier, terminal velocity, coyote/buffer and turn speeds (`player_stats.gd:6-30`). `LocomotionComponent` is the only consumer on both roles (`player.tscn:49-51`; `locomotion_component.gd:7,17-62`; server step at `player_controller.gd:206-207`). L2/L8 should not move these fields again; the question is whether body/camera data joins them or lives beside them.

---

## 3. Measured parity probe (read-only, temporary)

A temporary `SceneTree` probe instantiated `scenes/characters/player.tscn` on a floor at yaw 0, let the hand attachment settle, and compared the live nodes with `ServerCombat`’s static helpers. It was deleted before the commit.

| Measurement | Client (live scene) | Server helper | Delta |
|---|---|---|---|
| Body capsule | center `(0, 0.41, 0)`, `r 0.19`, `h 0.82` | same scene / same physics | 0 |
| Body hurtbox | center `(0, 0.40, 0)`, `r 0.19`, `h 0.80` | same scene / same physics | 0 |
| Visual scale | `(0.32244, 0.32244, 0.32244)` | not read (Visual disabled) | n/a |
| Camera, yaw 0, idle | local `(0.35, 0.95, 2.3)` relative to feet | `camera_origin` = `(0.35, 0.95, 2.3)` | `0.000 m` at rest |
| Muzzle, class 0, idle | `(0.074, 0.190, -0.804)` relative to feet | `canonical_muzzle` = `(0.14, 0.62, -0.30)` | **`0.666 m`** |
| Muzzle local marker | `(0, 0, -0.78)` under `GunMount` | fixed body-space offset | per-class / per-pose |

The camera matches at rest because `server_combat.gd:21-26` copies the current camera constants by hand. The muzzle does **not** match: the client fires its visual tracer from the animated right hand, while the server spawns the authoritative round from a fixed “eye + shoulder” point. The gap is 0.67 m for the Knight at idle and changes with class and animation.

---

## 4. Duplication and parity map

### 4.1 Camera constants are copied, not shared

`server_combat.gd:19-26` hard-codes `EYE_HEIGHT 0.62`, `SHOULDER (0.14, 0, -0.30)`, `CAMERA_PIVOT_HEIGHT 0.95`, `CAMERA_SHOULDER_X 0.35`, `CAMERA_BACK 2.3`. The client authors the same camera values in three places:

- `player.tscn:97-98` pivot `y 0.95`;
- `player.tscn:102` spring `2.3` **and** `camera_rig.gd:9,29` export `2.3` (the script overwrites the node at `_ready`);
- `player.tscn:108` camera `x 0.35` **and** `camera_rig.gd:15,30,61` `shoulder_offset 0.35` (the script overwrites the node).

Changing the camera in the scene/script without editing `server_combat.gd` silently desynchronises the server’s aim ray. There is no test that fails when they diverge.

### 4.2 The client camera compresses; the server camera does not

`CameraRig.update_aim` collapses the shoulder and the `SpringArm3D` shortens against world geometry (`camera_rig.gd:49-61`; scene mask `player.tscn:101-105`; regression test `tests/gdunit/test_world_geometry.gd:37-52`). The server’s `camera_origin` is always the full `2.3 m` behind the pivot (`server_combat.gd:449-455`), and `_aim_direction` traces from that fixed point (`server_combat.gd:458-468`). Near a wall the client’s crosshair ray and the server’s aim ray start from different points, so the authoritative shot direction can disagree with what the player sees. This is a real L8 gap, not just a cosmetic one.

### 4.3 Two independent 0.82 m values

The capsule is `0.82` (`player.tscn:16-18`); the visual is `2.543 × 0.32244 = 0.820` (`character_visual.gd:22,201`; `kaykit-character.md:30-31,127-133`). Nothing asserts they stay equal. Changing the capsule alone changes collision without changing the silhouette; changing `SCALE` alone changes the silhouette without changing collision.

### 4.4 Hurtbox and capsule are separate shapes

The hurtbox is `r 0.19 / h 0.80` at `y 0.40`; the movement capsule is `r 0.19 / h 0.82` at `y 0.41` (`player.tscn:16-25,45-47,73-75`). The 2 cm difference is deliberate today (tests at `test_smoke.gd:105-114`), but any data-driven system must preserve the relationship or make it explicit.

### 4.5 Client muzzle is hand-animated; server muzzle is fixed

The client’s visual shot origin is `muzzle.global_position` under the animated `handslot.r` (`weapon_controller.gd:398,429-443`; `character_visual.gd:647-687`), with per-class `MUZZLE_LOCAL` (`character_visual.gd:47-53,225-227`). The server’s origin is `canonical_muzzle` (`server_combat.gd:260,422-424`). Remote viewers render tracers from the server’s `SHOT` event origin (`game_manager.gd:1038-1043`), while the shooter renders from the hand. The same shot therefore has different visible origins for the shooter and for everyone else.

### 4.6 Body-size assumptions are scattered

Spawn `+0.2 m`, bot aim `+0.45 m`, LOS probes `+0.45/+0.6 m` (`game_manager.gd:532,554,639,726-727,777-778,852`) and the death marker (`character_visual.gd:418-452`) all encode “human-sized body” assumptions. A larger or smaller class would need these values revisited.

### 4.7 Documentation drift

- `docs/ARCHITECTURE.md:159,207` describes `BodyHurtbox / HeadHurtbox` and “resolve head hurtbox first”, but the scene has no `HeadHurtbox` and `test_smoke.gd:102` asserts its absence.
- `docs/research/kaykit-character.md:544-545` records a body hurtbox `r 0.19 / h 0.58 / y 0.29`; the current scene is `r 0.19 / h 0.80 / y 0.40`.
- `test_smoke.gd:84,122` still describes the avatar as “40% smaller” in comments; the numbers are current but the prose is historical.

These do not break gameplay, but they are exactly the kind of stale constant the L2/L8 work should eliminate.

---

## 5. Questions for the research agent

Answer each with a concrete schema/decision, file-level migration notes, and a test that would fail if the answer is wrong. Prefer evidence from this worktree over generic Godot advice.

### Q1 — Resource schema and source of truth

1. Should body/camera data be added to `PlayerStats`, split into a new `CharacterBodyStats`/`BodyProfile` resource, or composed as a sub-resource (`PlayerStats.body: BodyProfile`)?
2. How do we avoid duplicating movement data? `PlayerStats` already owns movement and jump (`player_stats.gd:6-30`); the body profile should not re-export `move_speed`, `jump_velocity`, etc.
3. Is the profile **per class** (`resources/players/knight_body.tres`, etc.), **per archetype** (small/medium/large), or **per scene** with class overrides?
4. Who applies the profile: `PlayerController._ready`, a `BodyComponent`, `LocomotionComponent`, or a static helper? It must run on `LOCAL`, `REMOTE` and `SERVER` roles (`player_controller.gd:63-141`).
5. What is the exact field list and default values that reproduce today’s rig byte-for-byte (capsule, hurtbox, visual scale, camera pivot/spring/shoulder, eye/aim, muzzle)? Which fields are body-space vs world-space?
6. How does the server load the profile without a scene node reference? A `PackedScene` `ext_resource` already gives both roles the same `.tres` (`player.tscn:4`), but the profile must be readable before/without `Visual`.

### Q2 — How scale is represented

1. Is the canonical value a uniform `visual_scale` plus explicit capsule/hurtbox dimensions, or a single `height` from which capsule/visual/hurtbox are derived?
2. What breaks under non-uniform scale? Consider `CharacterBody3D`/`CollisionShape3D` scaling, skinning, animation retargeting, `BoneAttachment3D`, the hand muzzle, `SpringArm3D`, and the death marker.
3. If `height` is canonical, what are the derivation rules and tolerances (capsule height = height, radius = height × k, hurtbox = height − margin, pivot = height × k, eye = height × k, spring = f(height))? Which of these should stay independent so artists can tune a class?
4. How do we validate a profile at load time (positive dimensions, capsule bottom at 0, hurtbox inside capsule, muzzle inside weapon reach, camera pivot inside capsule, spring length sane) and fail loudly in CI instead of silently producing a bad hitbox?
5. Does the answer change for the training dummy (`training_dummy.tscn:8-10,112-117`), which is 1.1/1.62 m and not a player?

### Q3 — Sharing without node references

1. What is the cleanest way to keep resources free of `NodePath`/`Node` references while still applying values to `CollisionShape3D`, `BodyHurtbox`, `CharacterVisual`, `CameraPivot`, `SpringArm3D`, `Camera3D` and the muzzle marker?
2. Should there be a single `BodyProfile.apply_to(actor)` helper, a `BodyComponent` node that owns the shapes, or per-consumer `configure(profile)` methods? Which keeps the server headless path free of rendering work?
3. How do `REMOTE` ghosts get the same body/hurtbox as the server? Today `make_remote` keeps `BodyHurtbox` for client-side shot stopping but disables damage (`player_controller.gd:90-122`). If the server’s hurtbox changes, the ghost’s must change too, or client-side shots stop in the wrong place.
4. Where should the profile live so `GameManager` can read it for spawn/LOS heights (`game_manager.gd:532,639,726-727`) without importing `CharacterVisual`?

### Q4 — Wire representation

1. Is `class_id` (already in `JOIN_REQ`, `JOIN_OK`, `ROSTER`; `net_protocol.gd:52-142`) sufficient to select the body profile, or does the body need its own `body_id`/`profile_id`?
2. Can a class/body change mid-match? If yes, what message updates it, how do `ROSTER` updates reach existing remotes (`game_manager.gd:1013-1024` only spawns new remotes), and how does prediction handle a capsule resize (teleport, history invalidation, correction burst)?
3. If class is locked per match, where is that enforced (menu, `JOIN_REQ`, server `sanitize_class` at `net_protocol.gd:39-40`), and what happens to a forged/unknown class?
4. Is a wire field needed at all if the profile is a pure function of `class_id` and both sides ship the same `.tres`? What is the failure mode for a client with stale resources (protocol version bump at `net_protocol.gd:22`)?
5. How does the 18-byte snapshot row (`net_protocol.gd:28,188-224`) stay unchanged? If not, what is the byte budget and the version-gate test (`test_net_version`)?

### Q5 — Hurtbox authoring and hit-test identity

1. Should the body hurtbox be a capsule, a sphere, or multiple volumes (head/torso/legs)? Today it is one capsule and there is no headshot (`test_smoke.gd:102`).
2. How do we guarantee the client ghost’s hurtbox and the server’s authoritative hit volume are the **same shape, size, offset and transform**? Is sharing a `Shape3D` resource enough, or do we need a generated shape from the profile on both sides?
3. If multiple volumes are introduced, how is priority resolved (the old doc says head first, `ARCHITECTURE.md:207`), and how does that interact with the server’s ray/`ShapeCast3D` sweep?
4. Should the hurtbox be slightly smaller than the capsule (today `0.80` vs `0.82`) or exactly the capsule? What is the gameplay reason for either?
5. How do we test edge hits: top of head, feet, left/right shoulder, and a shot that grazes the capsule but misses the hurtbox?

### Q6 — Camera, eye and muzzle derivation

1. Which camera values are **body data** (pivot height, spring length, shoulder offset, probe radius, FOV?) and which are **user/presentation settings** (FOV, sensitivity, scope zoom)?
2. How does the server reproduce the client’s **effective** aim origin when the spring arm is compressed by a wall? Options: replicate the spring-arm query server-side, send an aim point from the client (untrusted), use a fixed camera origin for both aim and crosshair, or accept a documented divergence. What does each cost in fairness and cheat surface?
3. Should the camera pivot be a fixed body-space point (today `y 0.95`) or derived from height/eye height? How do we keep the camera independent of body facing while the body turns (`player_controller.gd:176-179`)?
4. What is the canonical muzzle: a body-space offset per class (stable, server-friendly) or the animated hand bone (accurate visual, pose-dependent)? Can we make the client render the tracer from the canonical muzzle while keeping the flash on the hand, or vice versa?
5. If the muzzle is body-space, where does the per-class weapon length live (`WeaponStats` vs body profile vs `CharacterVisual.MUZZLE_LOCAL`)? Note the current per-class values `-0.78/-0.51/-0.39/-0.47/-0.54` (`character_visual.gd:47-53`) and the server’s single `SHOULDER` constant.
6. How should `EYE_HEIGHT 0.62` relate to the camera pivot `0.95` and the actual hand muzzle `~0.19`? Today these are three unrelated numbers.

### Q7 — Migration path for five classes and future variants

1. What is the safest first migration: add a profile that reproduces today’s exact values for all five classes, wire both roles to read it, then tune per class? What is the rollback point?
2. How do we keep the five existing classes visually and physically identical during the first step, so `test_smoke`, `test_rig`, `test_server_combat`, `test_class_weapons` and `test_world_geometry` stay green?
3. How are future variants (e.g. a larger Barbarian, a smaller Rogue, a hooded variant with the same rig) expressed without duplicating scenes? Does `CharacterVisual.variant_index_for` (`character_visual.gd:121-122`) become a profile lookup?
4. What happens to the class picker, `JOIN_OK` spawn adoption (`game_manager.gd:976-1000`), respawn (`player_controller.gd:254-269`), bots (`game_manager.gd:595-602`) and remote ghosts when the profile changes?
5. What is the acceptance bar for “no visual/hitbox regression”: exact old numbers for step 1, then per-class measurements and screenshots for step 2?

### Q8 — Tests and measurements that prove parity

1. What is the single parity test that instantiates a `LOCAL` and a `SERVER` actor from the same profile and asserts capsule, hurtbox, camera origin, eye/muzzle and jump values are equal within tolerance?
2. How do we measure the visual silhouette vs capsule (AABB of the scaled character, foot at y=0) and assert it is within, say, ±2 cm of the profile height?
3. How do we test camera clipping at the smallest and largest supported size, on flat ground, against a wall, and on a ramp? `test_world_geometry.gd:37-52` is the current single-size regression.
4. How do we test muzzle parity per class at idle, walking, aiming and firing, given the hand bone moves? What tolerance is meaningful (2 cm? 10 cm?) and what is the fallback if the hand cannot match the canonical origin?
5. How do we test hurtbox edge hits and ghost hit-stop parity, including `damage_enabled=false` on remotes (`player_controller.gd:112-118`)?
6. How do we test prediction stability after a profile change (corrections/sec, ack error) using the existing metrics (`player_controller.gd:335-355`; `test_prediction`, `test_net_loopback`)?
7. What web-export check proves the new `.tres` files are packed and load without runtime file access?

---

## 6. Options and trade-offs

For each area: **do nothing**, **tune**, **architectural**. “Gain” is relative to L2/L8 acceptance; “risk” includes netcode and web-export risk.

| Area | Do nothing | Tune | Architectural |
|---|---|---|---|
| Schema (Q1) | Keep literals; L2/L8 stay todo. Gain 0. Risk: every size change is a multi-file edit. | Add a few exports to `PlayerStats` (`capsule_height`, `visual_scale`) and read them in `_ready`. Gain: small, quick. Risk: movement and body data blur; camera/server still duplicated; no per-class profiles. | New `CharacterBodyStats`/`BodyProfile` composed with `PlayerStats`; one `.tres` per class/archetype; `apply_to` helper. Gain: real source of truth, testable, extensible. Risk: migration touches scene, controller, camera, server, tests; must preserve exact defaults. |
| Scale representation (Q2) | Keep `SCALE=0.32244` + capsule literals. Gain 0. | Add `visual_scale` and explicit capsule/hurtbox fields; keep them independent. Gain: artists can tune silhouette and collision separately. Risk: drift between the two unless validated. | Single canonical `height` + derivation rules with load-time invariants; explicit overrides only where art requires. Gain: one number per class, fewer mistakes. Risk: derivation may not fit all rigs/weapons; needs tolerance and override policy. |
| Sharing (Q3) | Keep scene literals; server duplicates constants. Gain 0. | Move values into a resource but apply only on the client; server still uses constants. Gain: partial. Risk: **worse** L8 (server silently stale). | Resource read by both roles; `apply_to` on `LOCAL`/`REMOTE`/`SERVER`; server reads plain floats, never `Visual`. Gain: true parity. Risk: headless server must not depend on rendering nodes; tests must cover all three roles. |
| Wire (Q4) | Keep `class_id` only; no mid-match changes. Gain 0, but matches current behavior. | Add `body_id`/`profile_id` to `JOIN_REQ`/`JOIN_OK`/`ROSTER`. Gain: decouples body from class. Risk: protocol bump, version-gate test, more bytes. | Lock class/body per match and treat profile as a pure function of `class_id`; roster updates only on join. Gain: no wire change, simplest prediction. Risk: no mid-match class change; future modes need a new message. |
| Hurtbox (Q5) | Keep one `0.80` capsule. Gain 0. | Parameterize the existing capsule (radius/height/offset) from the profile; keep one volume. Gain: sizes work, minimal risk. Risk: no headshots, still one shape. | Multi-volume head/torso/legs with explicit priority and shared shape generation. Gain: future headshots and better silhouette fit. Risk: hit-test ordering, server/client parity, more tests. |
| Camera/eye/muzzle (Q6) | Keep duplicated constants and fixed server muzzle. Gain 0; known 0.67 m visual gap and wall-aim gap remain. | Share camera constants via a resource, keep the hand muzzle and accept a documented visual delta. Gain: fixes camera drift, not muzzle/wall. Risk: still two muzzle truths. | One `CameraProfile` + canonical body-space muzzle shared by both roles; decide how to handle spring-arm compression (server query or fixed-origin policy). Gain: aim parity. Risk: server-side spring-arm query cost/complexity; muzzle visual may need a tracer-origin change. |
| Migration (Q7) | No migration. | Add one profile with today’s values, then per-class profiles. Gain: incremental, testable. Risk: temporary dual sources during the transition. | Big-bang rewrite of scene/controller/server. Gain: clean end state. Risk: high regression surface, hard to bisect. |
| Tests (Q8) | Keep literal assertions. | Add a parity test and a silhouette test. Gain: catches the main regressions. Risk: may miss camera clipping at extreme sizes. | Full matrix: per-class body/hurtbox/camera/muzzle, wall/ramp clipping, prediction metrics, web export. Gain: strong acceptance. Risk: test runtime and maintenance. |

**Recommendation to evaluate, not a decision:** architectural schema + incremental migration, with a first profile that is numerically identical to today. It is the only option that satisfies L8 without leaving a second source of truth, and it keeps the existing tests meaningful as migration guards.

---

## 7. Acceptance tests and falsification criteria

### Proposed acceptance tests

1. **`test_body_profile_parity`** — load the profile, instantiate `LOCAL` and `SERVER` actors, assert capsule radius/height/offset, hurtbox shape/offset, visual scale, camera pivot/spring/shoulder, eye/aim height and muzzle offset match the resource on both roles.
2. **`test_class_body_profiles`** — for each `class_id` 0..4, assert the profile is selected by `class_id` (not `net_id`), the visual variant matches, and the capsule/hurtbox are applied on `LOCAL`, `REMOTE` and `SERVER`.
3. **`test_silhouette_matches_capsule`** — measure the scaled character AABB with feet at y=0; assert height within ±0.02 m of the profile and the capsule bottom/top inside the silhouette.
4. **`test_hurtbox_edges`** — fire at the top, bottom and sides of the hurtbox; assert hits/misses match between the server query and the client ghost query; assert a grazing capsule shot that misses the hurtbox does not damage.
5. **`test_camera_origin_parity`** — at yaw/pitch samples, assert the server’s aim origin equals the client camera origin within epsilon when unobstructed; separately test the documented policy when the spring arm is compressed by a wall.
6. **`test_muzzle_parity`** — per class, at idle/aim/fire, assert the client’s rendered tracer origin and the server’s canonical muzzle agree within the chosen tolerance (or that the divergence is intentional and bounded).
7. **`test_camera_clipping_sizes`** — for min and max supported body sizes, place the player against the cliff/wall and on a ramp; assert the camera stays outside geometry and does not collapse behind the body (extend `test_world_geometry.gd:37-52`).
8. **`test_spawn_and_bot_heights`** — spawn/LOS/aim offsets derive from the profile; a larger class does not spawn inside the floor or aim at the wrong torso height.
9. **`test_profile_validation`** — malformed profiles (negative size, hurtbox outside capsule, pivot outside body, muzzle behind the body) fail at load with a clear error.
10. **`test_web_export_loads_profiles`** — exported build loads every profile without runtime file access (CI export gate).

### Falsification criteria

The answer/migration is wrong if any of these is true:

- A dimension still exists as a literal in a script or scene after the migration, or two files can disagree without a failing test.
- Changing the resource changes the client but not the server (or vice versa) for capsule, hurtbox, camera origin, eye height or muzzle.
- The client and server report different body/hurtbox/camera/muzzle values for the same `class_id` beyond the documented tolerance.
- The visual silhouette and capsule diverge by more than the agreed tolerance at any supported size.
- A shot that visibly hits the body on the client does not damage on the server, or vice versa, at any hurtbox edge.
- The camera clips geometry or collapses behind the player at the smallest/largest supported size.
- Prediction corrections per second or ack error regress materially after a profile change (compare with `prediction_stats()` at `player_controller.gd:335-355`).
- The web export grows past the budget or fails to load a profile.
- The first migration step changes any of today’s five classes’ dimensions or hit results.

---

## 8. Do not do

- **Do not scale `CharacterBody3D` non-uniformly.** It scales children (visual, camera, hurtbox) and is not a supported way to resize a physics body; Godot warns about scaled collision shapes. Use explicit capsule/hurtbox dimensions.
- **Do not scale `CollisionShape3D` to fake a size.** Physics shape scaling is unreliable and breaks the server/client contract. Author radius/height/offset.
- **Do not put `NodePath` or `Node` references in the body/camera resource.** Resources are shared data; node lookup belongs in an `apply_to` helper on the actor.
- **Do not sync node paths or scene paths over the wire.** `class_id`/`body_id` selects a local resource; never send `res://` paths or node paths.
- **Do not do per-frame resource lookups.** Load the profile once per actor (or preload it) and cache the applied values.
- **Do not derive the capsule from the visual AABB at runtime.** It makes physics depend on animation/mesh state and breaks determinism.
- **Do not let `CharacterVisual` be the only place scale is applied.** The server disables `Visual` (`player_controller.gd:139-141`); body data must be applied independently.
- **Do not change class/body size mid-match without a protocol and prediction plan.** A capsule resize invalidates prediction history and can teleport actors out of geometry.
- **Do not use negative scale** to mirror the character; the current rig uses positive uniform scale + 180° yaw (`kaykit-character.md:31-32,750-755`).
- **Do not scale the weapon with the character.** `test_rig.gd:50-53` asserts the gun keeps world scale `1.0`; the hand socket and per-class muzzle offsets are the contract.
- **Do not “fix” the muzzle by moving the hand bone or the visual only.** The server’s canonical origin is the authority; the client visual must be reconciled deliberately.
- **Do not update test constants blindly.** The first migration step must keep the old numbers as defaults so a changed test means a real regression.

---

## 9. Proposed implementation sequence (after the answers arrive; no code here)

1. **Decide the schema and policy** (Q1–Q6): profile fields, per-class vs per-archetype, wire policy, hurtbox shape policy, camera-collision policy, muzzle policy. Write the decision into `docs/PHASE2A-CONTRACTS.md` or a new `docs/L2-L8-CONTRACTS.md`.
2. **Add the resource with today’s exact values.** One `BodyProfile`/`CharacterBodyStats` `.tres` per class (or one shared profile first). Defaults reproduce `0.19/0.82/0.41`, `0.19/0.80/0.40`, `0.32244`, `0.95/2.3/0.35/0.08/0.05`, eye `0.62`, per-class muzzle offsets. No behavior change expected.
3. **Wire the client first, read-only.** `PlayerController` (or a new `BodyComponent`) applies the profile to the capsule, hurtbox, `CharacterVisual`, `CameraRig` and muzzle on `LOCAL`/`REMOTE`; keep the old scene values as fallback until tests pass.
4. **Wire the server to the same resource.** Replace `server_combat.gd:19-26` constants with profile reads; derive `canonical_muzzle`/`camera_origin` from the profile. Keep the server headless: no `Visual` reads, no rendering dependencies.
5. **Resolve the two hard parity decisions:** camera compression vs server aim origin (Q6.2) and hand muzzle vs canonical muzzle (Q6.4). Add the parity tests before tuning per-class sizes.
6. **Introduce per-class sizes** only after step 5 is green. Start with one class (e.g. Barbarian taller, Rogue shorter), measure silhouette/capsule/hurtbox/camera, then roll out. Update the class picker/roster only if the wire policy requires it.
7. **Add the acceptance matrix:** per-class body/hurtbox/camera/muzzle, wall/ramp clipping at min/max size, edge hits, prediction metrics, web export.
8. **Remove the old literals and stale docs.** Delete duplicated constants, update `ARCHITECTURE.md` (head hurtbox drift), `kaykit-character.md` (hurtbox drift) and the historical comments in `test_smoke.gd`.
9. **Run the full gate:** `./tools/check.sh --skip-export` first, then the web export/CI gate. Confirm `test_smoke`, `test_movement`, `test_rig`, `test_server_combat`, `test_class_weapons`, `test_world_geometry`, `test_prediction`, `test_net_loopback` and the new parity tests are green.

Likely touch list for the implementation phase (for estimation only): `scripts/components/player_stats.gd` or new `scripts/components/character_body_stats.gd`; `resources/players/*.tres`; `scenes/characters/player.tscn`; `scripts/player/player_controller.gd`; `scripts/player/character_visual.gd`; `scripts/player/camera_rig.gd`; `scripts/components/hurtbox_component.gd`; `scripts/game/server_combat.gd`; `scripts/game/game_manager.gd` (spawn/LOS/aim heights); `scripts/networking/net_protocol.gd` only if the wire policy requires a body id; the six existing tests plus new parity tests; `docs/ARCHITECTURE.md`, `docs/BACKLOG.md`, `docs/research/kaykit-character.md`.

---

## 10. Decisions the user must make before implementation

1. **Per-class body size or one shared size?** The five classes are identical today. If they stay identical, L2 is mostly a refactor; if they diverge, L8 needs a wire/prediction policy.
2. **Camera compression parity:** should the server replicate the spring arm, should both sides use a fixed aim origin, or is a documented near-wall divergence acceptable?
3. **Muzzle truth:** canonical body-space muzzle (server-friendly) vs animated hand muzzle (visual), and which one the tracer uses for the shooter and for remotes.
4. **Hurtbox model:** keep one capsule or introduce head/torso volumes now. The docs already promise headshots; the scene and tests do not.
5. **Crouch/variable height:** out of scope for L2/L8 v1, but the schema should leave room (a `height_state`/`stance` field) or explicitly exclude it.

---

## Appendix A — Files read for this brief

- `scripts/components/player_stats.gd`, `scripts/components/locomotion_component.gd`, `scripts/components/hurtbox_component.gd`, `scripts/components/health_component.gd`
- `scenes/characters/player.tscn`, `scenes/characters/training_dummy.tscn`
- `scripts/player/player_controller.gd`, `scripts/player/character_visual.gd`, `scripts/player/camera_rig.gd`
- `scripts/game/server_combat.gd`, `scripts/game/game_manager.gd`
- `scripts/networking/net_protocol.gd`
- `scripts/weapons/weapon_controller.gd`
- `tests/gdunit/test_smoke.gd`, `test_movement.gd`, `test_rig.gd`, `test_server_combat.gd`, `test_class_weapons.gd`, `test_world_geometry.gd`, `test_kaykit.gd`
- `docs/ARCHITECTURE.md`, `docs/PHASE2A-CONTRACTS.md`, `docs/BACKLOG.md`, `docs/research/kaykit-character.md`
- `project.godot`

## Appendix B — Probe notes

The temporary probe (`tools/_probe_l2l8.gd`, deleted) used `SceneTree` + `physics_frame`/`process_frame`, a 40×1×40 floor at `y -0.55`, and the real `player.tscn`. It printed the live `CollisionShape3D`, `BodyHurtbox/CollisionShape3D`, `CharacterVisual.character.scale`, `CameraPivot`, `SpringArm3D/Camera3D` and the muzzle found under `GunHand/GripSocket/GunMount`, then compared them with `ServerCombat.canonical_muzzle`/`camera_origin`. The camera was also watched from a `process_priority = 100` node to confirm the shoulder offset is applied in normal play (`x 0.35`), not just authored in the scene.

---

## Part 2 — L9 browser matrix

# L9 — Browser matrix research brief (CP5)

**Status:** questions open, no implementation started.
**Owner:** build/CI (L9), with the user supplying real Firefox/Safari/low-end hardware.
**Asked:** 2026-10-30, from `develop` @ `1bdb161`.
**Deliverable wanted:** a decision-ready answer to the seven questions in §4, plus a matrix
that a second person can execute without asking us anything.

**How to answer:** edit this file in place (or reply in chat) with one section per question.
Every claim needs either a citation (browser bug, Godot issue, vendor doc) or a measurement
with the device/browser/build recorded. If something cannot be measured, say so explicitly —
"unverified" is an acceptable answer, a guess is not.

**See also:** [`PERFORMANCE-AUDIT-2026-10-30.md`](PERFORMANCE-AUDIT-2026-10-30.md) §7 (the
open real-device measurements), [`../PLAYTEST-2026-10-29.md`](../PLAYTEST-2026-10-29.md)
(Firefox issue list), [`../BACKLOG.md`](../BACKLOG.md) S33/S34/S35/L9,
[`../ROADMAP.md`](../ROADMAP.md) Phase 5 acceptance criteria.

---

## 1. Context (verified in this worktree)

| Fact | Evidence |
|---|---|
| Godot **4.7.2-stable**, Compatibility renderer on desktop and mobile | `project.godot:16`, `project.godot:119-120` |
| Single-threaded web export, no `SharedArrayBuffer`/COOP/COEP | `export_presets.cfg:26` (`variant/thread_support=false`), `docs/DEPLOY.md:3-4`, `docs/ARCHITECTURE.md:194-201`; confirmed at runtime: console prints `single-threaded, no GDExtension support` |
| 30 Hz physics + 30 Hz snapshots, binary, 6 + 18·n bytes | `project.godot:113-114`, `scripts/networking/net_protocol.gd:26-28` |
| Actor caps: V1 accepts **8 total actors**; protocol allows **16** (294 B snapshot at 16) | `docs/BACKLOG.md:36`, `scripts/networking/net_protocol.gd:23`, `tests/headless/net16_probe.gd:1-15` |
| Maps: Sunken Quarry **150×150 m**; quantization supports **±327.68 m / 250 m maps** | `docs/BACKLOG.md:31`, `docs/ARCHITECTURE.md:50` |
| Five classes (Knight, Mage, Rogue, Rogue Hooded, Barbarian) | `resources/content/entries/class_*.tres` |
| Design resolution **1280×720**, `canvas_items` stretch, adaptive canvas | `project.godot:30-32`, `export_presets.cfg:32` |
| Custom shell with boot progress + missing-feature notice | `web/shell.html:283-301`, `web/shell.html:383-411` |
| One origin: static + `/ws` tunnel; HTML `no-store`, assets `no-cache` | `tools/serve.py:192-199`, `tools/serve.py:78-93`, `tools/dev.sh:5-11` |
| CI = import → gdUnit4 → arena → boots → web/server export → gzip size | `tools/check.sh:77-91`, `.github/workflows/ci.yml:29-30` |
| Existing browser tooling = one Playwright screenshot at 1280×720 | `tools/capture.sh:22-25` |
| Mobile/touch is **out of scope for V1** | `docs/ROADMAP.md:26`; input map is keyboard/mouse only (`project.godot:34-100`) |
| No touch/virtual keyboard | `export_presets.cfg:34` (`html/experimental_virtual_keyboard=false`) |
| PWA/service worker disabled | `export_presets.cfg:35-36` |

**Branch base:** `1bdb161`. Since this branch was cut, `develop` has advanced to `83db67e`
("Merge feature/l6: settings UI" + settings guard), which adds a render-quality setting with a 3D resolution
scale and directional shadow distance (`scripts/autoload/settings.gd` on `develop`). The
risk register and Q6 describe the **branch base**; re-validate the exact knobs against the
merged `develop` before implementation. Do not merge/rebase this branch to get them — the
L9 implementation phase will be rebased deliberately by the manager.

### 1.1 What the current build actually weighs (measured today, this worktree)

Exported with `./tools/godot --headless --path . --export-release "Web" build/web/index.html`
after a clean import. Sizes are bytes on disk; gzip is `gzip -6`.

| File | Raw | gzip -6 |
|---|---|---|
| `index.wasm` | 39,514,754 (37.7 MiB) | 10,142,423 (9.7 MiB) |
| `index.pck` | 5,992,928 (5.7 MiB) | 4,360,561 (4.2 MiB) |
| `index.js` | 279,815 | 68,668 |
| whole directory | 44,796 KiB | ≈ 14.6 MB total |

This is in line with `docs/TESTING.md:65` (44,768 KB raw / 14,244 KB gzip) and the audit's
`docs/research/PERFORMANCE-AUDIT-2026-10-30.md:250` (WEB-01: 39.5 MB wasm raw / 10.1 MB gzip).
The CP5 budget is ≤ 25 MB gzipped (`docs/ROADMAP.md:255`), so payload size passes **only if**
the host serves precompressed assets; `tools/serve.py` does not precompress and CI does not
serve over a CDN.

### 1.2 Browser capabilities measured in this sandbox (not release evidence)

Playwright 1.64.1, browsers from `/srv/opencode/pkg/playwright`, 1280×720, headless, Linux x86_64.

| Probe | Chromium 156.0.8078.4 | Firefox 157.0 |
|---|---|---|
| WebGL2 | **yes** | **no** (`AllowWebgl2:false restricts context creation on this system`) |
| WebGL renderer | `ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero)), SwiftShader driver)` | n/a |
| `SharedArrayBuffer` / `crossOriginIsolated` | false / false | false / false |
| Pointer Lock / Fullscreen / AudioContext API | yes / yes / yes | yes / yes / yes |
| Boot of exported build | overlay removed, canvas 1280×720, **no page errors** | shell shows "could not start … WebGL2" notice; never boots |
| rAF during 2 s of quarry | **2 frames** (≈ 1 fps, software raster) | n/a (no engine) |
| Time to engine start | **7.9 s** (cold, SwiftShader) | n/a |

Consequences:

- **Chromium numbers here are software-rasterised and must never be quoted as 720p/60
  evidence.** The `GPU stall due to ReadPixels` warnings are SwiftShader artefacts.
- **Headless Playwright Firefox cannot be used as a Firefox gate in this sandbox.** The
  failure is a hard pref (`AllowWebgl2:false`), and forcing `webgl.force-enabled`,
  `gfx.webrender.software`, etc. via `firefoxUserPrefs` did not change it. `docs/checkpoints/CP0.md:20`
  calls this a "headless GPU limitation"; it is stricter than that.
- No `webkit` browser is installed here, and Playwright WebKit on Linux is **not** Safari
  (no Apple GPU/driver, no iOS). Treat it as a third engine, not Safari coverage.

---

## 2. Test matrix proposal

### 2.1 Hardware classes

| ID | Class | Spec (minimum) | Why |
|---|---|---|---|
| **H1** | Reference low-end laptop | 2C/4T (e.g. i3-1115G4 / Ryzen 3 5300U), Intel UHD/Iris Xe, 8 GB, Win 11, 60 Hz, DPR 1, SSD, plugged in | The 720p/60 claim is only meaningful here |
| **H2** | Apple laptop | M1/M2 MacBook Air, 8 GB, macOS 26, 60 Hz | Safari desktop + Metal/ANGLE parity |
| **H3** | Mid mobile | Pixel 6a (Mali-G78) or iPhone 13 (A15), 4 GB | Load-only today (no touch controls) |
| **H4** | Discrete desktop | RTX 3060 / RX 6600, 1080p 144 Hz | Upper bound, not a gate |

Record GPU model, driver version, OS build, DPR, browser zoom (must be 100 %), extensions
(disabled), power profile (plugged in, no battery saver), and ambient temperature.

### 2.2 Browser / OS / network cells

Versions are proposals — Q1 must confirm or correct them. The sandbox builds observed here
(Chromium 156.0.8078.4, Firefox 157.0) are Playwright bundles, not necessarily the current
public stable; treat the numbers as illustrative.

**Tiers:** **G0** = release blocker (must pass before shipping), **G1** = supported and
measured each release but not blocking, **G2** = CI/proxy only (Linux desktop is not a
consumer target).

| Cell | Browser | OS | HW | Resolution | Network | Tier |
|---|---|---|---|---|---|---|
| C1 | Chrome latest (156+) | Win 11 | H1 | 1280×720 | LAN | **G0** |
| C2 | Edge latest (156+) | Win 11 | H1 | 1280×720 | LAN | **G0** |
| C3 | Firefox latest (157+) | Win 11 | H1 | 1280×720 | LAN | **G0** |
| C4 | Safari latest (26+) | macOS 26 | H2 | 1280×720 | LAN | **G0** |
| C5 | Chrome latest | macOS 26 | H2 | 1280×720 | LAN | G1 |
| C6 | Chrome latest | Ubuntu 24.04 | H1-class VM | 1280×720 | LAN | G2 (CI proxy) |
| C7 | Firefox latest | Ubuntu 24.04 | H1-class VM | 1280×720 | LAN | G2 (CI proxy) |
| C8 | Chrome latest | Android 15/16 | Pixel 6a | 390×844 | 4G | G1 (load-only) |
| C9 | Safari latest | iOS 26 | iPhone 13 | 390×844 | 4G | G1 (load-only) |
| C10 | Chrome latest | Win 11 | H1 | 1920×1080 | LAN | G1 |
| C11 | Firefox latest | Win 11 | H1 | 1280×720 | 100 ms / 1 % loss | **G0** |
| C12 | Chrome latest | Win 11 | H1 | 1280×720 | 4G (50 ms / 1 %) | G1 |
| C13 | Safari latest | macOS 26 | H2 | 1280×720 | 100 ms / 1 % | G1 |

Minimum supported versions (to be confirmed by Q1): Chrome/Edge **last 2 stable majors**,
Firefox **latest + previous**, Safari/iOS **current + previous major**, Android Chrome
**latest on Android 13+**. Anything older is "unsupported, may work".

Network profiles:

- **N1 LAN:** ≤ 5 ms RTT, 0 % loss, ≥ 100 Mbps.
- **N2 4G:** 50 ms RTT ± 10 ms, 1 % loss, 10 Mbps down / 3 Mbps up.
- **N3 adverse:** 100 ms RTT ± 20 ms, 1 % loss, 5 Mbps, TCP (no jitter buffer beyond the
  game's 2-interval + 1-tick extrapolation).

Shape with `tc netem` on the server host or a router, not only DevTools throttling (DevTools
does shape WebSocket, but it does not reproduce TCP retransmit behaviour at the OS level).

### 2.3 Per-cell measurements

Run each cell on a **named build hash** with a fixed scripted scenario: join `?join=1`, pick
one class, 8 actors (at least 4 human clients or 4 bots), 5 minutes, no menu idling. Warm up
10 s, then measure 60 s. Three runs per cell; report the **median run's** p95 (not the best
run).

| # | Metric | Method | G0 target | G1 target | Fail |
|---|---|---|---|---|---|
| M1 | Cold load | `navigationStart` → `#boot` removed (shell `startGame()` resolved, `web/shell.html:415-431`) | ≤ 10 s N1 | ≤ 15 s N1 / ≤ 25 s N2 | > 20 s N1 or > 35 s N2 |
| M2 | First frame | engine start → first rAF with a non-blank canvas | ≤ 5 s N1 | ≤ 8 s N1 | > 10 s, or shell notice |
| M3 | Frame p95 | rAF interval over 60 s after warm-up | **≤ 16.7 ms** | ≤ 20 ms | > 25 ms |
| M4 | Frame p99 / stalls | same samples | p99 ≤ 33 ms, 0 frames > 250 ms | p99 ≤ 50 ms | any frame > 500 ms |
| M5 | Average FPS | same samples | ≥ 55 | ≥ 45 | < 30 |
| M6 | Draw calls / tris | Godot `Performance` monitors (to be exposed) or Spector.js | ≤ 80 calls, ≤ 250 k tris | ≤ 120 calls | > 150 calls |
| M7 | Memory | `WebAssembly.Memory.buffer.byteLength` + `performance.memory` | ≤ 512 MB, growth ≤ 10 % after warm-up | ≤ 768 MB | OOM / `RangeError` / growth > 25 % |
| M8 | Pointer lock | click canvas → `document.pointerLockElement.id === "canvas"`; Esc releases; click re-acquires; alt-tab then one click re-acquires | all pass, ≤ 1 frame | same | lock never acquired, or camera spins on re-acquire |
| M9 | Audio | `AudioContext.state` after first gesture; shot/reload audible; no "prevented from starting" after gesture | `running`, audible | `running` | silent with no on-screen hint |
| M10 | Reconnect | drop socket mid-match (kill server / `tc` drop 3 s); then restore | HUD "lost" ≤ 1 s, reconnect ≤ 8 s (`RECONNECT_GRACE_MSEC`), no ghosts | same, ≤ 12 s | stuck in CLIENT limbo, stale ghosts, or silent offline |
| M11 | Input latency | pointer delta → rendered yaw change (instrumented) + optional 240 fps camera | ≤ 100 ms | ≤ 130 ms | > 200 ms, or unmeasurable |
| M12 | Tab throttling | background 30 s → foreground; check server input rate and state convergence | no input burst (> 4 steps/frame), converge ≤ 2 s | same | burst, desync, or frozen actor |
| M13 | Fullscreen | browser fullscreen + in-game request; canvas fills; pointer lock survives | pass | pass | letterboxed/stuck |
| M14 | Console | console + page errors for 5 min | 0 errors; warnings triaged | 0 errors | any uncaught error / engine abort |

C8/C9 (mobile) are **load-only**: M1, M2, M7, M9, M14 only. There are no touch controls
(`docs/ROADMAP.md:26`), so do not record mobile frame rate as a game result.

M3/M4 assume 60 Hz vsync; on a 60 Hz panel rAF intervals quantise to 16.67 ms, so p95
"≤ 16.7 ms" means essentially no missed vsync. Q4 must confirm whether the gate should use
rAF-interval p95 or a separate in-engine frame-time p95, and whether p99 ≤ 33 ms is the
right stall criterion.

---

## 3. Known risk register (substantiated from the repo)

| # | Risk | Evidence | Status |
|---|---|---|---|
| R1 | Headless Firefox cannot create WebGL2 here, so "Firefox coverage" cannot be automated in this sandbox | probe above; `docs/checkpoints/CP0.md:20` | **confirmed** |
| R2 | No real-GPU browser frame number exists anywhere in the repo; Chromium evidence is SwiftShader | probe above; `docs/research/PERFORMANCE-AUDIT-2026-10-30.md:47-49` ("native x86_64 numbers, not browser numbers") | **confirmed** |
| R3 | No resolution scale / quality tier **at this branch base**; 3D renders at window size with 90 m PSSM shadows (L6 on `develop` now adds both — re-check) | `project.godot:30-32` (no `rendering/scaling_3d`), `scenes/maps/arena_quarry.tscn:41-44`, `docs/BACKLOG.md:80` (L6 settings UI todo), `docs/ROADMAP.md:245` | **confirmed (base)** |
| R4 | Cold payload is ~14.6 MB gzip / 45.8 MB raw, single-threaded, no service worker; mobile VRAM compression is off | measured above; `export_presets.cfg:27-28,35` | **confirmed** |
| R5 | Background tabs throttle hard; two browser tabs in one browser cannot both simulate | `docs/PLAYTEST-2026-10-29.md:108`, `docs/checkpoints/CP4a.md:68`, `scripts/game/main.gd:42-46` (catch-up cap only) | **confirmed** |
| R6 | No explicit audio unlock / "click for sound" hint; shell only mentions pointer lock | `web/shell.html:299`, `scripts/autoload/audio_manager.gd:8-53` (no resume path), `docs/BACKLOG.md:22` (S35 pending), `docs/PLAYTEST-2026-10-29.md:104` | **confirmed** |
| R7 | Pointer lock is released on focus-out and only re-acquired by a canvas click; no `visibilitychange` path | `scripts/player/player_controller.gd:74-75,157-168` | **confirmed** (by design, but untested across browsers) |
| R8 | Firefox WebGL warnings (depth-filter LINEAR, attrib-0, viewport rect, `try` deprecation) are untriaged | `docs/PLAYTEST-2026-10-29.md:92-108`, `docs/BACKLOG.md:24` (S33 deferred) | **open** |
| R9 | Mobile is not playable (keyboard/mouse input map, virtual keyboard off) | `docs/ROADMAP.md:26`, `project.godot:34-100`, `export_presets.cfg:34` | **confirmed** |
| R10 | 16-actor snapshot is 294 B and the client decodes up to 16, but V1 only ships 8 actors; browser cost of 16 remotes is unmeasured | `scripts/networking/net_protocol.gd:23-28`, `tests/headless/net16_probe.gd` | **unmeasured** |
| R11 | CI has no browser job and no remote yet | `.github/workflows/ci.yml:29-30`, `docs/CI.md:3-4` | **confirmed** |

---

## 4. Questions for the research agent

Answer each with: recommendation, evidence/citation, confidence, and "what would change
your mind". Where the answer depends on our build, say which measurement we must run.

### Q1 — Which matrix is realistic, and what can be deferred?

For a web-first indie shooter shipping in late 2026 with 8–16 actors, 150–250 m maps and a
720p/60 target:

1. Which of C1–C13 are genuinely required for release, which are "supported but not gated",
   and which should be explicitly unsupported? Give a one-line rationale per cell.
2. What are the real minimum versions (WebGL2 + WASM + Pointer Lock + Web Audio) for
   Chrome, Edge, Firefox, Safari desktop, iOS Safari, Android Chrome? Cite caniuse/MDN or
   vendor docs, not memory.
3. Is Edge a separate cell or is it Chromium with a different update cadence and GPU
   blocklist? What Edge-specific failure modes exist (SmartScreen, enterprise policy,
   `--disable-gpu` fallbacks)?
4. Which hardware class is the honest "low-end laptop" in 2026, and is H1 above or below
   the median Steam/browser user? If H1 is too weak or too strong, propose the corrected
   spec.
5. What share of the target audience is Firefox/Safari-only, and does that justify a hard
   gate or a "best effort" label?

### Q2 — Godot 4.7.2 Compatibility/WebGL2 limitations per browser

1. Enumerate known Godot 4.7.x WebGL2 issues per engine (Firefox, Safari desktop, iOS
   Safari, Android Chrome): depth-texture filtering, vertex attrib 0, viewport/destination
   rect mismatch, PSSM shadows, `gl_compatibility` limits, `try`/`try_table` EH
   deprecation, audio worklet startup, pointer lock, fullscreen.
2. Which of these are **release blockers** (cannot boot / cannot play / visual corruption),
   which are performance-only, and which are cosmetic warnings we can suppress?
3. Does Godot 4.7.2 ship a Safari/iOS-specific known-issues list? Link the exact
   GitHub issues/PRs and whether they are fixed in 4.7.x or only in 4.8/dev.
4. Are the Firefox warnings in `docs/PLAYTEST-2026-10-29.md:92-108` engine bugs, our
   material settings, or harmless? For each, name the setting/flag to test.
5. Does single-threaded WASM change any of the above (e.g. shader compile on the main
   thread, audio worklet fallback, no `SharedArrayBuffer`)?
6. Is the Compatibility renderer still the right choice for a 2026 web release, or does
   Mobile/Forward+ on WebGPU change the matrix? (Assume we will not switch engines for V1;
   answer for planning, not as a proposal.)

### Q3 — How to automate Firefox/WebKit coverage, and what can CI run?

1. Given that headless Playwright Firefox in our sandbox cannot create WebGL2 at all, what
   are the viable options: xvfb + headed Firefox, a Firefox build with software WebGL,
   `MOZ_*` env/prefs, BrowserStack/Sauce Labs Firefox, or a self-hosted runner with a GPU?
   Give exact commands/prefs that are known to work in 2026.
2. Is Playwright WebKit on Linux useful as a proxy for Safari? What does it *not* cover
   (Apple GPU/driver, iOS memory limits, Safari audio, JIT differences, touch)?
3. What can CI realistically gate: boot smoke, console-error budget, pointer-lock API
   presence, screenshot diff, WebSocket join? What must stay manual (real frame rate,
   thermal throttling, audio)?
4. Cost/ops: GitHub-hosted runners (GPU? none), self-hosted low-end laptop, BrowserStack
   vs Sauce Labs plans, per-parallel-session pricing, and whether either exposes real
   Safari/iOS with WebGL2 and performance traces.
5. How should we store evidence (JSON metrics, screenshots, console logs, traces) so a
   release can be audited later?

### Q3a — Automation feasibility check (answer with a concrete experiment)

Propose the smallest experiment that proves a Firefox or Safari engine can boot our build
and join a match, with the exact browser version, flags/prefs, host OS and expected console
output. If no such experiment exists in CI-compatible form, say so and name the manual
fallback. Do **not** propose "run Playwright Firefox" without addressing the
`AllowWebgl2:false` result in §1.2.

### Q4 — Minimum reproducible performance harness and noise protocol

1. What is the minimum instrumentation to measure M1–M7 credibly in a browser: rAF
   sampling, `PerformanceObserver("longtask")`, `performance.memory` (Chrome-only),
   `WebAssembly.Memory.buffer.byteLength`, WebGL timer queries
   (`EXT_disjoint_timer_query_webgl2`), Spector.js, Chrome tracing, Firefox profiler?
2. Which of these work in Safari/iOS and Firefox, and which are Chromium-only? What is the
   fallback when timer queries are unavailable?
3. What is the correct noise protocol: warm-up length, run count, statistic (median p95 vs
   mean), handling of shader-compile first frames, thermal soak, DPR/zoom, OS compositor
   scaling, browser backgrounding, and how to detect a throttled/thermal-limited run?
4. What run-to-run variance is normal on integrated GPUs, and what threshold should
   invalidate a run (we propose > 15 % p95 spread across 3 runs)?
5. How do we separate CPU-bound from GPU-bound frames without a GPU timer (e.g. compare
   720p vs 480p render scale, HUD on/off, shadows on/off)?
6. What is the smallest scripted scenario that still represents a real match (bot count,
   movement, shooting, respawns) and how long must it run to catch hitches?

### Q5 — Which current features are at risk?

For each, say how it fails per browser and what the test is:

1. **Pointer lock:** request from click only (`player_controller.gd:157-163`), release on
   focus-out, no auto re-acquire. Safari/iOS behaviour, Esc handling, fullscreen
   interaction, `pointerlockerror`.
2. **Audio autoplay:** no explicit unlock in `audio_manager.gd`; Godot's web audio driver
   resume semantics per browser; worklet vs ScriptProcessor fallback; muted-tab behaviour.
3. **Tab throttling:** background rAF to ~1 fps; `Engine.max_physics_steps_per_frame = 4`
   (`main.gd:45`); input bursts, ack pinning, server kick/timeout.
4. **WASM memory:** 39.5 MB module + heap; iOS Safari per-tab limits; growth from bullet
   pool/remote scenes; OOM behaviour and recovery.
5. **WebSocket reconnect:** 6 s initial budget, 8 s mid-match grace
   (`network_manager.gd:35-44`); TCP head-of-line; proxies/CDNs that idle-timeout `/ws`;
   Safari/iOS background suspension.
6. **Fullscreen + canvas resize:** adaptive policy (`export_presets.cfg:32`), DPR changes,
   orientation change, Safari toolbar collapse.
7. **Mobile keyboard:** virtual keyboard off (`export_presets.cfg:34`); is there any
   supported path for names/chat on mobile, or is mobile explicitly load-only?
8. **Anything else** you consider a likely blocker for this specific stack (Godot 4.7.2
   Compatibility + single-threaded + 30 Hz WebSocket).

### Q6 — Fallbacks and degradation

1. Which levers give the most frame time per unit of visual damage on this renderer:
   `rendering/scaling_3d/scale`, shadow distance (90 → 45 m), shadow casters, MSAA,
   triplanar terrain, fog, HUD redraw, bullet visuals, remote-actor count?
2. How should the game choose a tier: static device class (UA/GPU string), measured
   first-30-s frame time, user setting, or a combination? Give a concrete rule with
   hysteresis so it does not oscillate.
3. What should the user see when a tier is applied (silent, toast, settings entry)?
4. What is the minimum acceptable visual quality at 720p on H1, and what must never be
   degraded (crosshair visibility, enemy readability, hit feedback)?
5. What is the fallback if WebGL2 is missing (current shell shows a notice,
   `web/shell.html:383-411`)? Is a static "unsupported browser" page enough, or do we need
   a WebGL1 path (probably not — confirm)?
6. Should mobile get a "desktop only" gate at load time rather than a broken playable page?

### Q7 — What evidence justifies blocking a release?

1. Define blocker vs warning per metric (M1–M14) and per cell. We propose: any G0 cell
   failing M1/M2/M3/M8/M9/M10/M14 blocks; M4–M7/M11–M13 are warnings unless they make the
   game unplayable.
2. What sample size and confidence are needed before calling a cell "pass"? Is 3×60 s
   enough, or does thermal drift require longer?
3. What is the escalation path when only one browser fails (ship with a banner? delay?
   drop the cell from the supported list?) — give a decision rule, not a vibe.
4. Which failures are acceptable to ship with a known-issues note (e.g. Firefox warning
   spam, iOS load-only)?
5. What evidence must be attached to the release record (build hash, browser versions,
   device specs, JSON metrics, screenshots, console logs, server logs)?

---

## 5. Options (cost / risk)

| Option | What it means | Cost | Risk | Verdict |
|---|---|---|---|---|
| **A. Do nothing** | Ship Chromium-only; label Firefox/Safari unsupported | 0 | High: CP5 gate explicitly requires Chrome/Firefox/Safari (`docs/ROADMAP.md:254`); Firefox/Safari users hit a boot or audio/lock failure with no signal | Reject |
| **B. Manual matrix** | Two people, C1–C5 + C8/C9, one pass per release candidate, checklist + screenshots | ~1–2 person-days per release; hardware owned by user | Human variance, no regression detection, easy to skip under deadline | **Minimum viable**; required regardless |
| **C. Automated matrix** | Playwright projects (Chromium + Firefox + WebKit) in CI: boot smoke, console budget, join, screenshot; JSON artifacts | ~3–5 engineer-days setup + CI minutes; no real GPU | Cannot measure real frame rate; WebKit ≠ Safari; Firefox headless WebGL2 unavailable here | **Do it for smoke**, not perf |
| **D. Device lab** | BrowserStack/Sauce for Safari/iOS/Android + one owned H1 laptop | ~$100–300/month + 1–2 days setup | Virtualised GPUs make perf numbers unreliable; still need H1 for 720p/60 | Use for **compatibility** on C4/C8/C9, not perf |
| **E. Self-hosted device rack** | Owned H1 + Mac mini + iPhone + Android, runner with display | Hardware cost + maintenance | Best fidelity, slowest to set up, single point of failure | Only if C+D cannot cover a blocker |

Recommended combination: **B for perf on H1/H2, C for boot/console smoke, D only for
Safari/iOS compatibility if no Apple hardware is available.** Do not let C or D produce the
720p/60 number.

---

## 6. Acceptance tests for the research answer

The research phase is done when:

1. **A1** Every cell in §2.2 has a browser version, OS, hardware spec and an owner.
2. **A2** Every threshold in §2.3 has a method a second person can run from a written
   command, with the expected output shape.
3. **A3** The automation recommendation names at least one **tested** path that renders
   WebGL2 in Firefox or Safari, or explicitly states that none exists and why.
4. **A4** The blocker list separates "cannot boot", "cannot play", "too slow", and
   "cosmetic warning".
5. **A5** Cost includes CI minutes and any device-lab subscription, with a monthly figure.
6. **A6** Fallbacks have a selection rule, a hysteresis rule, and a user-visible signal.
7. **A7** No claim violates §7.

### Falsification criteria

Reject an answer if any of these is true:

- It treats **Playwright WebKit on Linux as Safari** coverage.
- It treats **headless Playwright Firefox in this sandbox** as a Firefox gate (our probe
  shows `AllowWebgl2:false`; `docs/checkpoints/CP0.md:20` is stale on the cause).
- It quotes a frame rate from **SwiftShader/llvmpipe** as device evidence.
- It reports an **average FPS** without p95/p99 and stall counts.
- It measures with the HUD hidden, shadows off, or a smaller render scale without saying so.
- It claims reconnect works after only a **clean server shutdown** (TCP FIN), not a silent
  drop or 3 s blackhole.
- It claims mobile "works" while the build has no touch controls.
- It claims "no console errors" while ignoring warnings that are known WebGL failures.

---

## 7. Do not claim without measurement

- "60 fps at 720p on a low-end laptop" — no real-GPU browser number exists yet.
- "Firefox works" — only the missing-WebGL2 notice has been observed.
- "Safari/iOS works" — never run.
- "Loads in X seconds on 4G" — only cold localhost/SwiftShader was measured.
- "Memory is stable" — no 60 s sample, no iOS limit test.
- "Pointer lock recovers after tab switch" — focus-out release exists; re-acquire is a
  click, untested per browser.
- "Audio starts after first click" — no `AudioContext.state` check in the build.
- "Reconnect is seamless" — only unit/loopback tests, no browser socket drop.
- "Payload is under 25 MB" — true for gzip-on-disk, not for an arbitrary host; Brotli and
  CDN behaviour are unmeasured.
- "Firefox warnings are harmless" — untriaged (R8).

---

## 8. Proposed implementation sequence (after answers arrive)

No code in this phase; this is the order we will execute.

1. **Freeze the matrix** in this file (cells, thresholds, owners) and add a
   `docs/BROWSER-MATRIX.md` runbook with one checklist per cell and a JSON recording
   template.
2. **Add a measurement surface** (first code change): a `?perf=1` path that records
   navigation → engine start → first frame, rAF p50/p95/p99/max, long tasks, WASM heap,
   draw calls/tris, and emits one JSON blob (console + downloadable). Keep it inert in
   normal play.
3. **Expose degradation levers**: resolution scale, shadow distance/casters, MSAA, HUD
   throttle, remote-actor effects — all behind one quality tier with hysteresis (Q6).
4. **Add `tests/browser/` Playwright config**: projects `chromium` (gate), `firefox`
   (smoke only if WebGL2 is available), `webkit` (labelled "engine smoke, not Safari").
   Reuse `tools/serve.py` + `tools/dev.sh` and ephemeral ports.
5. **CI job `browser-smoke`**: build web once, start server + proxy, run Playwright, upload
   JSON/screenshots/console logs/traces. No perf gate in CI.
6. **Manual perf run**: H1 + H2, C1–C4/C10/C11, three runs each, recorded in
   `docs/checkpoints/CP5.md`.
7. **Device-lab pass** only for C4/C8/C9 if no owned Apple/Android hardware; record it as
   compatibility evidence, not performance.
8. **Promote to gates** after two consecutive releases with < 15 % run-to-run spread:
   M1/M2/M3/M8/M9/M10/M14 block; the rest warn.

---

## 9. Appendix — commands used for the evidence in this brief

```bash
# export + sizes (writes only gitignored build/)
./tools/godot --headless --path . --import
./tools/godot --headless --path . --export-release "Web" build/web/index.html
gzip -6 -c build/web/index.wasm | wc -c
gzip -6 -c build/web/index.pck  | wc -c

# serve the build without a game server
python3 tools/serve.py --root build/web --bind 127.0.0.1 --port 8399 --no-proxy

# browser capability + boot probe (Playwright 1.64.1)
PLAYWRIGHT_BROWSERS_PATH=/srv/opencode/pkg/playwright \
NODE_PATH=/srv/opencode/pkg/npm/lib/node_modules \
node /srv/opencode/tmp/opencode/l9-boot-probe.js
```

Raw probe output: `/srv/opencode/tmp/opencode/l9-boot.json` (not committed).
