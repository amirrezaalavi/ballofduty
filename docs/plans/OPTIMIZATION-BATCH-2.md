# Optimization Batch 2 — Protocol v2 / 16 Actors

**Status:** complete. Steps 1–3b committed; full check green.
**Source:** [`../research/OPTIMIZATION-ANSWERS-REVIEW.md`](../research/OPTIMIZATION-ANSWERS-REVIEW.md) §4.
**Constraint:** map session work stayed untouched.

---

## Result

| Metric | Before | After |
|---|---:|---:|
| Actor cap | 8 | **16** |
| Snapshot row | 22 B | **18 B** |
| Snapshot at 8 actors | 182 B | **150 B** |
| Snapshot at 16 actors | rejected (358 B) | **294 B** |
| Protocol version | none | **v2 in JOIN_REQ/JOIN_OK** |
| 16-bot server tick p95 | not measured | **~2.2–3.3 ms** |
| 8-marker map with 16 bots | 9–16 stacked at origin | **overflow rings, min pair distance 0.8 m** |
| Respawn on crowded markers | could stack | **ring-1 respawn, 0.82 m from marker** |

---

## Step 1 — Protocol v2 (`160ff43`)

- `PROTOCOL_VERSION = 2`, `MAX_PLAYERS = 16`, `SNAPSHOT_ROW_BYTES = 18`.
- Row: `id u8 | pos 3×i16 | packed24 | vel 3×i16 | ack u16`.
  - packed24: 12-bit yaw (≈1.53 mrad/step), 2-bit state, 1-bit `on_floor`, 7-bit HP.
  - Velocity keeps the existing 0.01 m/s precision, so prediction replay does not
    pay for the smaller row.
  - Ack is u16; a 5-minute match at 30 Hz is 9000 frames, inside the 36.4-minute
    wrap window.
- JOIN_REQ carries the version; JOIN_OK echoes it. `DENY(VERSION)` rejects a
  mismatched peer before `peer_joined`. The client surfaces “server protocol
  mismatch — update the game”.
- Golden 24 B packet test locks the layout.
- **Not accepted from the research answer:** its 16-byte row used `vel i8 ×10`
  (±12.7 m/s), which would clamp the 30 m/s terminal fall and break
  reconciliation. The 18 B row keeps velocity i16 and fits 16 actors in 294 B.

## Step 2 — 16-actor probe (`24cb267`)

`tests/headless/net16_probe.gd` starts 16 bots on an 8-marker flat world,
drives 300 measured ticks, builds the real `_snapshot_entry` rows, and gates:

- roster = 16;
- snapshot = **294 B** and decodes 16 rows;
- tick p95 ≤ **20 ms** (measured ~2.2–3.3 ms);
- no overlapping spawn positions.

`tools/check.sh` runs it after the 4-bot match.

## Step 3 — 8-marker overflow (`d824209`)

`_claim_slot` reuses a marker when all slots are used and assigns a ring
(1 = 0.8 m out, 2 = 1.6 m out). `_spawn_server_actor` applies
`_spawn_ring_offset(ring)`. The first 8 actors keep ring 0 exactly as before.
`_release_slot` and `_reset` clear the ring state. A 16-bot / 8-marker test
asserts no pair is closer than 0.1 m and every actor is within 5 m of a marker.

`tests/gdunit/test_net_version.gd` proves a v1 JOIN_REQ is denied before
`peer_joined`.

## Step 3b — Respawn rings (`1bdb161`)

`_choose_respawn` now builds candidates for every marker × ring up to
`ceil(MAX_PLAYERS / spawn_count)`, then keeps the distance-first / top-2 ray
pass. On 8 crowded markers a respawn lands **0.82 m** from the marker and
**0.80 m** from the nearest living actor, with 6 rays (bound 2 × living).

---

## Verification

- `test_net_protocol`: 14 cases; 8 actors = **150 B**, 16 = **294 B**; golden
  v2 bytes.
- `test_net_loopback`, `test_loopback_combat`, `test_prediction`,
  `test_menu_network`: green; live 2-actor snapshot = **42 B**.
- `test_bots`: 4-bot match + 16-on-8 spawn test green.
- `test_net_version`: stale version denied, current version accepted.
- `test_respawn`: top-2 rays + crowded overflow ring green.
- `NET16`: `spawns=8 overlap_ok=true result=PASS actors=16 bytes=294
  tick_avg_us≈1.3–2.2ms tick_p95_us≈2.2–3.3ms`.
- `QUARRY_MATCH`: PASS with 4 bots.

## Remaining 16-player caveats

- Maps should eventually expose 16 spawn markers; the overflow ring is a safe
  fallback, not a replacement for map-authored spawns.
- `_choose_respawn` does not reserve ring slots for other dead-but-not-respawned
  actors; simultaneous deaths can still pick the same ring in a rare case.
- Ack is u16. Matches must stay under ~36 minutes; the current 5-minute design
  is safe. A future long-session mode needs wrap-aware ack comparison.
- Snapshot headroom is 6 B at 16 actors. Any new per-row field needs a layout
  change, not a silent append.
