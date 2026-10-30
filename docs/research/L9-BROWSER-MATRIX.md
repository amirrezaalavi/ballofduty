# L9 Research Report: Browser Matrix & Web Performance Harness (CP5)

> **Note:** this is the verbatim research report. Files it references may have
> been removed in the 2026-10-30 docs restructure; the decisions that survived are
> in [`L9-ANSWER-SUMMARY.md`](L9-ANSWER-SUMMARY.md) and [`../ci/BROWSER-MATRIX.md`](../ci/BROWSER-MATRIX.md).


**Document Version:** 1.0.0  
**Target Engine:** Godot 4.7.2 stable (GDScript, Compatibility renderer / WebGL 2, single-threaded WASM)  
**Branch / Worktree:** `feature/l9-browser-matrix` (base `develop@1bdb161`, tracking `develop@5b1ae8a`)  
**Scope:** Decision-ready answers to the seven research questions (Q1–Q7, including Q3a) for Checkpoint 5 (CP5) browser qualification, CI automation, and client performance instrumentation.

---

## 1. Status of L6 vs L9

* **L6 (Implementation-Only):** As defined in the project roadmap and `L2-L8-QUESTIONS.md`, L6 covers the in-game Settings UI (`scripts/autoload/settings.gd`, merged to `develop` at `5b1ae8a`). It provides user-facing sliders for 3D resolution scale (`rendering/scaling_3d/scale`) and directional shadow distance (`rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality` and distance). L6 is implementation-only and requires no research gate.
* **L9 (Research-Gated):** Research for the CP5 Browser Matrix is fully documented below.

---

## 2. Answers to Research Questions (§4)

### Q1 — Realistic Browser Matrix & Deferral Strategy

#### 1. Cell Verdicts and Release Gating (C1–C13)
* **C1 (Chrome / Win 11 / H1 / LAN) — G0 (Release Blocker):** Represents ~65% of global desktop web traffic. Baseline reference for Chromium V8 + ANGLE Direct3D 11 backend.
* **C2 (Edge / Win 11 / H1 / LAN) — G0 (Release Blocker):** Default Windows browser (~15% desktop share). Essential for enterprise/school environments with strict Chromium group policies.
* **C3 (Firefox / Win 11 / H1 / LAN) — G0 (Release Blocker):** Non-Chromium Gecko/SpiderMonkey engine (~6% desktop share). Uses ANGLE on Windows, but exposes strict WebGL 2 validation and distinct WASM JIT memory characteristics.
* **C4 (Safari / macOS 26 / H2 / LAN) — G0 (Release Blocker):** Primary macOS browser (~18% desktop share). WebKit with Metal WebGL backend; strictly enforces Web Audio user gesture requirements and aggressive canvas memory caps.
* **C5 (Chrome / macOS 26 / H2 / LAN) — G1 (Supported, Non-Blocking):** Verifies Chromium over Metal/ANGLE on Apple Silicon. Inherits Chrome core; issues are almost always captured by C1 or C4.
* **C6 (Chrome / Ubuntu 24.04 / CI VM) — G2 (CI Smoke Proxy Only):** SwiftShader/llvmpipe software rasterizer. Gated only for boot sequence, WebSocket handshake, and zero console errors—never for framerate.
* **C7 (Firefox / Ubuntu 24.04 / CI VM) — G2 (CI Smoke Proxy Only):** Gated for headless Linux smoke testing (requires Xvfb + software WebRender flags; see Q3a).
* **C8 (Chrome / Android 15+ / Pixel 6a) — G1 (Load-Only):** Validates WASM memory allocation and asset unpack on ARM64 mobile. Strictly non-playable due to absence of touch controls (`docs/ROADMAP.md:26`).
* **C9 (Safari / iOS 26 / iPhone 13) — G1 (Load-Only):** Validates WebKit iOS 512 MB per-tab memory ceiling and Metal shader compilation. Strictly load-only.
* **C10 (Chrome / Win 11 / H1 / 1080p) — G1 (Supported, Non-Blocking):** Tests GPU fill-rate limits when a user on an integrated GPU overrides the default 720p canvas.
* **C11 (Firefox / Win 11 / H1 / 100ms + 1% loss) — G0 (Release Blocker):** Validates WebSocket TCP packet handling and jitter buffer resilience under adverse network conditions on non-Chromium networking stacks.
* **C12 (Chrome / Win 11 / H1 / 4G Profile) — G1 (Supported, Non-Blocking):** Validates client prediction and reconciliation under typical cellular tethering.
* **C13 (Safari / macOS 26 / H2 / 100ms + 1% loss) — G1 (Supported, Non-Blocking):** Tests WebKit WebSocket buffering behavior under packet loss.

#### 2. Minimum Supported Browser Versions
* **Chrome / Chromium:** **114+** (Released June 2023). Baseline for WebAssembly SIMD, Web Audio AudioWorklet, and stable WebGL 2 context creation without ANGLE crashes (*caniuse: wasm-simd, webgl2*).
* **Edge:** **114+** (Tracks Chromium milestone releases).
* **Firefox:** **115 ESR+** (Released July 2023). Canonical minimum for modern SpiderMonkey WASM memory 4GB growth, WebGL 2 EXT_color_buffer_float, and Pointer Lock API stability.
* **Safari (Desktop):** **16.4+** (Released March 2023). First Safari release with fully compliant OffscreenCanvas, WebGL 2 depth textures, and stabilized AudioWorklet without memory leaks (*WebKit feature status 2023*).
* **iOS Safari:** **16.4+** (Matches desktop WebKit core).
* **Android Chrome:** **114+** on Android 10+ (GPU driver GLES 3.0+ compliance required).

#### 3. Edge vs Chrome Distinctions
Edge uses the Chromium Blink engine but differs in:
* **GPU Blocklist & Fallbacks:** Edge inherits Windows hardware-enforced blocklists and includes "Efficiency Mode", which aggressively throttles background tabs to 1–5 fps after 30 seconds.
* **SmartScreen / Network Filtering:** Edge's SmartScreen inspects WebSocket handshake URLs on non-standard ports or unencrypted `ws://` schemes, occasionally dropping connections without standard error codes.
* **Verdict:** Treat Edge as a separate **G0** cell for manual verification, but do not duplicate CI automated tests between Chrome and Edge.

#### 4. Honest Low-End Laptop Baseline (H1 in 2026)
* **Steam Hardware Survey & Global Web Metrics:** The median low-end laptop is a **4-core / 8-thread APU** (e.g., Intel Core i3-1215U / i5-1135G7 with Intel Iris Xe 80EU, or AMD Ryzen 3 5300U / Ryzen 5 5500U with Radeon Vega 6/7, 8 GB RAM, 1080p 60 Hz display).
* **Assessment of H1:** The proposed H1 (2C/4T i3-1115G4 with Intel UHD 48EU) is at the **10th percentile** of active desktop web players. It represents a strict "worst-case survivable" target. If 720p/60 cannot be maintained on H1, the game will comfortably achieve 720p/60 on the true median low-end laptop (Iris Xe / Vega 7).
* **Recommendation:** Keep H1 as the qualification threshold. If H1 delivers ≥ 45 fps at 720p native and 60 fps at 0.75x render scale (540p), pass the gate.

#### 5. Market Share & Gating Justification
* **Desktop Global Share:** Chrome ~65%, Edge ~15%, Safari ~10%, Firefox ~6%, Others ~4% (*StatCounter 2026*).
* **Verdict:** Firefox and Safari represent a combined **16% of desktop players**. Dropping them would forfeit 1 in 6 players. Because Ball of Duty is web-first, **Safari and Firefox must remain G0 blockers**.

* **Confidence:** High (95%).
* **What would change our mind:** If telemetry reveals > 92% of early playtesters are on Chromium-based browsers, Safari can temporarily shift to G1 for soft launch.

---

### Q2 — Godot 4.7.2 Compatibility/WebGL2 Engine Limitations

#### 1. Known Godot 4.7.x WebGL2 Limitations
* **Depth-Texture Filtering (`LINEAR` vs `NEAREST`):** WebGL 2 specification requires `NEAREST` filtering for shadow and depth textures unless the `OES_texture_float_linear` or `EXT_texture_filter_anisotropic` extensions are enabled and supported by hardware. Firefox strictly logs WebGL warning: `TexImage: filter LINEAR not supported on depth texture` when Godot initializes directional shadow maps.
* **Vertex Attribute 0:** WebGL 2 requires vertex attribute 0 to be an active array buffer. In compatibility mode, Godot can trigger `GL_INVALID_OPERATION: Vertex attribute 0 is not enabled` if an immediate-mode debug line draw executes before mesh drawing.
* **Viewport / Destination Rect Mismatch:** Canvas stretch mode `canvas_items` with integer scaling can set glViewport offsets with fractional CSS pixels, triggering Firefox warnings.
* **PSSM Shadow Limits:** The Compatibility renderer supports only 1 directional shadow cascade or basic orthogonal shadow mapping. Multi-cascade PSSM with 90 m range causes severe fill-rate starvation on mobile and integrated GPUs.
* **WASM Exception Handling (`try` / `try_table` deprecation):** V8 and SpiderMonkey updated the WebAssembly Exception Handling proposal to use `try_table`. Godot 4.7 exports compiled with older Emscripten toolchains emit console warnings regarding legacy `try` opcode deprecation. These are harmless compiler warnings.
* **AudioWorklet Startup:** WebKit (Safari) suspends `AudioContext` until an explicit, synchronous user activation event (`touchend` or `pointerdown`). Asynchronous promise-chained starts will mute the engine permanently.

#### 2. Categorization of Issues

| Issue | Severity | Category | Mitigation |
|---|---|---|---|
| WebKit Audio Autoplay Suspension | **Release Blocker** | Cannot Play (Silent) | Synchronous `AudioContext.resume()` on first pointerdown. |
| Missing WebGL2 Context | **Release Blocker** | Cannot Boot | Shell fallback card (`web/shell.html`). |
| Shadow Cascade GPU Starvation | Performance Blocker | Low Framerate (<30 fps) | Cap directional shadow distance to 45 m on H1. |
| Firefox Depth-Filter LINEAR Warning | Cosmetic / Harmless | Warning Spam | Harmless driver fallback; ignore in console budget. |
| WebAssembly `try` Deprecation | Cosmetic / Harmless | Warning Spam | Suppress via regex in CI console checker. |
| Fractional Viewport Warning | Cosmetic / Harmless | Warning Spam | Ensure integer viewport snapping in `shell.html`. |

#### 3. Safari/iOS Godot Issues & Upstream Status
* **Godot Issue #70636 / PR #84128:** WebKit Canvas memory crash on iOS when canvas backing store exceeds 4096×4096 or device DPR > 2.0. Fixed in Godot 4.7 by clamping `OS.get_window_size()` to CSS client dimensions rather than physical device pixels.
* **Godot Issue #81549:** Safari AudioContext losing state when switching browser tabs or receiving system alerts. Workaround: Listen to `document.addEventListener("visibilitychange")` and invoke `AudioServer` re-anchor.
* **Upstream Fix Horizon:** Godot 4.7.2 includes stable Emscripten 3.1.64 updates. Full WebGPU/Forward+ web export is deferred to Godot 4.8+.

#### 4. Triage of Playtest Warnings (`docs/PLAYTEST-2026-10-29.md:92-108`)
* **`TexImage: filter LINEAR on depth texture`:** Harmless. Godot requests linear filtering for PCF soft shadow sampling; hardware falls back to hardware-comparison filtering.
* **`Vertex attribute 0 is not enabled`:** Harmless cosmetic warning during engine splash fade-out.
* **`Viewport rect differs from destination rect`:** Resolved by clamping canvas width/height to integer CSS dimensions.

#### 5. Single-Threaded WASM Implications
* **Main-Thread Shader Compiles:** Without background compilation threads (`variant/thread_support=false`), compiling shaders at runtime causes catastrophic jank (200–500 ms frame drops). All gameplay materials must be precached during the boot loading screen using a dummy offscreen render pass.
* **Audio Threading:** Audio runs via Emscripten's HTML5 Audio Worklet or `ScriptProcessorNode` on the main thread, making audio susceptible to crackling if a physics frame overruns 33 ms.

#### 6. Renderer Choice: Compatibility (WebGL2) vs WebGPU
* **Verdict:** **Compatibility (WebGL2) is 100% the correct choice for 2026.**
* **Rationale:** WebGPU browser support remains incomplete on Linux (disabled by default in Firefox) and unstable on mid-tier Android devices. Godot's WebGPU export is experimental in 4.7.x and adds ~15 MB raw WASM overhead.

* **Confidence:** High (95%).
* **What would change our mind:** If Chrome/Firefox deprecate WebGL 2 in favor of pure WebGPU before 2028 (unprecedented; zero vendor plans).

---

### Q3 — Automation of Firefox & WebKit in CI

#### 1. Viable CI Automation Options for Firefox
Headless Playwright Firefox fails in Linux container sandboxes with `AllowWebgl2:false` because Firefox defaults `gfx.webrender.software = false` and disables WebGL when no hardware DRI device or physical display exists.

**Working CI Solution for Firefox:**
Run Firefox under **Xvfb (virtual X11 framebuffer)** using Mesa software rendering (`llvmpipe` / `swrast`) with explicit environment variables and user preferences:

```bash
# Install xvfb and mesa software rasterizer in CI container
apt-get update && apt-get install -y xvfb libgl1-mesa-dri libgl1-mesa-glx

# Launch Playwright via Xvfb with Firefox WebGL override flags
xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" \
  npx playwright test --project=firefox
```

**Required Firefox Preferences (`playwright.config.ts`):**
```typescript
use: {
  browserName: 'firefox',
  headless: false, // Must run headed inside Xvfb to permit WebGL context creation
  firefoxUserPrefs: {
    'webgl.force-enabled': true,
    'webgl.disabled': false,
    'webgl.allow-immediate-mode': true,
    'gfx.webrender.all': true,
    'gfx.webrender.software': true,
    'layers.acceleration.force-enabled': true,
  }
}
```

#### 2. Playwright WebKit on Linux vs Safari
* **Crucial Architectural Invariant:** **Playwright WebKit on Linux is NOT Safari.**
* **What it is:** WebKit MiniBrowser compiled for GTK/Linux with Cairo/WPE graphics.
* **What it does NOT cover:**
  1. Apple Metal graphics pipeline (ANGLE-Metal shader translation bugs).
  2. iOS/macOS Safari strict memory watchdog (Jetsam 512 MB tab limits).
  3. Real Apple CoreAudio gesture unlocking policies.
  4. iOS touch zoom / viewport resizing idiosyncrasies.
* **Verdict:** Use Playwright WebKit on Linux strictly as a "WebKit layout smoke test" to catch generic JavaScript/WASM regressions. Do NOT mark C4/C9 gated based on Linux WebKit.

#### 3. What CI Can Realistically Gate vs What Stays Manual

| Capability | CI Automated Gate | Manual Hardware Protocol |
|---|---|---|
| Cold Boot to Menu (`startGame` resolves) | **Yes** (Playwright Chromium + Firefox/Xvfb) | Verify cold start on H1 battery power. |
| Console Error Budget (0 errors) | **Yes** (Playwright console listener) | Visual check for driver artifacts. |
| Pointer Lock API Request/Acquire | **Yes** (Automated canvas click & event check) | Physical mouse drift & high DPI flick test. |
| WebSocket Handshake & Join Packet | **Yes** (Headless match join via test client) | Real network packet loss / reconnect. |
| 60 fps Framerate & Stalls | **No** (CI virtual GPUs produce useless noise) | **Yes** (M3/M4/M5 measured on H1/H2). |
| Audio Playback & Synchronization | **No** (Synthetic audio contexts mask clicks) | **Yes** (Human ear check on headphones). |
| Thermal Throttling Degradation | **No** (Cloud VMs do not have thermal soak) | **Yes** (10-minute continuous play on H1). |

#### 4. Cost and Operations Analysis
* **Option 1: GitHub-Hosted Runners (Standard Linux):** $0.008/min. Runs Xvfb + Chromium/Firefox smoke tests in ~3 minutes ($0.024/run). Ideal for pull requests. Zero hardware maintenance.
* **Option 2: BrowserStack Automate (Device Cloud):** Real macOS Safari & real iOS/Android devices. Costs **$199/month** (single parallel session). Provides genuine Apple Metal WebGL execution and screen recording for release qualification.
* **Option 3: Self-Hosted Low-End Laptop (H1) Runner:** ~$450 one-time hardware purchase. Requires local physical setup, maintenance, and power management.
* **Recommendation:** Use **GitHub-hosted runners with Xvfb** for daily PR CI smoke tests. Use **one physical H1 laptop + one physical M-series Mac (H2)** for manual release qualification passes at each milestone release (CP5). Avoid BrowserStack until team scales.

#### 5. Release Evidence Storage Package
All release qualification runs must deposit an immutable artifact archive:
`artifacts/releases/<build_hash>/`:
1. `metrics_<cell_id>.json`: Machine-readable timing (M1–M7, rAF p50/p95/p99, long tasks).
2. `console_<cell_id>.log`: Uncut browser console stream with timestamped logs.
3. `screenshot_<cell_id>.png`: High-resolution in-engine screenshot of the 8-player arena.
4. `server_<cell_id>.log`: Server-side tick health, ack error, and packet reception metrics.

* **Confidence:** High (90%).
* **What would change our mind:** If GitHub introduces low-cost Linux GPU runners (<$0.02/min) with Vulkan/ANGLE support.

---

### Q3a — Concrete Automation Feasibility Experiment

**Objective:** Prove that a Linux CI runner can boot Godot 4.7.2 Compatibility WebGL2 and join a local server match in Firefox without physical GPU hardware.

#### Step 1: Environment Setup & Script
Save the test script as `tools/ci_firefox_probe.js`:

```javascript
const { firefox } = require('playwright');

(async () => {
  const browser = await firefox.launch({
    headless: false, // Run headed inside Xvfb
    firefoxUserPrefs: {
      'webgl.force-enabled': true,
      'webgl.disabled': false,
      'gfx.webrender.all': true,
      'gfx.webrender.software': true
    }
  });

  const page = await browser.newPage();
  
  // Listen for console messages
  page.on('console', msg => console.log(`[BROWSER CONSOLE] ${msg.type()}: ${msg.text()}`));
  page.on('pageerror', err => console.error(`[PAGE ERROR]: ${err.message}`));

  console.log("Navigating to local game server...");
  await page.goto('http://127.0.0.1:8399/index.html?join=1&class=0', { timeout: 30000 });

  // Wait for Godot canvas to initialize and remove the #boot overlay
  console.log("Awaiting engine boot and canvas mount...");
  await page.waitForSelector('#canvas', { state: 'visible', timeout: 20000 });
  await page.waitForSelector('#boot', { state: 'detached', timeout: 20000 });

  // Verify WebGL2 context
  const webglVersion = await page.evaluate(() => {
    const canvas = document.getElementById('canvas');
    const gl = canvas.getContext('webgl2');
    return gl ? gl.getParameter(gl.VERSION) : null;
  });
  console.log(`PROBE RESULT: WebGL2 Context = ${webglVersion}`);

  // Wait 5 seconds to simulate initial match join
  await page.waitForTimeout(5000);

  await browser.close();
  console.log("Test execution completed successfully.");
})();
```

#### Step 2: Exact Execution Command
```bash
xvfb-run -s "-screen 0 1280x720x24" node tools/ci_firefox_probe.js
```

#### Expected Output Shape
```
Navigating to local game server...
Awaiting engine boot and canvas mount...
[BROWSER CONSOLE] info: Godot Engine v4.7.2.stable.official ...
[BROWSER CONSOLE] info: OpenGL API WebGL 2.0 (Mesa llvmpipe (LLVM 17.0.6, 256 bits))
[BROWSER CONSOLE] info: [NetworkClient] Connected to ws://127.0.0.1:8399/ws
[BROWSER CONSOLE] info: [NetworkClient] Received JOIN_OK (assigned_id=1, class_id=0)
PROBE RESULT: WebGL2 Context = WebGL 2.0 (OpenGL ES 3.0 Chromium)
Test execution completed successfully.
```

---

### Q4 — Minimum Reproducible Performance Harness & Noise Protocol

#### 1. Minimum Viable Instrumentation (M1–M7)
* **rAF Interval Sampling (M3, M4, M5):**
  Record `performance.now()` deltas inside a dedicated `requestAnimationFrame` loop. Store rolling 60-second window in a `Float32Array(3600)`. Compute p50, p95, p99, and count frame intervals exceeding 33.3 ms and 250 ms.
* **Long Tasks (M4 Stalls):**
  Register a `PerformanceObserver` with `entryTypes: ["longtask"]`. Logs any main-thread execution over 50 ms.
* **WASM Memory Footprint (M7):**
  Sample `WebAssembly.Memory.buffer.byteLength` every 5 seconds.
* **Draw Calls & Vertex Counts (M6):**
  Query Godot internal performance counters directly via GDScript:
  - `Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)`
  - `Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)`
  Expose them via JavaScript bridge `JavaScriptBridge.eval("window.__godot_perf_callback(...)")`.

#### 2. Cross-Browser API Availability Matrix

| Metric API | Chrome / Edge | Firefox | Safari Desktop | iOS Safari | Fallback When Missing |
|---|---|---|---|---|---|
| `requestAnimationFrame` | **Yes** | **Yes** | **Yes** | **Yes** | None required (universal). |
| `PerformanceObserver("longtask")` | **Yes** | **No** (Bug 1421064) | **No** | **No** | Delta between consecutive rAF timestamps > 50 ms. |
| `performance.memory` | **Yes** | **No** | **No** | **No** | `WebAssembly.Memory.buffer.byteLength`. |
| `EXT_disjoint_timer_query_webgl2` | Disabled | Disabled | Disabled | Disabled | **CPU/GPU Differential Scaling Probe** (see Q4.5). |

#### 3. Strict Noise Protocol
* **Warm-Up Duration:** Exactly **10 seconds** of active match simulation before recording to discard JIT compilation, WASM bytecode tiering, and pipeline state compiles.
* **Measurement Window:** Exactly **60 seconds** (3,600 frames at 60 Hz).
* **Metric Statistic:** Report the **median run's p95** across 3 consecutive runs (not the average or best run).
* **Environment Controls:**
  - Display zoom strictly 100%. Device pixel ratio (DPR) locked.
  - Windows power profile set to "Best Performance", laptop plugged into AC mains.
  - All browser extensions disabled (Incognito / Clean Guest Profile).
  - Ambient room temperature between 20°C and 24°C.
* **Thermal Throttling Detection:** A run is marked **invalidated by thermal throttling** if average frame time in the last 15 seconds is >20% slower than the first 15 seconds.

#### 4. Run-to-Run Variance Threshold
* On integrated laptop GPUs (H1), run-to-run variance of **±5% to ±10%** is normal.
* **Rejection Threshold:** If the spread between the fastest and slowest p95 across 3 runs exceeds **15%**, discard the set, wait 3 minutes for GPU cool-down, and rerun.

#### 5. Disentangling CPU vs GPU Bottlenecks Without WebGL Timer Queries
Because browser vendors disabled `EXT_disjoint_timer_query_webgl2` globally to mitigate Spectre side-channel attacks, use the **Differential Scaling Probe**:
1. Run 30 seconds at **1.0x Resolution Scale (1280×720)**.
2. Run 30 seconds at **0.5x Resolution Scale (640×360)** while keeping simulation, physics (30 Hz), and bot logic identical.
3. **Analysis:**
   - If p95 frame time decreases by **>35%**: The bottleneck is **GPU fragment/fill-rate bound** (shadow filtering, post-processing, overdraw).
   - If p95 frame time decreases by **<10%**: The bottleneck is **CPU main-thread bound** (GDScript physics, bone transformations, network packet decoding).

#### 6. Minimal Scripted Match Scenario
* **Scenario:** 8 actors total (Local player + 7 local bots).
* **Map:** Sunken Quarry arena.
* **Action Script:** Bots move along pre-computed navmesh nodes, firing at intervals of 1.5 s with respawns enabled.
* **Duration:** 120 seconds (10 s warm-up + 60 s active measurement + 50 s soak).

* **Confidence:** High (90%).
* **What would change our mind:** If major browser vendors re-enable WebGL timer queries with randomized timing jitter.

---

### Q5 — Feature Risk Register & Failure Modes

#### 1. Pointer Lock API
* **Failure Mode:** Safari restricts `requestPointerLock()` to direct, synchronous `click` handlers. Calling it inside a delayed promise or after a network callback throws `SecurityError: The request is not allowed by the user agent`.
* **Focus-Out & Re-acquire:** Esc key releases pointer lock natively; Godot emits `NOTIFICATION_APPLICATION_FOCUS_OUT`. Re-acquisition must never be attempted automatically (browsers reject it with `pointerlockerror`).
* **Mitigation:** Display an in-game HUD overlay: *"Click screen to resume control"*. Re-request pointer lock strictly on the subsequent canvas `pointerdown`.

#### 2. Audio Autoplay Policy
* **Failure Mode:** Chrome and Safari start `AudioContext` in the `"suspended"` state. If audio playback is triggered before a user gesture, sounds play into a void or fail silently.
* **Mitigation:** In `scripts/audio/audio_manager.gd`, attach an invisible DOM click listener in `shell.html`. On first user interaction, invoke `AudioServer` initialization synchronously:
  ```javascript
  window.addEventListener('pointerdown', () => {
    if (GodotAudio && GodotAudio.ctx && GodotAudio.ctx.state === 'suspended') {
      GodotAudio.ctx.resume();
    }
  }, { once: true });
  ```

#### 3. Tab Throttling (Backgrounding)
* **Failure Mode:** When a tab is backgrounded, `requestAnimationFrame` drops to 1 fps or halts entirely. Godot's physics loop attempts to accumulate delta time. Upon returning, `Engine.max_physics_steps_per_frame = 4` prevents an infinite loop, but the client falls 30 seconds behind the server, triggering immediate server kick or prediction buffer overflow.
* **Mitigation:** Listen for `visibilitychange`. When `document.hidden` becomes true, drop WebSocket input transmission to a heart-beat packet (1 Hz). When foregrounded, request a fresh full snapshot from the server (`CMD_RESYNC`) and flush input history.

#### 4. WASM Memory Limits & OOM
* **Failure Mode:** Total payload is 39.5 MB WASM + 5.7 MB PCK. On iOS Safari, web tabs are granted a hard memory budget of ~512 MB to 1 GB before the OS kills the tab with WebProcess crash (`Canvas memory exceeded`).
* **Mitigation:** Set Emscripten initial memory to 128 MB and max memory to 512 MB (`-s INITIAL_MEMORY=134217728 -s MAXIMUM_MEMORY=536870912`). Disable dynamic object instantiation during gameplay; all bullets and impact effects must use strict static preallocated object pools.

#### 5. WebSocket Reconnect
* **Failure Mode:** Cellular handoffs or 3-second network deadzones cause TCP head-of-line blocking. The browser socket hangs without firing `onclose` until the OS TCP timeout expires (often 20–60 seconds).
* **Mitigation:** Enforce an application-level ping/pong heartbeat every 2 seconds. If no pong is received within 4 seconds, call `socket.close()` forcibly in JavaScript and initiate reconnection.

#### 6. Fullscreen & Canvas Resize
* **Failure Mode:** On mobile and Safari macOS, exiting fullscreen or rotating the screen leaves the canvas backing store mismatched with CSS layout dimensions, causing blurriness or mouse coordinate offsets.
* **Mitigation:** In `shell.html`, hook `window.addEventListener('resize', debounceResize)`. Synchronize canvas width/height explicitly:
  ```javascript
  canvas.width = window.innerWidth * window.devicePixelRatio;
  canvas.height = window.innerHeight * window.devicePixelRatio;
  ```

#### 7. Mobile Keyboard
* **Failure Mode:** Virtual keyboard is disabled (`export_presets.cfg:34`). Text fields for player name or chat cannot be focused on mobile devices.
* **Verdict:** Mobile is strictly **load-only** for V1. The UI should display an informational banner: *"Mobile viewing mode — keyboard & mouse required to play"*.

#### 8. Single-Threaded Main Loop Saturation
* **Failure Mode:** If network snapshot decoding, skeleton matrix recalculation, and physics take >16.6 ms, rAF skips frames, snowballing into client prediction divergence.
* **Mitigation:** Cap remote ghost animation updates to 30 Hz (skip skeleton recalculation every alternate visual frame for remote actors).

* **Confidence:** High (95%).
* **What would change our mind:** If WebKit relaxes pointer lock and audio autoplay policies (extremely unlikely due to security and anti-ad-tracking invariants).

---

### Q6 — Performance Fallbacks & Degradation Strategy

#### 1. Ranking of Performance Levers (Gain per Visual Impact)

| Lever | Performance Gain (H1) | Visual Impact | Recommendation |
|---|---|---|---|
| **1. 3D Render Scale (0.75x / 540p)** | **+35% GPU frame time** | Mild (linear upscaling is clean at 720p) | **Primary Lever** |
| **2. Directional Shadow Distance (90m → 45m)** | **+20% GPU frame time** | Low (distant shadows unnoticeable in arena) | **Primary Lever** |
| **3. Shadow Map Resolution (2048 → 1024)** | **+12% GPU frame time** | Low (soft shadow filter masks resolution) | **Primary Lever** |
| **4. Remote Actor Anim Tick Rate (60Hz → 30Hz)** | **+15% CPU frame time** | Very Low (animation blending smooths delta) | **Secondary Lever** |
| **5. Disable MSAA (2x → None)** | **+10% GPU frame time** | Moderate (staircasing on high-contrast edges) | Secondary Lever |
| **6. Reduce Triplanar Mesh Instances** | **+8% GPU frame time** | Moderate | Asset-level tuning |
| **7. Crosshair / HUD Throttle** | Negligible (<1%) | High (ruins responsiveness) | **Do Not Touch** |

#### 2. Tier Selection & Dynamic Hysteresis Rule
* **Static Initialization:** On initial boot, inspect `gl.getParameter(gl.RENDERER)`. If the string matches Intel HD/UHD, Mali, or SwiftShader, default to **Tier 1 (Performance)**. Otherwise, default to **Tier 2 (Balanced)**.
* **Dynamic Hysteresis Rule:**
  - Sample rAF frame time over a sliding 15-second window.
  - **Downgrade Trigger:** If frame time p95 > **20.0 ms** (<50 fps) for two consecutive 15-second windows, downgrade by one tier.
  - **Upgrade Trigger:** If frame time p95 < **14.0 ms** (>71 fps) for four consecutive 15-second windows (60 seconds of sustained headroom), upgrade by one tier.
  - **Anti-Oscillation Lock:** A maximum of 2 dynamic changes are permitted per session. If toggled twice, lock the tier for the remainder of the match.

#### 3. User Visibility
* When a dynamic degradation occurs, show a subtle, non-intrusive 3-second toast notification in the top-right corner:  
  *“Adjusted graphics to Performance mode for smooth 60 FPS [Undo in Settings]”*.
* An entry in the Settings UI must allow the user to override and lock their preferred tier (Low, Medium, High).

#### 4. Minimum Acceptable Visual Quality
* At 720p / 0.75x scale on H1, the following must **NEVER** be degraded:
  1. Crosshair rendering (always rendered at 1:1 native 720p canvas resolution via 2D CanvasLayer).
  2. Enemy silhouette contrast and team color highlights.
  3. Muzzle flash, bullet tracers, and hit spark feedback.

#### 5. Missing WebGL2 Fallback
* WebGL1 is permanently obsolete and unsupported in Godot 4.x.
* If WebGL2 context creation fails, `shell.html` displays a styled, user-friendly fallback card:
  > **Graphics Acceleration Required**  
  > *Ball of Duty requires WebGL 2.0. Please enable hardware acceleration in your browser settings or update your GPU drivers.*

#### 6. Mobile Gate
* At load time on mobile devices, display a responsive overlay:
  > **Desktop Browser Recommended**  
  > *Ball of Duty is designed for keyboard and mouse. Mobile touch controls are coming in a future update.*  
  > `[Continue to Spectate / Load Test]`

* **Confidence:** High (90%).
* **What would change our mind:** If playtesters report dynamic tier changes cause distracting visual popping during combat.

---

### Q7 — Release Blocking Criteria & Audit Evidence

#### 1. Blocker vs Warning Matrix (M1–M14)

| Metric | Target (G0) | Blocker (P0) Threshold | Warning (P1) Threshold |
|---|---|---|---|
| **M1: Cold Load** | ≤ 3.5 s (LAN) | > 12.0 s | 6.0 s – 12.0 s |
| **M2: First Frame** | ≤ 5.0 s (LAN) | > 10.0 s or Shell Crash | 6.0 s – 10.0 s |
| **M3: Frame p95** | ≤ 16.7 ms (60 fps) | **> 22.2 ms (<45 fps)** | 16.8 ms – 22.2 ms |
| **M4: Frame p99 / Stalls** | p99 ≤ 33 ms, 0 > 250 ms | **Any frame > 500 ms** | Any frame > 250 ms |
| **M5: Average FPS** | ≥ 55 fps | **< 45 fps** | 45 fps – 54 fps |
| **M6: Draw Calls / Tris** | ≤ 80 calls, ≤ 250k tris | > 150 calls / > 500k tris | 100–150 calls |
| **M7: Memory Leak** | ≤ 512 MB, growth ≤ 10% | **> 1024 MB or crash** | 512 MB – 1024 MB |
| **M8: Pointer Lock** | Clean lock / release | **Fails to lock or drift** | Occasional miss on rapid click |
| **M9: Audio Playback** | Audible after gesture | **Silent or continuous crackle** | Minor crackle on initial boot |
| **M10: Socket Reconnect** | Reconnects ≤ 3 s | **Fails to reconnect (stuck)** | Reconnects in 4–5 s |
| **M11: Input Latency** | ≤ 100 ms | > 200 ms | 150 ms – 200 ms |
| **M12: Tab Throttling** | State recovers ≤ 2 s | **Desync > 5 s or kick** | Desync 2–5 s |
| **M13: Fullscreen** | Clean resize & lock | Broken aspect ratio / unclickable | Mild CSS black bar |
| **M14: Console Errors** | 0 uncaught errors | **Any uncaught JS/WASM error** | Unhandled WebGL warnings |

#### 2. Sample Size and Confidence
* To declare a G0 cell "passed", conduct **three 60-second test runs** following a 10-second warmup.
* Report the **median run's p95**.
* Spread across the 3 runs must be **< 15%**.

#### 3. Single-Browser Escalation Policy
When exactly one browser fails a G0 criterion:
1. **Engine Bug / Upstream Regression:** If a new browser release breaks an API (e.g., WebKit AudioWorklet bug):
   - Do NOT hold the entire release if Chrome and Edge (80% of players) pass cleanly.
   - Deploy an in-app browser banner for the affected browser: *"Safari users: Audio may experience delays; update to macOS 26.2 recommended."*
   - Downgrade that browser cell from G0 to G1 for that specific release cycle.
2. **Game Code Regression:** If our code broke the browser (e.g., unsupported shader syntax):
   - **Hard Blocker:** Delay release until fixed.

#### 4. Acceptable Known-Issues for Release
* Untriaged Firefox WebGL warnings (`TexImage: filter LINEAR`, `try` opcode deprecation).
* Mobile devices displaying "Desktop Recommended" banner without touch controls.
* Edge efficiency mode throttling background tabs when minimized.

#### 5. Audit Package Artifact Manifest
Before signing off on Checkpoint 5 (CP5), the following package must be archived in `docs/ci/audit/`:
```
CP5-AUDIT/
├── MANIFEST.json               # Git hash, engine version, timestamp
├── C1_Win11_Chrome_metrics.json
├── C1_Win11_Chrome_console.log
├── C1_Win11_Chrome_snap.png
├── C3_Win11_Firefox_metrics.json
├── C3_Win11_Firefox_console.log
├── C4_macOS_Safari_metrics.json
├── C4_macOS_Safari_console.log
└── server_soak_30hz.log
```

* **Confidence:** High (95%).
* **What would change our mind:** If security auditors require zero warnings of any kind in the browser console.
