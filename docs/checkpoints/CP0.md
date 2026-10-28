# CP0 — Foundation & pipeline

- **Date:** 2026-10-28
- **Build:** `d8fbd67`
- **Engine:** Godot 4.7.2-stable (official), Compatibility renderer, 30 Hz physics
- **Accepted by:** pending (foundation gate; CP1 starts after the user's feel test)

## Acceptance criteria

- [x] **Import/boot clean.** `tools/check.sh` → import, 120-frame headless client boot and 120-frame
  headless server boot complete with **0 errors**. Evidence: `smoke: 42 checks, 0 failure(s)` and
  `BALL_OF_DUTY server tick=22/24`.
- [x] **Compatibility project.** `rendering/renderer/rendering_method="gl_compatibility"` asserted by
  `tests/headless/smoke_test.gd`; no Forward+/Mobile references.
- [x] **Headless server.** `--headless --quit-after 120 --max-fps 60 -- --server --port 9080` logs the
  listen banner and a physics-tick probe; no SIGTERM exit requirement (Godot does not trap it).
- [x] **Web export boots.** Chromium 156 (Playwright headless) at 1280×800: title `Ball of Duty`,
  WebGL2 context true, status overlay removed, **0 console errors**. Screenshot:
  [`cp0-web-boot.png`](./cp0-web-boot.png).
- [x] **Pointer lock requires a gesture.** Before click: `document.pointerLockElement === null`; after
  clicking the canvas: `"canvas"`. The controller no longer requests capture in `_ready`.
- [x] **Payload ≤ 20 MB gzipped.** Raw `38,984 KB`; gzip tar `10,028 KB`; `index.wasm` 39.5 MB served as
  `application/wasm`. Local wasm fetch: 197 ms.
- [x] **Linux server export starts without a display.** `build/server/ballofduty-server.x86_64` prints the
  banner + tick probe; no X11.
- [x] **`tools/check.sh` passes** on a clean build (`rm -rf build` at start): import → smoke → client boot →
  server boot → Web export → server export → server binary smoke.
- [~] **CI.** Workflow committed at `.github/workflows/ci.yml`; **first green remote run is deferred until a
  remote exists** (no remote configured in this workspace). Follow-up owner: me, before CP1 is signed off.
- [x] **Version visible.** In-game boot overlay shows `BALL OF DUTY v0.1.0` (from
  `application/config/version`); build SHA recorded here.
- [x] **Collision layers documented** in `docs/ARCHITECTURE.md` and used by the scene files.
- [x] **Grey-box arena** with floor, ramp, walls, crates and 8 spawn markers; ramp collision is a dedicated
  10×0.5×10 m box (review caught a 60×60 m collision slab, fixed).
- [x] **Player skeleton** with capsule body, correctly sized head/body hurtboxes, `Visual` pivot, spring-arm
  camera, 30 Hz movement stub and RMB FOV scope.
- [x] **Input map** (12 actions, physical keycodes) and minimal settings/version stamp.

## Deferred / known deviations

| Item | Reason | Owner / phase |
|---|---|---|
| CI first green run | No git remote configured in this workspace | me, before CP1 sign-off |
| Firefox/Safari verification | Only Chromium available in the sandbox; CP5 owns the full browser matrix | you + me, CP5 |
| WebSocket handshake | Transport intentionally lands in CP4a | me, CP4a |
| Audio buses / autoloads | Not needed for a grey box; added when used (CP1/CP3) | me, CP1/CP3 |

## Review findings absorbed

- Ramp reused the 60×60 floor collision shape → dedicated ramp shape.
- Head hurtbox was a full 1.7 m capsule overlapping the body → sphere r=0.24 at y=1.49; body ends at y=0.
- Shoulder offset on the Camera3D was overwritten by SpringArm3D → offset moved to `CameraPivot`.
- Pointer lock requested at boot without a gesture → capture only from the first click; capture click is consumed.
- Snapshot budget contradiction (1 KB @ 30 Hz vs 10 KB/s) → ≤300 B binary snapshots.
- Interpolation math (100 ms ≠ 2 snapshots) → 2 intervals (67 ms) + jitter, newest-wins.
- CP4a lacked an input path and ack field → minimal 30 Hz input frame + `acked_input_seq` added.
- Client-supplied fire origin, TCP HOL claims, SIGTERM expectations, reconnect semantics, headless CPU spin,
  player collision mask, VRAM compression, PWA isolation headers, warning/error wording — corrected in
  `ROADMAP.md`, `PLAN.md`, `ARCHITECTURE.md` and project settings.
- CP0 boot only ran 5 frames (no physics) → 120 frames at 60 FPS plus a server tick probe.
- Smoke tests now assert hurtbox extents, ramp shape, physics interpolation and player mask.

## Commands

```bash
tools/check.sh
tools/serve.sh            # then open http://127.0.0.1:8099/
tools/godot --headless --path . --script tests/headless/smoke_test.gd
```
