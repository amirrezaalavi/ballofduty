# Review: Optimization Answers (`docs/research/optimization_answers.md`)

> **Note:** this review references the original research answer file, which was
> removed in the 2026-10-30 restructure. The decisions live here.


**Reviewer:** implementation session
**Reviewed against:** `37775d6` plus the current worktree (2026-10-30)
**Status:** not accepted as-is. The report contains real findings, useful
directions and several claims that are measured, projected, or simply not in
this codebase. Nothing from the report has been applied except one verified
latent protocol bug (see §4).

The report is useful as a **hypothesis list**. It is not yet a measured
production blueprint. The main problem is not the direction of most suggestions;
it is that many effect sizes and several code paths are presented as verified
when they are extrapolations or do not exist.

---

## 1. Verdict in one page

| Area | Verdict |
|---|---|
| **NET-02 count/loop bug** | **Real.** Verified. Fixed defensively (truncate to the cap); the proposed 16-byte layout is **not** accepted as written. |
| **Map generation / bake (MEM-04)** | **Real bottleneck, right direction.** Effect size (18–24 ms, 23–30×) is optimistic and map-specific; bake after the three maps land. |
| **HUD dirty flag (CLI-04)** | **Real unconditional redraw.** The fix is plausible; the 0.4–0.8 ms figure is unmeasured and the dirty flag must keep transient timers redrawing. |
| **Bullet pool prewarm (CLI-05)** | **Real first-shot pool build.** Prewarming is safe; the 2.25 ms figure is unmeasured. |
| **Bot AI `_entry_by_id` / LOS (SRV-02)** | **Real O(n) scan and per-tick rays.** The 6.8→1.9 ms figure is a projection; 10 Hz LOS needs a bot-accuracy test. |
| **Respawn rays (SRV-03)** | **Real up-to-64-rays-per-death path.** The 1.2–2.5 ms spike is unmeasured. |
| **Snapshot/health allocations (SRV-05)** | **Real `get_node_or_null` per actor per tick.** The 95→32 µs figure is unmeasured. |
| **Server actor stripping (SRV-06)** | **Real that `make_server` only disables the visual.** Memory/instantiation figures are unmeasured. |
| **Prediction replay cap (CLI-01)** | **Real uncapped replay (up to 64).** A hard 8-frame cap is risky without measurement. |
| **Rendering (REN-01/02/03/06)** | **Directionally plausible, per-map.** MultiMesh AABB culling and chunking need a Godot 4.7.2 check and per-map measurement; several effect sizes are unsourced. |
| **Camera per-frame shape cast (CLI-06)** | **False for this code.** `CameraRig.update_aim` only reads `SpringArm3D.get_hit_length()`; there is no script-level shape cast. |
| **Streaming / post-match (REN-05)** | **Not in this build.** No post-match intermission or scoreboard exists; the suggested `get_tree().unload_unused_resources()` is not the right API. |
| **Drain cap (NET-05)** | **Wrong bottleneck math.** 64 packets/frame × 30 Hz = 1,920/s, above the 960/s from 32 clients at 30 Hz. No evidence for the claimed ingress bottleneck. |
| **Match changes (MAT-02)** | **Reject.** It changes the locked 3 s respawn / 5 min match requirements without evidence. |
| **Rollback/deploy (SAF-02)** | **Fabricated for this repo.** `docs/ci/DEPLOY.md` is a planned CP5 target; there is no Docker/blue-green/health endpoint/rollback script or protocol-version handshake. |
| **Observability (OBS-01/02/03)** | **Useful direction.** The exact 1.8×/1.4×/2.8× multipliers are unsourced; use them only after browser calibration. |

---

## 2. Verified facts in the shipping code

These are the facts the review is based on.

| Fact | Evidence |
|---|---|
| 8-actor cap, 22 B row, 182 B packet | `scripts/networking/net_protocol.gd:17,173-198,201-206` |
| Count/loop mismatch for >8 entries | `encode_snapshot` wrote `count = min(entries.size(), 8)` but looped every entry; a 16-entry array produced 358 B and `decode_snapshot` rejected it (`6 + 8×22 ≠ 358`). **Fixed** by truncating the loop to `count`. |
| Positions now 1 cm over ±327.68 m | `net_protocol.gd:21-24,326-330` |
| Terminal fall speed is 30 m/s | `scripts/components/player_stats.gd:22` |
| Actual class projectile speeds | 36 / 40 / 57 / 64 / 77 m/s (`resources/weapons/class_*.tres`), not 81 m/s |
| HUD redraws every frame | `scripts/ui/hud.gd:109-119` |
| Bullet pool is built on first shot | `scripts/weapons/bullet_field.gd:1-11,93-107` |
| Camera has no script-level shape cast | `scripts/player/camera_rig.gd:49-61` only reads `SpringArm3D.get_hit_length()` |
| Respawn can fire up to 8 spawns × roster rays | `scripts/game/game_manager.gd:486-515` |
| `_entry_by_id` is a linear roster scan | `game_manager.gd:692-697` |
| `_health` does `get_node_or_null` during snapshot | `game_manager.gd:405-419` |
| `make_server` only disables the visual subtree | `scripts/player/player_controller.gd:113-129` |
| Prediction history is capped at 64, replay is uncapped | `player_controller.gd:11,358-368,394-408` |
| Map generation 581.7 ms, scatter 271.3 ms, detail texture 193.8 ms | `docs/research/PERFORMANCE-AUDIT-2026-10-30.md` |
| Quarry: 49 draw calls, 192,842 triangles, 1,832 instances | same audit |
| Shadow distance 90 m, PSSM 2 | `scenes/maps/arena_quarry.tscn:42-44` |
| Terrain triplanar + `CULL_DISABLED` | `scripts/game/quarry_arena.gd:352-358` |
| Export includes all resources | `export_presets.cfg:9-11` |
| `MAX_DRAIN_PER_FRAME = 64` | `scripts/networking/network_manager.gd:34` |
| 30 Hz physics, Compatibility renderer | `project.godot:113,119-120` |

---

## 3. What is right and worth doing (with conditions)

### 3.1 Client-side, low risk

- **HUD dirty flag.** The redraw is genuinely unconditional. The correct fix is
  not only “redraw on health/ammo change”: `_hit_time`, `_kill_time`,
  `_damage_flash`, `_crosshair_kick` and the debug timer animate over time, so
  they must keep the HUD dirty while non-zero. Acceptance: standing still with
  no transients should drop canvas submission to near zero; taking damage,
  firing, hitmarkers and the scoreboard must still update immediately.
- **Bullet pool prewarm.** `BulletField` is created on first use and `_ready`
  builds 64 bullet nodes + 24 impact nodes. Prewarm during the loading screen
  (before the first shot) is safe and cosmetic. Acceptance: `pool_builds == 1`
  before the first shot; first shot allocates no nodes.
- **Interpolator allocations.** `NetworkInterpolator.sample()` returns a new
  Dictionary per remote per frame. Reusing a struct or typed arrays is a
  reasonable, cosmetic-side change. Measure before claiming a join-hitch win.

### 3.2 Server-side, low risk

- **`_entry_by_id` map.** Replace the linear roster scan with an id-indexed
  dictionary. This is a pure lookup change; it does not alter authority.
- **Health reference cache.** Store the `HealthComponent` on the roster entry
  instead of `get_node_or_null` every snapshot. Keep the snapshot row unchanged.
- **Single snapshot buffer.** Encode into one pre-sized `PackedByteArray`
  instead of appending many small arrays. Keep the 22 B row and byte-for-byte
  protocol tests.
- **Respawn selection.** The current path can raycast every spawn × every
  nearby actor. A distance pass first, then raycasts only for the top two
  candidates, is a safe server-only change. Acceptance: 10 simultaneous deaths
  do not exceed 1.2× the running tick average, and no spawn is within 15 m of a
  live enemy with line of sight.
- **Bot LOS staggering.** Real per-tick rays. Staggering to 10 Hz is plausible,
  but bot accuracy/TTK must stay within a stated tolerance (e.g. ±5 % kills over
  a 60 s run) before accepting it.

### 3.3 Map/rendering, after the three maps land

- **Bake generation** (mesh, placements/MultiMesh transforms, collider data,
  detail texture). This is the highest-value startup fix, but it must be a
  **map-agnostic bake contract**, not a quarry-specific patch. The three maps
  are the right first users.
- **Scatter spatial hash.** The O(n²) clearance check is real; a 4 m grid is a
  safe fallback if baking slips.
- **MultiMesh chunking.** The AABB-culling argument is plausible, but chunking
  increases draw calls. Measure per map from four camera poses before/after.
- **Shadow distance / far plane / triplanar.** These are real settings, but the
  3–5 ms and 35 % claims are unsourced. Treat them as visual/perf trade-offs to
  A/B on the reference web build, not free wins.

---

## 4. NET-02: the bug is real, the proposed layout is not acceptable

### 4.1 What is real

`encode_snapshot` capped the count byte at `MAX_PLAYERS` but looped every entry.
With 16 entries it wrote 358 B and a count of 8; the decoder requires
`6 + count × 22`, so it rejected the packet. This is a latent bug today because
the roster is capped at 8, but it becomes live the moment the cap is raised.

**Applied guard:** the encoder now truncates the loop to `count` and the packet
stays at the 8-actor size. A test covers 9 entries. This does **not** raise the
cap; it only prevents a malformed packet.

### 4.2 Why the 16-byte row is not accepted as written

The report proposes:

```
id u8 | pos 3×i16 | yaw u8 | vel 3×i8 (×10) | hp u8 | flags u8 | ack u16
```

Problems:

1. **Velocity range is too small.** `i8 × 10` covers ±12.7 m/s. The player's
   terminal fall speed is **30 m/s** (`player_stats.gd:22`), and knockback is a
   separate impulse. Snapshot velocity is fed back into reconciliation
   (`player_controller.gd:392`), so a falling player would receive a clamped
   vertical velocity and predict the wrong landing. This is a correctness bug,
   not a bandwidth trade-off.
2. **Yaw at u8 is 1.4° per step.** That may be acceptable for remote body
   facing, but the report claims “100 % fidelity”; it is not. Measure remote
   turning at 5–10 m before accepting.
3. **`ack u16` wraps every 36.4 minutes at 30 Hz.** A 5-minute match fits, but
   reconnect/session lifetimes and wrap-aware comparison need to be specified.
   The current field is u32.
4. **32 actors at 518 B is not “within the ≤300 B budget.”** It is within a
   1,460 B TCP segment, but the product requirement was a ≤300 B snapshot. If
   32 actors is a target, that budget must be explicitly renegotiated or the
   layout must use delta/interest management.
5. **“Fits in one TCP segment” is not the right argument for WebSocket.** TCP is
   a stream; packet size does not map to IP fragmentation the way the report
   implies. 518 B is still small, but the reasoning is wrong.
6. **There is no protocol version byte or magic `0xBD` in this code.** The
   report's rollback plan (“bump magic from 0xBD to 0xBE, `PROTOCOL_VERSION=2`”)
   does not exist. Any layout change needs a real version/handshake first.

### 4.3 Corrected options

**Option 0 — keep 8 actors.** Keep the 22 B row; the truncation guard is enough.
No protocol change. This is the correct choice until 16 actors is measured.

**Option 1 — 16 actors, 18 B row, 294 B packet.**
`id u8 | pos 3×i16 | yaw u8 | vel 3×i16 | hp u8 | flags u8 | ack u16`
- Keeps current velocity precision (0.01 m/s).
- Yaw is 1.4°/step; measure remote facing.
- 6 + 16×18 = **294 B**, inside 300 B.
- 32 actors = 582 B, outside 300 B.

**Option 2 — 16 actors, 16 B row, 262 B packet.**
`id u8 | pos 3×i16 | yaw i16 | vel 3×i8 scale 4 | hp u8 | flags u8 | ack u16`
- Keeps yaw precision; velocity becomes 0.25 m/s over ±31.75 m/s, enough for the
  30 m/s fall and sprint, but coarser than today.
- 6 + 16×16 = **262 B**.
- Requires a prediction-error test at terminal velocity.

**Option 3 — 32 actors.** Needs either a renegotiated snapshot budget
(518–582 B), delta compression, or distance-tiered updates. Do not start here.

**Recommendation:** measure a 16-actor match first, with the current 22 B row
truncated at 8 as a control and a synthetic 16-row encoder. Then choose Option 1
or 2 based on measured prediction error, not on the report's byte count.

---

## 5. Claims that are false, fabricated, or not usable

### 5.1 Wrong code paths / APIs

- `tests/unit/test_net_protocol.gd` — actual path is
  `tests/gdunit/test_net_protocol.gd`.
- `pos_probe.gd`, `test_map_bake.gd`, `remote_puppet.tscn`,
  `TelemetryManager`, `PROTOCOL_VERSION`, packet magic `0xBD` — not in the
  repo.
- `get_tree().unload_unused_resources()` — not a `SceneTree` method. Verify the
  correct `ResourceLoader` API before using it.
- `scripts/player/camera_rig.gd` does not perform a shape cast every frame;
  `SpringArm3D` owns the collision query and `update_aim` only reads its length.
- The report says “34 questions”; the brief has **36**.

### 5.2 Numbers presented as measured but are projections

- SRV-01 16/32-actor p50/p95: linear extrapolation from 8 bots, not a 16/32 run.
- SRV-02 6.8→1.9 ms at 32 bots: projection; no 32-bot measurement.
- SRV-03 1.2–2.5 ms spawn spike: no measurement.
- SRV-04 13.5→2.1 µs per splash: no measurement; no current 60-round automatic
  weapon exists (max magazine is 12).
- SRV-05 95→32 µs: no measurement.
- SRV-06 42 % memory / 1.4 MB per actor / 45 MB at 32: no measurement.
- CLI-01 2.2 ms replay: derived from a server movement cost, not a client replay
  trace.
- CLI-02 50–200 ms join hitch: no measurement.
- CLI-03 45 % animation saving: no browser measurement.
- CLI-04 0.4–0.8 ms HUD saving: no browser trace.
- CLI-05 2.25 ms first-shot: plausible from the pool build, but not measured.
- REN-01 60–75 % instance / 55–70 % vertex reduction: no per-pose measurement.
- REN-03 65 % shadow geometry / 3–4.8 ms: no measurement.
- REN-06 35 % fragment / 2.8 ms: no measurement.
- MEM-01 14.5→9.8 MB Brotli / 32 %: no compression benchmark in this repo.
- MEM-02 160 MB / 250 MB ceilings: no browser memory trace.
- MEM-03 0.3 ms/tick: no measurement; projectile churn is ~15/s, not obviously
  a problem.
- MAT-01 “15 % CPU” is inconsistent with 2.79 ms / 33.3 ms ≈ 8.4 % of one core.
- MAT-02 28 % clustering reduction: no measurement.
- MAT-03 draw-call projections: no measurement.

### 5.3 Reasoning errors

- **NET-05 drain cap.** `MAX_DRAIN_PER_FRAME = 64` at 30 Hz drains up to
  1,920 packets/s. 32 clients × 30 inputs/s = 960/s. The cap is not the
  bottleneck described. Raising it to 128 may be harmless, but it is not
  evidence-driven.
- **REN-04 vs REN-01.** REN-01 recommends chunking MultiMeshes; REN-04 says
  chunked MultiMeshes keep draw calls under 100. Chunking necessarily increases
  draw calls. The two claims need a joint per-map measurement.
- **REN-05 post-match.** The report assumes an 8 s intermission and a 5 s
  scoreboard. Neither exists. The match-over phase is wired to
  `match_state_changed`, but no match-end flow emits it yet.
- **NET-04 projectile speed.** It uses 81 m/s; current class speeds are
  36–77 m/s. The swept-ray conclusion still holds, but the arithmetic is wrong.
- **SAF-02 deployment.** `docs/ci/DEPLOY.md` is explicitly “planned, CP5”. There is
  no Docker, blue-green switch, health endpoint, rollback script, or protocol
  version handshake. Do not present this as an existing rollback plan.

---

## 6. Product changes to reject now

These are not optimizations; they change the game contract:

- **MAT-02:** 3 s → 4 s respawn, 2 s invulnerability, 7-minute match. The current
  requirements are 3 s respawn and 5-minute matches. Reject unless the product
  owner explicitly changes them.
- **32 actors at 518 B:** changes the ≤300 B snapshot requirement. Reject until
  the budget is renegotiated or a delta/AOI layout is designed.
- **Client hitscan / rewind, multithreading/SAB:** already correctly rejected in
  the report; keep them rejected.

---

## 7. Safe first batch I would actually apply

Ordered by risk, all map-agnostic:

1. **HUD dirty flag** with transient-timer handling; browser trace before/after.
2. **BulletField prewarm** on the loading screen; assert no first-shot pool
   build.
3. **Snapshot encode into one buffer + health cache**; keep 22 B/182 B and
   byte-identical codec tests.
4. **`_entry_by_id` map + bot LOS stagger**; measure 8 and 16 bots, bot
   accuracy/TTK.
5. **Respawn top-2 raycast**; clustered-death test.
6. **Map bake contract** (tool + fixture, no specific map) after the three maps
   land; then scatter hash and detail-texture bake.
7. **NET-02 decision** after a 16-actor measurement; add a protocol version byte
   before any layout change.
8. **Rendering budget pass** on each of the three maps: chunking, shadows, far
   plane, triplanar. Per-map acceptance, not global claims.

I would not apply NET-05, REN-05, CLI-06, MAT-02, SAF-02, or the 16-byte row as
written.

---

## 8. What “accepted” will look like

For any of the above, the change needs:

1. a reproducible command and raw numbers (native **and** browser where the
   claim is client-side);
2. an effect size against the noise floor, not a single run;
3. a statement of the actor count and map family it applies to;
4. a rollback path (flag, revert, or protocol version);
5. an acceptance test that would fail if the optimization regressed;
6. no change to server authority, prediction determinism, or the snapshot
   budget unless that change is explicitly part of the proposal.

The content standard in [`docs/data/CONTENT-STANDARD.md`](../data/CONTENT-STANDARD.md) is
the other half of this: new maps, weapons, classes and collectibles declare
their own budgets and are validated in CI, so optimization work does not have
to be re-litigated for every artifact.
