# Project Status

**Date:** 2026-10-30
**Branch:** `develop` (single clone at `ballofduty/`, GitHub is the head)
**Engine:** Godot 4.7.2, GDScript, Compatibility/WebGL 2, single-threaded WASM
**Tests:** **172 green, 0 failures**; `tools/check.sh --skip-export` green

---

## Where the project is

Ball of Duty is a **playable vertical slice**, not a finished release.

Shipped:

- Five classes with distinct long-range weapons, per-class visuals and HUD.
- Solo practice and server-authoritative online play: 30 Hz, WebSocket, binary
  snapshots, prediction and reconciliation.
- Protocol v2: **8 actors by default, 16-actor capability**, 18 B snapshot row
  (150 B at 8, 294 B at 16).
- Four maps: Sunken Quarry (default, 35-section physics walkthrough) plus
  Starfall Crater, Dune Canyon and Jungle Ruins, selectable from the menu and
  over the wire (`map_id` in JOIN).
- Phase-aware quick menu, settings panel (sensitivity, invert Y, scope scale,
  volume, LOW/MEDIUM/HIGH quality), content standard with budget validation.
- `CharacterBodyStats`: one body/camera/muzzle profile applied to LOCAL, REMOTE
  and SERVER. All five class profiles are currently identical.
- Optimization batches 1 and 2 (HUD dirty flag, bullet prewarm, single-buffer
  snapshot encode, roster health cache, O(1) bot index, 10 Hz bot LOS).
- L9 web surface: opt-in performance probe (`?perf=1`), WebGL 2 fallback card,
  mobile load-only banner, audio unlock hook, pointer-lock resume hint, integer
  canvas snapping, Playwright browser smoke harness.

### Verification

`tools/check.sh --skip-export`: content manifest, 172 gdUnit tests, arena
budget, 35-section quarry walkthrough, 4-bot match, 16-actor probe, headless
client/server boot.

- `QUARRY_MATCH`: 4 bots, PASS.
- `NET16`: 16 bots, 8 spawn markers, 294 B snapshot, tick p95 ~2.8 ms.
- Browser (Chromium, software WebGL): boot 8.8 s, `?join=1&perf=1` reaches
  `phase:"match"` with pointer lock and 0 console errors.
- Web export ≈ 44.8 MB raw / ~14.3 MB gzip.

---

## How stable is it?

**Stable core, unfinished product.**

Strong:

- Server authority, prediction, loopback combat, protocol golden bytes and
  16-actor capacity are covered by tests.
- Movement/jump, class weapons, TTK, spawn protection, respawn and bot behavior
  are tested; the quarry walkthrough and camera-clip checks pass.
- Content validation is a CI gate; new artifacts fail closed.

Not yet proven:

- **No real-GPU evidence.** Chromium in this sandbox is SwiftShader; Firefox,
  Safari, iOS and low-end laptops are unmeasured (see `docs/ci/BROWSER-MATRIX.md`).
- **No deployment.** `docs/ci/DEPLOY.md` is a plan; no host, TLS, rollback drill
  or precompressed hosting.
- **The three new maps are WIP.** They load and have headless walkthroughs, but
  the bake/scatter/detail-texture and per-map budget pass has not run.
- **L2/L8 Step 2 is not done.** All classes share one body size.
- **Camera/muzzle parity is partial.** The client hand muzzle and server
  canonical muzzle differ (~0.67 m Knight idle); the client spring arm compresses
  against walls while the server aim origin is fixed.
- **No match-end flow.** The quick menu has a match-over phase, but nothing
  emits it yet.
- **Loss recovery is TCP-bound.** A lost segment stalls the stream for at least
  one RTO; the 67 ms interpolation buffer hides most of it, but a 300 ms stall is
  visible.
- **No headshots** (locked decision), no mobile/touch controls.

---

## What is left

### Next

1. **Map polish** — bake/scatter/detail texture, MultiMesh chunking, per-map
   budgets, 16 spawn markers, decide the rotation and whether the quarry stays.
2. **L2/L8 Step 2** — apply per-class sizes (Mage 0.856, Knight 0.820,
   Barbarian 0.773, Rogue 0.703), re-run silhouette/hurtbox/camera/prediction.
3. **Match-end flow** — 5-minute timer, scoreboard, `match_state_changed`.
4. **Real browser qualification** — run the 13-cell matrix on H1/H2, Safari and
   iOS; enable the Firefox/Xvfb CI job after one green manual pass.
5. **Deployment** — host, domain, TLS, precompressed assets, rollback drill.

### Engineering gaps

- Default actor cap vs 16-cap product decision; ack is u16 (safe under 36 min).
- Snapshot headroom is 6 B at 16 actors; new per-row fields need a layout change.
- Content standard covers classes and weapons; maps are only partially catalogued.
- `MapRegistry` and `main_menu.CLASSES` still duplicate catalog data.
- `GameManager` spawn/LOS/aim height literals are not profile-derived.
- Training dummy is not wired to `CharacterBodyStats`.
- Tab throttling suppresses input but cannot resync snapshots (no protocol cmd).
- 32 actors unsupported; needs an AOI/snapshot-budget decision.
- Audio unlock exists but no explicit "click for sound" hint in the HUD.

---

## Open questions

1. **Maps:** final rotation, default map, 16-spawn layout, quarry retirement.
2. **Actors:** confirm 8 default and 16-player release target.
3. **Match:** confirm 5-minute length / 3-second respawn and the scoreboard flow.
4. **L2/L8 Step 2:** approve per-class sizes; camera-compression policy; canonical
   vs animated-hand muzzle; training dummy adoption.
5. **Deployment:** first host, domain, TLS, precompressed assets.
6. **Browser gate:** confirm G0 blockers (Chrome, Edge, Firefox, Safari) and
   whether mobile stays load-only for v1.

---

## Workflow

- One clone; GitHub is the source of truth. Work on a branch, open a PR into
  `develop`, keep `develop` protected.
- `tools/check.sh` is the full local gate; GitHub Actions runs a light
  import + tests + content check only.
- See [`development/FEATURE-BRANCHES.md`](development/FEATURE-BRANCHES.md).

## Run it

```bash
cd ballofduty
./tools/check.sh --skip-export
./tools/dev.sh up            # server :9180, web :8080
# open http://127.0.0.1:8080/?join=1&name=You
./tools/dev.sh down
```
