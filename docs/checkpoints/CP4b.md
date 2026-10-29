# CP4b — Movement prediction & reconciliation

- **Date:** 2026-10-29
- **Status:** implementation + playtest fixes complete — **awaiting retest**
- **Engine:** Godot 4.7.2, 30 Hz physics, binary WebSocket transport
- **Depends on:** CP4a (accepted)

## What landed

- **Input intake is now a queue, not a slot.** The server consumes exactly one input per tick,
  repeats the last frame if the queue is empty (ack stays pinned), and caps the queue at 16 frames.
  Sequence numbers are deduplicated; a 90 frame/s token window drops floods.
- **Snapshot carries motion state.** Each player row now includes velocity (i16 cm/s ×3) and an
  on-floor flag, so replay can restart from the authoritative pose *and* velocity. Row = **22 B**,
  8-player snapshot = **182 B** (budget 300 B).
- **Client prediction buffer.** Every locally simulated frame is stored with its resulting
  position/velocity/yaw/ground state. Snapshots for the local id rewind to the acked state and
  replay every unacked input through the same `LocomotionComponent`.
- **Visible corrections are smoothed.** The collision body takes the authoritative pose
  immediately; `Visual` and `CameraPivot` receive a decaying world-space offset (~100 ms), so a
  correction does not snap the camera. The first authoritative state after join is applied as a
  plain snap (spawn baseline) to avoid smoothing the spawn settle.
- **Displacement guard.** A server step that exceeds `8.6 m/s × dt` is rolled back and its
  horizontal velocity zeroed; violations are counted and logged.
- **Metrics** in the F3 overlay: `ack`, `pending`, `replay`, `ack err`, `corr` (total and per second),
  `vis` (size of the current render offset).

## Playtest pass (2026-10-29)

Browser feedback from the first CP4b test, and what changed:

| Report | Fix | Evidence |
|---|---|---|
| Camera ends up behind/inside walls | `SpringArm3D` uses `cast_motion`, which ignores initial overlap. Pivot moved to the capsule center, shoulder offset moved to the camera, cast sphere 0.22 → 0.05, shoulder collapses as the arm compresses | `test_world_geometry.test_camera_stays_out_of_the_cliff`; camera x=29.097 vs cliff face 29.15 |
| Speed too high for a 0.82 m character | Walk **1.0 m/s**, sprint **2.5 m/s**; animation thresholds/speed scales retuned | `test_movement`; overlay speed 1.00 m/s |
| Sprint worked in the air | Sprint target only applies on the floor; air preserves momentum but cannot accelerate | `test_release_and_sprint` airborne sprint = 1.00 m/s |
| Character slid with its back to the camera | View yaw is independent; WASD is camera-relative; body turns toward movement at 14 rad/s; movement scales by facing alignment so it turns before translating. Aiming locks facing to the view and allows strafing | `test_turning` 4 cases; 180° tie-break regression |
| Gun floated while walking | Gun reparented to `DEF-hand.R` through an external `BoneAttachment3D` (bone index resolved after the skeleton), stabilised to the aim direction; upper-body `Pistol_Aim_Neutral` hold overlay keeps it in a ready pose while the legs animate | `test_rig`; gun-to-hand gap **0.020 m** |
| No shooting animation | Filtered `Pistol_Shoot` overlay (12 upper-body tracks, zero lower-body) on the real `shot_fired` signal | `test_rig`; overlay plays `Pistol_Shoot`, main player keeps locomotion |
| Trees could be walked through | Border ring now gets trunk colliders too (diagonals fall inside the square cliff) | `test_world_geometry`; colliders 117 → 145 |
| `ERR_CONNECTION_REFUSED` once | A tab opened while the server was being restarted; clients do not retry until CP4d. Refresh fixes it | no code change |

Also: a 180° turn could resolve to opposite rotation directions on client and server after yaw quantization, producing ~0.4 m corrections. Fixed with a deterministic +PI tie-break and covered by a regression test. The overlay now reports the recent ack error and current visual offset instead of stale values.

Screenshots: [`cp4b-gun-ready.png`](./cp4b-gun-ready.png), [`cp4b-turn.png`](./cp4b-turn.png).

## Bugs found while building it

| Bug | Symptom | Fix |
|---|---|---|
| Server overwrote input | Only the newest frame survived per tick, so replay had no history to reapply | Per-player input queue + pinned ack on repeat |
| Snapshot lacked velocity | Replay restarted from a guessed velocity and diverged whenever the server had slid or landed differently | Added velocity + ground flag to the row |
| Test drove a different tick | Loopback sent inputs without calling the prediction path, so the owning client never reconciled | `PlayerController.simulate_tick()` is now the single local-tick seam for input, tests and future bots |
| Startup correction hitch | First authoritative state differed by 0.43 m while the server actor settled | Apply the first ack as a snap; smooth only gameplay corrections |
| Visual offset recursion | Helper called itself after an over-broad replacement | Extracted `_apply_visual_offset()`; caught by the smoothing assertion |

## Automated evidence

| Suite | Result |
|---|---|
| `tests/gdunit/test_prediction.gd` | **3 cases / 13 assertions** — deterministic replay, divergence correction + decay, stale ack ignored |
| `tests/gdunit/test_net_loopback.gd` | **1 case / 37 assertions** — adds prediction p95, forced divergence recovery, ordered/duplicate/flooded input |
| `tests/gdunit/test_net_protocol.gd` | **6 cases / 30 assertions** — 182 B budget, velocity + ground flag roundtrip |
| Full suite | **38 test cases · ~488 assertions · 0 failures** |

Measured on this machine:

- Loopback ack error **p95 = 0.0007 m** over 38 steady-state samples (criterion < 0.02 m)
- 100 ms RTT + 20 ms jitter ack error **median 0.000 m, p95 = 0.001 m** (criterion < 0.05 m)
- Replay depth **1–5 frames** at 100 ms (criterion ≤ 8)
- Forced 2 m client teleport recovered to **0.000 m** against authority in ≤ 12 ticks, counted as one
  correction
- 8-player snapshot **182 B**; 2-player live snapshot **50 B**; input **12 B**
- Normal movement trips the displacement guard **0 times**

## Acceptance criteria

| Criterion | Status |
|---|---|
| Loopback p95 error < 0.02 m | **Pass** — 0.0007 m |
| 100 ms + 20 ms p95 < 0.05 m | **Pass** — 0.001 m |
| No rubber-banding; corrections invisible | **Awaiting your feel test** |
| Replay depth ≤ 8 at 150 ms | **Pass** — 1–5 at 100 ms |
| Impossible displacement rejected and logged | **Pass** — step rolled back, legitimate movement never rejected |
| Walk/sprint scale, airborne sprint, body-facing turn, gun-in-hand, camera at walls | **Awaiting retest** — see the playtest table |
| Disconnect/reconnect with grace | CP4d (not in scope) |
| **Your sign-off** | Pending |

## How to test (browser)

```bash
tools/check.sh && tools/dev.sh up
# then open:
# http://127.0.0.1:8099/?join=1&port=9180&name=You
# (host defaults to the page hostname, so a forwarded URL works unchanged)
```

Press **F3** for the debug overlay. The two prediction lines are the important ones:

```text
pred ack 412   pending 1   replay 0
ack err 0.001 m   corr 0 (0.0/s)   vis 0.000 m
```

Test script:

1. **Baseline, 60 s.** Walk, sprint, jump, strafe, run into walls and the ramp. Expect
   `pending` 0–2, `ack err` under ~0.01 m, `corr` near 0, no camera snap.
2. **Latency.** Reopen with `…&name=You&sim=100,20`. Repeat. Movement should still start
   immediately (prediction); `ack err` should stay small; `corr` should stay near 0.
3. **Worst case.** Add jitter and deliberately run into geometry while turning. Report any visible
   rubber-band, camera hitch, or `corr` spike (screenshot the overlay).
4. **Second player (optional).** Open a second *window or profile* (background tabs are throttled)
   with `name=Bob`. Both should see each other move; shooting still does nothing on the other
   screen until CP4c.

Server-side intake stats are printed once a second (ack, last_seq, queue, dropped) because
`tools/dev.sh` starts the server with `--net-stats`; they also land in `.cache/server.log`.

The server/web are left running for the retest. Stop with `tools/dev.sh down`.

## Known gaps carried into CP4c

- Prediction covers movement only. Firing, ammo, hit registration and death are still local/CP3.
- The input packet has no fire/reload intent yet; CP4c adds `{seq, tick, aim, buttons}` validation.
- Reconnect/grace and repeated-abuse escalation are CP4d.
