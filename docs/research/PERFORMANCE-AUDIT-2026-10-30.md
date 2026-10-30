# Performance & Bottleneck Audit — 2026-10-30

**Scope:** Ball of Duty web-first third-person shooter, Godot 4.7.2, Compatibility
(WebGL 2), single-threaded WASM, 8 actors, 30 Hz authority, 150 × 150 m
`arena_quarry`. Read-only audit: no gameplay, balance, protocol or visual code
was changed. The only addition is `tests/headless/perf_probe.gd`.

**Headline:** the known `?join=1` connect-budget symptom is **map generation, not
network or rendering**: the quarry builds in **582 ms on this native Xeon**, and
**~99 % of the main-scene ready time (590 ms) is the arena**. On single-threaded
WASM that is a multi-second main-thread stall. Two deterministic loops account
for **80 % of it** (scatter 271 ms + runtime detail texture 194 ms), and both are
bakeable or replaceable with a spatial hash.

---

## 1. Executive summary — top 5 fixes

| # | Fix | Measured evidence | Expected gain | Effort |
|---|-----|-------------------|---------------|--------|
| 1 | **Bake the quarry** (chunk meshes, heightmap data, placements/MultiMesh transforms, detail texture) into exported resources | Arena generation **581.7 ms**; main-scene ready **590.2 ms**; breakdown: scatter 271.3, texture 193.8, terrain 102.5, multimesh 8.4, colliders 4.3 ms | Generation **20–40×** faster (≈15–30 ms load); removes the 1–2 s WASM first-frame stall and the need for the 3-frame auto-join defer | M (1–2 d) |
| 2 | **Fix `_is_dressing_clear` O(n²)** with a spatial hash (or bake placements) | 200 clearance calls = **33.5 ms → 167 µs per candidate** at 1,832 placements; scatter total **271.3 ms** | Scatter **271 ms → <10 ms** if not baking; also fixes any future 200 m map | S (2–4 h) |
| 3 | **Bake or shrink the 256 px detail texture** | `_detail_texture()` = **193.8 ms** (33 % of generation): 65,536 `set_pixel` × 3 noise octaves | **194 ms → <2 ms** (load a 64–256 px PNG/`.ctex`, or 64 px runtime) | S (1–2 h) |
| 4 | **Trim web payload + enable Brotli/cache** | `index.wasm` 39.5 MB raw / **10.1 MB gzip**; `index.pck` 5.94 MB / 4.31 MB gzip; **~2.6 MB of PCK is unreferenced imported `.scn`** (rig 1.29, adventurer 1.13, weapon 0.17 MB) | PCK **−~44 % raw**, total gzip **−~1.3 MB**; biggest cold-join lever on mobile | S–M (0.5–1 d, verify refs) |
| 5 | **Stop redrawing the HUD every frame / building net-panel strings every frame** | `HUD._process` calls `queue_redraw()` unconditionally; per-frame strings **4.5 µs**; `main._update_net_panel_stats` formats and assigns a `Label.text` every frame while online | 0.3–1 ms/frame on low-end WebGL (estimated; draw skipped headless); zero visual change | S (2–3 h) |

Server CPU is **not** in the top five at the current 8-actor cap: 8 bots cost
**3.5 ms/tick avg / 6.7 ms p95** (10–20 % of the 33 ms budget), dominated by
engine heightfield movement, not scripts. It is a server-sizing item, not a
blocker. Details in §4.

---

## 2. Methodology, context, and how to rerun

### Hardware / runtime context

| | |
|---|---|
| CPU | Intel Xeon Gold 6242 @ 2.80 GHz, **8 vCPU** (VMware VM, shared) |
| RAM | 11 GB |
| OS | Linux x86_64 |
| Engine | Godot **4.7.2.stable.official** `ed1daf0bf`, headless (`DisplayServer=headless`, dummy renderer) |
| Project | `physics_ticks_per_second=30`, `physics_interpolation=true`, Compatibility renderer, `Engine.max_fps=0` in probe |
| Web build | `build/web`: wasm 39,514,754 B, pck 5,939,240 B, js 279,815 B |

**These are native x86_64 numbers, not browser numbers.** GDScript-heavy loops
typically run **1.5–3× slower** in single-threaded WASM; GPU, shader compilation,
canvas draw, and WASM memory growth are **absent** headless. Treat CPU numbers
as a lower bound and GPU/draw as “needs real device” (§6).

### Harness design

`tests/headless/perf_probe.gd` (extends `SceneTree`, no autoloads) measures with
`Time.get_ticks_usec()` and reports **n / avg / p95 / max** (nearest-rank p95)
on machine-readable `PERF_*` lines.

* **Arena totals** are real: `load()` → `instantiate()` → `add_child()` (which
  runs `_ready()` synchronously) → 2 physics frames for collider registration.
* **Arena breakdown** replays the arena’s own build steps one at a time on a
  *detached* instance, then checks the sum against the real total
  (578.5 ms vs 581.7 ms, 0.5 % residual). It calls the underscore-prefixed
  methods directly; the arena code is untouched.
* **Server ticks** call `GameManager._physics_process(1/30)` manually with
  `set_physics_process(false)` so the engine does not double-simulate, and await
  one physics frame between ticks for the physics server to flush. Transport is
  a `FakeNet` stub that counts packets/bytes instead of opening a socket, so
  numbers exclude WebSocket scheduling.
* **Tick breakdown** replicates the manager loop and times `_bot_frame`,
  `ServerCombat.process`, `server_step`, `_snapshot_entry` per actor.
* **Projectiles** use the real `Projectile` scene and the real swept-ray code.
* **Client scripts** are driven manually (`set_process(false)` + explicit
  `_process(1/60)`) on 1 local + 7 remote players, a bound HUD, a `BulletField`,
  and a `NetworkManager` decode path.
* The harness returns to **12 nodes / 0 orphans** at exit, so it is not leaking
  into the numbers.

### Rerun

```bash
cd ballofduty

# full run (~2 min): 300 ticks/config + breakdowns
tools/godot --headless --path . --script tests/headless/perf_probe.gd \
  | tee /tmp/perf.log | grep -E '^PERF'

# fast run (~50 s): 120 ticks/config
tools/godot --headless --path . --script tests/headless/perf_probe.gd -- --quick
```

Primary run: `/tmp/perf.log`; three full runs were taken. Container noise is
visible: 8-bot tick avg **2.92–3.54 ms**, p95 **5.71–6.74 ms**. The report uses
the last full run unless a range is stated.

---

## 3. Measured results

### 3.1 Map generation (the join stall)

| Map | load | instantiate | `_ready()` generation | total | nodes | MultiMesh instances | collider shapes | triangles | draw surfaces |
|---|---|---|---|---|---|---|---|---|---|
| `arena_quarry` | 0.76 ms | 0.16 ms | **581.7 ms** | **582.6 ms** | 831 | 1,832 | 388 (387 bodies) | 192,842 | 49 |
| `arena_nature` | 2.07 ms | 0.41 ms | **27.8 ms** | **30.3 ms** | 349 | 281 | 148 | 32,544 | 50 |

Quarry breakdown (detached replay; real-sequence sum 578.5 ms):

| Step | ms | % of 581.7 |
|---|---:|---:|
| `_scatter_dressing()` | **271.3** | 46.6 % |
| `_build_materials()` incl. `_detail_texture()` | **190.7** | 32.8 % |
| ↳ `_detail_texture()` alone | **193.8** | 33.3 % |
| `_build_terrain()` (mesh + HeightMapShape + nodes) | **102.5** | 17.6 % |
| ↳ `_build_chunk_mesh()` ×9 (visual only) | 67.4 | 11.6 % |
| ↳ heightmap sampling 9×51×51 | 35.1 | 6.0 % |
| `_build_multimeshes()` | 8.4 | 1.4 % |
| `_build_colliders()` | 4.3 | 0.7 % |
| boundary / cave / ridge / hero props / atmosphere | ~1.3 | 0.2 % |
| `_is_dressing_clear()` ×200 (probe-only) | 33.5 → **167 µs/call** | — |

Nature breakdown: scatter 18.4 ms, MultiMesh 6.5 ms, colliders 1.3 ms, border
0.23 ms, hero props 0.14 ms.

**Main scene boot** (`scenes/main.tscn`, the real client path):

```
load 1.0 ms · instantiate 1.1 ms · add_child(_ready) 590.2 ms
first process frame 5.0 ms · second 1.3 ms · +937 nodes · +9.3 MB static
```

590.2 ms ready ≈ 581.7 ms quarry generation → **~99 % of client startup is the
map**, before any rendering or networking. This is exactly the frame that used
to burn the 6 s connect budget.

### 3.2 Server tick (authority CPU)

300 ticks per config, 8-bot world, `FakeNet` (no socket):

| Bots | avg | p95 | max | % of 33.3 ms budget (p95) | rays/tick (analytic) |
|---:|---:|---:|---:|---:|---:|
| 0 | 9.0 µs | 15 µs | 25 µs | 0.0 % | 0 |
| 5 | 1.81 ms | 3.54 ms | 4.50 ms | 10.6 % | 10 (5×LOS + 5×feeler) |
| 8 | **3.54 ms** | **6.74 ms** | 8.08 ms | **20.2 %** | 16 (8×LOS + 8×feeler) |

8-bot breakdown (per tick, summed over 8 actors):

| Sub-step | µs/tick | % of tick | per actor |
|---|---:|---:|---:|
| `PlayerController.server_step` (locomotion + `move_and_slide`) | **2,755.7** | 77.8 % | 344 µs |
| `GameManager._bot_frame` (target, LOS, feeler, aim) | 464.7 | 13.1 % | 58 µs |
| `ServerCombat.process` (timers, fire, projectile spawn) | 112.8 | 3.2 % | 14 µs |
| `_snapshot_entry` (dictionary + `get_node_or_null`) | 84.6 | 2.4 % | 10.6 µs |
| remainder (combat timers, displacement guard, events) | ~123 | 3.5 % | — |

Ray primitives: LOS **10.8 µs**, forward feeler **5.7 µs**. 16 bot rays/tick ≈
**173 µs/tick** (5 %). `server_start` cost: 0.53 ms / 6.58 ms / **13.5 ms** for
0 / 5 / 8 bots (spawns full player scenes).

**Why movement is expensive:** a grounded single actor costs **117 µs/step**
(p95 153 µs) vs **14 µs** airborne. Eight grounded actors cost 143 µs (clustered)
to 194 µs (spread) per actor. Removing the 374 prop colliders did **not** reduce
the step (the test was confounded by contact early-out), so this is
**HeightMapShape3D ground contact**, not broadphase body count. Collider merging
is not a CPU fix.

### 3.3 Snapshot codec / payload

| Item | Bytes | avg | p95 | max |
|---|---:|---:|---:|---:|
| `encode_snapshot` 8 actors | **182** | 47.5 µs | 56 µs | 81 µs |
| `decode_snapshot` 8 actors | 182 | 32.7 µs | 40 µs | 779 µs |
| input encode+decode | 12 | 5.2 µs | 6 µs | 49 µs |
| `NetworkManager._route_client` (decode + emit) | 182 | 32.8 µs | 32 µs | 760 µs |

182 B is comfortably under the 300 B budget. At 30 Hz, encode is **1.4 ms/s**
and client decode is **~1 ms/s**. Not a bottleneck.

### 3.4 Projectiles and node churn

| Item | Result |
|---|---|
| Spawn (instantiate + add + setup) | **13.2 µs** avg, p95 16 µs |
| 60-shot burst | resolves in **2 physics frames / 1.1 ms**; peak **+120 nodes**, **0 after**; **0 orphans** |
| Swept ray per projectile per tick | **3.4 µs** |
| `queue_free()` per resolve | one node per shot; no pool, but no measurable churn at 10 Hz |

### 3.5 Heaviest client scripts (headless CPU)

| Script | avg | p95 | Notes |
|---|---:|---:|---|
| `CharacterVisual._process` (local) | 6.7 µs | 17 µs | blocks 8.4 / 5.9 / 5.9 µs; early animation frames 8–18 µs |
| `CharacterVisual._process` (remote) | 7.2 µs | 19 µs | 7 remotes ≈ **0.05 ms/frame** |
| `PlayerController._process` local | 2.7 µs | 3 µs | camera + visual offset |
| `PlayerController._process` remote | 8.2 µs | 9 µs | includes `_apply_remote` + interp sample |
| `NetworkInterpolator.push_sample` ×8 | 11.6 µs | 12 µs | per snapshot |
| `NetworkInterpolator.sample` ×1 | 2.6 µs | 5 µs | per remote per frame |
| `PlayerController.accept_server_state` | 3.8 µs | 4 µs | per snapshot |
| `HUD._process` (queue_redraw) | 0.43 µs | 1 µs | **draw not executed headless** |
| HUD per-frame string work | 4.5 µs | 5 µs | `%`, `str()`, `to_upper()` |
| HUD debug text refresh | 2.4 µs | 3 µs | 4×/s |
| `BulletField._ensure_pool()` | **2,031 µs** | — | +216 nodes, +1.1 MB, once on first shot |
| `BulletField._launch` | 13.1 µs | 18 µs | scans 64 slots |
| 64 `BulletVisual._process` | **311.5 µs/frame** | 321 µs | **4.87 µs per bullet per frame** (one ray each) |

### 3.6 Memory / allocation proxies (headless)

| Point | Static | Nodes | Orphans | Objects | Resources |
|---|---:|---:|---:|---:|---:|
| baseline | 49.9 MB | 12 | 0 | — | — |
| after quarry | 57.0 MB (+5.7) | 843 | 0 | 3,114 | 246 |
| after quarry free | 52.2 MB | 12 | 0 | 1,742 | 189 |
| after main boot | — (+9.3) | 937 | 0 | — | — |
| final / peak | **58.8 / 66.9 MB** | 12 | 0 | 1,791 | 189 |

No orphan growth and no node leak in any section. The 5.7 MB quarry delta is
meshes, MultiMesh buffers, 374 collision shapes, and 831 nodes.

### 3.7 Web payload (static)

| File | Raw | gzip -6 |
|---|---:|---:|
| `index.wasm` | 39.51 MB | **10.14 MB** |
| `index.pck` | 5.94 MB | **4.31 MB** |
| `index.js` | 0.28 MB | 0.07 MB |
| **total** | **45.73 MB** | **14.52 MB** |

PCK buckets (enumerated by loading the pack): imported resources **2.73 MB**
(rig_medium 1.29, adventurer 1.13, weapon 0.17, kenney 0.11, blocky 0.02),
pre-built `.scn` **1.57 MB**, animation `.res` **1.12 MB**, scripts 235 KB,
everything else ~0.3 MB. The built adventurer/weapon `.scn` bundle their
ArrayMesh/Skin; the matching `.godot/imported/*.scn` (2.59 MB) are not referenced
at runtime by `CharacterVisual` (which preloads the `.scn` and `.res`). Excluding
the source `.glb` files via `exclude_filter` should remove both the source and
its import.

---

## 4. Prioritized findings

Effort: S ≤ 4 h, M ≤ 2 d, L > 2 d. “Gain” is measured where stated, estimated
otherwise.

| ID | Area | Evidence | Suspected cost | Proposed fix | Expected gain | Effort | Risk | Pri |
|---|---|---|---|---|---|---|---|---|
| **MAP-01** | map/startup | scatter **271.3 ms**; `_is_dressing_clear` **167 µs/call** at 1,832 placements; `quarry_arena.gd:1172` loops `_hero_anchors` + every placement per candidate | O(candidates × placements) linear scans, ~1,600 candidates × ~2,100 distance checks | Spatial hash grid (4 m cells) for placements/anchors/spawns; or bake placement lists | **271 → <10 ms** | S | Low | **P0** |
| **MAP-02** | map/startup | `_detail_texture()` **193.8 ms**; `quarry_arena.gd:382-423`; 65,536 `set_pixel` × 3 octaves | CPU image synthesis + `generate_mipmaps` every load | Bake PNG/`.ctex`; fallback 64 px (≈12 ms) or 2 octaves | **194 → <2 ms** | S | Low | **P0** |
| **MAP-03** | map/startup | `_build_terrain` **102.5 ms**; chunk meshes 67.4, heightmap 35.1; `quarry_arena.gd:432-540` | 9 non-indexed `ArrayMesh` builds + 23,409 `height_at` evaluations | Bake per-chunk `ArrayMesh` + `HeightMapShape3D.map_data` resources | **102 → <10 ms** | M | Low | **P0** |
| **MAP-04** | startup/join | full generation **581.7 ms**; main ready **590.2 ms**; 99 % map | synchronous `_ready` before first frame | Bake MAP-01/02/03 into `.res`; load in `_ready` | **20–40×**; removes 1–2 s WASM stall | M | Low | **P0** |
| **MAP-05** | startup fallback | if baking slips: 582 ms single stall | one long frame | Build in a coroutine, yield every ~4 ms behind the loading screen; keep socket poll alive | no frame >16 ms; total unchanged | M | Low | P1 |
| **WEB-01** | web/payload | wasm **39.5 MB raw / 10.1 MB gzip**; total **45.7 / 14.5 MB** | cold download | Brotli-11 + `Cache-Control: immutable`; confirm release template; consider `wasm` streaming | ~10–14 MB on first visit | S | Low | **P1** |
| **WEB-02** | web/payload | PCK 5.94 MB; **2.59 MB imported scenes unreferenced** (rig 1.29, adventurer 1.13, weapon 0.17) | `export_filter=all_resources` exports every import | Exclude `assets/kaykit/animations/rig_medium_*.glb`, `assets/kaykit/adventurers/*.glb`, `assets/weapons/class/source/*`, `assets/kaykit/tools/*`; verify with a boot test | PCK **−~44 % raw**; ~−1.3 MB gzip | M | Medium (verify no runtime `load(.glb)`) | **P1** |
| **MAP-06** | GPU/draw | Sun `shadow_enabled`, PSSM 2, **90 m**; 1,832 instances, most tree/rock/cliff/stone casters (`quarry_arena.gd:1231`) | second scene pass; shadow map fill | Disable shadows on `ridge_rock`, `cliff_wall`, `stone_box`, distant pines; reduce max distance to 45–60 m | est. **20–40 %** GPU frame | S | Low–Med (visual) | **P1** |
| **MAP-07** | GPU/draw | terrain material `uv1_triplanar`, `CULL_DISABLED`, anisotropic (`quarry_arena.gd:344-367`); 192,842 tris | 3 texture samples/px, backfaces, aniso | Use existing UVs (drop triplanar), `CULL_BACK`, `LINEAR_WITH_MIPMAPS` | est. **20–50 %** terrain fragment cost | S | Low–Med (cliff stretching) | **P1** |
| **CLIENT-01** | client/UI | `HUD._process` **queue_redraw every frame** (`hud.gd:109-119`); `_draw` has ~15 `draw_string` + `%`/`to_upper`; strings **4.5 µs/frame** | CanvasItem rebuild + text shaping every frame even when idle | Dirty flag (only on ammo/hp/heat/kill/state change) or throttle to 30 Hz; cache formatted strings | est. **0.3–1 ms/frame** on low-end WebGL | S | Low | **P1** |
| **SERVER-01** | server CPU | 8 bots **3.54 ms avg / 6.74 ms p95**; movement **2.76 ms (78 %)**; grounded step **117 µs** vs airborne 14 µs | HeightMapShape3D contact resolution in `move_and_slide` | Size the VPS for ~4–6 ms/tick; if it grows, consider 20 Hz authority (protocol/feel change) or a cheaper ground collider on the server | avoids tick overrun on small VPS | M | Medium | P1 |
| **SERVER-02** | server CPU | bot AI **464.7 µs/tick (13 %)**; LOS 10.8 + feeler 5.7 µs × 8; `game_manager.gd:642,683` | 16 raycasts/tick, every tick | Cache LOS for 2–3 ticks (stagger bots); keep feeler | **−150–250 µs/tick** | S | Medium (bot feel) | P2 |
| **SERVER-03** | server CPU | `_snapshot_entry` **84.6 µs/tick**; `_health()` `get_node_or_null` per actor per tick (`game_manager.gd:405-409`) | tree lookup + dictionary per actor | Cache `HealthComponent` on the roster entry at spawn | **−30–50 µs/tick** | S | Low | P2 |
| **SERVER-04** | server burst | `_choose_respawn` (`game_manager.gd:486`) does up to 8 spawns × 8 players raycasts | 64 rays per death | Limit to nearest 3 spawns / reuse last clear spawn | removes ~0.5–1 ms respawn spike | S | Low | P2 |
| **NET-01** | network codec | encode **47.5 µs**, decode **32.7 µs**; `net_protocol.gd:170-236` | ~50 small `PackedByteArray` allocations per snapshot (`_i16`/`_u32`) | Preallocate `pkt.resize(6+n*22)` and write at offsets | **2–4×** codec (saves ~35 µs/tick) | S | Low | P2 |
| **CLIENT-02** | client/UI | `main._process` every frame → `_update_net_panel_stats` formats `Label.text` every frame while online (`main.gd:527-547`); banner same | string + label layout every frame | Throttle panel/banner to 4–10 Hz; set text only on change | est. **20–80 µs/frame** | S | Low | P2 |
| **CLIENT-03** | client/startup | BulletField pool **2.03 ms**, +216 nodes, +1.1 MB on first shot (`bullet_field.gd:104`) | pool + material creation mid-match | Build the pool hidden during map load / after join; or halve `POOL_SIZE` | removes first-shot hitch | S | Low | P2 |
| **CLIENT-04** | client/CPU | `BulletVisual._process` **4.87 µs/bullet/frame**, one ray each (`bullet_visual.gd:93-102`); 64 = **311 µs** | per-bullet physics query at render rate | Raycast every 2nd frame or only within 30 m; server events already authoritative | **−50 %** bullet CPU | S | Low | P2 |
| **CLIENT-05** | client/join | `_spawn_remote` instantiates the full `player.tscn` per remote (`game_manager.gd:983`); 7 remotes at join | character + 3 AnimationPlayers + weapon + materials per remote | Prewarm one hidden instance; pool/reuse on roster churn | est. **50–200 ms** join hitch removed | M | Medium | P2 |
| **CLIENT-06** | client/CPU | `CameraRig.update_aim` calls `SpringArm3D.get_hit_length()` every frame (`camera_rig.gd:49-73`) | one shape cast/frame against layer 1 | Throttle to every 2nd frame; or use a cheap ray | small, device-measured | S | Low | P2 |
| **CLIENT-07** | client/CPU | `_apply_remote` `get_node_or_null("NetworkInterpolator")` per remote per frame (`player_controller.gd:456-462`); sample returns a new Dictionary (`network_interpolator.gd:76-125`) | 7 lookups + 7 dicts/frame | Cache interpolator on `make_remote`; return a reused struct/array | est. 20–40 µs/frame | S | Low | P2 |
| **MAP-08** | server/startup | `server_start` 8 bots **13.5 ms**; server actors instantiate full character/weapon/anim stack then disable Visual (`player_controller.gd:124-128`) | wasted nodes/materials on authority | Visual-less server actor scene | less server memory, faster start | M | Low | P2 |
| **MAP-09** | map/materials | `_restyle_mesh` creates a `StandardMaterial3D` per surface and **mutates the shared GLB mesh resource** (`quarry_arena.gd:1290`) | ~50 materials; cross-arena shared state | Clone the mesh before restyling, or share palette materials | correctness more than perf | S | Low | P2 |

---

## 5. Already fine — do not regress

These were suspected and measured cheap. Leave them alone unless the design
changes:

* **Snapshot size 182 B at 8 actors** (limit 300 B) and **encode 47.5 µs /
  decode 32.7 µs**. The byte-by-byte codec is fine at this scale; NET-01 is a
  micro-opt only.
* **Input packet 12 B**, encode+decode **5.2 µs**.
* **BulletField pooling**: `_launch` **13.1 µs**, **zero node churn per shot**;
  the 64-slot cap is correct.
* **Projectile spawn 13.2 µs**, swept step **3.4 µs**, 60-shot burst returns to
  **0 extra nodes / 0 orphans**.
* **CharacterVisual 6–18 µs per actor per frame**; 8 actors ≈ 0.05–0.12 ms.
* **NetworkInterpolator**: 11.6 µs for 8 pushes, 2.6 µs per sample.
* **HUD string formatting 4.5 µs/frame** (the problem is the unconditional
  redraw, not the strings).
* **Server baseline 9 µs/tick with 0 actors**; 8-bot tick is 10–20 % of budget
  on this CPU.
* **49 draw calls / 1,832 MultiMesh instances / 192,842 triangles** — MultiMesh
  is the right choice; do not merge props into one giant mesh (loses per-instance
  culling and increases vertex memory).
* **387 static bodies / 374 prop colliders**: no measurable broadphase penalty
  in the movement test. Keep them for accurate per-prop hits; merging is a node
  count exercise, not a CPU win.
* **Signal connects** are guarded with `is_connected` (43 sites); no per-frame
  connect/disconnect churn.
* **Audio**: 6 pooled `AudioStreamPlayer`s, synthesized buffers, no per-shot node
  creation.
* **`Engine.max_physics_steps_per_frame = 4`, `physics_jitter_fix = 0`** — keep
  the background-tab guard.
* **Deterministic generation** (fixed seed, height function is the single source
  of truth) — this is what makes MAP-04 safe.

---

## 6. Recommendations specific to the 150 m quarry

### Startup bake (highest leverage)

1. **Bake per-chunk terrain**: for each of the 9 chunks, store the `ArrayMesh`
   and the `PackedFloat32Array` heightmap in a `.res` (or one packed resource).
   Load and assign in `_build_terrain`. Removes 102 ms and guarantees server and
   client agree bit-for-bit.
2. **Bake the detail texture** as a 256 px PNG/`.ctex` (or 64 px if size matters).
   Removes 194 ms and the `generate_mipmaps` cost.
3. **Bake placements**: dump `_placements` (key → `Array[Transform3D]`) after the
   deterministic scatter, then build MultiMeshes from the baked arrays. Removes
   the 271 ms scatter entirely. Keep the generator in the repo for map edits and
   regenerate offline.
4. Expected result: **generation 582 ms → ~15–30 ms**, mostly resource load.
   On WASM (1.5–3×) that is **~50–90 ms** instead of 1–2 s. The 3-frame
   auto-join defer can then be reduced or removed.

If baking must wait, do MAP-01 + MAP-02 first (465 ms of the 582 ms) and make the
remaining build incremental (MAP-05) so no single frame exceeds ~16 ms.

### LOD / occlusion / shadows

* At 9 chunks / 49 draw calls, **do not add a complex LOD system**. Add simple
  per-chunk `visibility_range` (e.g. 90 m) or toggle chunk visibility when the
  camera is deep in the cave; that is enough.
* **Shadow casters are the GPU risk**, not draw calls: 1,832 instances, PSSM 2
  splits, 90 m max distance. Turn shadows off for `ridge_rock`, `cliff_wall`,
  `stone_box` and the far ridge pines; keep hero trees/rocks. Test 45–60 m
  shadow distance on a low-end laptop.
* Keep the **single warm/cool 3-light rig** (Sun + Fill + 5 shadowless cave
  omnis). Do not add shadowed point lights in the cave.

### Colliders

* Keep one `StaticBody3D` per prop for now; the CPU test did **not** show a
  broadphase win from removing 374 bodies. If node count becomes a problem,
  group shapes under a few bodies, but do not expect a tick improvement.
* The heightfield is the real movement cost. If server CPU ever becomes tight,
  the lever is tick rate or a server-only simplified ground collider, not prop
  merging.

### MultiMesh vs merged meshes

* Keep MultiMesh. It gives 1,832 instances in 31 mesh groups and 49 surfaces.
  Merging would increase vertex memory and lose per-instance culling; it would
  not reduce the shadow pass meaningfully.
* Keep per-chunk terrain meshes (9) rather than one 150 m mesh: chunked culling
  and future streaming are worth more than 8 draw calls.

### Heightmap resolution

* Keep **1 m collision** (`CHUNK_SAMPLES=51`) — this is what makes movement and
  bot pathing feel right. Do not reduce it to save generation time; bake it
  instead.
* The **2 m visual step** (`VISUAL_SAMPLES=26`) is already a deliberate low-poly
  look. If GPU vertex cost matters, bake an indexed mesh with flat-normal splits
  instead of the current non-indexed 578k-vertex buffer; do not coarsen further
  without an art review.

### Materials / GPU flags to A/B on device

* Terrain: drop `uv1_triplanar` (UVs are already generated), switch
  `CULL_DISABLED → CULL_BACK`, and try `LINEAR_WITH_MIPMAPS` instead of
  anisotropic. These are one-line material changes but visible on cliffs, so
  A/B with screenshots.
* Fog (`0.0015`) and ProceduralSky are cheap; keep them.

---

## 7. Open questions that need real-device measurement

1. **HUD draw cost**: headless never emits the `draw` signal (`draw_signal_count=0`).
   Measure `_draw` + text shaping on a low-end laptop (Intel UHD) in Chrome and
   Firefox with the HUD visible vs hidden. This decides whether CLIENT-01 is
   P1 or P2.
2. **GPU frame**: 49 draw calls + shadow pass + triplanar terrain. Capture
   `Performance`/WebGL timer queries or use Chrome tracing on the quarry at
   1280×720. Test shadow distance 90 → 45 m and triplanar on/off.
3. **First-draw shader compilation**: the 590 ms ready time is script/scene; the
   first *rendered* frame may add shader compile + texture upload. Measure the
   time from `first_frame` to a stable 60 FPS in the browser.
4. **WASM memory growth**: headless static memory is 58.8 MB. Measure
   `performance.memory` / `WebAssembly.Memory.buffer.byteLength` in Chrome after
   loading the quarry and after 60 s of play; look for growth from the 2.03 ms
   BulletField pool and per-remote player scenes.
5. **Firefox / Safari**: WebGL2 extension differences (anisotropic filtering,
   PSSM shadows), audio worklet startup, and `?join=1` timing.
6. **Mobile**: touch controls aside, measure thermal throttling and whether
   39.5 MB wasm + 5.9 MB pck is acceptable on 4G. This is the main argument for
   WEB-02.
7. **Real network drain**: the probe measures decode/handler, not
   `WebSocketMultiplayerPeer.poll()` under jitter. Use `soak_runner` with
   `--sim-latency/--sim-jitter` and 8 clients if join-time CPU is suspected.
8. **Server on a small VPS**: 3.5 ms/tick here; measure on a 1–2 vCPU cloud
   instance with 8 actors to decide whether SERVER-01 needs action.

---

## 8. Appendix — raw probe output (last full run)

```
PERF_CONTEXT engine=4.7.2-stable renderer=gl_compatibility display=headless
  cpu=Intel Xeon Gold 6242 @ 2.80GHz cores=8 physics_hz=30 max_fps=0
PERF_ARENA map=quarry load_us=763 instantiate_us=160 generate_us=581715
  nodes=831 multimesh_instances=1832 colliders=388 triangles=192842 surfaces=49
PERF_ARENA map=nature load_us=2071 instantiate_us=411 generate_us=27849
  nodes=349 multimesh_instances=281 colliders=148 triangles=32544 surfaces=50
PERF_MAIN ready_us=590245 first_frame_us=5026 second_frame_us=1313
PERF_SERVER bots=8 avg_us=3540.6 p95_us=6744 max_us=8077
PERF_TICK_BREAKDOWN bots=8 bot_ai_per_tick_us=464.7 combat_per_tick_us=112.8
  move_per_tick_us=2755.7 snapshot_per_tick_us=84.6 los_per_ray_us=10.8
  feeler_per_ray_us=5.7
PERF_CODEC snapshot_8 bytes=182 encode_avg_us=47.5 encode_p95_us=56
  decode_avg_us=32.7 decode_p95_us=40
PERF_PROJECTILE burst=60 spawn_avg_us=13.2 resolve_frames=2 node_delta_peak=120
  node_delta_after=0 orphan_after=0
PERF_CHARVISUAL local_avg_us=6.7 remote_avg_us=7.2 seven_remotes_ms=0.05
PERF_BULLETFIELD pool_build_us=2031 launch_avg_us=13.1
  sixtyfour_avg_us=311.5 per_bullet_us=4.87
PERF_STATIC os_static_mb=58.8 os_static_peak_mb=66.9
```

Full `PERF_*` log: rerun the command in §2; the harness prints the same schema.
