# Map-Agnostic Optimization Research Brief

**Status:** open questions for an external research agent. This is a **read-only
research brief**: no gameplay, balance, map, protocol, test or UI code was
changed. The only companion change is a pointer in
[`OPEN-QUESTIONS.md`](OPEN-QUESTIONS.md).

**Scope:** Ball of Duty, Godot 4.7.2, Compatibility renderer (WebGL 2),
single-threaded WASM, one origin, 30 Hz authority, 8 actors today, binary
snapshots, one arena at a time. The growth target is **any 150–250 m map**,
**3 maps in rotation**, and **8 → 16 → 32 actors** (humans and/or bots).

**Explicitly out of scope:** designing or inspecting the three maps being built
in another session, changing the current map, changing balance, or applying any
recommendation. Questions here must be answerable without that map work.

**How to use this file**

1. Pick questions by priority and by the manager's current decision.
2. Answer in the required format in §10.3. An answer that does not include a
   reproducible measurement, an effect size, a rollback story and a per-map /
   per-actor-count statement is not an answer.
3. Do not use the current 150 m map's numbers as a budget for future maps. The
   current map is a **reference measurement**, not a target.

---

## 0. Context and assumptions

| Fact | Value / source |
|---|---|
| Engine / renderer | Godot 4.7.2, Compatibility (WebGL 2), `gl_compatibility` |
| Web constraints | single-threaded WASM, no SharedArrayBuffer, no COOP/COEP requirement |
| Tick | 30 Hz fixed (`project.godot` `[physics]`) |
| Actors today | `NetProtocol.MAX_PLAYERS = 8` (`scripts/networking/net_protocol.gd:17`) |
| Snapshot | 6 B header + 22 B/actor; 182 B at 8 (`net_protocol.gd:170-210`) |
| Snapshot budget | ≤ 300 B at 8 players (`docs/ROADMAP.md`, locked decision) |
| Position quantization | millimetres over **±32.768 m** (`net_protocol.gd:21,325-327`) |
| Match intent | 8 players, 5-minute FFA, 3 s respawn (`README.md`, `docs/ROADMAP.md`); no match timer was found in tracked code, only the `match_state_changed` signal |
| Maps | one at a time today; 3 in rotation is the stated growth; each map 150–250 m playable |
| Deployment | one origin, static web build + `wss://host/ws` reverse proxy (`docs/DEPLOY.md`, planned) |
| Authority | server owns movement, fire rate/ammo, projectile path, damage/death/score; client predicts movement and draws cosmetic tracers (`docs/ARCHITECTURE.md`) |

### 0.1 Measured baseline (native headless, reference only)

These numbers are **native x86_64 headless**, not browser numbers. They are
useful for scale and for catching regressions; they are not a web budget.
The 1.5–3× WASM factor in the previous audit is a **hypothesis**, not a
measurement.

**Command (fresh quick run, 2026-10-30):**

```bash
cd ballofduty
tools/godot --headless --path . --script tests/headless/perf_probe.gd -- --quick
# full run: omit --quick
```

| Metric | Fresh quick run | Previous audit (full) | Notes |
|---|---:|---:|---|
| Main scene ready | 590.4 ms | 590.2 ms | ~99 % is arena generation |
| Arena generation (current 150 m map, reference only) | 578.9 ms | 581.7 ms | synchronous in `_ready()` |
| Server tick, 8 bots avg / p95 | 2.79 / 5.61 ms | 3.54 / 6.74 ms | 33.3 ms budget; shared-container noise is large |
| Server tick, 5 bots avg / p95 | 1.48 / 1.75 ms | 1.81 / 3.54 ms | linear-ish with actor count |
| Server tick, 0 bots | 7.8 µs | 9.0 µs | baseline |
| Movement sub-step, 8 bots | 3.65 ms summed | 2.76 ms (77.8 %) | measured separately; sums can exceed total |
| Bot AI sub-step, 8 bots | 0.68 ms | 0.46 ms | 13–24 % of tick |
| Grounded one-actor step | 120.8 µs | 117 µs | vs 14 µs airborne |
| LOS ray | 29.9 µs | 10.8 µs | map/ray-length dependent |
| Snapshot encode / decode, 8 | 48.6 / 32.8 µs | 47.5 / 32.7 µs | 182 B |
| Client scripts, 7 remotes | ~0.05 ms/frame | ~0.05 ms/frame | CharacterVisual only |
| 64 bullet visuals | 334 µs/frame | 311 µs/frame | 4.9–5.2 µs per bullet per frame |
| BulletField first-shot pool | 2.25 ms | 2.03 ms | +216 nodes, +1.1 MB |
| Static memory, final / peak | 59.1 / 66.9 MB | 58.8 / 66.9 MB | native; WASM heap differs |
| Current map draw calls / triangles | 49 / 192,842 | 49 / 192,842 | `tests/headless/arena_stats.gd` |
| Web payload | wasm 39.5 MB raw / 10.1 MB gzip; pck 5.94 MB / 4.31 MB gzip | same | total 45.7 MB / 14.5 MB gzip |

**Quantization probe (native headless, 2026-10-30):** a temporary read-only
script outside the repo (`/srv/opencode/tmp/opencode/pos_probe.gd`) called the
real `NetProtocol.encode_snapshot` / `decode_snapshot`:

```bash
tools/godot --headless --path . --script /srv/opencode/tmp/opencode/pos_probe.gd
```

| Input position | Decoded position | Error |
|---|---|---:|
| (20, 0, 20) | (20, 0, 20) | 0.000 m |
| (32.7, 0, −32.7) | (32.7, 0, −32.7) | 0.000 m |
| (40, 0, 0) | (32.767, 0, 0) | **7.233 m** |
| (69.5, 0, −69.5) | (32.767, 0, −32.768) | **51.948 m** |
| (125, 0, −125) | (32.767, 0, −32.768) | **130.436 m** |

| Actor count | Encoded bytes | Count byte | Decode result |
|---:|---:|---:|---|
| 8 | 182 | 8 | ok |
| 16 | 358 | **8** | **rejected** |
| 32 | 710 | **8** | **rejected** |

This is why NET-01 and NET-02 are at the top of the index: they are not
hypothetical future problems.

---

## 1. Question index

Priority is an initial guess, not a decision. `P0` = likely to block a
150–250 m / 3-map / 16–32-actor release; `P1` = likely to matter at that scale;
`P2` = measure, but do not pre-emptively build.

| ID | Title | Domain | Priority |
|---|---|---|---|
| **SRV-01** | Tick headroom at 8 → 16 → 32 actors | server | P1 |
| **SRV-02** | Bot AI, LOS and O(n²) target scan | server | P1 |
| **SRV-03** | Respawn / spawn-selection bursts | server | P2 |
| **SRV-04** | Projectiles, splash and status effects at scale | server | P2 |
| **SRV-05** | Per-tick allocations and roster data structures | server | P2 |
| **SRV-06** | Server actor representation and spawn cost | server | P2 |
| **CLI-01** | Prediction / reconciliation replay cost | client | P1 |
| **CLI-02** | Remote actor instantiation and interpolation | client | P1 |
| **CLI-03** | CharacterVisual / animation at 16–32 actors | client | P2 |
| **CLI-04** | HUD / UI redraw and per-frame strings | client | P1 |
| **CLI-05** | Bullet and impact FX at high fire rates | client | P2 |
| **CLI-06** | Client frame budget, camera, allocations, WASM | client | P1 |
| **REN-01** | How much of a 150–250 m map is actually rendered | rendering | P1 |
| **REN-02** | Draw calls vs triangles vs fill rate | rendering | P1 |
| **REN-03** | Shadows: cost, casters, per-map budget | rendering | P1 |
| **REN-04** | LOD, MultiMesh vs merged meshes at 3-map scale | rendering | P2 |
| **REN-05** | Chunk streaming, residency and 3-map rotation | rendering | P1 |
| **REN-06** | Materials, textures, fog, far plane, overdraw | rendering | P1 |
| **NET-01** | Position quantization vs map size | network | **P0** |
| **NET-02** | Actor cap, snapshot size and protocol layout | network | **P0** |
| **NET-03** | Interest management / delta compression | network | P2 |
| **NET-04** | Snapshot rate vs tick rate (20 / 30 / 60) | network | P1 |
| **NET-05** | Drain, backpressure, TCP HOL, WebSocket cost | network | P1 |
| **NET-06** | Join/reconnect storms, rate limits, proxy, mobile | network | P1 |
| **MEM-01** | WASM/PCK payload and cold join | memory | P1 |
| **MEM-02** | Runtime memory ceiling and 3-map residency | memory | P1 |
| **MEM-03** | Node/object churn and GC at 32 actors | memory | P2 |
| **MEM-04** | Bake vs runtime generation and cache strategy | memory | **P0** |
| **OBS-01** | What to measure in dev and production | observability | P1 |
| **OBS-02** | Thresholds that should trigger work | observability | P1 |
| **OBS-03** | How to prove a fix; headless→browser calibration | observability | **P0** |
| **MAT-01** | Is the current 5-min / 8-actor / 30 Hz model a bottleneck? | match | P1 |
| **MAT-02** | Match length, respawn and join/leave churn | match | P2 |
| **MAT-03** | Actor cap and bot/human mix | match | P1 |
| **SAF-01** | Safe vs risky optimizations (authority/prediction/web) | safety | **P0** |
| **SAF-02** | Rollback plans and feature flags | safety | P1 |

---

## 2. Server calculations

### SRV-01 — Tick headroom at 8 → 16 → 32 actors

**Growth scenario / why it matters.** The server is a single Godot process
simulating every actor at 30 Hz. If a 250 m map with 32 grounded actors pushes
p95 over 33 ms, the authority loop stalls, snapshots bunch, and every client
sees hitches. This is the first question to settle before promising 16 or 32.

**Current evidence.** At 8 bots, native headless: **2.79 ms avg / 5.61 ms p95**
(fresh) and **3.54 / 6.74 ms** (previous audit), i.e. 8–20 % of the 33.3 ms
budget. The dominant sub-step is movement: grounded `server_step` is
**117–121 µs** per actor vs **14 µs** airborne; removing 374 prop colliders did
not reduce it, so it is heightfield ground contact, not broadphase count
(`scripts/player/player_controller.gd:194`, `scripts/game/game_manager.gd:282`).
Actor count is capped at 8 (`net_protocol.gd:17`), so **16/32 numbers are
hypotheses**, not measurements.

**Questions for the research agent.**
1. What is the marginal cost of one additional grounded actor on the target
   server CPU class (1–2 vCPU VPS, not this 8-vCPU host)?
2. Is the cost linear, superlinear (contacts/props/heightfield), or dominated by
   p99 contact spikes?
3. What are p50/p95/p99 at 8, 16 and 32 actors, with bots and with humans?
4. Does map size/collider count change the marginal cost, or only the ray/LOS
   cost?
5. What is the correct policy on tick overrun: drop a tick, slow the tick,
   freeze an actor, or shed snapshots? What does Godot's `max_physics_steps_per_frame=4`
   already do in the background-tab case?
6. What server CPU budget should be reserved for GC/allocation spikes and
   network send?

**Options.**
- **Do nothing (stay at 8).** Gain: zero risk. Cost: caps the product.
- **Tune.** Cache `HealthComponent`, reduce bot rays, simplify server ground
  collision, preallocate snapshot buffers. Expected: 10–25 % tick reduction;
  cost S–M; risk low–medium (server-only).
- **Architectural.** 20 Hz authority, split simulation from network, or a
  server-only movement collider. Expected: 33 % (20 Hz) or more; cost M–L; risk
  high (feel, prediction determinism, protocol).

**How to answer.** Extend the probe in a branch (the 8-actor cap must be lifted
only for the test) and run 300 ticks × 3 runs at 8/16/32, reporting
p50/p95/p99 and run-to-run spread. Repeat on a 1–2 vCPU cloud instance.
**Threshold/acceptance:** p95 ≤ 8 ms at 8, ≤ 12 ms at 16, ≤ 20 ms at 32 (or a
documented 20 Hz decision), with no tick over 33 ms in a 10-minute soak.

**Risk / safety.** Server-only changes do not touch prediction, but changing
`delta` or ground collision does: the client replays the same
`LocomotionComponent` at `1/30` (`player_controller.gd:394-412`). Any server
movement change must be mirrored exactly or reconciliation error will rise.

**Priority / confidence.** **P1 · high confidence** that movement dominates at 8;
**medium confidence** in the 16/32 extrapolation.

---

### SRV-02 — Bot AI, LOS and O(n²) target scan

**Growth scenario / why it matters.** Bots are used to fill lobbies. At 8 bots
the AI is 0.46–0.68 ms/tick; at 32 bots the target scan and LOS rays scale
quadratically and linearly respectively, on a 150–250 m map with longer sight
lines and more geometry.

**Current evidence.** `_bot_frame` does a nearest-enemy scan, a LOS ray and a
forward feeler every tick (`game_manager.gd:534-651`); `_nearest_enemy` scans
the whole roster (`:653-681`); `_entry_by_id` is an O(n) dictionary scan
(`:692-698`); `_has_los` is one ray (`:683-690`). 16 rays/tick at 8 bots; LOS
10.8–29.9 µs, feeler 5.7–7.9 µs. Audit: 464.7 µs/tick (13 %); fresh: 675.5 µs
(24 %). `_entry_by_id` is called for sticky targets and respawn, so the roster
is walked several times per bot per tick.

**Questions for the research agent.**
1. What is AI cost at 16/32 bots, and how much is raycast vs dictionary vs
   math?
2. Can LOS be cached for 2–3 ticks or staggered across bots without a
   perceptible change in bot lethality/reaction?
3. What is the perceptual threshold for bot target reacquisition and aim
   updates? Is 30 Hz necessary, or is 10–15 Hz AI enough?
4. Does a spatial hash / distance bucket beat the O(n) scan at 32, or is the
   constant too small to matter?
5. How do longer 250 m sight lines change ray cost and hit rate?
6. Can bots use a cheaper "far" AI mode (no feeler, coarser LOS) beyond 40 m?

**Options.**
- **Do nothing at 8.** Gain: zero. Cost: zero.
- **Tune.** Cache LOS 2–3 ticks, stagger bots, cache target id, spatial hash.
  Expected: 30–50 % AI reduction (0.15–0.25 ms/tick at 8); cost S; risk medium
  (bot feel).
- **Architectural.** Navmesh + utility AI / AI LOD. Expected: large at 32; cost
  L; risk medium–high (bot quality).

**How to answer.** Instrument rays/bot/tick and µs by sub-step; run 8/16/32 bots
for 300 ticks; A/B cached-LOS vs per-tick LOS over 100 simulated matches,
comparing hit rate, TTK and reaction time. **Acceptance:** AI ≤ 1.5 ms/tick at
16 and ≤ 3 ms at 32; bot hit rate/TTK within 5 % of the per-tick baseline.

**Risk / safety.** Server-only, so prediction is unaffected. Bot feel and
fairness are the risks; do not ship a change that makes bots either aimbots or
blind.

**Priority / confidence.** **P1 · high confidence** in the cost; **medium** in
the perceptual threshold.

---

### SRV-03 — Respawn / spawn-selection bursts

**Growth scenario / why it matters.** Deaths cluster. At 16–32 actors, several
players can die in the same tick; each death runs `_choose_respawn`, which
loops every spawn × every living actor and raycasts for nearby actors. A
respawn spike is exactly when the server can least afford a tick overrun.

**Current evidence.** `_choose_respawn` (`game_manager.gd:486-516`) loops
`_spawns` and the roster, and for every other actor within 25 m issues a
`PhysicsRayQueryParameters3D` + `intersect_ray`. With 8 spawns and 8 actors that
is up to 64 rays per death (audit SERVER-04 estimated 0.5–1 ms); at 32 actors it
is up to 256. `_respawn` also resets health/combat/queue and broadcasts an event
(`:457-484`). Respawn delay is 3 s (`:27`).

**Questions for the research agent.**
1. What is the p99 tick when 4–8 actors die in the same tick at 16/32?
2. Is the per-spawn LOS ray necessary, or can distance + a precomputed
   cover/safety grid produce equally fair spawns?
3. How often do multi-death bursts occur in real matches (instrument deaths per
   tick)?
4. Does the spawn-selection cost show up above the noise, or is it dominated by
   the death event broadcast?
5. Can spawn selection be amortized over ticks or cached per death?

**Options.**
- **Do nothing.** Gain: zero. Cost: zero.
- **Tune.** Limit to the nearest 3 spawns, reuse last clear spawn, cache spawn
  safety, or stagger selection. Expected: removes the 0.5–1 ms spike; cost S;
  risk low.
- **Architectural.** Precomputed spawn-safety grid / async selection. Expected:
  constant-time; cost M; risk low–medium.

**How to answer.** Synthetic simultaneous deaths at 8/16/32, measure tick
p99/max and spawn fairness (distance to nearest enemy, LOS, spawn-camp rate).
**Acceptance:** no tick > 2× baseline during a 10-death burst; spawn fairness
metrics unchanged.

**Risk / safety.** Server-only; the main risk is unfair spawns. Keep a
deterministic fallback if all candidate spawns are blocked.

**Priority / confidence.** **P2 · high confidence** in the code path; **low**
that it is a top bottleneck at 8.

---

### SRV-04 — Projectiles, splash and status effects at scale

**Growth scenario / why it matters.** More actors and more fire means more
active projectiles, more swept rays, more splash queries and more per-player
status dictionaries. At 8 actors this is cheap; at 32 with automatic weapons it
may not be.

**Current evidence.** Projectile spawn 13.2–13.7 µs; swept step 3.25–3.4 µs per
projectile per tick; a 60-shot burst resolves in 2 physics frames with 0 orphans
(`scripts/weapons/projectile.gd:77-98`). Splash allocates a `SphereShape3D`, a
`PhysicsShapeQueryParameters3D`, a duplicated exclusion array and a `seen`
dictionary **per impact** (`projectile.gd:179-205`). Status effects are a
dictionary per player ticked every tick (`server_combat.gd:409-420`). Fire
traces a 250 m view ray per shot (`server_combat.gd:458-469`).

**Questions for the research agent.**
1. What is the active-projectile count and per-tick cost at 16/32 actors with
   the fastest weapon and continuous fire?
2. Does the splash allocation show in p99, or is it lost in the noise?
3. Can projectile objects be pooled server-side without changing hit
   semantics?
4. Can the splash query reuse one shape/params object, and what is the gain?
5. Do status effects need a dictionary per player, or a packed array?
6. Does the 250 m aim ray need to be that long on a 150–250 m map, and does it
   hit sky/backdrop geometry?

**Options.**
- **Do nothing at 8.** Gain: zero.
- **Tune.** Reuse splash shape/params, pool projectiles, pack status, cap aim
  ray at map diagonal. Expected: 20–40 % projectile/splash cost; cost S; risk
  low.
- **Architectural.** Hitscan or lag-compensated hit resolution. Expected:
  large; cost L; risk high (feel/authority).

**How to answer.** Instrument active projectiles, splash count, status count
and p99 tick in a 32-bot 10-minute soak. **Acceptance:** projectile + status
≤ 1 ms/tick at 32; no orphan/node growth; no change in hit registration.

**Risk / safety.** Server authority and hit registration; keep the swept ray
(the anti-tunneling property) unless the research proves an alternative.

**Priority / confidence.** **P2 · high confidence** in the code path; **low**
that it matters at 8.

---

### SRV-05 — Per-tick allocations and roster data structures

**Growth scenario / why it matters.** WASM's allocator and GC behaviour differs
from native. A dictionary per actor per tick and ~50 `PackedByteArray`
allocations per snapshot may be invisible natively but cause sawtooth frame
times in a browser-hosted server or a small VPS.

**Current evidence.** `_snapshot_entry` builds a new Dictionary per actor per
tick (`game_manager.gd:409-421`); `_health` does `get_node_or_null` per actor
per tick (`:405-406`); `encode_snapshot` appends many small arrays
(`net_protocol.gd:170-190`; audit NET-01 measured ~50 allocations/snapshot);
`_bot_frame` creates a `PlayerInputFrame.new()` per bot per tick (`:534`);
`_nearest_enemy` returns dictionary references and `_entry_by_id` scans the
roster (`:653-698`). Snapshot entry cost: 84.6–110.1 µs/tick at 8.

**Questions for the research agent.**
1. How many allocations per tick at 8/16/32, and what is their p99 cost in WASM
   and on a small VPS?
2. Which allocations are avoidable without a risky rewrite: cache health,
   preallocate the snapshot buffer, reuse input frames, replace `_entry_by_id`
   with an id→entry map?
3. Does Godot's Dictionary allocation dominate, or is it the `get_node_or_null`
   tree lookup?
4. What is the steady-state memory growth over a 10-minute match?
5. Is a struct-of-arrays / packed-array roster worth the maintenance cost?

**Options.**
- **Do nothing.** Gain: zero; cost: zero.
- **Tune.** Cache `HealthComponent` on the roster entry, preallocate
  `pkt.resize(6 + 22n)` and write at offsets, reuse bot frames, add id→entry
  map. Expected: 20–40 % snapshot/roster cost; cost S; risk low.
- **Architectural.** Struct-of-arrays roster / packed snapshot builder.
  Expected: 2–4× codec/roster; cost M; risk medium.

**How to answer.** Add allocation counters and measure p95/p99 tick plus static
memory over 10 minutes at 8/16/32. **Acceptance:** zero steady-state growth;
p95 tick improvement ≥ 10 %; no behaviour change in 100 matches.

**Risk / safety.** Roster refactors can break reconnect/respawn/score; keep the
public entry shape until tests pass.

**Priority / confidence.** **P2 · medium confidence** — likely a real WASM
issue, unmeasured in a browser.

---

### SRV-06 — Server actor representation and spawn cost

**Growth scenario / why it matters.** Every server actor instantiates the full
client `player.tscn` and then disables the visual. At 32 actors that is 4× the
nodes, materials, animation players and memory, and a bigger join/spawn burst.

**Current evidence.** `_spawn_server_actor` instantiates `PLAYER_SCENE`
(`game_manager.gd:741-756`); `make_server` disables the visual
(`player_controller.gd:113-128`). The player scene has 17 top-level nodes plus
the character sub-scene and several `AnimationPlayer` overlays
(`scenes/characters/player.tscn`; `character_visual.gd:292-313`). `server_start`
is 10.7 ms fresh / 13.5 ms audit for 8 bots; 8 joins at once would be a burst.

**Questions for the research agent.**
1. What is the node/object/memory cost per server actor, and how much is
   visual/animation that the server never uses?
2. Can a server-only scene keep `CharacterBody3D`, collision, hurtboxes,
   `LocomotionComponent`, `HealthComponent` and `ServerCombat` semantics while
   dropping camera/animation/weapon visuals?
3. Does disabling `Visual` stop `CharacterVisual._process` and the
   `AnimationPlayer`s, or do they still tick?
4. What is the join/spawn burst at 16/32 simultaneous joins?
5. Does the server need the weapon scene/materials at all for canonical muzzle
   and projectile spawn?

**Options.**
- **Do nothing.** Gain: zero; cost: zero.
- **Tune.** Free/hide visual nodes after `make_server`, prewarm one actor.
  Expected: 20–40 % server actor memory and spawn time; cost S–M; risk low.
- **Architectural.** Dedicated server actor scene. Expected: 50 %+ memory and
  spawn time; cost M; risk medium (collision/hurtbox divergence).

**How to answer.** Measure `server_start`, per-actor memory and tick at
8/16/32; compare hitboxes/projectile hits with the full scene. **Acceptance:**
join burst ≤ 100 ms per actor native, server memory −30 %, identical combat
outcomes in 100 matches.

**Risk / safety.** The server's collision/hurtbox shape is part of authority;
any divergence from the client scene changes hit registration. Keep the
collision/hurtbox subtree identical.

**Priority / confidence.** **P2 · high confidence** in the waste; **medium** in
the payoff.

---

## 3. Client calculations

### CLI-01 — Prediction / reconciliation replay cost

**Growth scenario / why it matters.** The local client replays every unacked
input after each snapshot. At 100–150 ms RTT that is 3–8 steps; on WASM each
grounded step is the same expensive heightfield contact as the server. If the
replay cost spikes, the local player feels a stutter exactly when the network
is bad.

**Current evidence.** `MAX_PREDICTION_FRAMES = 64`; `_apply_correction` rewinds
to the authoritative pose and replays the tail (`player_controller.gd:371-430`);
`accept_server_state` ignores stale acks (`:307-321`). The server step is
117–121 µs grounded, so 8 replay steps is ~1 ms native before WASM derating.
`MAX_EXTRAPOLATION_TICKS = 2` (`game_manager.gd:26`).

**Questions for the research agent.**
1. What is the replay cost per correction at 50/100/150 ms RTT on WASM?
2. What is the p99 frame time during a correction burst, and how often do
   corrections occur on a 150–250 m map?
3. Does replay depth exceed the 8-frame target? What is the distribution?
4. Can replay be capped or time-sliced without visible rubber-banding?
5. Does a 20/60 Hz tick change replay depth and cost? (Link NET-04.)
6. Is the current correction epsilon (1 cm) and visual offset (2 m cap) still
   appropriate at map scale?

**Options.**
- **Do nothing.** Gain: zero; cost: zero.
- **Tune.** Cap replay, time-slice, cache collision state, reduce grounded
  contact cost. Expected: p99 frame −20–40 %; cost S–M; risk medium (feel).
- **Architectural.** Deterministic batch replay / rollback with a cheaper
  movement model. Expected: large; cost L; risk high.

**How to answer.** Browser profile with `?sim=` latency and a scripted
correction storm; record replay depth, corrections/s, frame p95/p99.
**Acceptance:** p99 frame ≤ 16.7 ms at 60 fps, corrections < 2/s, no visible
rubber-band in a 2-minute playtest at 150 ms RTT.

**Risk / safety.** Prediction determinism is the highest-risk area in the
project. Any change to `LocomotionComponent` must be mirrored server-side and
covered by the existing prediction tests.

**Priority / confidence.** **P1 · high confidence** in the code path; **medium**
in the browser magnitude.

---

### CLI-02 — Remote actor instantiation and interpolation

**Growth scenario / why it matters.** Every remote is a full `player.tscn`
(camera, input, weapon, animation, character). At 7 remotes this is tolerable;
at 16–32 it is a join hitch, a memory cost, and a per-frame node-lookup cost.

**Current evidence.** `_spawn_remote` instantiates the full scene
(`game_manager.gd:983-992`); `_apply_remote` does
`get_node_or_null("NetworkInterpolator")` per remote per frame
(`player_controller.gd:456-462`); `NetworkInterpolator.sample` returns a new
Dictionary per remote per frame (`network_interpolator.gd:76-125`); the buffer
holds 16 samples (`:16`). Audit CLIENT-05 estimated a 50–200 ms join hitch for 7
remotes; the probe measured 0.05 ms/frame for 7 CharacterVisuals, but not the
spawn burst or the dictionary churn.

**Questions for the research agent.**
1. What is the join hitch and memory cost at 8/16/32 remotes on WASM?
2. Can a remote-only scene drop camera/input/weapon logic while keeping the
   visual, hurtboxes and animation?
3. Can the interpolator return a reused struct/array instead of a Dictionary?
4. What is the per-frame cost of 32 remotes on WASM, including node lookups?
5. Should remotes be pooled across join/leave/map rotation?
6. Does `visible=false` until the first sample still cost process/animation?

**Options.**
- **Do nothing at 8.** Gain: zero.
- **Tune.** Prewarm/pool remote scenes, cache the interpolator on `make_remote`,
  reuse the sample dictionary, skip invisible remotes. Expected: removes join
  hitch, 20–40 % remote frame cost; cost S–M; risk low.
- **Architectural.** Remote proxy scene / data-oriented renderer. Expected:
  large at 32; cost L; risk medium.

**How to answer.** Measure spawn burst for 1/8/16/32 remotes, frame p95 and
memory in Chrome; profile a 32-remote scene. **Acceptance:** join hitch
< 100 ms, 32 remotes scripts ≤ 1.5 ms/frame on the reference low-end, no visual
or animation regression.

**Risk / safety.** Visual/animation fidelity; remote hurtboxes must remain for
projectile blocking even though damage is disabled (`docs/ARCHITECTURE.md`).

**Priority / confidence.** **P1 · high confidence** in the waste; **medium** in
the size at 16.

---

### CLI-03 — CharacterVisual / animation at 16–32 actors

**Growth scenario / why it matters.** Each actor runs a main `AnimationPlayer`
plus three overlay players and per-frame bone/gun attachment math. At 32 actors
this may be the largest client script cost after UI.

**Current evidence.** `CharacterVisual._process` is 6.1–7.2 µs/actor/frame
headless; 7 remotes ≈ 0.05 ms (`character_visual.gd:159`); it updates motion,
death, aim, grip and gun attachment every frame (`:159-185`, `:706-733`). Three
overlay players are created in `_add_overlay` (`:292-313`). The probe runs
headless, so animation blending/skinning on the GPU is absent.

**Questions for the research agent.**
1. What is the real browser cost per actor with animation (not headless)?
2. At 16/32 actors, what is the CPU/GPU split for animation/skinning?
3. Can remote animation update at 15/30 Hz or by distance LOD without visible
   pop?
4. Do the overlay `AnimationPlayer`s double the cost, and are they needed on
   remotes beyond 30 m?
5. Can far actors use a cheaper rig or a static pose?
6. Does the gun attachment bone math need to run for every remote every frame?

**Options.**
- **Do nothing at 8.** Gain: zero.
- **Tune.** Animation LOD by distance, disable overlays for far remotes, update
  at 15/30 Hz. Expected: 30–60 % animation cost at 32; cost S–M; risk low–
  medium (visual).
- **Architectural.** GPU skinning / instanced animation (verify Compatibility
  support). Expected: large; cost L; risk high (web compatibility).

**How to answer.** Chrome tracing on 8/16/32 actors at 720p; measure
`AnimationPlayer`/skeleton cost; A/B animation LOD with screenshots.
**Acceptance:** 32 actors ≤ 2 ms/frame scripts on low-end; no visible pop at
normal combat distances.

**Risk / safety.** Visual only; no authority/prediction risk. Keep the local
player's animation at full rate.

**Priority / confidence.** **P2 · medium confidence** — likely real, but not yet
measured in a browser.

---

### CLI-04 — HUD / UI redraw and per-frame strings

**Growth scenario / why it matters.** The HUD redraws every frame even when
nothing changed, and the net panel formats labels every frame while online. On
low-end WebGL, canvas rebuild + text shaping can cost more than the game logic.

**Current evidence.** `HUD._process` calls `queue_redraw()` unconditionally
(`scripts/ui/hud.gd:109-119`); `_draw` has ~15 `draw_string` calls (`:179-262`);
per-frame string work measured at 4.6 µs headless, but **headless never emits
the draw signal** (audit CLIENT-01/02). `main._process` calls
`_update_net_panel_stats` every frame and assigns `Label.text`
(`scripts/game/main.gd:98-104,724-744`); the banner does the same (`:757-780`).

**Questions for the research agent.**
1. What is the real `_draw` + text-shaping cost in Chrome/Firefox at 720p and
   1080p, with the HUD visible vs hidden?
2. Does unconditional `queue_redraw()` rebuild the canvas every frame even when
   the values are unchanged?
3. What is the gain from a dirty flag, a 30 Hz throttle, or cached formatted
   strings?
4. What does the net panel/banner cost when closed vs open?
5. Does the HUD cost scale with resolution/DPI or only with text count?
6. Is the crosshair/meter drawing the dominant part, or the text?

**Options.**
- **Do nothing.** Gain: zero; cost: zero.
- **Tune.** Dirty flag, 30 Hz throttle, cache strings, set `Label.text` only on
  change. Expected: 0.3–1 ms/frame on low-end WebGL; cost S; risk low (UI
  staleness).
- **Architectural.** Retained-mode UI / pre-rendered text atlas. Expected:
  large; cost M; risk medium.

**How to answer.** Chrome performance profile with HUD visible/hidden and
online/offline; measure frame p95 and `_draw` time. **Acceptance:** ≥ 0.3 ms/
frame saved on the reference low-end, zero visual change, no redraw when idle.

**Risk / safety.** UI only; no authority/prediction risk. Do not let a dirty
flag hide a real state change (ammo, HP, reload, death).

**Priority / confidence.** **P1 · high confidence** that the redraw is
unconditional; **medium** in the browser cost.

---

### CLI-05 — Bullet and impact FX at high fire rates

**Growth scenario / why it matters.** Bullet visuals run at render rate and each
does a physics ray per frame. At 32 actors and 120 Hz displays, 64 bullets can
consume a measurable slice of the frame; the pool also builds on the first shot
mid-match.

**Current evidence.** 64 bullets = 311–334 µs/frame native, 4.87–5.23 µs per
bullet per frame (`scripts/weapons/bullet_visual.gd:93-102`); one ray each;
pool build 2.03–2.25 ms, +216 nodes, +1.1 MB on first shot
(`bullet_field.gd:104`); `POOL_SIZE=64` (`:11`), oldest slot reused.

**Questions for the research agent.**
1. What is the browser cost at 64 bullets on a 120 Hz display? Does the ray
   double with frame rate?
2. Can the ray run every 2nd frame or only within 30 m of the camera without
   visible misses?
3. Does pool exhaustion at 32 actors cause visible artifacts, and is 64 the
   right cap?
4. Can impacts use GPU particles / a single MultiMesh instead of pooled nodes?
5. Should the pool be prewarmed during load instead of on first shot?
6. Does the cosmetic tracer need collision at all, given the server is
   authoritative?

**Options.**
- **Do nothing.** Gain: zero.
- **Tune.** Ray every 2nd frame, distance cull, prewarm, raise/lower pool.
  Expected: −50 % bullet CPU, removes first-shot hitch; cost S; risk low.
- **Architectural.** GPU trails/particles. Expected: large; cost M; risk medium
  (web compatibility).

**How to answer.** Browser profile with 64 simultaneous bullets at 60/120 Hz;
measure frame p95 and visual hit accuracy. **Acceptance:** ≤ 0.5 ms/frame at 64
on low-end, no missed cosmetic impacts, pool prewarmed before the match.

**Risk / safety.** Cosmetic only; the server remains authoritative. Do not let
a visual optimization hide a real hit event.

**Priority / confidence.** **P2 · high confidence** in the cost; **medium** in
the need at 8.

---

### CLI-06 — Client frame budget, camera, allocations, WASM

**Growth scenario / why it matters.** The browser has one main thread for
script, physics, canvas and (in Compatibility) much of the draw submission.
At 32 actors and 3 maps, the sum of many small scripts can exceed 16.7 ms even
if each is cheap. This question owns the end-to-end client budget.

**Current evidence.** Camera `update_aim` calls `SpringArm3D.get_hit_length()`
every frame (`camera_rig.gd:49-73`); `_apply_remote` does a node lookup per
remote per frame (`player_controller.gd:456-462`); the interpolator allocates a
Dictionary per sample (`network_interpolator.gd:76-125`); `main._process`
formats labels every frame (`main.gd:98-104`). Native headless scripts are
~0.5 ms total; WASM is 1.5–3× by hypothesis. `Engine.max_physics_steps_per_frame=4`
and `physics_jitter_fix=0` protect background tabs (`docs/ARCHITECTURE.md`).

**Questions for the research agent.**
1. What is the actual browser main-thread breakdown (script, physics, canvas,
   compositor, GPU) at 720p on the reference low-end?
2. Which scripts exceed 0.5 ms/frame at 32 actors, and what is the p95?
3. Does the camera shape cast show up, and can it run every 2nd frame?
4. What is the real WASM/native factor **per subsystem** (not one number)?
5. Can 60 fps at 32 actors be reached on Intel UHD, or is the honest target
   30 fps / resolution scale?
6. What is the fallback ladder: resolution scale, actor LOD, effect LOD, cap?
7. How much does a background tab / thermal throttling change the answer?

**Options.**
- **Do nothing.** Gain: zero.
- **Tune.** Throttle camera, cache nodes, dirty-flag UI, LOD effects.
  Expected: 1–3 ms/frame; cost S–M; risk low.
- **Architectural.** Resolution scaling / dynamic quality / worker offload
  (not available single-threaded). Expected: large; cost M–L; risk medium.

**How to answer.** Chrome tracing + `Performance` monitors on a matrix of
8/16/32 actors, 720p/1080p, HUD on/off, 1 vs 3 maps. **Acceptance:** p95 frame
≤ 16.7 ms at 8, ≤ 33 ms at 32 on low-end, or a documented cap with a quality
ladder.

**Risk / safety.** Web compatibility is the hard constraint: no threads, no
SAB, no Forward+. Test on Chrome, Firefox and Safari, not only headless.

**Priority / confidence.** **P1 · high confidence** that this is the real client
question; **low confidence** in any specific number until browser-profiled.

---

## 4. Rendering / how much map is rendered

### REN-01 — How much of a 150–250 m map is actually rendered

**Growth scenario / why it matters.** A 250 m map with the same prop density as
a 150 m map has ~2.8× the instances and triangles. If Godot draws all
MultiMesh instances whenever the MultiMesh AABB is visible, map size directly
multiplies vertex cost even when most of the map is behind the camera.

**Current evidence.** The current reference map reports 49 draw calls, 192,842
triangles, 1,832 MultiMesh instances and 31 meshes (`arena_stats`); props are
built as **one MultiMesh per prop type**, not per chunk
(`scripts/game/quarry_arena.gd:1221-1235`; this is a reference pattern only — the
three new maps are out of scope). No `visibility_range`, `visibility_parent`,
LOD or occlusion setup was found in tracked scripts/scenes. The camera has no
explicit `far` value (Godot default is large), so fog, not the far plane, is
currently hiding distance.

**Questions for the research agent.**
1. Does Godot 4.7 Compatibility cull MultiMesh **per instance** or only by the
   MultiMesh AABB? Cite engine source/docs.
2. What fraction of a 150–250 m map's instances/triangles are actually inside
   the frustum at typical third-person camera poses (ground, ridge, cave)?
3. What is the gain from splitting each prop MultiMesh by map chunk so off-screen
   chunks cull as a unit?
4. What is the gain from `visibility_range` per chunk, and what pop does it
   cause?
5. Is occlusion culling available and worthwhile in Compatibility/WebGL2, or
   does it require a bake/Forward+ only path?
6. What camera far plane and fog density are appropriate for 150–250 m without
   visible clipping or haze?
7. How should a per-map "visible triangle" budget be measured, not just total
   triangles?

**Options.**
- **Do nothing.** Gain: zero; cost: zero.
- **Tune.** Split MultiMeshes per chunk, add per-chunk `visibility_range`, set a
  far plane. Expected: 20–50 % visible geometry on typical poses; cost S–M;
  risk medium (pop).
- **Architectural.** Chunk streaming / occlusion bake / impostors. Expected:
  large; cost L; risk high.

**How to answer.** Use a parameterized synthetic arena at 150/200/250 m with
controlled instance counts; capture draw calls, visible instances/triangles and
GPU time from several camera poses; A/B chunk-split MultiMeshes. **Acceptance:**
≥ 30 % fewer visible triangles on typical poses, no visible pop, draw calls
within budget.

**Risk / safety.** Visual only, but map-specific tuning must not become a
per-map hack. Ask for a rule (e.g., "split at 50 m chunks") that any map can
follow.

**Priority / confidence.** **P1 · high confidence** that map size changes the
rendered load; **medium** in the MultiMesh culling details until verified in
engine source.

---

### REN-02 — Draw calls vs triangles vs fill rate

**Growth scenario / why it matters.** "49 draw calls / 192k triangles" is
within the project's 150 / 250k acceptance budget, but a 250 m map with 3 maps
and 32 actors may hit a different limit: fill rate, shader complexity, shadow
pass or texture bandwidth on mobile GPUs. Optimizing the wrong axis wastes
weeks.

**Current evidence.** Current reference map: 49 draw calls, 192,842 triangles,
1,832 instances, 49 surfaces (`arena_stats`); project acceptance is draw calls
≤ 150 and triangles ≤ 250k (`docs/ROADMAP.md` Phase 2). The terrain material uses
triplanar UVs, `CULL_DISABLED` and anisotropic filtering in the current map
(audit MAP-07; reference only). Compatibility/WebGL2, 1280×720 base, mobile
targets unknown.

**Questions for the research agent.**
1. On the reference low-end WebGL2 device, which limit binds first: draw calls,
   vertex/triangle throughput, fill rate, shader ALU, texture bandwidth, or
   shadow pass?
2. What is the frame time at 49/100/150 draw calls and 100k/200k/400k triangles
   at 720p and 1080p?
3. How much does the shadow pass add, and does it double vertex cost?
4. Is 250k triangles a safe per-map budget for 3 maps and 32 actors, or should
   it be lower/higher?
5. What is the cost of full-screen overdraw from terrain/fog/sky?
6. What synthetic benchmark should the team keep in CI to answer this per map?

**Options.**
- **Do nothing.** Gain: zero.
- **Tune.** Shadow casters, material flags, chunking, resolution scale.
  Expected: 20–40 % frame; cost S–M; risk medium (visual).
- **Architectural.** LOD/impostors/streaming. Expected: large; cost L; risk
  medium–high.

**How to answer.** Build a synthetic benchmark with controlled draw calls and
triangles; run on Intel UHD laptop, mid-range Android and iPhone Safari; use
Chrome tracing/GPU timer queries. **Acceptance:** 60 fps at 720p on reference
low-end at the agreed budget; a documented quality ladder if not.

**Risk / safety.** Visual; keep a screenshot A/B for every material/shadow
change. Do not lower the budget based on one fast desktop GPU.

**Priority / confidence.** **P1 · high confidence** that this decides the render
budget; **low confidence** in which axis binds until measured.

---

### REN-03 — Shadows: cost, casters, per-map budget

**Growth scenario / why it matters.** Shadows are a second scene pass over every
caster. The current reference map enables a 90 m PSSM 2 shadow on a sun with
1,832 instances, most of which cast. A 250 m map with more props multiplies the
shadow pass, and 3 maps make it a per-map budget problem.

**Current evidence.** Current reference map: `shadow_enabled=true`,
`directional_shadow_mode=1` (PSSM 2), `directional_shadow_max_distance=90`
(`scenes/maps/arena_quarry.tscn:38-44`); audit MAP-06 estimated 20–40 % GPU
frame from shadow casters and recommended disabling shadows on ridge/cliff/
stone/distant pines and testing 45–60 m. No per-map shadow budget or caster
policy was found.

**Questions for the research agent.**
1. What is the shadow-pass cost per map/pose on the reference low-end, at 45,
   60 and 90 m and 1 vs 2 vs 4 splits?
2. Which caster categories are visually necessary at third-person distance, and
   which can be shadowless or blob-shadowed?
3. Does turning shadows off on distant props cause visible pop when the player
   approaches?
4. What is a defensible per-map shadow budget (casters, distance, splits,
   resolution)?
5. Do shadowed point lights in caves matter, or can they stay shadowless?
6. How does shadow cost scale with 3 maps in rotation (residency, atlas)?

**Options.**
- **Do nothing.** Gain: zero.
- **Tune.** 45–60 m, 1 split, caster flags, blob shadows for small props.
  Expected: 20–40 % GPU frame; cost S; risk low–medium (visual).
- **Architectural.** Baked lightmaps / static shadow atlas. Expected: large;
  cost L; risk medium (bake pipeline, map workflow).

**How to answer.** A/B screenshots + GPU timer on the same camera poses; measure
frame p95 at 45/60/90 m. **Acceptance:** ≥ 20 % frame improvement on low-end,
no obvious visual regression, per-map caster budget declared.

**Risk / safety.** Visual only; no authority/prediction risk. Keep hero
shadows; do not make the scene flat.

**Priority / confidence.** **P1 · medium-high confidence** — the audit's estimate
is plausible but not browser-measured.

---

### REN-04 — LOD, MultiMesh vs merged meshes at 3-map scale

**Growth scenario / why it matters.** The project currently uses MultiMesh per
prop type and no LODs. At 3 maps and 250 m, the team needs a rule for when
MultiMesh is right, when merging is right, and when LOD/impostors pay for
themselves.

**Current evidence.** 1,832 instances in 31 MultiMeshes / 49 surfaces on the
reference map; audit says keep MultiMesh and do not merge props into one giant
mesh (loses per-instance culling, increases vertex memory); project Phase 2 says
"LODs off". No LOD or visibility-range code was found.

**Questions for the research agent.**
1. Does MultiMesh cull per instance or per AABB in Compatibility? (Same engine
   question as REN-01.)
2. At what instance count/distance do LODs or impostors pay off on WebGL2?
3. Is merging props into one mesh ever better for draw calls, given the culling
   and memory trade-off?
4. What is the per-map instance budget (500 / 1,000 / 2,500 / 5,000)?
5. Do LOD transitions cause visible pop at 60 fps, and what hysteresis is
   needed?
6. Can distant props be replaced by a baked impostor atlas without a custom
   shader that breaks Compatibility?

**Options.**
- **Do nothing.** Gain: zero.
- **Tune.** Per-chunk MultiMesh + visibility range + 2 LODs for hero props.
  Expected: 20–40 % visible geometry; cost M; risk medium.
- **Architectural.** Impostor/LOD system. Expected: large; cost L; risk high
  (web compatibility, art pipeline).

**How to answer.** Synthetic instance-scaling benchmark (500/1k/2.5k/5k) with
and without LOD; GPU timer + screenshots. **Acceptance:** 60 fps at target
instances, draw calls within budget, no visible pop.

**Risk / safety.** Visual/art pipeline; keep a simple fallback (no LOD) for
low-end.

**Priority / confidence.** **P2 · medium confidence** — likely a scale issue,
but only after REN-01/02.

---

### REN-05 — Chunk streaming, residency and 3-map rotation

**Growth scenario / why it matters.** Three maps in rotation means loading,
freeing and swapping large scenes during a session. If each swap is a full
synchronous generation like the current reference map (590 ms native), the
browser will freeze for seconds between matches, and keeping all three resident
may blow mobile memory.

**Current evidence.** The current map generates synchronously in `_ready`
(578.9 ms fresh; 99 % of main ready); `_set_map` loads and replaces the arena
node (`scripts/game/main.gd:262-287`); no streaming or preload of the next map
was found. Map memory delta is ~5.7 MB native for the reference map; 3 maps plus
WASM overhead is unknown.

**Questions for the research agent.**
1. What is the swap hitch for 3 maps on WASM, and what is the memory cost of
   keeping 1, 2 or 3 resident?
2. Is chunk streaming worth it for 150–250 m maps, or is a baked load + one
   loading screen enough?
3. Can the next map be preloaded during the match countdown without a frame
   spike?
4. What is the eviction policy and how do we prove resources are freed?
5. Does the server need all 3 maps resident, or only the current one?
6. How does a map swap interact with connected clients (do they reload, or does
   the server restart)?

**Options.**
- **Do nothing (one map per process).** Gain: zero; cost: zero; but no rotation.
- **Tune.** Bake maps, preload next, free previous, loading screen. Expected:
  swap ≤ 1 s; cost M; risk medium (memory).
- **Architectural.** Chunk streaming / additive scenes. Expected: large; cost
  L; risk high.

**How to answer.** Measure swap time, frame p95 and WASM heap over 10 rotations
on desktop and mobile. **Acceptance:** swap ≤ 1 s, no frame > 100 ms, no
monotonic memory growth, 3 rotations stable.

**Risk / safety.** Memory and visual pop; keep one-map fallback for low-memory
devices.

**Priority / confidence.** **P1 · high confidence** that 3-map rotation needs a
plan; **medium** in the best mechanism.

---

### REN-06 — Materials, textures, fog, far plane, overdraw

**Growth scenario / why it matters.** Per-map material/texture choices decide
fragment cost and memory. Triplanar terrain, disabled backface culling,
anisotropic filtering and a huge default far plane may be cheap on desktop and
expensive on mobile.

**Current evidence.** Current reference map terrain uses `uv1_triplanar`,
`CULL_DISABLED`, anisotropic filtering (audit MAP-07; reference only); fog
density 0.0015 and ProceduralSky; no explicit camera `far`; web export enables
S3TC/BPTC but `vram_texture_compression/for_mobile=false`
(`export_presets.cfg`); texture memory per map is unmeasured.

**Questions for the research agent.**
1. What is texture memory per map at the current asset sizes, and what is the
   mobile ceiling?
2. Does triplanar/`CULL_DISABLED`/aniso measurably change fragment cost on
   WebGL2 low-end?
3. What far plane and fog density should a 150–250 m map use to avoid clipping
   and overdraw?
4. Are textures exported in a mobile-compatible compressed format (ETC2/ASTC),
   or only S3TC/BPTC? What is the fallback?
5. What is the per-map material/surface budget?
6. Does ProceduralSky cost per frame, and can a static skybox replace it?

**Options.**
- **Do nothing.** Gain: zero.
- **Tune.** Drop triplanar where UVs exist, `CULL_BACK`, mipmaps, far plane
  250–350 m, texture size/compression. Expected: 20–50 % terrain fragment cost;
  cost S; risk low–medium (visual stretching).
- **Architectural.** Texture atlas/streaming, static sky. Expected: medium;
  cost M; risk medium.

**How to answer.** GPU timer + texture-memory report per map; A/B screenshots;
test on mobile Safari/Chrome. **Acceptance:** ≤ 80 MB textures/map, ≥ 20 %
fragment reduction if triplanar is removed, no visible stretching/clipping.

**Risk / safety.** Visual; no authority risk. Keep a per-map screenshot
baseline.

**Priority / confidence.** **P1 · medium confidence** — plausible, but needs
device measurement.

---

## 5. Network / connection handling

### NET-01 — Position quantization vs map size  **[P0]**

**Growth scenario / why it matters.** The wire format quantizes absolute world
positions to millimetres over ±32.768 m. Any playable area beyond that is
**clamped**, not compressed: remote actors and the local reconciliation pose are
wrong by metres. This is already true on a 150 m map and is fatal on a 250 m map.
It is a correctness bug, not just a bandwidth question.

**Current evidence.** `POS_RANGE = 32.768`, `_quant_pos` clamps to
`[-32768, 32767]` (`scripts/networking/net_protocol.gd:21,325-327`); snapshot
positions are absolute (`:174-190`); the local client applies the decoded pose
in reconciliation (`player_controller.gd:307-321,371-394`). Probe results:
40 m → 32.767 (7.233 m error), 69.5 m → 32.767 (51.948 m error), 125 m →
130.436 m error. The current reference map has spawns at |x|/|z| up to 62 m
(`scripts/game/quarry_arena.gd:72-84`), so this is live, not theoretical.

**Questions for the research agent.**
1. What is the correct quantization scheme for a ±125 m playable area with
   acceptable prediction/interpolation error (target ≤ 1–2 cm)?
2. Which option is best: (a) i16 over ±131.072 m at 4 mm, (b) per-snapshot
   reference origin + i16 local offsets, (c) 24-bit positions, (d) float16?
3. How do relative coordinates interact with join, respawn, teleport, late
   join and packet loss?
4. What is the smallest per-actor byte layout that keeps ≤ 2 cm error at 250 m?
5. How does the change migrate the protocol (version byte, mixed clients,
   reconnect)?
6. Does the same problem affect velocity, yaw or event positions (shot/hit/
   death/respawn)?
7. What is the acceptance test at map edges and after a respawn?

**Options.**
- **Do nothing.** Broken beyond ±32.768 m; not viable.
- **Tune.** Widen range to ±131.072 m at 4 mm (same 6 B/axis), or use a
  per-snapshot origin. Expected: fixes correctness, same snapshot size; cost S;
  risk medium (protocol).
- **Architectural.** Relative/origin-rebased coordinates or 24-bit positions.
  Expected: correct and scalable; cost M; risk medium–high (prediction,
  protocol).

**How to answer.** Unit-test round-trip error across the full ±125 m extents and
at 1 mm/1 cm/1 m granularity; run a two-client edge-of-map reconciliation test;
measure snapshot size. **Acceptance:** max position error ≤ 2 cm across the
whole map, snapshot ≤ 300 B at 8, no rubber-band at edges/respawn, decode
rejects malformed packets.

**Risk / safety.** Protocol compatibility and prediction determinism are both
high risk. Version the protocol and keep a mixed-version test. Do not ship a
map larger than the quantization range before this is fixed.

**Priority / confidence.** **P0 · high confidence** — measured with the real
codec.

---

### NET-02 — Actor cap, snapshot size and protocol layout  **[P0]**

**Growth scenario / why it matters.** `MAX_PLAYERS=8` is baked into the count
byte, decoder, roster, UI and scoreboard. At 16 actors the current encoder emits
358 B and the decoder rejects it; at 32 it emits 710 B and still rejects it.
"Just raise the cap" does not work.

**Current evidence.** `MAX_PLAYERS=8` (`net_protocol.gd:17`); `encode_snapshot`
writes `min(entries.size(), MAX_PLAYERS)` as the count but then loops **all**
entries (`:170-190`); `decode_snapshot` requires
`pkt.size() == 6 + count * 22` and `count <= MAX_PLAYERS` (`:192-214`). Probe:
8 → 182 B ok; 16 → 358 B, count byte 8, decode rejected; 32 → 710 B, count byte
8, decode rejected. Budget is ≤ 300 B at 8.

**Questions for the research agent.**
1. What is the minimum per-actor byte layout at 16/32 with acceptable precision
   (id, pos, yaw, state, vel, on_floor, hp, ack)?
2. Can bit-packing (yaw 9 bits, state 2, hp 7, flags 1, ack 16) plus delta/
   interest fit 16 actors in ≤ 300 B, or is a larger budget required?
3. What is the right budget: fixed 300 B at 8, 512 B at 16, 1 KB at 32, or a
   per-client interest-managed budget?
4. How should the protocol version and mixed-client compatibility work?
5. What is the UI/scoreboard/spawn/roster impact of raising the cap?
6. Does the count byte need to become u16, and what breaks?
7. What is the mobile/TCP cost of the larger snapshot at 30 Hz?

**Options.**
- **Do nothing at 8.** Gain: zero; caps product.
- **Tune.** Bit-pack, widen count, raise budget to 512 B/1 KB. Expected: 16/32
  possible; cost S–M; risk medium (protocol).
- **Architectural.** Interest management + delta + relative positions. Expected:
  keeps 300 B at 32; cost L; risk high.

**How to answer.** Encode/decode benchmarks at 8/16/32, byte counts, decode p95,
malformed-packet tests. **Acceptance:** 16 actors ≤ 512 B and 32 ≤ 1 KB (or
interest-managed ≤ 300 B), decode p95 ≤ 100 µs, no rejected valid packet.

**Risk / safety.** Protocol and prediction; version it and test mixed clients.
The count byte bug (encode all, count capped) must be fixed regardless.

**Priority / confidence.** **P0 · high confidence** — measured with the real
codec.

---

### NET-03 — Interest management / delta compression

**Growth scenario / why it matters.** Today every client receives every actor
and every event. At 32 actors on a 250 m map, a client may not need distant
actors at full rate. Interest management (AOI) or delta compression could keep
the 300 B budget, but both add state and correctness risk.

**Current evidence.** The server encodes one snapshot and sends it to every
joined peer (`game_manager.gd:369-373`); events are broadcast to every peer
(`:700-707`); no per-client filtering, delta baseline or priority was found.
Snapshots are reliable/ordered WebSocket messages. At 8 actors, 182 B × 30 Hz =
5.5 KB/s down; at 32 the naive size is 710 B × 30 Hz = 21.3 KB/s.

**Questions for the research agent.**
1. At 32 actors, is full-roster broadcast acceptable on desktop and mobile
   (bytes/s, battery, TCP)? What is the measured downstream per client?
2. How much would distance/visibility AOI save, and what is the complexity/
   correctness cost?
3. How do actors entering/leaving AOI interact with interpolation, prediction,
   scoreboard and hit events?
4. Does delta compression help on a reliable/ordered TCP WebSocket, or does it
   only add baseline/reconnect state?
5. What is the reconnect/late-join baseline story?
6. Is per-event relevance filtering (shots/hits far away) worth it?

**Options.**
- **Do nothing.** Gain: zero; cost: zero.
- **Tune.** Distance-cull far actors (e.g., > 120 m at 5 Hz), filter far events,
  keep full rate near. Expected: 30–50 % downstream at 32; cost M; risk medium.
- **Architectural.** AOI + delta + priority. Expected: keeps 300 B at 32; cost
  L; risk high (state, correctness).

**How to answer.** Simulate 32 actors with realistic distribution; measure
bytes/s, CPU, and visual correctness with AOI on/off. **Acceptance:** ≥ 40 %
downstream reduction at 32 with no visible pop/desync; no new authority path.

**Risk / safety.** High complexity; do not attempt before NET-01/02 and only if
NET-02 shows the naive budget is unacceptable.

**Priority / confidence.** **P2 · medium confidence** — likely needed only at 32.

---

### NET-04 — Snapshot rate vs tick rate (20 / 30 / 60)

**Growth scenario / why it matters.** Tick rate is the biggest single lever on
server CPU, bandwidth and feel. 20 Hz cuts both by ~33 %; 60 Hz doubles them.
The project currently couples physics and snapshot at 30 Hz and predicts at
1/30. Changing it is a product decision, not a micro-optimization.

**Current evidence.** `physics_ticks_per_second=30` (`project.godot`); snapshot
once per tick (`game_manager.gd:369`); input 12 B at 30 Hz; remote interpolation
2.5 ticks = 83 ms (`network_interpolator.gd:12-14`); prediction replays at
`1/30` (`player_controller.gd:394-412`); audit SERVER-01 suggested 20 Hz as a
fallback if server CPU grows. At 30 Hz a projectile at 81 m/s moves 2.7 m/tick;
the swept ray prevents tunneling.

**Questions for the research agent.**
1. What does 20 Hz buy in server CPU, bandwidth and battery, and what does it
   cost in input latency, hit registration and feel?
2. What does 60 Hz buy in hit registration/feel, and what does it cost in CPU,
   bandwidth and WASM client cost?
3. Can tick and snapshot rates differ (30 Hz tick, 15/20 Hz snapshot) without
   breaking prediction/interpolation? What is the ack semantics?
4. What is the minimum tick rate for 81 m/s projectiles and 8.6 m/s movement
   with the current swept ray?
5. How does tick rate affect replay depth at 100–150 ms RTT?
6. Is 30 Hz still right for a 250 m map with 32 actors, or should it be
   per-map/per-mode?

**Options.**
- **Do nothing (30 Hz).** Gain: zero; cost: zero.
- **Tune.** 20 Hz for server cost, or 60 Hz for feel, or decouple snapshot at
  20 Hz. Expected: ±33–100 % CPU/bandwidth; cost M; risk high (feel/protocol).
- **Architectural.** Adaptive tick / separate snapshot rate / lag compensation.
  Expected: best fit; cost L; risk very high.

**How to answer.** A/B on server CPU, bandwidth, input latency, hit registration
and player feel; measure p95 tick and frame; run a blind playtest.
**Acceptance:** server p95 ≤ 50 % budget, no tunneling, no > 1 frame added
input latency, feel sign-off.

**Risk / safety.** Highest feel/authority risk after NET-01. Any tick change
must update `delta` in prediction, replay, interpolation and projectile
sweeps atomically.

**Priority / confidence.** **P1 · high confidence** in the trade-off direction;
**low** in the right answer without playtest.

---

### NET-05 — Drain, backpressure, TCP HOL, WebSocket cost

**Growth scenario / why it matters.** WebSocket is TCP: one slow client or one
lost packet can stall that client's stream, and per-peer sends at 32 clients
mean 960 WebSocket writes/s. The server currently polls once per frame, drains
at most 64 packets, and calls `put_packet` per peer with no visible send-queue
or backpressure policy.

**Current evidence.** `MAX_DRAIN_PER_FRAME=64` (`network_manager.gd:34,471-484`);
`_peer.poll()` in `_process` (`:320-326`); `server_send` → `_send_to` →
`set_target_peer` + `put_packet` (`:433-452`); snapshot sent per peer per tick
(`game_manager.gd:369-373`); events are separate messages; one-origin proxy is
planned (`docs/DEPLOY.md`).

**Questions for the research agent.**
1. What happens when a client's TCP send buffer is full: does `put_packet`
   block, drop, or grow memory? Cite Godot/WebSocketPeer behavior.
2. How do we detect a slow/stalled peer and avoid letting it affect others?
3. Should snapshots be coalesced (newest-wins) per peer before send? What is
   the gain at 32 clients?
4. What is the server CPU/egress cost of 32 × 30 WebSocket sends/s?
5. How bad is TCP head-of-line blocking for a 30 Hz shooter on 4G? Is
   WebTransport/QUIC a realistic web option in 2026, and what is the fallback?
6. Does the one-origin reverse proxy add latency, connection limits, or
   buffering?
7. What is the drain budget at 32 clients (64 packets/frame may be too low)?

**Options.**
- **Do nothing at 8.** Gain: zero.
- **Tune.** Per-peer snapshot coalescing, send budget, drain budget, slow-peer
  detection, event batching. Expected: protects tick under load; cost M; risk
  medium.
- **Architectural.** WebTransport/QUIC or a separate unreliable channel.
  Expected: removes HOL; cost L; risk high (browser support, deployment).

**How to answer.** Soak 32 clients with `--sim-latency/--sim-jitter` and a
deliberately slow client; measure queue depth, RTT, drops, tick p95 and server
CPU. **Acceptance:** server tick p95 ≤ budget, no unbounded queue, one slow
client does not degrade others.

**Risk / safety.** Reliability/complexity; do not silently drop authoritative
events (death/respawn) even if snapshots are coalesced.

**Priority / confidence.** **P1 · high confidence** at 32 clients; **medium** at
8.

---

### NET-06 — Join/reconnect storms, rate limits, proxy, mobile

**Growth scenario / why it matters.** A 32-player launch or a proxy restart can
produce simultaneous joins/reconnects. Each join spawns a full actor, sends a
roster, and starts snapshots; each client also loads a map. The current
handshake and reconnect policy was designed for 8.

**Current evidence.** Join handshake `JOIN_REQ`/`JOIN_OK`/`ROSTER`
(`network_manager.gd:494-520`); `_spawn_server_actor` full scene
(`game_manager.gd:741`); `_pending_joins` expires after 5 s
(`network_manager.gd:32,571-585`); reconnect grace 8 s (`:44,382-412`); connect
budget 6 s (`:37,339-375`); input rate limit 90/s and queue 16
(`game_manager.gd:19-20,241-280`); drain 64/frame; one-origin proxy planned.

**Questions for the research agent.**
1. What is the server tick/CPU/network spike for 8/16/32 simultaneous joins?
2. Does each join need to instantiate a full actor synchronously, and can joins
   be queued over several ticks?
3. What is the client cold-join time on 4G (download + compile + map + join)?
4. Do reconnect storms after a proxy restart create a thundering herd? What
   jitter/backoff is needed?
5. Are rate limits per peer, per IP, or per connection? What stops a join flood?
6. Does the one-origin proxy add connection limits or buffering?
7. What is the mobile background-tab/reconnect behavior (iOS Safari kills
   sockets)?

**Options.**
- **Do nothing at 8.** Gain: zero.
- **Tune.** Queue joins, prewarm actor, jitter reconnect, per-IP limits, join
  budget. Expected: no tick spike, 95 % join < 2 s; cost M; risk medium.
- **Architectural.** Lobby/queue service, session tokens, dedicated join
  workers. Expected: scales to 32+; cost L; risk high.

**How to answer.** Synthetic join storm (32 clients in 1 s, then 32 reconnects
after a forced drop); measure tick p99, join success, time-to-play, server CPU.
**Acceptance:** no tick > 2× baseline, 95 % join < 2 s, no dropped joins, no
cross-client interference.

**Risk / safety.** UX/security; rate limits must not punish legitimate mobile
reconnects.

**Priority / confidence.** **P1 · high confidence** at 32; **medium** at 8.

---

## 6. Memory / payload / startup

### MEM-01 — WASM/PCK payload and cold join

**Growth scenario / why it matters.** The web build is ~45.7 MB raw / ~14.5 MB
gzip before any new map assets. On 4G that is a multi-second download plus WASM
compile plus map generation. This is the largest fixed cost for a new player.

**Current evidence.** `build/web`: wasm 39.5 MB raw / 10.1 MB gzip; pck 5.94 MB
/ 4.31 MB gzip; js 0.28 MB; total 45.7 / 14.5 MB. Audit WEB-02 found ~2.59 MB
of unreferenced imported scenes (rig/adventurer/weapon) in the PCK. Audio is
synthesized at runtime (6 pooled players, no external audio assets), so audio
memory is negligible today; add it to the per-map asset budget if music/voice
lands. Project Phase 0 budget: ≤ 20 MB gzip and ≤ 10 s to interactive on
localhost. Current map ready is 590 ms native, likely 1–2 s WASM.

**Questions for the research agent.**
1. What is the smallest viable Godot 4.7 web build for this game (module strip,
   Brotli, PCK dedupe, exclude filters), and what breaks?
2. What is cold join on 4G/3G and on a mid-range phone: download, compile,
   first frame, map ready, join?
3. Is 20 MB gzip still the right budget for 3 maps, or should it be per-map
   lazy-loaded?
4. Does `WebAssembly.instantiateStreaming` / wasm streaming compile help, and
   is the server configured for it?
5. What is the warm-cache path, and how do we verify `Cache-Control: immutable`
   + Brotli?
6. What is the cost/benefit of a custom engine build vs asset trimming?

**Options.**
- **Do nothing.** Gain: zero; cost: zero.
- **Tune.** Brotli-11, immutable cache, exclude unreferenced imports, per-map
  lazy load. Expected: −1.3 MB gzip+; cost S–M; risk medium (missing assets).
- **Architectural.** Custom engine build / asset streaming. Expected: large;
  cost L; risk high (maintenance).

**How to answer.** Measure cold/warm load on throttled 4G and desktop, with
cache disabled/enabled; verify every asset loads. **Acceptance:** ≤ 15 s cold
join on 4G, ≤ 5 s warm, total ≤ 20 MB gzip, no missing asset.

**Risk / safety.** Build/export complexity; keep a boot test that loads every
map and fires a shot.

**Priority / confidence.** **P1 · high confidence** in the payload; **medium**
in the achievable reduction.

---

### MEM-02 — Runtime memory ceiling and 3-map residency

**Growth scenario / why it matters.** WASM memory grows in large pages and does
not always return to the OS. Three maps, 32 actors and pooled effects can push a
mobile browser close to its tab limit, causing a crash rather than a frame drop.

**Current evidence.** Native headless: 59.1 MB static final, 66.9 MB peak;
reference map adds ~5.7 MB. Browser WASM heap is unmeasured. No memory metric is
shown in the HUD; `Performance.MEMORY_STATIC` is native-only. 3 maps in rotation
and 32 actors are the growth scenario.

**Questions for the research agent.**
1. What is the WASM heap after 1/2/3 maps and after 10 rotations?
2. Does Godot free map meshes/MultiMeshes/materials when the arena is freed?
3. What is the practical tab memory ceiling on iOS Safari, Android Chrome and
   desktop Chrome?
4. Can 3 maps be resident, or must only one be?
5. What is the peak during map swap (old + new alive)?
6. What telemetry can expose heap growth in production?

**Options.**
- **Do nothing.** Gain: zero; cost: zero.
- **Tune.** Free previous map, preload next, cap pools, reduce textures.
  Expected: keeps peak under ceiling; cost M; risk medium.
- **Architectural.** Streaming/eviction. Expected: large; cost L; risk high.

**How to answer.** `WebAssembly.Memory.buffer.byteLength` + `performance.memory`
(where available) over 10 rotations and a 10-minute 32-actor match on real
devices. **Acceptance:** no monotonic growth, peak ≤ 250 MB, no crash on 3
rotations.

**Risk / safety.** Mobile crashes; keep a one-map/low-memory fallback.

**Priority / confidence.** **P1 · high confidence** that 3 maps change the
ceiling; **low** in the exact number until measured.

---

### MEM-03 — Node/object churn and GC at 32 actors

**Growth scenario / why it matters.** The current probes show 0 orphans, but
they run at 8 actors for seconds. A 10-minute 32-actor match with projectiles,
remote joins/leaves and map rotation is a different test.

**Current evidence.** Projectiles `queue_free()` per resolve, no pool
(`projectile.gd:220-231`); bullet pool is fixed and zero-churn; remote actors
are full scenes created/freed on join/leave (`game_manager.gd:983-1014`);
`_snapshot_entry`/interpolator allocate dictionaries per tick/frame; probes
report 0 orphans at 8 actors. `CharacterVisual._swap_character` frees and
instantiates on class change (once per actor).

**Questions for the research agent.**
1. What is node/object churn per minute at 32 actors and max fire rate?
2. Does `queue_free` per projectile cause GC spikes, or is the rate too low?
3. Should projectiles and remote actors be pooled?
4. What is the orphan/object count after a 10-minute match and 10 rotations?
5. Does Godot's allocator return memory to WASM, or does the heap plateau?
6. What is the p99 frame/tick impact of a join/leave burst?

**Options.**
- **Do nothing.** Gain: zero.
- **Tune.** Pool projectiles/remotes, reuse dictionaries. Expected: removes
  spikes; cost M; risk medium.
- **Architectural.** Object pools / data-oriented actors. Expected: large; cost
  L; risk high.

**How to answer.** 10-minute soak at 32 actors with `soak_runner`; monitor
nodes/objects/orphans/static memory and p99 frame/tick. **Acceptance:** zero
orphan growth, no monotonic memory, p99 stable.

**Risk / safety.** Pooling can leak state between uses; reset every field.

**Priority / confidence.** **P2 · high confidence** in the current zero-churn
result at 8; **medium** at 32.

---

### MEM-04 — Bake vs runtime generation and cache strategy  **[P0]**

**Growth scenario / why it matters.** The current map generates synchronously in
`_ready` (590 ms native, 99 % of startup). If each of the three new maps does
the same, every cold join and every map swap pays a multi-second WASM stall.
Baking is the difference between a playable web build and a loading-screen
simulator.

**Current evidence.** Reference map generation 578.9–581.7 ms native: scatter
267–271 ms, detail texture 194 ms, terrain 101–102 ms; deterministic seed;
main ready 590 ms. Audit MAP-01..04 propose a spatial hash, baked texture and
baked chunk meshes/heightmap/placements, with a 20–40× generation reduction.
The new maps are out of scope, so this question must be answered as a
**map-agnostic contract**, not a quarry fix.

**Questions for the research agent.**
1. What is the per-map generation budget on native and WASM (target: ≤ 50 ms
   native / ≤ 150 ms WASM)?
2. Which parts must be baked: chunk meshes, `HeightMapShape3D.map_data`,
   placement transforms, detail textures, collision shapes? Which can stay
   runtime?
3. How do we guarantee server and client generate bit-identical heightmaps and
   colliders after baking?
4. What is the bake artifact size/format (`.res`, `.scn`, binary) and load
   time?
5. How does baking interact with map iteration/hot reload in the editor?
6. What is the fallback if a map cannot be baked (incremental build behind the
   loading screen, no frame > 16 ms)?
7. What is the cache strategy across 3 maps (bake once at export, load per
   match)?

**Options.**
- **Do nothing.** Gain: zero; cost: zero; but multi-second stalls.
- **Tune.** Spatial hash + smaller runtime texture if bake slips. Expected:
  465 ms of 582 ms removed; cost S; risk low.
- **Architectural.** Full bake pipeline (terrain, heightmap, placements,
  textures) + resource loader. Expected: 20–40× generation; cost M; risk low–
  medium (workflow).

**How to answer.** Measure generation per map on native and WASM, broken down
by step; verify baked vs generated geometry/collision equality; measure cold
join and swap. **Acceptance:** map ready ≤ 150 ms WASM, ≤ 50 ms native; no
frame > 16 ms during load; server/client heightmap identical; bake artifact
within size budget.

**Risk / safety.** Correctness and workflow; keep the generator in the repo and
regenerate offline. Do not let a stale bake ship silently — hash the source
inputs.

**Priority / confidence.** **P0 · high confidence** — measured on the reference
map, and the new maps are larger.

---

## 7. Observability / budgets

### OBS-01 — What to measure in dev and production

**Growth scenario / why it matters.** The team cannot manage 3 maps / 32 actors
with ad-hoc prints. Every budget in §12 needs a named metric, a source and a
sampling rate, or the manager cannot tell a regression from noise.

**Current evidence.** Existing counters: `NetworkManager.snapshots_processed/
dropped/last_snapshot_bytes/rtt_ms` (`network_manager.gd:54-62`);
`PlayerController.prediction_stats()` (`player_controller.gd:323-345`);
`BulletField.pool_stats()`; `ServerCombat.telemetry_line()`; `DebugOverlay`
FPS/tick/pos/camera/pred (`debug_overlay.gd:41-88`); `perf_probe` `PERF_*`;
`soak_runner` `SOAK_*`. Missing: tick histogram, frame p95/p99, draw calls,
visible triangles, texture/heap memory, join/swap timings, per-peer send queue.

**Questions for the research agent.**
1. What is the minimum metric set per domain (server, client, render, network,
   memory, match)?
2. Which metrics can ship in production without privacy/overhead problems, and
   which stay dev-only (`?perf=1`, F3)?
3. What sampling rate/histogram buckets are enough to catch p99 spikes?
4. What schema should `PERF_*`/`SOAK_*` use so CI and the manager can compare
   runs?
5. Can the HUD/debug overlay show the budget metrics without adding cost?
6. How do we measure per-map metrics (draw calls, tris, memory, generation)
   automatically?

**Options.**
- **Do nothing.** Gain: zero; cost: zero; but blind.
- **Tune.** Add counters/histograms and a hidden perf panel. Expected: makes
  every other question measurable; cost S–M; risk low.
- **Architectural.** Telemetry pipeline/dashboard. Expected: large; cost L;
  risk medium (privacy/ops).

**How to answer.** Define a schema, implement read-only counters, run a 10-minute
soak and compare. **Acceptance:** every budget metric has a source, < 1 %
overhead, reproducible across runs.

**Risk / safety.** Overhead and privacy; no player identifiers in telemetry.

**Priority / confidence.** **P1 · high confidence** — prerequisite for OBS-02/03.

---

### OBS-02 — Thresholds that should trigger work

**Growth scenario / why it matters.** Without thresholds, "it feels slower" wins
arguments. With thresholds, the manager can decide: tune, roll back, or accept.

**Current evidence.** Known budgets: 33.3 ms tick, 16.7 ms frame at 60 fps,
≤ 300 B snapshot at 8, ≤ 10 s localhost interactive, ≤ 150 draw calls, ≤ 250k
triangles, ≤ 100 MB textures (Phase 2). Current measured: tick p95 5.6–6.7 ms at
8; 49 draw calls / 192k triangles; map ready 590 ms. No alert/CI gate exists.

**Questions for the research agent.**
1. What are the yellow/red thresholds per metric, per map and per actor count?
2. How many consecutive samples/which percentile (p95 vs p99) should trigger?
3. What is the regression threshold for CI (e.g., > 10 % and > 2× noise)?
4. Should thresholds differ for desktop/mobile/high-DPI?
5. What is the rollback trigger vs the "file a ticket" trigger?
6. How do we avoid alert fatigue from shared-container noise?

**Options.**
- **Do nothing.** Gain: zero.
- **Tune.** Publish a threshold table and CI gates. Expected: catches
  regressions early; cost S; risk low.
- **Architectural.** Automated perf CI with device lab. Expected: large; cost L;
  risk medium.

**How to answer.** Derive thresholds from 3+ baseline runs and the budget table;
validate with a deliberately regressed build. **Acceptance:** CI fails on a
known 15 % regression, passes on noise; runbook exists.

**Risk / safety.** False positives; use run-to-run variance and require browser
confirmation for GPU claims.

**Priority / confidence.** **P1 · high confidence.**

---

### OBS-03 — How to prove a fix; headless→browser calibration  **[P0]**

**Growth scenario / why it matters.** The manager will reject "it should be
faster". Native headless numbers exclude GPU, canvas, shader compile, WASM
memory growth and browser scheduling, and the shared container varies by 20–30 %
between runs (8-bot tick 2.79–3.54 ms avg). A credible answer needs a paired
A/B on the target runtime and a stated noise floor.

**Current evidence.** Previous audit explicitly labels native numbers as lower
bounds and lists open device questions (HUD draw, GPU frame, shader compile,
WASM memory, Firefox/Safari, mobile, real socket drain, small VPS). The probe
uses `Time.get_ticks_usec()` and nearest-rank p95; three full runs were taken
for the audit. No browser profiling is committed. `tools/capture.sh` exists for
screenshots, not perf.

**Questions for the research agent.**
1. What sample size/run count is needed to claim a 10 % gain on this noisy
   container? What statistic (median, p95, bootstrap CI)?
2. What is the native→WASM factor per subsystem (scripts, physics, codec,
   rendering), measured rather than assumed?
3. Which metrics are invalid headless (GPU, canvas draw, shader compile,
   texture upload, WASM heap, socket scheduling)?
4. What is the minimum device matrix (Chrome/Firefox/Safari, Intel UHD, mid
   Android, iPhone)?
5. How do we A/B a change on device without shipping two builds (query flag,
   runtime toggle, canary)?
6. What is the acceptance evidence for a rendering change (screenshots + GPU
   timer) vs a server change (tick histogram)?
7. What would falsify the claimed gain?

**Options.**
- **Do nothing.** Gain: zero; cost: zero; but answers are not defensible.
- **Tune.** 3+ paired runs, p50/p95/p99, browser confirmation, screenshots.
  Expected: credible decisions; cost S; risk low.
- **Architectural.** Device lab / automated browser perf CI. Expected: large;
  cost L; risk medium.

**How to answer.** Paired A/B (same build, toggle, interleaved runs), 3+ runs,
report median/p95/p99 with variance; confirm the end-to-end metric on the target
device. **Acceptance:** gain > 2× noise and ≥ 10 % on the target metric, plus a
browser confirmation; otherwise the answer is "not proven".

**Risk / safety.** False conclusions; require the raw log and command.

**Priority / confidence.** **P0 · high confidence** — the manager's rubric
depends on this.

---

## 8. The match itself

### MAT-01 — Is the current 5-min / 8-actor / 30 Hz model a bottleneck?

**Growth scenario / why it matters.** This must be a real question, not an
assumed problem. At 8 actors the measured server tick is 2.8–3.5 ms (8–20 % of
budget), the snapshot is 182 B, and client scripts are ~0.5 ms. The actual
startup bottleneck is map generation. Changing the match model may buy nothing
and cost feel.

**Current evidence.** 8 actors / 30 Hz: server 2.79–3.54 ms avg, 5.61–6.74 ms
p95; snapshot 182 B; input 12 B; client scripts ~0.5 ms; main ready 590 ms (99 %
map). The 5-minute FFA is product intent in `README.md`/`docs/ROADMAP.md`, but
**no match timer implementation was found** in tracked code (only the
`match_state_changed` signal in `event_bus.gd`). 32 actors is 4× the current
cap and 4× the snapshot bytes.

**Questions for the research agent.**
1. At 8 actors, is the match model actually limiting fun, retention, server cost
   or client performance? Quantify.
2. What is the target player count and map size for the next milestone, and what
   does the current model fail to deliver?
3. What would 16/32 actors buy in fun/retention, and what would it cost in
   server CPU, client frame, network and content?
4. Is 5 minutes the right length for 8/16/32 actors and 150–250 m maps? What
   does 10 minutes or rounds buy/cost?
5. Is the bottleneck server, client, network, content, or onboarding (cold
   join)?
6. What is the cost of bots filling empty slots vs waiting for humans?
7. What is the smallest change that tests the hypothesis (e.g., 12 actors, 8
   minutes) before a full 32-player architecture?

**Options.**
- **Do nothing.** Gain: zero; cost: zero; but may leave growth on the table.
- **Tune.** 12–16 actors, 8–10 min, more bots. Expected: moderate; cost M; risk
  medium (feel/balance).
- **Architectural.** 32-player/round-based/teams/matchmaking. Expected: large;
  cost L; risk high.

**How to answer.** Measure current end-to-end at 8; model 16/32 with the SRV/
CLI/NET data; run a playtest with 8/12/16 actors and 5/8/10 minutes; compare
fun, retention proxy, server cost and frame. **Acceptance:** a decision backed
by measured headroom + playtest, not an assumption.

**Risk / safety.** Scope/feel; do not change the match model to fix a startup
problem that baking solves.

**Priority / confidence.** **P1 · high confidence** that the current model is
not the main bottleneck at 8; **medium** in the right growth target.

---

### MAT-02 — Match length, respawn and join/leave churn

**Growth scenario / why it matters.** Five-minute FFA with 3 s respawn and 1.5 s
protection is a churn-heavy loop: players join/leave mid-match, die often, and
respawn often. At 32 actors the death/respawn/event rate could be the difference
between a calm tick and a spike.

**Current evidence.** `RESPAWN_DELAY_MSEC=3000`, `SPAWN_PROTECTION_MSEC=1500`
(`game_manager.gd:27-28`); respawn resets combat/health/queue and broadcasts an
event (`:457-484`); no match timer found; join/leave can happen at any time
(`_on_peer_joined`/`_on_peer_left`, `:190-239`). No death/respawn rate metric
exists.

**Questions for the research agent.**
1. What is the death/respawn rate at 8/16/32 actors, and how bursty is it?
2. Does 3 s respawn cause spawn-camping or a respawn spike? Would 5 s be better?
3. Does 5-minute FFA produce enough join/leave churn to stress the server or
   ruin match quality?
4. Should match length scale with actor count/map size?
5. What is the cost/benefit of a match timer + scoreboard + end-of-match flow?
6. Do rounds/teams reduce churn and server spikes?

**Options.**
- **Do nothing.** Gain: zero.
- **Tune.** 5 → 8/10 min, respawn 3 → 5 s, warmup. Expected: smoother matches;
  cost S; risk low (feel).
- **Architectural.** Round-based/teams/matchmaking. Expected: large; cost L;
  risk high.

**How to answer.** Instrument deaths/min, respawns/min, joins/leaves and tick
p99 per match; playtest. **Acceptance:** no tick spikes attributable to
respawn; player feedback positive.

**Risk / safety.** Feel; keep the current values as a fallback.

**Priority / confidence.** **P2 · medium confidence.**

---

### MAT-03 — Actor cap and bot/human mix

**Growth scenario / why it matters.** The cap is the single number that drives
server, client, network and map design. 8 → 16 → 32 is not a free multiplier:
snapshot bytes, actor scenes, AI and UI all scale.

**Current evidence.** `MAX_PLAYERS=8`; bots fill free slots
(`game_manager.gd:522-532`); server_start 10.7–13.5 ms for 8 bots; bot AI
0.46–0.68 ms/tick at 8; snapshot 182 B; 16/32 currently cannot encode/decode
(NET-02). Client remote scenes are full player scenes (CLI-02).

**Questions for the research agent.**
1. What is the maximum actor count for 60 fps client / 30 Hz server on the
   reference hardware, with humans vs bots?
2. How many bots are acceptable before AI cost/feel degrades?
3. Can bots use a cheaper AI LOD at 32 while humans keep full fidelity?
4. What is the player-facing cap given 150–250 m maps, 8+ spawns and the
   scoreboard/UI?
5. What is the cost of raising the cap to 12/16/32 in protocol, UI, map spawns
   and matchmaking?
6. Is 8 still the right V1 cap, with 16 as a stretch?

**Options.**
- **Do nothing (8).** Gain: zero.
- **Tune.** 12/16 with bot LOD and protocol widening. Expected: moderate; cost
  M; risk medium.
- **Architectural.** 32 with interest management and server actor LOD. Expected:
  large; cost L; risk high.

**How to answer.** Load test 8/12/16/32 with bots/humans; measure server p95,
client p95, bytes/s; playtest. **Acceptance:** server p95 ≤ budget, client p95
≤ budget, fun sign-off.

**Risk / safety.** Gameplay/feel and protocol; stage the cap (8 → 12 → 16 → 32)
with a rollback.

**Priority / confidence.** **P1 · high confidence** that the cap drives
everything; **medium** in the right number.

---

## 9. Safe vs risky optimizations

### SAF-01 — Classification matrix  **[P0]**

**Growth scenario / why it matters.** The manager needs to know which changes
can be applied immediately and which need a rollback plan. The project's hard
rules are server authority, prediction determinism and web compatibility
(no threads/SAB, Compatibility only).

**Current evidence.** Authority table and prediction/reconciliation design are
in `docs/ARCHITECTURE.md`; the client replays `LocomotionComponent` at 1/30;
the server owns damage/projectiles/spawn; the web export is single-threaded
(`export_presets.cfg` `variant/thread_support=false`).

| Change | Authority | Prediction | Web | Verdict |
|---|---|---|---|---|
| Bake map resources | unchanged | unchanged (same heightmap) | better | **Safe** |
| Spatial hash for scatter | unchanged | unchanged | better | **Safe** |
| Cache `HealthComponent` / node refs | unchanged | unchanged | better | **Safe** |
| Preallocate snapshot buffer / bit-pack | unchanged | unchanged (decode same values) | better | **Safe if codec tests pass** |
| Dirty-flag HUD / throttle UI | unchanged | unchanged | better | **Safe** |
| Shadow distance / caster flags | unchanged | unchanged | better | **Safe (visual A/B)** |
| Per-chunk MultiMesh / visibility range | unchanged | unchanged | better | **Safe (visual pop risk)** |
| Pool projectiles / remote scenes | unchanged | unchanged if reset | better | **Safe with reset tests** |
| Animation LOD for remotes | unchanged | unchanged | better | **Safe (visual)** |
| Widen position range / relative coords | unchanged | **changes decoded pose** | neutral | **Risky: protocol + prediction** |
| Raise actor cap / snapshot layout | unchanged | **ack/state changes** | neutral | **Risky: protocol + UI** |
| Interest management / delta | unchanged | **changes visibility/acks** | neutral | **Risky: state/reconnect** |
| Tick rate 20/60 | unchanged | **changes dt/replay** | neutral | **Risky: feel/protocol** |
| Server-only movement collider | unchanged | **diverges from client** | neutral | **Risky: reconciliation** |
| Hitscan / lag compensation | **changes authority** | **changes hit model** | neutral | **Very risky: design change** |
| Threads/SAB/Forward+ | unchanged | unchanged | **breaks web constraint** | **Reject unless web target changes** |

**Questions for the research agent.**
1. Which optimizations are provably authority-neutral, prediction-neutral and
   web-compatible? Provide the proof/test, not an assertion.
2. Which require a protocol version, a feature flag, or a client/server lockstep
   release?
3. Which can be map-specific without contaminating other maps?
4. Which change the feel (tick rate, interpolation, animation LOD) and need a
   playtest sign-off?
5. What is the blast radius of each (server-only, client-only, both, protocol)?

**Options.**
- **Do nothing.** Gain: zero; cost: zero; but unsafe changes can slip in.
- **Tune.** Adopt the matrix as a PR/design-review gate and add the missing
  tests. Expected: prevents authority/prediction regressions; cost S; risk low.
- **Architectural.** Encode the matrix in CI (protocol-version and prediction
  test gates). Expected: durable safety; cost M; risk low–medium.

**How to answer.** For each proposal, state authority/prediction/web impact and
the test that proves it. **Acceptance:** no authority or prediction change ships
without the existing reconciliation/authority tests plus a new regression test.

**Risk / safety.** This is the safety question. Default to "risky" if unsure.

**Priority / confidence.** **P0 · high confidence.**

---

### SAF-02 — Rollback plans and feature flags

**Growth scenario / why it matters.** A protocol or tick-rate change that goes
wrong cannot be fixed by a client refresh if the server is already live. The
project needs a rollback story before the change, not after.

**Current evidence.** No feature-flag system, no protocol version byte, no
canary/staged deploy was found. The server is a single process; the web build is
static; `docs/DEPLOY.md` is a planned single-origin Caddy config. Reconnect
grace is 8 s; connect budget 6 s.

**Questions for the research agent.**
1. What is the minimum rollback plan for each risky change (tick rate, protocol,
   actor cap, AOI, map bake)?
2. Do we need a protocol version byte and mixed-version handling? What is the
   compatibility window?
3. Can the change be feature-flagged per server/map/match, and how?
4. What is the canary/staged rollout for a single-origin web game?
5. How fast can we revert (target ≤ 15 min) without breaking connected clients?
6. What data/metrics prove the change is bad, and who triggers the rollback?
7. What is the rollback drill, and how often do we run it?

**Options.**
- **Do nothing.** Gain: zero; risk: unrecoverable bad release.
- **Tune.** Protocol version + server flag + revert runbook. Expected: safe
  releases; cost S–M; risk low.
- **Architectural.** Canary/blue-green + client compatibility. Expected: large;
  cost L; risk medium.

**How to answer.** Write a one-page rollback plan per risky change; run a drill
on a staging server. **Acceptance:** revert ≤ 15 min, no data loss, clients
either stay compatible or get a clear "update" path.

**Risk / safety.** Operational; the plan must be tested, not just written.

**Priority / confidence.** **P1 · high confidence.**

---

## 10. Decision rubric for the manager

Use this to score an answer. Do not accept a score without the raw evidence.

### 10.1 Criteria

| Criterion | Weight | What earns a high score | What earns a low score |
|---|---:|---|---|
| **Evidence quality** | 30 % | Measured on the target runtime (browser/WASM for client, target VPS for server), reproducible command/commit/hardware, n and p50/p95/p99, variance stated; code path cited | Only a microbenchmark; native-only claim for a GPU/WASM question; no sample size; "should be faster" |
| **Measured gain** | 25 % | End-to-end metric improves ≥ 10 % and > 2× run noise; per-map and per-actor-count numbers; p95/p99 not just avg | 1–2 % micro-win; avg-only; gain disappears under p95; one lucky run |
| **Risk** | 15 % | Authority/prediction/web unchanged, or a proven test covers the change | Changes decoded pose, ack semantics, hit model, or requires threads/SAB |
| **Rollback** | 10 % | Feature flag/protocol version, revert ≤ 15 min, tested drill | No way back; protocol lockstep; data migration |
| **Implementation cost** | 10 % | S/M with clear owner; no new system | L with new pipeline/team; maintenance burden |
| **Map-agnostic / strategic fit** | 10 % | Rule works for any 150–250 m map and 3-map rotation; scales to 16/32 | Only helps the current map; hard-coded numbers; one-off |

Suggested score: `0.30*E + 0.25*G + 0.15*(5-R) + 0.10*B + 0.10*(5-C) + 0.10*S`,
each 0–5. Accept if **E ≥ 4, G ≥ 3, (5−R) ≥ 3, B ≥ 3, C ≥ 3**; otherwise
"needs more evidence" or "reject".

### 10.2 What would make us reject an answer

Reject or return for more evidence if any of these is true:

- It relies on the current 150 m map's numbers as a general budget.
- It claims a browser/GPU gain from a headless probe, or a server gain from a
  desktop CPU without a small-VPS check.
- It reports only averages, or a gain smaller than the run-to-run noise.
- It changes the decoded pose, ack semantics, tick `delta`, or hit model without
  a prediction/reconciliation test.
- It requires threads, SharedArrayBuffer, Forward+, or a browser feature that
  breaks the single-threaded Compatibility constraint.
- It has no rollback/feature-flag story for a protocol or tick-rate change.
- It proposes a large architecture (AOI, delta, streaming, custom engine) before
  the cheap measured fixes (bake, dirty flags, caches) are exhausted.
- It cannot state what would falsify the claim.
- It optimizes a metric that is already comfortably inside budget while a P0
  correctness issue (NET-01/NET-02) is open.
- It only helps one map, one actor count, or one device.

### 10.3 Answer format (what "answered" looks like)

Every answer must contain:

1. **Claim** — one sentence, falsifiable.
2. **Evidence** — command, commit, hardware/device, n, p50/p95/p99, variance;
   code path with `file:line`; native vs WASM label.
3. **Effect size** — absolute and relative, on the end-to-end metric, per map and
   per actor count.
4. **Options** — do nothing / tune / architectural, with gain, cost, risk.
5. **Rollback** — flag/version/revert time.
6. **Acceptance test** — reproducible by the team, with thresholds.
7. **What would falsify this** — the test that would prove the claim wrong.
8. **Confidence** — high/medium/low, and why.

Hypotheses must be labelled **hypothesis**. A recommendation without a
measurement is allowed only if it is marked as a hypothesis and paired with the
measurement plan.

---

## 11. Do not optimize (measured fine — do not waste research time)

From the previous audit's "already fine" section, re-checked where the fresh run
touched it. Revisit only if the design changes (actor cap, tick rate, map size).

| Item | Measured | Verdict / revisit if |
|---|---|---|
| Snapshot size at 8 | 182 B (limit 300) | Fine at 8. **Revisit for 16/32 — see NET-02.** |
| Snapshot encode/decode at 8 | 47–49 / 33 µs | Fine at 8; micro-opt only. |
| Input packet | 12 B; 5.1 µs encode+decode | Fine. |
| BulletField pooling | launch 13.1–13.6 µs; 0 churn/shot; 64 slots | Fine; prewarm is the only fix. |
| Projectile spawn / sweep | 13.2–13.7 µs / 3.25–3.4 µs | Fine at 8; revisit at 32 fire rates. |
| 60-shot burst | resolves in 2 frames; +120 peak nodes; 0 after; 0 orphans | Fine. |
| CharacterVisual | 6.1–7.2 µs/actor/frame; 7 remotes ≈ 0.05 ms | Fine at 8; revisit at 16/32. |
| NetworkInterpolator | 11.6 µs for 8 pushes; 2.5 µs/sample | Fine; dict churn is a WASM question, not a native one. |
| HUD string formatting | 4.6 µs/frame | Fine; the problem is unconditional redraw, not the strings. |
| Server baseline | 7.8–9 µs/tick with 0 actors | Fine. |
| 8-bot server tick | 2.8–3.5 ms avg / 5.6–6.7 ms p95 | Fine at 8 (8–20 % budget); revisit at 16/32. |
| 49 draw calls / 1,832 instances / 192k triangles | Within 150 / 250k | Fine at the current map; **not a budget for 250 m** — see REN-01/02. |
| MultiMesh vs merged props | 31 mesh groups / 49 surfaces | Keep MultiMesh; do not merge into one giant mesh. |
| 387 static bodies / 374 prop colliders | No measurable broadphase penalty in movement test | Keep; merging is a node-count exercise, not a CPU win. |
| Signal connects | Guarded with `is_connected` (43 sites) | Fine. |
| Audio | 6 pooled players, synthesized buffers | Fine. |
| `Engine.max_physics_steps_per_frame=4`, `physics_jitter_fix=0` | Background-tab guard | Keep. |
| Deterministic generation | Fixed seed, single height function | Keep; this is what makes baking safe. |

**Do not** spend research time on: micro-optimizing the 8-actor codec, merging
all props, replacing MultiMesh with one mesh, removing prop colliders for CPU,
or adding a complex LOD system before REN-01/02 show it is needed.

---

## 12. Map-agnostic budget template

These are **proposed** targets for a 150–250 m map, to be validated by
OBS-01/02/03. They are not the current map's numbers. Ranges are intentional:
the manager should set one value per map and enforce it in CI.

### 12.1 Per-map budget

| Metric | Target range (150–250 m) | Hard cap | How to measure |
|---|---:|---:|---|
| Playable footprint | 150–250 m | 250 m | map metadata |
| Draw calls | 60–120 | **150** | `arena_stats` / renderer |
| Visible triangles (typical pose) | 100–200k | **250k** | renderer/`arena_stats` |
| Total triangles (authored) | 150–300k | 400k | mesh scan |
| Surfaces / materials | 30–60 | 80 | mesh scan |
| MultiMesh instances | 500–2,500 | 4,000 | mesh scan |
| Static colliders | 200–500 | 800 | physics scan |
| Texture memory | 40–80 MB | **100 MB** | resource/texture report |
| Shadow casters | 100–300 | 400 | scene scan |
| Shadow distance / splits | 45–60 m / 1–2 | 90 m / 2 | scene config |
| Spawn points | ≥ 8, pairwise ≥ 15 m | — | `arena_stats` |
| Map generation (native) | ≤ 50 ms | 100 ms | bake/probe |
| Map generation (WASM) | ≤ 150 ms | 300 ms | browser probe |
| Bake artifact (compressed) | 5–15 MB | 25 MB | export size |
| Map memory delta (native) | 5–15 MB | 25 MB | `Performance` |

### 12.2 Runtime budget

| Metric | 8 actors | 16 actors | 32 actors | How to measure |
|---|---:|---:|---:|---|
| Server tick avg | ≤ 4 ms | ≤ 8 ms | ≤ 16 ms | tick histogram |
| Server tick p95 | ≤ 8 ms | ≤ 12 ms | ≤ 24 ms | tick histogram |
| Server tick p99 | ≤ 12 ms | ≤ 20 ms | ≤ 30 ms | tick histogram |
| Client scripts/frame (60 fps) | ≤ 1 ms | ≤ 2 ms | ≤ 3 ms | browser profile |
| Client frame p95 (low-end, 720p) | ≤ 16.7 ms | ≤ 16.7 ms | ≤ 33 ms | browser profile |
| Snapshot bytes/actor | ≤ 22 B | ≤ 22 B | ≤ 22 B (or interest) | codec probe |
| Snapshot bytes/client | ≤ 300 B | ≤ 512 B | ≤ 1 KB (or ≤ 300 B with AOI) | codec probe |
| Upstream input | ≤ 12 B/actor/tick | same | same | codec probe |
| Cold join (desktop) | ≤ 5 s | ≤ 5 s | ≤ 8 s | browser timing |
| Cold join (4G mobile) | ≤ 15 s | ≤ 15 s | ≤ 20 s | throttled network |
| Warm join (cache hit) | ≤ 3 s | ≤ 3 s | ≤ 5 s | browser timing |
| WASM heap (1 map) | ≤ 150 MB | ≤ 180 MB | ≤ 220 MB | `WebAssembly.Memory` |
| WASM heap (3 maps) | ≤ 250 MB | ≤ 280 MB | ≤ 320 MB | `WebAssembly.Memory` |
| Reconnect | ≤ 8 s | ≤ 8 s | ≤ 8 s | forced drop |
| Join storm (32 in 1 s) | — | no tick > 2× | no tick > 2× | synthetic |
| Match length | 5–10 min | 5–10 min | 5–10 min | product |

**How to use the template:** each map declares its budget in a small resource
(e.g., `MapBudget`) and CI fails when a metric exceeds the cap by > 10 %. The
server records the actor-count row for the current match. If a metric has no
source, OBS-01 is not done.

---

## 13. Dependencies, open decisions, and non-goals

**Dependencies**

- The three new maps are owned by another session; this brief only asks for
  **contracts and budgets**, not map content. Any answer that depends on a
  specific map's layout is out of scope.
- NET-01 and NET-02 are correctness prerequisites for 150–250 m / 16+ actors.
  Fixing them is not an optimization; it is a release gate.
- OBS-01/03 are prerequisites for trusting any other answer.

**Open decisions the manager must make**

1. Target actor cap for the next milestone (8 / 12 / 16 / 32).
2. Target map size and whether 3 maps are resident or loaded per match.
3. Tick rate policy (20 / 30 / 60, and whether snapshot rate is decoupled).
4. Whether interest management/delta is in scope for V1 or deferred.
5. Mobile support level (which devices, what frame rate, what payload).
6. Whether 5-minute FFA remains the match model at 16/32.

**Non-goals**

- Designing or modifying the three maps.
- Changing balance, weapons, TTK or match rules.
- Implementing any recommendation in this brief.
- Replacing the authoritative server model with client authority.
- Threads, SharedArrayBuffer, Forward+, or a non-web renderer.

---

## 14. Appendix — commands and evidence index

```bash
# Native headless perf (quick / full)
tools/godot --headless --path . --script tests/headless/perf_probe.gd -- --quick
tools/godot --headless --path . --script tests/headless/perf_probe.gd

# Per-map draw calls / triangles / colliders (current maps only; reference)
tools/godot --headless --path . --script tests/headless/arena_stats.gd

# Soak: 8 clients + 4 bots, 120 s, simulated latency/jitter
tools/godot --headless --path . --script tests/headless/soak_runner.gd -- \
  --seconds 120 --clients 8 --bots 4 --port 9255 --sim-latency 100 --sim-jitter 20

# Quantization probe used in §0.1 (temporary, outside the repo)
tools/godot --headless --path . --script /srv/opencode/tmp/opencode/pos_probe.gd
```

**Evidence index**

| Topic | File |
|---|---|
| Previous audit (reference map) | `docs/research/PERFORMANCE-AUDIT-2026-10-30.md` |
| Authority, tick, protocol, prediction | `docs/ARCHITECTURE.md` |
| Locked decisions, phase budgets | `docs/ROADMAP.md` |
| Deploy / one-origin proxy | `docs/DEPLOY.md` |
| Server loop / bots / respawn / snapshots | `scripts/game/game_manager.gd` |
| Wire format / quantization / cap | `scripts/networking/net_protocol.gd` |
| Poll / drain / reconnect | `scripts/networking/network_manager.gd` |
| Prediction / reconciliation | `scripts/player/player_controller.gd` |
| Remote interpolation | `scripts/networking/network_interpolator.gd` |
| HUD / net panel | `scripts/ui/hud.gd`, `scripts/game/main.gd` |
| Bullet FX | `scripts/weapons/bullet_field.gd`, `bullet_visual.gd` |
| Server combat / projectiles | `scripts/game/server_combat.gd`, `scripts/weapons/projectile.gd` |
| Character visual / animation | `scripts/player/character_visual.gd` |
| Camera | `scripts/player/camera_rig.gd` |
| Probe / soak / arena stats | `tests/headless/perf_probe.gd`, `soak_runner.gd`, `arena_stats.gd` |

---

*End of brief. Answers should be appended as new files or linked from
[`OPEN-QUESTIONS.md`](OPEN-QUESTIONS.md), not edited into this question list.*
