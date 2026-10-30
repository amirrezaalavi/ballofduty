# Browser Matrix & Manual Qualification

**Owner:** L9 (browser matrix + web performance harness)  
**Engine:** Godot 4.7.2, Compatibility / WebGL 2, single-threaded WASM  
**Research:** `docs/research/L9-BROWSER-MATRIX.md`  
**Answer summary:** `docs/research/L9-ANSWER-SUMMARY.md`

This is the operator-facing matrix. CI only proves boot, WebGL 2, console
hygiene, pointer lock and the optional join bridge. Framerate, audio, thermal
and Apple-hardware results are manual and must be recorded with the protocol
below.

---

## 1. Hardware definitions

| ID | Definition | Notes |
|---|---|---|
| **H1** | 2-core / 4-thread low-end laptop, e.g. Intel Core i3-1115G4 with Intel UHD 48EU, 8 GB RAM, 1080p 60 Hz | Worst-case survivable target (~10th percentile of active desktop web players). Record the exact model, RAM, driver and power profile in the run sheet. |
| **H2** | Apple Silicon Mac, M3/M4/M5 class, macOS 26, internal 60 Hz display | Record the exact model, unified-memory size and macOS build. Safari H2 runs must use a clean profile. |

Reference target: H1 should reach **≥ 45 fps at 720p native** and **60 fps at
0.75× render scale (540p)**. H2 is expected to hold 60 fps at native 720p.

---

## 2. Matrix

| Cell | Browser / OS | Hardware | Network | Gate | How it is qualified |
|---|---|---|---|---|---|
| C1 | Chrome / Windows 11 | H1 | LAN | **G0** | manual 3 × 60 s + CI Chromium proxy |
| C2 | Edge / Windows 11 | H1 | LAN | **G0** | manual 3 × 60 s |
| C3 | Firefox / Windows 11 | H1 | LAN | **G0** | manual 3 × 60 s + Firefox/Xvfb proxy |
| C4 | Safari / macOS 26 | H2 | LAN | **G0** | manual 3 × 60 s on real Safari |
| C5 | Chrome / macOS 26 | H2 | LAN | G1 | manual 3 × 60 s |
| C6 | Chrome / Ubuntu 24.04 | CI VM (SwiftShader) | LAN | G2 | `tools/ci/browser_smoke.mjs` (boot only) |
| C7 | Firefox / Ubuntu 24.04 | CI VM (llvmpipe/Xvfb) | LAN | G2 | `browser_smoke.mjs --browser firefox --headed` under Xvfb (documented, not enabled) |
| C8 | Chrome / Android 15+ | Pixel 6a | LAN | G1 (load-only) | manual load; mobile banner must show |
| C9 | Safari / iOS 26 | iPhone 13 | LAN | G1 (load-only) | manual load on real device |
| C10 | Chrome / Windows 11 | H1 | LAN, 1080p canvas | G1 | manual 3 × 60 s |
| C11 | Firefox / Windows 11 | H1 | 100 ms + 1 % loss | **G0** | manual netem run |
| C12 | Chrome / Windows 11 | H1 | 4G profile | G1 | manual throttled run |
| C13 | Safari / macOS 26 | H2 | 100 ms + 1 % loss | G1 | manual netem run |

Gate meanings:

- **G0** — release blocker. A failure stops the release unless the single-browser
  escalation policy applies (engine/upstream regression only; game-code
  regressions are hard blockers).
- **G1** — supported, non-blocking. Record the result; do not block on it.
- **G2** — CI smoke proxy. Never used as framerate or real-GPU evidence.

---

## 3. Manual qualification protocol

### 3.1 Measurement setup

1. Use the **`?perf=1`** URL parameter (or `--perf` for native builds). The
   probe is disabled by default and only reports; it never changes quality.
2. Run **3 consecutive 60-second measurement windows** per cell.
3. Discard the **first 10 seconds** of each run (JIT, WASM tiering, shader
   compilation). The probe does this automatically.
4. Report the **median run's p95 frame time** — not the average and not the best
   run.
5. Run-to-run spread (fastest p95 → slowest p95) must be **< 15 %**. If it is
   ≥ 15 %, discard the set, wait 3 minutes for GPU cool-down, and rerun.
6. A run is **invalidated by thermal throttling** if the average frame time in
   the last 15 seconds is **> 20 % slower** than the first 15 seconds.
7. Environment controls:
   - display zoom 100 %, device pixel ratio locked;
   - Windows power profile "Best Performance", laptop on AC mains;
   - clean/incognito profile, all extensions disabled;
   - ambient temperature 20–24 °C;
   - no other GPU-heavy applications.

### 3.2 Reading the probe

With `?perf=1`, the page exposes:

```js
window.__bod_perf()        // JSON string: frames, fps_avg, frame_ms_p50/p95/p99,
                           // frames_over_33_3ms / 250ms / 500ms, draw_calls,
                           // primitives, js_heap_bytes, warmup_remaining
window.__bod_perf_reset()  // restart the 60 s window and 10 s warm-up
window.__bod_state         // {in_game, phase, class_id, net}
```

`frame_ms_*` are milliseconds. Convert to fps with `1000 / frame_ms`.
`js_heap_bytes` is `null` when `performance.memory` is unavailable (Firefox,
Safari); do not invent a number.

### 3.3 Pass/fail thresholds

| Metric | Target (G0) | Warning (P1) | Blocker (P0) |
|---|---|---|---|
| Cold load | ≤ 3.5 s LAN | 6.0–12.0 s | > 12.0 s |
| First frame | ≤ 5.0 s LAN | 6.0–10.0 s | > 10.0 s or shell crash |
| Frame p95 | ≤ 16.7 ms | 16.8–22.2 ms | > 22.2 ms (< 45 fps) |
| Frame p99 / stalls | p99 ≤ 33 ms, 0 frames > 250 ms | any frame > 250 ms | any frame > 500 ms |
| Average fps | ≥ 55 | 45–54 | < 45 |
| Draw calls / triangles | ≤ 80 / ≤ 250k | 100–150 calls | > 150 calls / > 500k tris |
| Memory | ≤ 512 MB, growth ≤ 10 % | 512–1024 MB | > 1024 MB or crash |
| Pointer lock | clean lock/release | occasional miss on rapid click | fails to lock or drifts |
| Audio | audible after gesture | minor boot crackle | silent or continuous crackle |
| Reconnect | ≤ 3 s | 4–5 s | stuck |
| Input latency | ≤ 100 ms | 150–200 ms | > 200 ms |
| Tab throttling | recovers ≤ 2 s | desync 2–5 s | desync > 5 s or kick |
| Fullscreen | clean resize/lock | mild CSS black bar | broken aspect/unclickable |
| Console errors | 0 uncaught | unhandled WebGL warnings | any uncaught JS/WASM error |

### 3.4 Quality levers (manual only)

The user chooses LOW / MEDIUM / HIGH in the L6 settings panel. That maps to:

| Tier | 3D scale | Directional shadow atlas |
|---|---|---|
| LOW | 0.7 | 1024 |
| MEDIUM | 0.85 | 2048 |
| HIGH | 1.0 | 4096 |

There is **no automatic quality switching** and no dynamic hysteresis. A future
hysteresis engine is deferred; it must not mutate settings without an explicit
product decision.

MSAA is not a lever. Directional shadow distance is a project setting read at
startup, so it is not changed at runtime.

---

## 4. Tab throttling and reconnect

The only client-side mitigation is input suppression: while `document.hidden`
is true, `InputHandler.sample()` returns a neutral frame (no movement, jump,
fire, aim or reload). Reconnection uses the existing 8 s grace in
`NetworkManager`.

There is **no** `CMD_RESYNC`, no full-snapshot request and no new packet. If a
tab stays hidden past the grace, the client can be disconnected; if it returns
inside the grace, prediction divergence is possible until the next snapshot
reconciliation. Record this as a known gap rather than treating it as a new
protocol feature.

---

## 5. Automated vs manual checklist

Automated (CI, Chromium; Firefox/Xvfb documented but disabled):

- [ ] `#canvas` visible and `#boot` detached within 30 s.
- [ ] `canvas.getContext('webgl2')` returns a version string.
- [ ] no non-harmless console errors or pageerrors.
- [ ] pointer lock acquired (warning only if refused).
- [ ] optional `?join=1&perf=1`: `window.__bod_state.in_game === true`.

Manual (must be signed off per release):

- [ ] C1, C2, C3, C11 on H1.
- [ ] C4 on H2 Safari.
- [ ] C5, C10, C12 on the listed hardware.
- [ ] C8, C9 load-only on real devices.
- [ ] C13 loss run on H2.
- [ ] 3 × 60 s protocol, median p95, < 15 % spread, thermal invalidation.
- [ ] Audio after gesture on headphones.
- [ ] Fullscreen/resize and pointer-lock drift.

---

## 6. Evidence naming

Automated smoke:

```
artifacts/browser-smoke/
├── metrics_chromium.json
├── console_chromium.log
└── screenshot_chromium.png
```

Release audit (copy per cell):

```
docs/ci/audit/
├── MANIFEST.json
├── C1_Win11_Chrome_metrics.json
├── C1_Win11_Chrome_console.log
├── C1_Win11_Chrome_snap.png
├── C3_Win11_Firefox_metrics.json
├── C3_Win11_Firefox_console.log
├── C4_macOS_Safari_metrics.json
├── C4_macOS_Safari_console.log
└── server_soak_30hz.log
```

Do not put SwiftShader/Linux-WebKit numbers in a G0 row. They are C6/C7 (G2)
evidence only.
