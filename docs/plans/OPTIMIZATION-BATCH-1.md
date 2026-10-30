# Optimization Batch 1 — Safe, Map-Agnostic Steps

**Status:** in progress.
**Source:** [`../research/OPTIMIZATION-ANSWERS-REVIEW.md`](../research/OPTIMIZATION-ANSWERS-REVIEW.md) §7.
**Constraint:** the map session's uncommitted files are off-limits. Do not edit
`scripts/game/main.gd`, `scripts/ui/main_menu.gd`, `scripts/game/map_registry.gd`,
`tests/gdunit/test_menu.gd`, `scenes/maps/arena_{crater,dunes,jungle}.tscn`,
`scripts/game/{crater,dunes,jungle}_arena.gd`, `tests/headless/*_walk.gd` or
`docs/checkpoints/CP-maps.md`.

Each step is one subagent, one reviewable diff, targeted tests, then a commit.
No step may change server authority, prediction determinism or the snapshot
layout (except the byte-stable single-buffer refactor in step 3).

---

## Baseline (2026-10-30, current worktree)

| Metric | Baseline |
|---|---:|
| `perf_probe` snapshot encode 8 actors | **49.42 µs avg / 59 µs p95** |
| After step 3 | **20.34 µs avg / 24 µs p95** (182 B unchanged) |
| `perf_probe` grounded actor step | **118.3 µs avg / 154 µs p95** |
| `perf_probe` bullet pool build | **2,130 µs** |
| `perf_probe` HUD `_process` (headless, no canvas) | 0.41 µs |
| `quarry_match` 4 bots, 45 s | shots 114 · hits 31 · damage 426 · deaths 4 |
| Full check | 130 tests green, 0 failures |

Headless HUD numbers are not a browser measurement; the HUD acceptance is a
functional test plus a Chrome trace before/after, not the headless microsecond
number.

---

## Step 1 — HUD dirty flag  ✅ done (`45208a0`)

**Files:** `scripts/ui/hud.gd`, `tests/gdunit/test_hud.gd` (new).

**Change**
- Add `_mark_dirty()` and a `redraw_requests` counter for tests.
- `_process` only redraws while a transient timer is non-zero (`_hit_time`,
  `_kill_time`, `_damage_flash`, `_crosshair_kick`) or the 4 Hz debug text
  refreshes.
- Every state setter (`_on_health`, `_on_ammo`, `_on_reload`,
  `_on_weapon_changed`, `_on_heat`, `_on_charge`, `_on_hit`, `_on_shot`,
  `_on_death`, `_on_respawn`, F3 toggle, `bind_player`) marks dirty.

**Acceptance**
- Idle `_process` does not request a redraw.
- Damage, hitmarker, shot kick, death/respawn and ammo/heat/charge changes each
  request a redraw.
- `test_class_weapon_visual` still passes.
- Browser screenshot/trace sanity in solo.

**Result:** 9 HUD tests + 4 class-weapon visual tests green. `_process` no
longer redraws when idle; transients and 4 Hz debug text still paint.

**Rollback:** remove `_mark_dirty()` calls; the old unconditional
`queue_redraw()` is one line.

---

## Step 2 — BulletField prewarm  ✅ done (`569f355`)

**Files:** `scripts/weapons/bullet_field.gd`,
`scripts/player/player_controller.gd`, `tests/gdunit/test_bullet_pool.gd`.

**Change**
- Add `BulletField.prewarm(parent)` and a test-only `reset()`.
- Prewarm once when the local player is ready (solo or client), before the
  first shot. Headless/server stays lazy.
- Keep the 64 + 24 pool sizes and all counters.

**Acceptance**
- `pool_builds == 1` before the first launch.
- First launch does not increase `pool_builds` or node count.
- Existing 500-round/impact tests pass.
- `perf_probe` `bulletfield_pool_build` is no longer paid on the first shot
  (it moves to player ready).

**Result:** 5 bullet-pool tests + 4 class-weapon visual tests green. The pool
is built once before the first launch; first launch adds no nodes.

**Rollback:** remove the prewarm call; first shot builds the pool as before.

---

## Step 3 — Snapshot single buffer + health cache  ✅ done (`7f51d35`)

**Files:** `scripts/networking/net_protocol.gd`, `scripts/game/game_manager.gd`,
`tests/gdunit/test_net_protocol.gd`.

**Change**
- Encode the snapshot into one pre-sized `PackedByteArray` with
  `encode_u8/s16/u32` at fixed offsets.
- Keep the row layout and bytes **identical**; add a golden-byte test.
- Cache `HealthComponent` on the roster entry and reuse it in
  `_snapshot_entry`; fall back to a lookup if the node was freed.

**Acceptance**
- 8-actor packet is still 182 B; 1-actor golden hex unchanged.
- `test_net_protocol`, `test_net_loopback`, `test_loopback_combat`,
  `test_prediction` pass.
- `perf_probe` encode 8 actors improves or stays within noise; no allocation
  regression.

**Result:** 12 protocol + 1 loopback + 1 loopback-combat + 3 prediction tests
green. Golden 28 B hex unchanged; 8-actor packet still 182 B. Encode
49.42 → 20.34 µs avg (p95 59 → 24 µs).

**Rollback:** revert to append encoding; health cache is independent.

---

## Step 4 — Bot id index + LOS stagger  ⏳ in progress

**Files:** `scripts/game/game_manager.gd`, `tests/gdunit/test_bots.gd` (or a
focused new suite).

**Change**
- Maintain `_by_id: Dictionary` when roster entries are added/removed/reset;
  `_entry_by_id` becomes O(1).
- Evaluate bot LOS on a per-bot 3-tick phase (~10 Hz) and cache
  `bot_has_los`; movement/aim/fire still run every tick.
- Keep the feeler ray every tick; it is a movement probe, not target LOS.

**Acceptance**
- 4-bot `quarry_match` still passes; kills/damage stay in the same order of
  magnitude as baseline (shots 114 / hits 31 / deaths 4).
- `test_bots`, `test_bot_feel`, `test_class_weapons` bot test pass.
- `_entry_by_id` returns the same entry for every roster id after join/leave.

**Rollback:** restore per-tick `_has_los`; id index can stay.

---

## Step 5 — Respawn top-2 raycast

**Files:** `scripts/game/game_manager.gd`, `tests/gdunit/test_bots.gd` or a
focused respawn test.

**Change**
- First pass: distance to every living actor for every spawn (no rays).
- Rank spawns by nearest distance; raycast only the top two candidates against
  actors within 25 m.
- Keep the existing `nearest + 5 if clear` score; fall back to the best
  distance if both candidates are blocked.

**Acceptance**
- Respawn still returns a valid spawn point.
- Clustered deaths do not exceed 1.2× the running tick average.
- `quarry_match` and `test_bots` pass.
- Add a `spawn_raycasts` counter to make the reduction testable.

**Rollback:** restore the full spawn × roster raycast loop.

---

## Not in this batch

- Map bake / scatter hash / detail texture: wait for the three maps.
- MultiMesh chunking, shadows, far plane, triplanar: per-map A/B.
- NET-02 layout: needs a 16-actor measurement and a protocol version byte.
- NET-05, REN-05, CLI-06, MAT-02, SAF-02: rejected/deferred in the review.

---

## Gate after each step

```bash
./tools/gdcheck.sh <changed .gd files>
./tools/godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a <targeted suites> -c --ignoreHeadlessMode
```

After steps 3 and 5, rerun `tests/headless/perf_probe.gd` and compare to the
baseline. After step 5, run `tools/check.sh --skip-export`. Full `tools/check.sh`
once at the end of the batch.
