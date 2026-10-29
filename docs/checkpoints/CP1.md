# CP1 — Movement, camera & feel

> **Post-playtest note (CP4b):** walk/sprint were later retuned to **1.0 / 2.5 m/s** for the 0.82 m
> avatar. The numbers below are the original CP1 measurements and remain as accepted history.

- **Date:** 2026-10-28
- **Build:** `34b354e` (feedback revision: smaller avatar, higher jump)
- **Engine:** Godot 4.7.2-stable, Compatibility, 30 Hz physics + physics interpolation
- **Status:** **accepted by user** (2026-10-28)

## Automated acceptance evidence

| Criterion | Result | Evidence |
|---|---|---|
| Fixed 30 Hz simulation | pass | `smoke_test.gd`: physics tick = 30, interpolation on |
| 3 s travel distance | **16.63 m** | `movement_test.gd` (90 ticks, from rest) |
| No diagonal speed boost | cardinal **5.60** / diagonal **5.60 m/s** | `movement_test.gd` |
| Sprint | **7.56 m/s** (5.6 × 1.35) | `movement_test.gd` |
| Jump apex | **1.35 m** (+10 % from 1.23 m) | `movement_test.gd` |
| Coyote time (0.10 s) | pass | jump one tick after leaving floor |
| Jump buffer (0.12 s) | pass | jump fires on landing |
| Release deceleration | stops in < 0.2 s | 60 m/s² ground acceleration |
| Settings persistence | pass | sensitivity / invert-Y / volume round-trip through `user://` |
| InputMap only | pass | no `Input.is_key_pressed`; only the mouse-capture gesture uses a raw button |
| Character size | **1.36 m** capsule / mesh (20 % smaller) | `smoke_test.gd` |
| Components present | pass | Locomotion, InputHandler, Health, CameraRig, DebugOverlay (62 smoke checks) |
| Web boot | pass | 0 console errors, pointer lock after click, debug overlay renders |
| Full pipeline | pass | 62 smoke + 14 movement checks, Web + Linux server exports, gzip **10,042 KB** |

Screenshot: [`cp1-debug-overlay.png`](./cp1-debug-overlay.png) (headless Chromium).

## User feel test (accepted)

1. **Mouse-look feel at 144 Hz** — no 30 Hz stepping.
2. **Camera**: distance (3.6 m), shoulder offset (0.55 m), height (1.55 m).
3. **Camera collision** — walk behind the brown `CameraWall` at `(-9, 1.5, -14)`; the spring arm must shorten without clipping.
4. **Ramp/fall-through** — walk down the ramp; no fall-through at 30 FPS.
5. **Platform gap** — jump the 2 m gap between the two 0.8 m platforms at `(12, -6)` and `(12, -12)`.
6. **Scope** — hold RMB: FOV 75 → 55 in ~70 ms, sensitivity scales to 0.7×.
7. **Movement feel**: 5.6 m/s walk, 7.56 sprint, **1.35 m jump**, 0.12 s jump buffer, 0.10 s coyote — on a **1.36 m** character.

## How to test

```bash
# desktop (recommended for feel)
tools/godot --path .

# or the exported web build
tools/check.sh
tools/serve.sh          # http://127.0.0.1:8099
```

Click the canvas to capture the mouse. `F3` toggles diagnostics (FPS, physics tick, speed, seq,
camera distance, FOV). `Esc` releases the mouse.

## Tuning knobs (no recompile, no magic numbers in scripts)

| Knob | File | Current |
|---|---|---|
| Walk/sprint/jump/gravity/coyote/buffer | `resources/players/default_player.tres` | 5.6 / 1.35× / **7.34** / 22 / 0.10 / 0.12 |
| Spring length, FOV, scope FOV, pitch clamp | `scenes/characters/player.tscn` → `CameraPivot` | 3.6 / 75 / 55 / 1.35–0.95 |
| Character capsule/mesh/hurtboxes | `scenes/characters/player.tscn` | 1.36 m, r 0.32 (0.8×) |
| Shoulder offset, camera height | `CameraPivot` transform | x 0.55, y 1.55 |
| Sensitivity / invert / scope scale | `user://settings.cfg` via `Settings` | 0.0022 / off / 0.7 |

Accepted as-is; tuning requests are tracked in `docs/BACKLOG.md`. Reply with numbers to change (e.g. “camera 4.2 m, shoulder 0.7, FOV 80, speed 6.0”) and I
will tune the resources, rebuild, and re-check. A video/screenshot of the bad feel is even better.

## Notes / deviations

- Headless Chromium renders with software rasterization (≈11 FPS shown in the screenshot). That is the
  sandbox GPU, not a game budget measurement; real Chrome/desktop is the feel target.
- The Settings autoload exists and persists, but the in-game settings UI is CP5. Change values in
  `user://settings.cfg` or via code for now.
- Camera pitch is clamped to [-1.35, 0.95]; no camera shake yet.
- The full browser matrix (Firefox/Safari) remains CP5.
- Camera framing was intentionally **not** changed with the avatar shrink, so the size change can be judged on its own.
- Feedback and follow-ups are tracked in [`../BACKLOG.md`](../BACKLOG.md); jump floatiness and final map scale are recorded there, not silently changed.
