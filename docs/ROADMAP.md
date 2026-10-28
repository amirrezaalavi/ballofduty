# Ball of Duty — Roadmap & Acceptance Criteria

Status: **CP0 in progress** · Engine: **Godot 4.7.2 (GDScript)** · Renderer: **Compatibility**
Platform: **Web (primary) + native desktop/headless Linux (dev & server)**

A checkpoint is **done** only when every acceptance criterion is met and the evidence is recorded
in `docs/checkpoints/CPn.md` (numbers, screenshots, logs — not "looks good").

---

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Server | Godot 4.7.2 headless, authoritative | Same scene/physics as client; no reimplementation of Godot's wire protocol |
| Transport | `WebSocketMultiplayerPeer` (WSS in prod) | Only option for browser clients; works for desktop too |
| Simulation | 30 Hz fixed tick, client prediction + reconciliation | Matches snapshot rate; predictable CPU and bandwidth |
| Snapshot rate | 30 Hz, binary `PackedByteArray`, ≤ 300 B | 8 players; ~7 KB/s downstream; no delta compression for V1 |
| Combat | Server-spawned projectiles, client cosmetic tracer | No lag-compensation/rewind needed for V1 |
| Interpolation | 2 intervals (67 ms) + jitter margin, newest-wins | ~100 ms render delay; late packets hold last pose, no snap-back |
| Match | Auto-join room, max 8, 5-min FFA, 3 s respawn | Smallest complete game loop |
| Web export | Single-threaded, Compatibility, no SAB | Works on any static host without COOP/COEP |
| Game scope | 1 arena, 1 rifle, no accounts/progression | Prove the loop before content |

Out of scope for V1: matchmaking, room codes, accounts, progression, cosmetics, multiple weapons/maps,
chat/voice, mobile/touch, recoil patterns beyond cosmetic, anti-cheat beyond server validation.

---

## Phase 0 — Foundation & pipeline  *(CP0)*

**Owner:** me. **Gate:** none.

### Tasks
1. Pin Godot 4.7.2 editor + export templates; install locally; document paths.
2. Repo skeleton, `.gitignore`, `.gitattributes`, CI.
3. Project settings: Compatibility renderer, 30 Hz physics, 1280×720 base, canvas-items stretch,
   single-threaded web export, audio bus layout.
4. Input map (`move_*`, `jump`, `fire`, `aim`, `reload`, `scoreboard`, `pause`), collision layer table.
5. Grey-box arena (`arena_greybox.tscn`): floor, ramp, cover blocks, perimeter walls, 8 spawn markers.
6. `Player.tscn` component skeleton + stub controller (enough to walk around).
7. Headless server entry scene that boots, logs, and exits cleanly.
8. Web export preset + Linux server export preset; custom HTML shell with progress + error text.
9. Smoke test script (`tools/check.sh`): headless import, headless boot, web export, server export.
10. CI workflow building both artifacts and uploading them.

### Acceptance criteria
- [ ] `godot --headless --path . --quit` completes with **0 errors**; any warnings are triaged in the evidence file.
- [ ] Project opens in the editor with Compatibility renderer; no Forward+/Mobile references.
- [ ] `--headless --quit-after 120 --max-fps 60 -- --server --port 9080` boots, logs the listen banner **and a physics-tick probe** (no SIGTERM requirement; Godot does not trap it).
- [ ] Web build loads in Chrome and Firefox from `http://localhost` with **no console errors**, pointer lock works, grey-box scene renders.
- [ ] Web initial payload **≤ 20 MB gzipped**; load to interactive **≤ 10 s** on localhost.
- [ ] Linux server build starts without X11/display and prints the listen banner; WebSocket handshake is verified in CP4a.
- [ ] `tools/check.sh` passes on a clean checkout; the CI workflow is committed (first green remote run deferred until a remote exists — tracked as a CP0 follow-up).
- [ ] `config/version` is visible on the in-game boot overlay (build SHA recorded in the evidence file).
- [ ] Collision layer table documented in `docs/ARCHITECTURE.md` and used consistently.

---

## Phase 1 — Movement, camera & feel *(CP1)*

**Owner:** me (build), **you** (feel test). **Gate:** CP0 green.

### Tasks
1. `Player.tscn`: `CharacterBody3D`, capsule, head/body `Area3D` hurtboxes (layers only, no damage yet),
   placeholder mesh, `HealthComponent`, `LocomotionComponent`, `CameraRig`, `InputHandler`.
2. `PlayerController.gd`: run at `_physics_process` 30 Hz; acceleration/friction; gravity; `move_and_slide`;
   normalized diagonals; mesh yaw via `lerp_angle`.
3. Mouse-look **per render frame**, accumulated into the tick's input frame; pitch clamp.
4. Spring-arm camera: shoulder offset, collision mask world-only, margin, wall-clip test.
5. RMB scope: FOV 75 → 55 within 100 ms; sensitivity scaling while scoped.
6. Input capture: click to capture, `Esc` release, re-capture on click, focus-loss handling.
7. Debug overlay: FPS, physics tick, velocity, input seq, camera distance; `F3` toggle.
8. Small test course: flat ground, ramp, wall, gap.
9. Minimal `Settings` autoload: sensitivity + invert-Y persisted to `user://settings.cfg` (full settings UI lands in CP5).

### Acceptance criteria
- [ ] Travel distance over 3 s at 30/60/144 FPS differs by **< 2%** (measured, logged); rendering is smooth via physics interpolation (no 30 Hz camera judder).
- [ ] Mouse-look has no 30 Hz stepping; a 360° turn shows no visible stair-stepping at 144 FPS.
- [ ] Diagonal movement is **not** faster than cardinal (≤ 0.1% difference).
- [ ] Camera does not clip through the test wall; spring arm recovers smoothly in < 200 ms.
- [ ] Scope reach 55° FOV in < 100 ms; releasing returns to 75° in < 100 ms.
- [ ] Player cannot fall through the floor at 30 FPS or while walking down the ramp.
- [ ] No `Input.is_key_pressed`-style hardcoded keys remain; all actions come from the InputMap.
- [ ] Sensitivity and invert-Y persist across restarts (minimal `Settings` autoload).
- [ ] **Your sign-off:** camera distance, shoulder offset, FOV, speed, and scope feel right.

---

## Phase 2 — Arena, assets & lighting *(CP2)*

**Owner:** you (asset selection), me (integration/optimization). **Gate:** CP1 signed off.

### Tasks
1. Asset audit: one pack family (Kenney **or** Quaternius), consistent scale/palette; `assets/CREDITS.md`.
2. Arena layout 60×60 m: cover loops, 2–3 sightlines, 8 spawn points ≥ 15 m apart, visible boundaries.
3. Scatter tool: seeded, idempotent, excludes spawns/paths/overlaps; `MultiMeshInstance3D` for repeats.
4. Collision: terrain trimesh/HeightMapShape, large props only; invisible perimeter walls; kill plane.
5. Lighting: one directional light, low-res or no shadows, ambient via sky/vertex colors; no SSAO/SSIL/fog/glow.
6. Import hygiene: ETC2/ASTC textures ≤ 1024 px, shadow casting off on small props, LODs off.
7. Out-of-bounds reset + spawn-point visualization toggle (`F4`, dev only).

### Acceptance criteria
- [ ] Walking the full perimeter and every ramp/cover piece: **no stuck spots, no fall-throughs, no clipping**.
- [ ] 8 spawn markers, pairwise distance ≥ 15 m, none inside geometry.
- [ ] Draw calls **≤ 150**, triangles **≤ 250k**, texture memory **≤ 100 MB**, 1 directional light.
- [ ] 60 FPS at 1280×720 on the reference low-end device (Intel UHD-class); else resolution scale fallback documented.
- [ ] Seeded scatter produces identical output on re-run; running twice adds no duplicates.
- [ ] Assets are CC0/CC-BY with attribution in `CREDITS.md`; no unlicensed files.
- [ ] Visual style reads as one coherent cute low-poly set (palette, scale, shading).

---

## Phase 3 — Local combat, HUD & audio *(CP3)*

**Owner:** me (build), **you** (feel test). **Gate:** CP2 budgets met.

### Tasks
1. `WeaponStats` resource: damage, headshot multiplier, projectile speed, fire rate, spread, magazine,
   reserve, reload time, automatic, recoil, muzzle offset, projectile scene, lifetime.
2. `Projectile.tscn`: **ShapeCast/ray sweep** per tick (no tunneling); muzzle → crosshair convergence.
3. `HurtboxComponent` with `owner_id` + multiplier; head/body on player and dummies; self-hit exclusion.
4. `HealthComponent`: `health_changed`, `died(source_id, position)`; server-ready API.
5. `CombatResolver` single damage entry point (local authority now, server authority later).
6. HUD: crosshair (dynamic spread), health, ammo/reserve, reload indicator, hitmarker, damage vignette,
   directional damage arrow, kill feed.
7. FX/audio: muzzle flash, tracer, impact puff, shoot/hit/death/reload SFX, light camera kick.
8. Dummies: static + strafing, auto-reset, head/body hitboxes.

### Acceptance criteria
- [ ] All weapon values come from `.tres`; zero gameplay magic numbers in scripts (verified by review).
- [ ] Body damage 25, headshot 50 (2×), rifle 10 rps, magazine 30, reload 1.6 s — matches resource.
- [ ] 20/20 shots hit a 0.4 m head hurtbox at 5, 15, 30 m with no tunneling at 30 Hz.
- [ ] Crosshair convergence: projectile lands within 0.1 m of the aim point at 5/15/30 m.
- [ ] Cannot fire while reloading, cannot reload a full magazine, auto-reload at 0 works.
- [ ] HUD reflects state within 1 frame; damage flash and hitmarker fire exactly once per event.
- [ ] Shooter can never damage their own hurtboxes; friendly fire disabled.
- [ ] Damage flows exclusively through `CombatResolver` (grep-verifiable); switching to server authority is a one-file change.
- [ ] **Your sign-off:** shooting/impact/audio feel and TTK are fun.

---

## Phase 4a — Transport & replication *(CP4a)*

**Owner:** me (build), **you** (two-client test). **Gate:** CP3 signed off.

### Tasks
1. `NetworkManager` autoload: client connect/disconnect; server listen; CLI `--server --port`.
2. Headless server scene: no camera/HUD/local player; deterministic world load.
3. Join/leave handshake: assign id + sanitized name, broadcast roster, clean despawn.
4. Minimal input path: `{seq, move, jump, sprint, aim_yaw, aim_pitch, scope}` at 30 Hz; server simulates movement and acks each player's last processed seq (full reconciliation in 4b).
5. Snapshot encode/decode: `{tick, seq, players:[{id, pos, yaw, state, hp, acked_input_seq}]}` at 30 Hz, binary and quantized.
6. `NetworkInterpolator` on remote players: 67 ms buffer + jitter margin, newest-wins (drop stale), extrapolation ≤ 1 tick or hold last pose.
7. Motion-state replication (idle/run/air) and yaw; animation driven locally from state.
8. Dev instrumentation: snapshots processed/dropped, snapshot bytes, RTT, server tick offset.

### Acceptance criteria
- [ ] 2 browser clients + 1 desktop client join simultaneously; all see each other move.
- [ ] Remote movement is smooth at 60 and 144 FPS; **no visible teleporting** while walking/running.
- [ ] Snapshot size ≤ 300 B with 8 players; downstream ≤ 10 KB/s per client (quantized, binary).
- [ ] Server process runs with no display; CPU < 25% of one core with 8 connected clients idle.
- [ ] Client processes at most one snapshot per tick after draining and keeps the newest; processed/dropped counters are logged.
- [ ] Join mid-match spawns a player; leaving removes the node and the scoreboard row within 1 s.
- [ ] Malformed/oversized packets are rejected without crashing or stalling the server.
- [ ] At simulated 100 ms RTT + 20 ms jitter, remote interpolation stays smooth with ≤ 1 tick extrapolation; late packets never cause snap-back (local input lag is expected at this stage).

---

## Phase 4b — Movement prediction & reconciliation *(CP4b)*

**Owner:** me (build), **you** (latency test). **Gate:** CP4a acceptance.

### Tasks
1. Input frames `{seq, move, jump, aim_yaw, aim_pitch, scope}` sent at 30 Hz; sequence ring buffer.
2. Server simulation of the **same** `LocomotionComponent` from inputs; acks last processed seq.
3. Session token + 30 s reconnect grace (defined here, consumed in 4d).
4. Client rewind-and-replay of unacked inputs on each snapshot; smooth visual correction over 100 ms.
5. Fixed-tick local simulation with render interpolation; no variable-dt movement.
6. Server validation: input rate limit, sequence dedupe, and a server-side displacement assertion (`|Δpos| ≤ max_speed·dt + ε`) — no position packets exist to trust or reject.
7. Correction meters: position error, correction count/s, replay depth; RTT graph.

### Acceptance criteria
- [ ] Metric defined: server position at the acked tick vs the client's stored state for that same tick. At loopback, p95 error **< 0.02 m** steady-state.
- [ ] At 100 ms RTT + 20 ms jitter, p95 error **< 0.05 m** and corrections are invisible (no rubber-banding). A small residual is acceptable; browser-wasm vs native contact ordering is not bit-identical.
- [ ] Wall sliding and stair/ramp behavior identical on client and server (side-by-side replay test).
- [ ] Input replay depth stays ≤ 8 frames at 150 ms RTT.
- [ ] Server rejects impossible displacement (2× speed) within 1 s and logs it; legitimate movement is never falsely rejected.
- [ ] Disconnect during movement leaves no ghost; reconnect within the 30 s grace restores identity and score.
- [ ] **Your sign-off:** movement feels responsive at 100–150 ms simulated latency.

---

## Phase 4c — Combat authority & bots *(CP4c)*

**Owner:** me (build), **you** (gameplay test). **Gate:** CP4b acceptance.

### Tasks
1. Fire intent `{seq, client_tick, aim_yaw, aim_pitch, buttons}` → server derives origin/direction from its own player state, validates fire rate/ammo/ownership, spawns authoritative projectile.
2. Client cosmetic tracer prediction; hitmarker/kill confirmed by server events.
3. Server hurtbox resolution + damage + death + kill attribution (`source_id` on projectile).
4. Server-authoritative respawn selection (farthest spawn with LOS check), 1.5 s spawn protection.
5. Server-side bots (simple chase/strafe/shoot AI) usable to fill a match and to test solo.
6. Authored events: `shot_fired`, `damage_dealt`, `player_died`, `kill_credited`.

### Acceptance criteria
- [ ] Client cannot deal damage directly; injecting a fake damage packet has no effect.
- [ ] Fire rate > weapon spec is rejected; ammo cannot go negative; firing without ammo is rejected.
- [ ] Headshots confirmed server-side at 2×; kill attributed to the correct shooter.
- [ ] 8-player match with 4 bots runs 10 min: no desync, no ghost players, server CPU < 50% of one core.
- [ ] At 100 ms RTT, the tracer is cosmetic and the server-confirmed hit point is authoritative; hitmarkers/kills appear only on server events. No rewind/lag compensation in V1.
- [ ] Spawn protection blocks damage for 1.5 s and cancels on firing; spawn is ≥ 10 m from nearest enemy.
- [ ] **Your sign-off:** firefights feel fair; deaths and hitmarkers are understandable.

---

## Phase 4d — Resilience & ops *(CP4d)*

**Owner:** me. **Gate:** CP4c acceptance.

### Tasks
1. Timeouts (10 s), reconnect (30 s grace), session cleanup.
2. Server rate limits and packet caps; name sanitization; max-players enforcement.
3. 8-client soak test script + memory/CPU/bandwidth report.
4. Structured server logs, `/healthz`, graceful shutdown.
5. WSS reverse-proxy config (Caddy) + deployment runbook.

### Acceptance criteria
- [ ] Kill a client mid-match: server removes it within 10 s; no orphan projectiles/scoreboard rows.
- [ ] Reconnect within 30 s restores identity and score.
- [ ] 8 clients × 10 min soak: RSS stable (±10%), 0 unhandled errors, 0 disconnects.
- [ ] 9th client receives a clean "server full" message.
- [ ] Oversized/rapid packets are dropped; server stays responsive (< 5 ms tick time).
- [ ] A supervisor/shutdown command stops the server and notifies peers within 10 s; SIGTERM behavior is documented (Godot exits 143 without a handler).

---

## Phase 5 — Match loop, polish & web release *(CP5)*

**Owner:** me (build/deploy), **you** (browser matrix + playtest). **Gate:** CP4d acceptance.

### Tasks
1. Match state machine: `Warmup → Live → Post`; 5-min timer; tie handling; 10 s post-match; auto-rematch.
2. Scoreboard (`Tab`): name, kills, deaths, ping; sorted; live updates; end-of-match summary.
3. Respawn UX: 3 s countdown, spawn protection flicker, death cam/spectate-lite.
4. Settings: sensitivity, invert Y, volume, quality/resolution scale; persisted to `user://`.
5. Web polish: custom HTML shell, Brotli/gzip, correct MIME, WSS, loading/error states, audio unlock, pointer lock recovery, tab-blur handling.
6. Deployment: one command builds web + server, uploads, restarts; version stamp.
7. Final test matrix and 8-player playtest.

### Acceptance criteria
- [ ] A full 5-min match runs start→finish→auto-rematch with correct winner and no manual reset.
- [ ] Respawn at 3 s; spawn protection 1.5 s (cancelled on fire); scoreboard updates ≤ 1 s.
- [ ] Ties resolved deterministically and shown correctly.
- [ ] Chrome, Firefox, **Safari** (latest) all load over HTTPS/WSS with no console errors.
- [ ] Web payload ≤ 25 MB (gzipped), interactive ≤ 10 s on broadband, 60 FPS at 720p on reference low-end.
- [ ] Settings persist; audio starts after first click; pointer lock recovers after tab switch.
- [ ] 8 humans/bots play 15 min: 0 critical bugs (crash, desync, unplayable frame rate, stuck spawn), 0 unplanned disconnects, max tick time < 10 ms.
- [ ] One-command deploy reproduces the release; `docs/RELEASE.md` runbook works from scratch.
- [ ] **Your sign-off:** web build is fun and stable enough to share publicly.

---

## Cross-cutting workstreams

| Area | When | Owner | Notes |
|---|---|---|---|
| Bots | 4c | me | Also used for load/soak tests |
| Audio | 3 & 5 | me | Placeholder SFX from day one; mix at CP5 |
| CI/CD | 0 onward | me | Web + server artifacts every push |
| Tests | 0 onward | me | GUT unit tests + headless 2-client integration |
| Docs | continuous | me | Architecture, events, runbooks, checkpoints |
| Art direction | 2 | **you** | Asset pack, palette, map reference |
| Feel testing | 1, 3, 5 | **you** | The only criteria I cannot self-certify |
| Hosting/DNS/TLS | 5 | **you** (creds) | I supply Caddy config + deploy script |

---

## Performance budgets (reference device: 4-core/8 GB laptop, Intel UHD 620-class iGPU, 1280×720)

| Metric | Budget | Hard fail |
|---|---|---|
| FPS | 60 | < 45 sustained |
| Draw calls | ≤ 150 | > 250 |
| Triangles | ≤ 250k | > 400k |
| Texture memory | ≤ 100 MB | > 150 MB |
| Web payload (gzip) | ≤ 20 MB | > 30 MB |
| Server tick (8 players) | ≤ 5 ms | > 10 ms |
| Snapshot size (8 players) | ≤ 300 B | > 500 B |
| Snapshot downstream | ≤ 10 KB/s | > 20 KB/s |
| Client memory | ≤ 300 MB | > 500 MB |

---

## Checkpoint evidence template

`docs/checkpoints/CPn.md`:

```md
# CPn — <name>
Date:
Build: <git sha>
Accepted by:

## Criteria
- [x] <criterion> — evidence: <number/log/screenshot link>

## Deviations
...

## Known issues carried forward
...
```
