# L9 Answer Summary — Browser Matrix & Web Performance Harness

**Branch:** `feature/l9-browser-matrix`  
**Engine:** Godot 4.7.2, Compatibility / WebGL 2, single-threaded WASM  
**Research input:** `docs/research/L9-BROWSER-MATRIX.md`  
**Status:** implementation complete for the CI-testable surface; real-GPU,
Safari/iOS and thermal evidence remain manual.

---

## 1. Decisions adopted

| Decision | Implementation |
|---|---|
| Browser matrix is 13 cells with G0/G1/G2 gates | `docs/ci/BROWSER-MATRIX.md` |
| CI proves boot/WebGL 2/console/pointer lock, never framerate | `tools/ci/browser_smoke.mjs` |
| Firefox CI needs Xvfb + software-WebRender prefs | documented in `tools/ci/README.md`; not enabled until a green manual run |
| WebKit-on-Linux is a layout smoke test, not Safari | documented; never used to mark C4/C9 |
| Performance probe is opt-in (`?perf=1` / `--perf`) | `scripts/autoload/perf_probe.gd` |
| 10 s warm-up, 60 s window, preallocated ring | `perf_probe.gd` (`WARMUP_FRAMES`, `WINDOW_FRAMES`) |
| Quality stays a manual user choice (L6 lock) | no auto switching; probe only reports |
| No MSAA toggle, no runtime shadow-distance lever | only 3D scale + shadow atlas are used by L6 |
| No protocol changes / no resync packet | tab throttling is handled client-side only |
| No headshot or gameplay changes | untouched |

### Tab-throttle mitigation (the only permitted form)

`scripts/components/input_handler.gd` polls `document.hidden` at 4 Hz and returns
a neutral input frame (no movement, jump, fire, aim or reload) while the tab is
hidden. Reconnection still relies on the existing 8 s grace in
`scripts/networking/network_manager.gd`.

**Gap:** there is no `CMD_RESYNC` and no full-snapshot resync. A client that is
hidden for longer than the grace can still be disconnected; a client that
returns inside the grace may show prediction divergence until the next snapshot
reconciliation. This is accepted and documented rather than hidden behind a new
protocol command.

---

## 2. The 13-cell matrix

Gate definitions: **G0** = release blocker, **G1** = supported but
non-blocking, **G2** = CI smoke proxy only (never framerate evidence).

| Cell | Browser / OS | Hardware | Network | Gate | Evidence path |
|---|---|---|---|---|---|
| C1 | Chrome / Windows 11 | H1 | LAN | **G0** | manual H1 run + CI Chromium proxy |
| C2 | Edge / Windows 11 | H1 | LAN | **G0** | manual H1 run (no duplicate CI job) |
| C3 | Firefox / Windows 11 | H1 | LAN | **G0** | manual H1 run + Firefox/Xvfb proxy |
| C4 | Safari / macOS 26 | H2 | LAN | **G0** | manual H2 run only |
| C5 | Chrome / macOS 26 | H2 | LAN | G1 | manual H2 run |
| C6 | Chrome / Ubuntu 24.04 | CI VM (SwiftShader) | LAN | G2 | `browser_smoke.mjs --browser chromium` |
| C7 | Firefox / Ubuntu 24.04 | CI VM (llvmpipe/Xvfb) | LAN | G2 | `browser_smoke.mjs --browser firefox --headed` under Xvfb (documented, not enabled) |
| C8 | Chrome / Android 15+ | Pixel 6a | LAN | G1 (load-only) | manual load test; mobile banner |
| C9 | Safari / iOS 26 | iPhone 13 | LAN | G1 (load-only) | manual load test on real device |
| C10 | Chrome / Windows 11 | H1 | LAN, 1080p canvas | G1 | manual H1 run |
| C11 | Firefox / Windows 11 | H1 | 100 ms + 1 % loss | **G0** | manual netem/loss run |
| C12 | Chrome / Windows 11 | H1 | 4G profile | G1 | manual throttled run |
| C13 | Safari / macOS 26 | H2 | 100 ms + 1 % loss | G1 | manual H2 run |

CI does **not** cover C1–C5, C8–C13. It covers the boot/console/pointer-lock
subset of C6, and C7 only when the Xvfb path is enabled after a green manual
pass.

---

## 3. Minimum supported browser versions

| Browser | Minimum | Why |
|---|---|---|
| Chrome / Chromium | **114+** | WebAssembly SIMD, AudioWorklet, stable WebGL 2 context creation |
| Edge | **114+** | tracks the Chromium milestone |
| Firefox | **115 ESR+** | SpiderMonkey WASM growth, WebGL 2 float colour buffers, pointer lock |
| Safari (desktop) | **16.4+** | WebGL 2 depth textures, AudioWorklet stability, OffscreenCanvas |
| iOS Safari | **16.4+** | same WebKit core as desktop 16.4 |
| Android Chrome | **114+** on Android 10+ | GLES 3.0 driver compliance |

---

## 4. What CI gates vs what stays manual

| Capability | CI gate | Manual |
|---|---|---|
| Cold boot to menu (`#boot` detached) | **Yes** — Chromium, 30 s budget | H1 battery cold start |
| WebGL 2 context | **Yes** — `canvas.getContext('webgl2')` version string | real GPU renderer strings |
| Console error budget | **Yes** — non-harmless errors fail | visual driver artefacts |
| Pointer Lock acquire | **Warning only** — headless Chromium often refuses | physical mouse drift / high-DPI flick |
| WebSocket join + in-match bridge | **Optional** — `?join=1&perf=1` | real loss/reconnect |
| 60 fps / p95 / stalls | **No** — software GPUs are noise | **Yes**, 3 × 60 s on H1/H2 |
| Audio playback | **No** — synthetic contexts mask clicks | **Yes**, headphones |
| Thermal throttling | **No** | **Yes**, 10 min soak |
| Safari / iOS | **No** — Linux WebKit is not Safari | **Yes**, real Apple hardware |

---

## 5. Artifact manifest

Per automated run (`tools/ci/browser_smoke.mjs --out <dir>`):

```
<dir>/
├── metrics_<browser>.json    # boot ms, first-frame ms, console counts,
│                             # WebGL version, pointer lock, in_match,
│                             # __bod_state, fps_p50/p95/p99 when available
├── console_<browser>.log     # every console message + pageerror, [harmless] tagged
└── screenshot_<browser>.png  # viewport screenshot after boot/join
```

For a CP5 release audit, copy those three files per cell into
`docs/ci/audit/` together with:

```
MANIFEST.json                 # git hash, engine version, timestamp
C1_Win11_Chrome_metrics.json
C1_Win11_Chrome_console.log
C1_Win11_Chrome_snap.png
C3_Win11_Firefox_metrics.json
C3_Win11_Firefox_console.log
C4_macOS_Safari_metrics.json
C4_macOS_Safari_console.log
server_soak_30hz.log
```

The automated `fps_*` fields stay `null` until the probe's 10 s warm-up has
passed; a smoke run is not a framerate measurement.

---

## 6. Local sandbox evidence (commands actually run)

All values below come from this workspace. No real-GPU, Safari or iOS claim is
made.

```bash
./tools/gdcheck.sh scripts/autoload/perf_probe.gd tests/gdunit/test_perf_probe.gd
# ok   scripts/autoload/perf_probe.gd
# ok   tests/gdunit/test_perf_probe.gd

timeout 600 ./tools/godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
  -a tests/gdunit/test_perf_probe.gd -a tests/gdunit/test_settings_ui.gd \
  -a tests/gdunit/test_smoke.gd -c --ignoreHeadlessMode
# Overall Summary: 21 test cases | 0 errors | 0 failures | ... | Exit code: 0

timeout 1800 ./tools/check.sh --skip-export
# Overall Summary: 170 test cases | 0 errors | 0 failures | ... | Exit code: 0
# QUARRY_WALK ... result=PASS
# QUARRY_MATCH result=PASS ...
# NET16 ... result=PASS ...
```

Web export and shell checks:

```bash
mkdir -p build/web
./tools/godot --headless --path . --export-release "Web" build/web/index.html
grep -c "Graphics Acceleration Required" build/web/index.html   # 1
grep -c "mobile-banner" build/web/index.html                    # 7
grep -c "lock-hint" build/web/index.html                        # 4
grep -c "unlockAudio" build/web/index.html                      # 3
grep -c "snapCanvasToViewport" build/web/index.html             # 3
```

Chromium smoke, plain boot (software WebGL, headless):

```bash
node tools/ci/browser_smoke.mjs \
  --url http://127.0.0.1:8099/index.html \
  --browser chromium --out artifacts/browser-smoke
# boot_ms: 8810
# webgl: WebGL 2.0 (OpenGL ES 3.0 Chromium)
# pointer_lock: false   (reported as a warning, not a failure)
# console: 0 errors, 4 warnings, 0 harmless
```

Chromium smoke with the join bridge:

```bash
node tools/ci/browser_smoke.mjs \
  --url "http://127.0.0.1:8099/index.html?join=1&perf=1" \
  --browser chromium --out artifacts/browser-smoke-join
# boot_ms: 8748
# pointer_lock: true
# in_match: true
# console: 0 errors, 4 warnings, 0 harmless
```

The four warnings were Chromium's `GPU stall due to ReadPixels` driver messages;
they are not in the research doc's harmless list and do not fail the run.

WebGL 2 fallback and mobile banner were checked with a throwaway Playwright
script:

```js
// --disable-webgl / --disable-webgl2 / --disable-3d-apis
// card: "GRAPHICS ACCELERATION REQUIRED" + WebGL 2.0 body text, #boot retained
// hasTouch: true, 390x844
// banner: "Desktop browser recommended — keyboard and mouse required. Load-only on mobile."
```

**Not run here:** Firefox (no Xvfb/display), WebKit (not installed), real GPU,
Safari, iOS, Android, thermal soak, packet-loss runs.

---

## 7. Rejected / deferred

**Rejected (do not implement):**

- `CMD_RESYNC`, any new packet, or any new snapshot field.
- Automatic quality switching / dynamic hysteresis that mutates settings.
- MSAA toggle.
- Runtime directional shadow-distance changes (project setting read at startup).
- Headshot or any gameplay change.
- Claiming Safari/iOS/real-GPU results from Playwright WebKit on Linux.
- Fabricated metrics; every number in this document is from a command above.

**Deferred:**

- Dynamic quality hysteresis (downgrade/upgrade windows, anti-oscillation lock).
  The user still chooses LOW/MEDIUM/HIGH in L6.
- Enabling Firefox/Xvfb in `ci.yml` (needs a green manual `xvfb-run` pass).
- Playwright WebKit CI job.
- BrowserStack or self-hosted H1 runner.
- `PerformanceObserver("longtask")` — Firefox/Safari do not support it; the probe
  uses frame-time deltas instead.
- WASM heap sampling — `WebAssembly.Memory` is not reachable from GDScript; the
  probe reports `performance.memory.usedJSHeapSize` when present, otherwise
  `null`.

---

## 8. Still needs a human with real hardware

1. C1–C5, C10–C13 on H1 (Windows low-end laptop) and H2 (Apple Silicon Mac).
2. C4/C9 on real Safari macOS/iOS, including AudioContext gesture policy and
   Jetsam memory limits.
3. C8 on a real Pixel 6a (load-only).
4. C11/C13 packet-loss runs with `tc netem`.
5. Thermal soak (10 minutes) and the 3 × 60 s median-p95 protocol.
6. A green Firefox/Xvfb CI feasibility run before that job is enabled.
