# Project Status

**Date:** 2026-10-30
**Canonical branch:** `develop` (latest)
**Engine:** Godot 4.7.2, GDScript, Compatibility/WebGL 2, single-threaded WASM
**Tests:** **163 green, 0 failures** on `develop`; full `tools/check.sh` green

---

## Where the project is

Ball of Duty is a **playable vertical slice**, not a finished release:

- Five classes with distinct long-range weapons and per-class visuals.
- Solo practice and server-authoritative online play, 30 Hz, WebSocket, binary snapshots.
- Protocol v2: **8 actors by default, 16-actor capability**, 18 B snapshot row
  (150 B at 8, 294 B at 16).
- 150 × 150 m Sunken Quarry map with a 35-section physics walkthrough.
- Phase-aware quick menu (Esc) and a real settings panel (sensitivity, invert Y,
  scope scale, volume, LOW/MEDIUM/HIGH quality).
- Data-driven content standard: manifest, packs, entries, budget validation,
  catalog-backed weapon registry.
- L2/L8 Step 1: `CharacterBodyStats` is the shared body/camera/muzzle profile
  for LOCAL, REMOTE and SERVER; all five profiles are numerically identical to
  the old 0.82 m rig.
- Optimization batch 1 and 2: HUD dirty flag, bullet-pool prewarm, single-buffer
  snapshot encode, roster health cache, O(1) bot id index, 10 Hz bot LOS,
  top-2 respawn rays, protocol v2/16 actors, 8-marker overflow rings.

### Current verification

- `tools/check.sh`: content manifest, 163 tests, arena budget, 35-section
  quarry walkthrough, 4-bot match, 16-actor probe, headless client/server boot,
  web + Linux server export, server smoke.
- Browser (Chromium, software WebGL): auto-join renders character, gun, camera
  and HUD with **0 console errors**; settings panel persists quality/volume.
- `NET16`: 16 bots, 8 spawn markers, 294 B snapshot, tick p95 ~2–3 ms.
- `QUARRY_MATCH`: 4 bots, PASS.

---

## How stable is it?

**Stable core, unfinished product.**

Strong:

- Server authority, prediction/reconciliation, loopback combat, protocol
  golden-byte layout and 16-actor capacity are covered by tests.
- Movement/jump, five class weapons, damage/TTK, spawn protection, respawn and
  bot behavior are tested.
- The map walkthrough and camera-clip checks pass.
- Content validation is a CI gate; new artifacts fail closed.

Not yet proven:

- **No real Firefox/Safari/low-end-GPU evidence.** Chromium in this sandbox is
  SwiftShader; Playwright Firefox cannot create WebGL2 here. L9 is research-gated.
- **No real deployment.** `docs/DEPLOY.md` is a planned CP5 target; no Docker,
  blue-green, health endpoint or protocol-update rollback drill.
- **No CI remote or browser job** yet.
- **Current map is slated for replacement.** The three candidate maps are being
  built in another session and are not integrated into `develop`.
- **L2/L8 Step 2 is not done.** All classes still share the same body size;
  per-class sizing is a separate balance/visual change.
- **Camera/muzzle parity is partial.** The client hand muzzle and the server
  canonical muzzle still differ (measured ~0.67 m for the Knight at idle), and
  the client spring arm compresses against walls while the server aim origin is
  fixed. This is documented, not silently fixed.
- **No match-end flow.** The quick menu has a match-over phase, but no match-end
  emitter drives it yet.
- **No headshots** (intentional locked decision).
- **No mobile/touch support**; mobile is load-only.

---

## What is left

### Blocking / next

1. **Integrate the three maps** from the map session (`arena_crater`,
   `arena_dunes`, `arena_jungle`), retire/replace the quarry, add a map content
   pack, make `MapRegistry` a catalog adapter, and run each map's walkthrough.
2. **L9 browser matrix** — answer the research brief, then implement the
   Playwright/CI matrix, real-GPU measurements, pointer-lock/audio/reconnect
   checks and quality fallbacks.
3. **L2/L8 Step 2** — decide and apply per-class body sizes (Mage 0.856,
   Knight 0.820, Barbarian 0.773, Rogue 0.703), then re-run silhouette, hurtbox,
   camera and prediction tests.
4. **Match-end flow** — 5-minute timer, scoreboard, `match_state_changed`, and
   the quick-menu match-over path.
5. **Map bake / rendering pass** — bake generation, scatter spatial hash, detail
   texture, MultiMesh chunking, shadows/far plane, per-map budgets.

### Product / engineering gaps

- Default actor cap vs 16-cap product decision; maps need 16 spawn markers.
- Ack is u16: matches must stay under ~36 minutes; current 5-minute design is safe.
- Snapshot headroom is 6 B at 16 actors; any new per-row field needs a layout
  change.
- Content standard has classes/weapons; no map pack, collectibles or modes yet.
- `MapRegistry` and `main_menu.CLASSES` still duplicate catalog data.
- `GameManager` spawn/LOS/aim height literals are not fully profile-derived.
- Training dummy is not wired to `CharacterBodyStats`.
- Audio unlock / "click for sound" hint is not explicit.
- Web payload is ~14.3 MB gzip; precompressed Brotli hosting is planned, not live.
- 32 actors are not supported; needs a snapshot-budget/AOI decision.
- Deployment, rollback drill, CI remote and browser CI are all open.

---

## Open questions for the user/researcher

1. **L9:** answer the 13-cell browser/OS/hardware matrix and 7 questions in
   `docs/research/L9-QUESTIONS.md` / `docs/research/FEATURE-QUESTIONS.md`.
2. **L2/L8 Step 2:** approve per-class body sizes; choose the camera-compression
   policy (server spring-arm query vs fixed aim origin vs documented divergence);
   choose canonical muzzle vs animated hand for the visible tracer; decide
   whether the training dummy joins the profile system.
3. **Maps:** confirm the three-map rotation, default map, 16-spawn layout and
   whether the quarry is retired.
4. **Actors:** confirm default match size (8) and 16-player release target.
5. **Match:** confirm 5-minute length / 3-second respawn remain locked, and the
   desired scoreboard/end-of-match flow.
6. **Deployment:** where the first real server/CI runs (host, domain, TLS,
   precompressed assets).

---

## Branches / worktrees

| Branch | Purpose | State |
|---|---|---|
| `develop` | integration | clean, 163 tests green |
| `maps-candidates` | map session | **uncommitted map/UI work**, not merged |
| `feature/l2-l8` | L2/L8 | Step 1 merged; Step 2 pending |
| `feature/l6` | settings UI | merged |
| `feature/l9` | browser matrix | research only, awaiting answers |

Old phase worktrees `ballofduty-wt-a`…`-e` and their merged branches were removed.
The L6 worktree/branch was removed after merge. Generated `build/` and `reports/`
directories were deleted; `tools/check.sh` recreates them. Active worktrees:
`ballofduty` (maps-candidates), `ballofduty-wt-develop`, `ballofduty-wt-l2l8`,
`ballofduty-wt-l9`.

---

## Run it

```bash
cd ballofduty-wt-develop          # canonical develop worktree
./tools/check.sh                  # full gate
./tools/dev.sh up                 # server + web on :9180 / :8099
# open http://127.0.0.1:8099/?join=1&name=You
./tools/dev.sh down
```
