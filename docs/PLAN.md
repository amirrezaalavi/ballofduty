# Ball of Duty — revised execution plan

- **Updated:** 2026-10-29, after the CP4c browser test
- **Status:** connection confirmed working (both ports forwarded); combat and 4 bots are live.
  This plan replaces the ad-hoc CP4c/CP4d sequencing in `ROADMAP.md` for the next cycle.
- **Goal:** a trustworthy, readable, good-looking V1: you can see every bullet, hits register,
  the gun stays in the hand, bots fight, and the entry flow never lies about being connected.

## 1. Confirmed state

| Area | State |
|---|---|
| Transport | WebSocket join/leave works; both `8099` and `9180` forwarded. Server logged `net connect` / `net join id=5`. |
| Combat | Server-authoritative fire, projectiles, hit/death/respawn work; bots fight and kill. |
| Bots | 4 bots, aggressive and accurate; battle reads as "intensive". No difficulty change queued yet. |
| Connection UX | **Still a product bug:** a failed socket looks playable (cosmetic-only fire, no damage, no error). Must be fixed before any public build. |
| Gun | Box-mesh gun oriented by camera yaw/pitch instead of the hand. |
| Bullets | 0.08 s tracer, no visible projectile; hard to track. |
| Character | Quaternius UAL mannequin, no strafe clips. |
| Firefox | Recorded in `PLAYTEST-2026-10-29.md`; deferred. |

## 2. Tuning locked in this pass

| Setting | Now | New | Notes |
|---|---:|---:|---|
| Walk speed | 1.00 m/s | **1.05 m/s** | +5 % |
| Sprint speed | 2.50 m/s | **2.75 m/s** | +10 %; implement as `move_speed 1.05 × sprint_multiplier 2.62` (2.751 m/s) |
| Projectile speed | 90 m/s | **81 m/s** | −10 %; 2.5 s lifetime still gives 202 m range |
| Bullet visual | 0.08 s, 0.9 m box | **long thin tracer** | 2.2 m trail / 2.4 m rim; radial thickness only 5 % |
| Camera | accepted | unchanged | |
| Jump/gravity | unchanged | unchanged | separate item (S26) |

Travel time at 20 m becomes **247 ms** (was 222 ms). If your perceived lag is around ⅓ s, a 10 %
slowdown alone will not cover it; report the `rtt=` value in the bottom-right panel so we can
separate network RTT from render lag.

## 3. Phase 0 status — implemented 2026-10-29

| Task | Status | Evidence |
|---|---|---|
| Visible pooled bullets | **Done** | 64-node pool, 2.5 m trail + 2.8 m dark rim, 100 ms impact, prewarmed materials |
| Speed tuning | **Done** | walk 1.05, sprint 2.751 (1.05 × 2.62), projectile 81 |
| Gun / turn-to-fire / legs | **Done** | gun welded to hand, additive spine aim ±70°, 8°/150 ms fire gate, ADS turns body |
| Connection truth | **Done** | 6 s connect timeout, 500 ms refused detection, HUD banner, offline fallback, ghost cleanup |
| Combat telemetry | **Done** | shots/projectiles/hits/deaths/blocked counters every 150 ticks |
| Remote smoothing | **Done** | 83 ms virtual-clock buffer, 1-tick damped extrapolation, render-offset decay, physics interpolation off on puppets |
| Regression | **Done** | 51 cases green; live 1v4 join, death/respawn, client fire confirmed (`ammo 30 → 26`, server `shots=4`) |

The Phase 0 gate is ready for your retest.

## 3. Visible-bullet design (P0)

Replace the single short tracer with a pooled `BulletVisual`:

- Long, thin tracer: **0.018 m core**, 0.006 m trail, 0.026 m dark rim, **2.2 m / 2.4 m** long.
- Flies at the real **81 m/s** from the muzzle, max **1.2 s**; grows out of the gun (the streak's
  back end never sits behind the muzzle), so it cannot read as a camera-origin beam.
- Swept ray each render frame against world/actors (no damage) so it stops on the first surface.
- Local fire spawns one immediately; remote `SHOT` events spawn the same visual at the server
  origin/direction.
- **64-bullet pool**, materials and meshes created once at boot; muzzle flash retained.
- Impact spark on the client-side stop point, also pooled. Hitmarker stays **server-only**.

This is cosmetic. The authoritative projectile remains server-side; a visible bullet that misses
while the server hits is expected under lag and is better than an invisible one.

### KayKit findings (Phase 1 A input)

- Adventurers 2.0 free tier + Character Animations 1.1 **Rig_Medium**: 23 bones, identical
  names/parents, no retargeting. Source height 2.543 m → scale **0.32244** for the 0.82 m capsule;
  faces **+Z**, so yaw 180°.
- Free CC0 clips include `Walking_A/B/C`, `Running_A/B`, `Running_Strafe_Left/Right`,
  `Walking_Backwards`, `Jump_Start/Idle/Land`, `Ranged_2H_Aiming/Reload/Shoot/Shooting`, hit/death.
  **No aim-walk clip** → use `Ranged_2H_Aiming` as an upper-body overlay, matching the Phase 0
  spine modifier. `Ranged_2H_Reload` is 1.60 s, matching the rifle.
- **Draw-call risk:** 9 meshes per character. Merge to one skinned mesh and disable character
  shadows; 12 unmerged characters would exceed the 150-call budget.
- **Head hurtbox mismatch:** visual head is ~0.35–0.82 m, current sphere is at 0.72 m / r 0.115.
  Decide whether to resize/move the head hurtbox (changes hit feel) or keep it.
- **Rifle:** Quaternius CC0 M4 on Poly Pizza (1,930 tris, 3 materials); AK/musket alternates.
- Detect `vel` for strafe animation on remotes: snapshot already carries it; the interpolator
  currently drops it.

## 4. Gun, turn-to-fire, legs (P0)

Current: the gun socket is oriented from `view_yaw` + camera pitch, and the aim overlay always runs.

New contract:

1. **Gun is welded to the hand.** `GunMount` inherits the right-hand/upper-body transform only; no
   camera yaw/pitch is applied to the socket. It moves when the character moves.
2. **Legs own the movement direction.** Body yaw keeps following movement (existing model).
3. **Upper body aims.** Add an additive spine/chest yaw+pitch toward `view_yaw`/camera pitch,
   clamped to roughly **±70° yaw / −60…+45° pitch**. The hand and gun ride this, so the gun points
   where you look without leaving the hand.
4. **Turn-then-shoot.** On fire, if the target aim is outside the torso clamp (or body yaw differs
   by more than ~25°), queue the shot and rotate the body toward `view_yaw` at `turn_speed`.
   Fire when aligned within **5°**, or after a **150 ms** cap (then fire at the best alignment).
   While rotating, legs keep animating in the movement direction.
5. **No permanent aim pose.** `Pistol_Aim_Neutral` is used only while aiming/scoped or within a
   short post-fire window; otherwise the normal hold/idle plays.

Phase 1 workstream A replaces the mannequin/rifle and can then supply real strafe clips; the
procedural upper-body split stays as the fallback if a clip set is incomplete.

## 5. Phases

### Phase 0 — Trust and feel (me, ~0.5–1 day)

| # | Task | Acceptance |
|---|---|---|
| 0.1 | Visible pooled bullets + impact + muzzle light | Every local/remote shot is visibly trackable for its flight; no per-shot allocations; no first-shot hitch |
| 0.2 | Tuning: 1.05 / 2.75 m/s, 81 m/s | Values in `.tres`; walk/sprint regression tests updated |
| 0.3 | Gun/upper-body/turn-to-fire per §4 | Gun never follows the camera; body turns before firing; legs keep moving |
| 0.4 | Connection truth | `CONNECTING → CONNECTED → FAILED/TIMEOUT/LOST`; banner + retry; ghosts cleared; offline play restored; no silent cosmetic-only state |
| 0.5 | Combat telemetry | Server counters for shots accepted/rejected, projectiles spawned/expired, hits/misses, event bytes; toggleable debug line |
| 0.6 | Regression | `tools/check.sh` green; 5-minute live 1v4 browser run |

**Gate:** you retest. Success = bullets trackable, hits/deaths readable, gun behaves, connection
failure impossible to miss.

### Phase 1 — Parallel build (3 agents + me, ~2–3 days)

| Agent | Scope | Files it owns | Deliverable |
|---|---|---|---|
| **A — Character & weapon art** | Research/import CC0 rig + rifle; strafe or procedural legs; animation map; muzzle/grip contract | `assets/`, `scenes/characters/`, `character_visual.gd`, new visual tests | Better character, real rifle, stable hand attachment, walk/sprint/strafe/aim set |
| **B — Entry UX & network resilience** | Main menu, animated loading screen, one-origin static+WS proxy, reconnect grace, retry, LAN/tunnel-safe join | `main.gd`, `network_manager.gd`, web shell/template, `tools/` | Open page → menu → name/host/join → loading animation → match; one port only |
| **C — Combat feel, perf, bots** | Pool audit, projectile visibility, bot reaction/spread, tick/CPU profiling, 10-minute soak harness, telemetry surface | `server_combat.gd`, `projectile.gd`, `tracer.gd`/bullet visual, `hud.gd`, soak tests | Stable 30 Hz under 4 bots + 8 clients, tunable bots, measured CPU |

Rules:

- Each agent works in its own **git worktree**, on disjoint files.
- Shared interfaces are frozen before spawn: `Msg.EVENT` schema, `AnimState` byte map, grip/muzzle
  node names, `GameManager` public API. Breaking one requires my approval.
- Each agent runs its own targeted tests and returns a diff + report. **I** run the full suite,
  integrate in order (B → C → A), run a live browser match, then restart the server for you.
- Only I run/deploy the live server; agents use ephemeral ports.

**Phase 1 gate:** character/rifle visible and stable at 2.3 m camera distance; menu and loading
animation complete; 10-minute soak clean; no regression in hit/death/respawn.

### Phase 2 — World & polish (optional 4th agent, ~2 days)

- Arena art pass around the new character style (props, ground, sky, lighting), within the
  existing draw-call/triangle budget.
- Starts only after A's character contract lands, so two agents never edit `arena.tscn`/materials.
- Camera occlusion by players (dither), remote death clip, hit feedback polish.

### Phase 3 — CP4d/CP5 hardening (~3–5 days)

- 8 clients + 4 bots for 10 minutes; CPU/memory/tick-rate report.
- 100 ms RTT and packet-loss feel; reconnect grace; rate limits; abuse cases.
- Match loop: 5-minute timer, score, scoreboard, end-of-match.
- Deployment: remote host, single-origin serving, CI green (needs a git remote).

## 6. Estimates

| Milestone | Effort | Calendar |
|---|---|---|
| Phase 0 trustworthy build | 0.5–1 day | same day / next |
| Phase 1 parallel round | 2–3 days | 3 agents + integration |
| Phase 2 world polish | ~2 days | after Phase 1 |
| Phase 3 soak + match loop + deploy | 3–5 days | after sign-off |

**~2 days** to a build that connects, tracks bullets, hits, dies, respawns, and holds the gun
correctly. **~5–7 days** to the full visual/menu/world upgrade. **~10–12 days** to a deployable V1
with match loop and soak.

## 7. Why 3 agents, not more

- Three disjoint surfaces (art, entry/network, combat/perf) cover the current bottlenecks.
- A fourth (world art) conflicts with A on scenes/materials; it waits for the character contract.
- More agents on a 6.9 MB asset repo with shared `.tscn` files create merge churn faster than they
  save time. Two rounds of three beats six at once.

## 8. Open decisions

1. **RTT:** what does the bottom-right `rtt=` show during a match? If it is ~330 ms, we should add
   lag compensation or raise projectile speed back after the visibility fix, not just slow bullets.
2. **Art direction:** (A) keep UAL and add the full CC0 clip set + rifle (fast), or (B) switch to
   KayKit Adventurers + animations (cuter/cohesive, more rework).
3. **Turn-to-fire:** confirm the 5° / 150 ms rule and whether the body stays aimed after firing
   until movement resumes.
4. **Start:** Phase 0 now, then retest before spawning Phase 1 agents — or spawn all three
   immediately after Phase 0's interface freeze.
