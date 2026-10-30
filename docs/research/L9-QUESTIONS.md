# L9 — Browser matrix research brief (CP5)

**Status:** questions open, no implementation started.
**Owner:** build/CI (L9), with the user supplying real Firefox/Safari/low-end hardware.
**Asked:** 2026-10-30, from `develop` @ `1bdb161`.
**Deliverable wanted:** a decision-ready answer to the seven questions in §4, plus a matrix
that a second person can execute without asking us anything.

**How to answer:** edit this file in place (or reply in chat) with one section per question.
Every claim needs either a citation (browser bug, Godot issue, vendor doc) or a measurement
with the device/browser/build recorded. If something cannot be measured, say so explicitly —
"unverified" is an acceptable answer, a guess is not.

**See also:** [`PERFORMANCE-AUDIT-2026-10-30.md`](PERFORMANCE-AUDIT-2026-10-30.md) §7 (the
open real-device measurements), [`../PLAYTEST-2026-10-29.md`](../PLAYTEST-2026-10-29.md)
(Firefox issue list), [`../BACKLOG.md`](../BACKLOG.md) S33/S34/S35/L9,
[`../ROADMAP.md`](../ROADMAP.md) Phase 5 acceptance criteria.

---

## 1. Context (verified in this worktree)

| Fact | Evidence |
|---|---|
| Godot **4.7.2-stable**, Compatibility renderer on desktop and mobile | `project.godot:16`, `project.godot:119-120` |
| Single-threaded web export, no `SharedArrayBuffer`/COOP/COEP | `export_presets.cfg:26` (`variant/thread_support=false`), `docs/DEPLOY.md:3-4`, `docs/ARCHITECTURE.md:194-201`; confirmed at runtime: console prints `single-threaded, no GDExtension support` |
| 30 Hz physics + 30 Hz snapshots, binary, 6 + 18·n bytes | `project.godot:113-114`, `scripts/networking/net_protocol.gd:26-28` |
| Actor caps: V1 accepts **8 total actors**; protocol allows **16** (294 B snapshot at 16) | `docs/BACKLOG.md:36`, `scripts/networking/net_protocol.gd:23`, `tests/headless/net16_probe.gd:1-15` |
| Maps: Sunken Quarry **150×150 m**; quantization supports **±327.68 m / 250 m maps** | `docs/BACKLOG.md:31`, `docs/ARCHITECTURE.md:50` |
| Five classes (Knight, Mage, Rogue, Rogue Hooded, Barbarian) | `resources/content/entries/class_*.tres` |
| Design resolution **1280×720**, `canvas_items` stretch, adaptive canvas | `project.godot:30-32`, `export_presets.cfg:32` |
| Custom shell with boot progress + missing-feature notice | `web/shell.html:283-301`, `web/shell.html:383-411` |
| One origin: static + `/ws` tunnel; HTML `no-store`, assets `no-cache` | `tools/serve.py:192-199`, `tools/serve.py:78-93`, `tools/dev.sh:5-11` |
| CI = import → gdUnit4 → arena → boots → web/server export → gzip size | `tools/check.sh:77-91`, `.github/workflows/ci.yml:29-30` |
| Existing browser tooling = one Playwright screenshot at 1280×720 | `tools/capture.sh:22-25` |
| Mobile/touch is **out of scope for V1** | `docs/ROADMAP.md:26`; input map is keyboard/mouse only (`project.godot:34-100`) |
| No touch/virtual keyboard | `export_presets.cfg:34` (`html/experimental_virtual_keyboard=false`) |
| PWA/service worker disabled | `export_presets.cfg:35-36` |

**Branch base:** `1bdb161`. Since this branch was cut, `develop` has advanced to `5b1ae8a`
("Merge feature/l6: settings UI"), which adds a render-quality setting with a 3D resolution
scale and directional shadow distance (`scripts/autoload/settings.gd` on `develop`). The
risk register and Q6 describe the **branch base**; re-validate the exact knobs against the
merged `develop` before implementation. Do not merge/rebase this branch to get them — the
L9 implementation phase will be rebased deliberately by the manager.

### 1.1 What the current build actually weighs (measured today, this worktree)

Exported with `./tools/godot --headless --path . --export-release "Web" build/web/index.html`
after a clean import. Sizes are bytes on disk; gzip is `gzip -6`.

| File | Raw | gzip -6 |
|---|---|---|
| `index.wasm` | 39,514,754 (37.7 MiB) | 10,142,423 (9.7 MiB) |
| `index.pck` | 5,992,928 (5.7 MiB) | 4,360,561 (4.2 MiB) |
| `index.js` | 279,815 | 68,668 |
| whole directory | 44,796 KiB | ≈ 14.6 MB total |

This is in line with `docs/TESTING.md:65` (44,768 KB raw / 14,244 KB gzip) and the audit's
`docs/research/PERFORMANCE-AUDIT-2026-10-30.md:250` (WEB-01: 39.5 MB wasm raw / 10.1 MB gzip).
The CP5 budget is ≤ 25 MB gzipped (`docs/ROADMAP.md:255`), so payload size passes **only if**
the host serves precompressed assets; `tools/serve.py` does not precompress and CI does not
serve over a CDN.

### 1.2 Browser capabilities measured in this sandbox (not release evidence)

Playwright 1.64.1, browsers from `/srv/opencode/pkg/playwright`, 1280×720, headless, Linux x86_64.

| Probe | Chromium 156.0.8078.4 | Firefox 157.0 |
|---|---|---|
| WebGL2 | **yes** | **no** (`AllowWebgl2:false restricts context creation on this system`) |
| WebGL renderer | `ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero)), SwiftShader driver)` | n/a |
| `SharedArrayBuffer` / `crossOriginIsolated` | false / false | false / false |
| Pointer Lock / Fullscreen / AudioContext API | yes / yes / yes | yes / yes / yes |
| Boot of exported build | overlay removed, canvas 1280×720, **no page errors** | shell shows "could not start … WebGL2" notice; never boots |
| rAF during 2 s of quarry | **2 frames** (≈ 1 fps, software raster) | n/a (no engine) |
| Time to engine start | **7.9 s** (cold, SwiftShader) | n/a |

Consequences:

- **Chromium numbers here are software-rasterised and must never be quoted as 720p/60
  evidence.** The `GPU stall due to ReadPixels` warnings are SwiftShader artefacts.
- **Headless Playwright Firefox cannot be used as a Firefox gate in this sandbox.** The
  failure is a hard pref (`AllowWebgl2:false`), and forcing `webgl.force-enabled`,
  `gfx.webrender.software`, etc. via `firefoxUserPrefs` did not change it. `docs/checkpoints/CP0.md:20`
  calls this a "headless GPU limitation"; it is stricter than that.
- No `webkit` browser is installed here, and Playwright WebKit on Linux is **not** Safari
  (no Apple GPU/driver, no iOS). Treat it as a third engine, not Safari coverage.

---

## 2. Test matrix proposal

### 2.1 Hardware classes

| ID | Class | Spec (minimum) | Why |
|---|---|---|---|
| **H1** | Reference low-end laptop | 2C/4T (e.g. i3-1115G4 / Ryzen 3 5300U), Intel UHD/Iris Xe, 8 GB, Win 11, 60 Hz, DPR 1, SSD, plugged in | The 720p/60 claim is only meaningful here |
| **H2** | Apple laptop | M1/M2 MacBook Air, 8 GB, macOS 26, 60 Hz | Safari desktop + Metal/ANGLE parity |
| **H3** | Mid mobile | Pixel 6a (Mali-G78) or iPhone 13 (A15), 4 GB | Load-only today (no touch controls) |
| **H4** | Discrete desktop | RTX 3060 / RX 6600, 1080p 144 Hz | Upper bound, not a gate |

Record GPU model, driver version, OS build, DPR, browser zoom (must be 100 %), extensions
(disabled), power profile (plugged in, no battery saver), and ambient temperature.

### 2.2 Browser / OS / network cells

Versions are proposals — Q1 must confirm or correct them. The sandbox builds observed here
(Chromium 156.0.8078.4, Firefox 157.0) are Playwright bundles, not necessarily the current
public stable; treat the numbers as illustrative.

**Tiers:** **G0** = release blocker (must pass before shipping), **G1** = supported and
measured each release but not blocking, **G2** = CI/proxy only (Linux desktop is not a
consumer target).

| Cell | Browser | OS | HW | Resolution | Network | Tier |
|---|---|---|---|---|---|---|
| C1 | Chrome latest (156+) | Win 11 | H1 | 1280×720 | LAN | **G0** |
| C2 | Edge latest (156+) | Win 11 | H1 | 1280×720 | LAN | **G0** |
| C3 | Firefox latest (157+) | Win 11 | H1 | 1280×720 | LAN | **G0** |
| C4 | Safari latest (26+) | macOS 26 | H2 | 1280×720 | LAN | **G0** |
| C5 | Chrome latest | macOS 26 | H2 | 1280×720 | LAN | G1 |
| C6 | Chrome latest | Ubuntu 24.04 | H1-class VM | 1280×720 | LAN | G2 (CI proxy) |
| C7 | Firefox latest | Ubuntu 24.04 | H1-class VM | 1280×720 | LAN | G2 (CI proxy) |
| C8 | Chrome latest | Android 15/16 | Pixel 6a | 390×844 | 4G | G1 (load-only) |
| C9 | Safari latest | iOS 26 | iPhone 13 | 390×844 | 4G | G1 (load-only) |
| C10 | Chrome latest | Win 11 | H1 | 1920×1080 | LAN | G1 |
| C11 | Firefox latest | Win 11 | H1 | 1280×720 | 100 ms / 1 % loss | **G0** |
| C12 | Chrome latest | Win 11 | H1 | 1280×720 | 4G (50 ms / 1 %) | G1 |
| C13 | Safari latest | macOS 26 | H2 | 1280×720 | 100 ms / 1 % | G1 |

Minimum supported versions (to be confirmed by Q1): Chrome/Edge **last 2 stable majors**,
Firefox **latest + previous**, Safari/iOS **current + previous major**, Android Chrome
**latest on Android 13+**. Anything older is "unsupported, may work".

Network profiles:

- **N1 LAN:** ≤ 5 ms RTT, 0 % loss, ≥ 100 Mbps.
- **N2 4G:** 50 ms RTT ± 10 ms, 1 % loss, 10 Mbps down / 3 Mbps up.
- **N3 adverse:** 100 ms RTT ± 20 ms, 1 % loss, 5 Mbps, TCP (no jitter buffer beyond the
  game's 2-interval + 1-tick extrapolation).

Shape with `tc netem` on the server host or a router, not only DevTools throttling (DevTools
does shape WebSocket, but it does not reproduce TCP retransmit behaviour at the OS level).

### 2.3 Per-cell measurements

Run each cell on a **named build hash** with a fixed scripted scenario: join `?join=1`, pick
one class, 8 actors (at least 4 human clients or 4 bots), 5 minutes, no menu idling. Warm up
10 s, then measure 60 s. Three runs per cell; report the **median run's** p95 (not the best
run).

| # | Metric | Method | G0 target | G1 target | Fail |
|---|---|---|---|---|---|
| M1 | Cold load | `navigationStart` → `#boot` removed (shell `startGame()` resolved, `web/shell.html:415-431`) | ≤ 10 s N1 | ≤ 15 s N1 / ≤ 25 s N2 | > 20 s N1 or > 35 s N2 |
| M2 | First frame | engine start → first rAF with a non-blank canvas | ≤ 5 s N1 | ≤ 8 s N1 | > 10 s, or shell notice |
| M3 | Frame p95 | rAF interval over 60 s after warm-up | **≤ 16.7 ms** | ≤ 20 ms | > 25 ms |
| M4 | Frame p99 / stalls | same samples | p99 ≤ 33 ms, 0 frames > 250 ms | p99 ≤ 50 ms | any frame > 500 ms |
| M5 | Average FPS | same samples | ≥ 55 | ≥ 45 | < 30 |
| M6 | Draw calls / tris | Godot `Performance` monitors (to be exposed) or Spector.js | ≤ 80 calls, ≤ 250 k tris | ≤ 120 calls | > 150 calls |
| M7 | Memory | `WebAssembly.Memory.buffer.byteLength` + `performance.memory` | ≤ 512 MB, growth ≤ 10 % after warm-up | ≤ 768 MB | OOM / `RangeError` / growth > 25 % |
| M8 | Pointer lock | click canvas → `document.pointerLockElement.id === "canvas"`; Esc releases; click re-acquires; alt-tab then one click re-acquires | all pass, ≤ 1 frame | same | lock never acquired, or camera spins on re-acquire |
| M9 | Audio | `AudioContext.state` after first gesture; shot/reload audible; no "prevented from starting" after gesture | `running`, audible | `running` | silent with no on-screen hint |
| M10 | Reconnect | drop socket mid-match (kill server / `tc` drop 3 s); then restore | HUD "lost" ≤ 1 s, reconnect ≤ 8 s (`RECONNECT_GRACE_MSEC`), no ghosts | same, ≤ 12 s | stuck in CLIENT limbo, stale ghosts, or silent offline |
| M11 | Input latency | pointer delta → rendered yaw change (instrumented) + optional 240 fps camera | ≤ 100 ms | ≤ 130 ms | > 200 ms, or unmeasurable |
| M12 | Tab throttling | background 30 s → foreground; check server input rate and state convergence | no input burst (> 4 steps/frame), converge ≤ 2 s | same | burst, desync, or frozen actor |
| M13 | Fullscreen | browser fullscreen + in-game request; canvas fills; pointer lock survives | pass | pass | letterboxed/stuck |
| M14 | Console | console + page errors for 5 min | 0 errors; warnings triaged | 0 errors | any uncaught error / engine abort |

C8/C9 (mobile) are **load-only**: M1, M2, M7, M9, M14 only. There are no touch controls
(`docs/ROADMAP.md:26`), so do not record mobile frame rate as a game result.

M3/M4 assume 60 Hz vsync; on a 60 Hz panel rAF intervals quantise to 16.67 ms, so p95
"≤ 16.7 ms" means essentially no missed vsync. Q4 must confirm whether the gate should use
rAF-interval p95 or a separate in-engine frame-time p95, and whether p99 ≤ 33 ms is the
right stall criterion.

---

## 3. Known risk register (substantiated from the repo)

| # | Risk | Evidence | Status |
|---|---|---|---|
| R1 | Headless Firefox cannot create WebGL2 here, so "Firefox coverage" cannot be automated in this sandbox | probe above; `docs/checkpoints/CP0.md:20` | **confirmed** |
| R2 | No real-GPU browser frame number exists anywhere in the repo; Chromium evidence is SwiftShader | probe above; `docs/research/PERFORMANCE-AUDIT-2026-10-30.md:47-49` ("native x86_64 numbers, not browser numbers") | **confirmed** |
| R3 | No resolution scale / quality tier **at this branch base**; 3D renders at window size with 90 m PSSM shadows (L6 on `develop` now adds both — re-check) | `project.godot:30-32` (no `rendering/scaling_3d`), `scenes/maps/arena_quarry.tscn:41-44`, `docs/BACKLOG.md:80` (L6 settings UI todo), `docs/ROADMAP.md:245` | **confirmed (base)** |
| R4 | Cold payload is ~14.6 MB gzip / 45.8 MB raw, single-threaded, no service worker; mobile VRAM compression is off | measured above; `export_presets.cfg:27-28,35` | **confirmed** |
| R5 | Background tabs throttle hard; two browser tabs in one browser cannot both simulate | `docs/PLAYTEST-2026-10-29.md:108`, `docs/checkpoints/CP4a.md:68`, `scripts/game/main.gd:42-46` (catch-up cap only) | **confirmed** |
| R6 | No explicit audio unlock / "click for sound" hint; shell only mentions pointer lock | `web/shell.html:299`, `scripts/autoload/audio_manager.gd:8-53` (no resume path), `docs/BACKLOG.md:22` (S35 pending), `docs/PLAYTEST-2026-10-29.md:104` | **confirmed** |
| R7 | Pointer lock is released on focus-out and only re-acquired by a canvas click; no `visibilitychange` path | `scripts/player/player_controller.gd:74-75,157-168` | **confirmed** (by design, but untested across browsers) |
| R8 | Firefox WebGL warnings (depth-filter LINEAR, attrib-0, viewport rect, `try` deprecation) are untriaged | `docs/PLAYTEST-2026-10-29.md:92-108`, `docs/BACKLOG.md:24` (S33 deferred) | **open** |
| R9 | Mobile is not playable (keyboard/mouse input map, virtual keyboard off) | `docs/ROADMAP.md:26`, `project.godot:34-100`, `export_presets.cfg:34` | **confirmed** |
| R10 | 16-actor snapshot is 294 B and the client decodes up to 16, but V1 only ships 8 actors; browser cost of 16 remotes is unmeasured | `scripts/networking/net_protocol.gd:23-28`, `tests/headless/net16_probe.gd` | **unmeasured** |
| R11 | CI has no browser job and no remote yet | `.github/workflows/ci.yml:29-30`, `docs/CI.md:3-4` | **confirmed** |

---

## 4. Questions for the research agent

Answer each with: recommendation, evidence/citation, confidence, and "what would change
your mind". Where the answer depends on our build, say which measurement we must run.

### Q1 — Which matrix is realistic, and what can be deferred?

For a web-first indie shooter shipping in late 2026 with 8–16 actors, 150–250 m maps and a
720p/60 target:

1. Which of C1–C13 are genuinely required for release, which are "supported but not gated",
   and which should be explicitly unsupported? Give a one-line rationale per cell.
2. What are the real minimum versions (WebGL2 + WASM + Pointer Lock + Web Audio) for
   Chrome, Edge, Firefox, Safari desktop, iOS Safari, Android Chrome? Cite caniuse/MDN or
   vendor docs, not memory.
3. Is Edge a separate cell or is it Chromium with a different update cadence and GPU
   blocklist? What Edge-specific failure modes exist (SmartScreen, enterprise policy,
   `--disable-gpu` fallbacks)?
4. Which hardware class is the honest "low-end laptop" in 2026, and is H1 above or below
   the median Steam/browser user? If H1 is too weak or too strong, propose the corrected
   spec.
5. What share of the target audience is Firefox/Safari-only, and does that justify a hard
   gate or a "best effort" label?

### Q2 — Godot 4.7.2 Compatibility/WebGL2 limitations per browser

1. Enumerate known Godot 4.7.x WebGL2 issues per engine (Firefox, Safari desktop, iOS
   Safari, Android Chrome): depth-texture filtering, vertex attrib 0, viewport/destination
   rect mismatch, PSSM shadows, `gl_compatibility` limits, `try`/`try_table` EH
   deprecation, audio worklet startup, pointer lock, fullscreen.
2. Which of these are **release blockers** (cannot boot / cannot play / visual corruption),
   which are performance-only, and which are cosmetic warnings we can suppress?
3. Does Godot 4.7.2 ship a Safari/iOS-specific known-issues list? Link the exact
   GitHub issues/PRs and whether they are fixed in 4.7.x or only in 4.8/dev.
4. Are the Firefox warnings in `docs/PLAYTEST-2026-10-29.md:92-108` engine bugs, our
   material settings, or harmless? For each, name the setting/flag to test.
5. Does single-threaded WASM change any of the above (e.g. shader compile on the main
   thread, audio worklet fallback, no `SharedArrayBuffer`)?
6. Is the Compatibility renderer still the right choice for a 2026 web release, or does
   Mobile/Forward+ on WebGPU change the matrix? (Assume we will not switch engines for V1;
   answer for planning, not as a proposal.)

### Q3 — How to automate Firefox/WebKit coverage, and what can CI run?

1. Given that headless Playwright Firefox in our sandbox cannot create WebGL2 at all, what
   are the viable options: xvfb + headed Firefox, a Firefox build with software WebGL,
   `MOZ_*` env/prefs, BrowserStack/Sauce Labs Firefox, or a self-hosted runner with a GPU?
   Give exact commands/prefs that are known to work in 2026.
2. Is Playwright WebKit on Linux useful as a proxy for Safari? What does it *not* cover
   (Apple GPU/driver, iOS memory limits, Safari audio, JIT differences, touch)?
3. What can CI realistically gate: boot smoke, console-error budget, pointer-lock API
   presence, screenshot diff, WebSocket join? What must stay manual (real frame rate,
   thermal throttling, audio)?
4. Cost/ops: GitHub-hosted runners (GPU? none), self-hosted low-end laptop, BrowserStack
   vs Sauce Labs plans, per-parallel-session pricing, and whether either exposes real
   Safari/iOS with WebGL2 and performance traces.
5. How should we store evidence (JSON metrics, screenshots, console logs, traces) so a
   release can be audited later?

### Q3a — Automation feasibility check (answer with a concrete experiment)

Propose the smallest experiment that proves a Firefox or Safari engine can boot our build
and join a match, with the exact browser version, flags/prefs, host OS and expected console
output. If no such experiment exists in CI-compatible form, say so and name the manual
fallback. Do **not** propose "run Playwright Firefox" without addressing the
`AllowWebgl2:false` result in §1.2.

### Q4 — Minimum reproducible performance harness and noise protocol

1. What is the minimum instrumentation to measure M1–M7 credibly in a browser: rAF
   sampling, `PerformanceObserver("longtask")`, `performance.memory` (Chrome-only),
   `WebAssembly.Memory.buffer.byteLength`, WebGL timer queries
   (`EXT_disjoint_timer_query_webgl2`), Spector.js, Chrome tracing, Firefox profiler?
2. Which of these work in Safari/iOS and Firefox, and which are Chromium-only? What is the
   fallback when timer queries are unavailable?
3. What is the correct noise protocol: warm-up length, run count, statistic (median p95 vs
   mean), handling of shader-compile first frames, thermal soak, DPR/zoom, OS compositor
   scaling, browser backgrounding, and how to detect a throttled/thermal-limited run?
4. What run-to-run variance is normal on integrated GPUs, and what threshold should
   invalidate a run (we propose > 15 % p95 spread across 3 runs)?
5. How do we separate CPU-bound from GPU-bound frames without a GPU timer (e.g. compare
   720p vs 480p render scale, HUD on/off, shadows on/off)?
6. What is the smallest scripted scenario that still represents a real match (bot count,
   movement, shooting, respawns) and how long must it run to catch hitches?

### Q5 — Which current features are at risk?

For each, say how it fails per browser and what the test is:

1. **Pointer lock:** request from click only (`player_controller.gd:157-163`), release on
   focus-out, no auto re-acquire. Safari/iOS behaviour, Esc handling, fullscreen
   interaction, `pointerlockerror`.
2. **Audio autoplay:** no explicit unlock in `audio_manager.gd`; Godot's web audio driver
   resume semantics per browser; worklet vs ScriptProcessor fallback; muted-tab behaviour.
3. **Tab throttling:** background rAF to ~1 fps; `Engine.max_physics_steps_per_frame = 4`
   (`main.gd:45`); input bursts, ack pinning, server kick/timeout.
4. **WASM memory:** 39.5 MB module + heap; iOS Safari per-tab limits; growth from bullet
   pool/remote scenes; OOM behaviour and recovery.
5. **WebSocket reconnect:** 6 s initial budget, 8 s mid-match grace
   (`network_manager.gd:35-44`); TCP head-of-line; proxies/CDNs that idle-timeout `/ws`;
   Safari/iOS background suspension.
6. **Fullscreen + canvas resize:** adaptive policy (`export_presets.cfg:32`), DPR changes,
   orientation change, Safari toolbar collapse.
7. **Mobile keyboard:** virtual keyboard off (`export_presets.cfg:34`); is there any
   supported path for names/chat on mobile, or is mobile explicitly load-only?
8. **Anything else** you consider a likely blocker for this specific stack (Godot 4.7.2
   Compatibility + single-threaded + 30 Hz WebSocket).

### Q6 — Fallbacks and degradation

1. Which levers give the most frame time per unit of visual damage on this renderer:
   `rendering/scaling_3d/scale`, shadow distance (90 → 45 m), shadow casters, MSAA,
   triplanar terrain, fog, HUD redraw, bullet visuals, remote-actor count?
2. How should the game choose a tier: static device class (UA/GPU string), measured
   first-30-s frame time, user setting, or a combination? Give a concrete rule with
   hysteresis so it does not oscillate.
3. What should the user see when a tier is applied (silent, toast, settings entry)?
4. What is the minimum acceptable visual quality at 720p on H1, and what must never be
   degraded (crosshair visibility, enemy readability, hit feedback)?
5. What is the fallback if WebGL2 is missing (current shell shows a notice,
   `web/shell.html:383-411`)? Is a static "unsupported browser" page enough, or do we need
   a WebGL1 path (probably not — confirm)?
6. Should mobile get a "desktop only" gate at load time rather than a broken playable page?

### Q7 — What evidence justifies blocking a release?

1. Define blocker vs warning per metric (M1–M14) and per cell. We propose: any G0 cell
   failing M1/M2/M3/M8/M9/M10/M14 blocks; M4–M7/M11–M13 are warnings unless they make the
   game unplayable.
2. What sample size and confidence are needed before calling a cell "pass"? Is 3×60 s
   enough, or does thermal drift require longer?
3. What is the escalation path when only one browser fails (ship with a banner? delay?
   drop the cell from the supported list?) — give a decision rule, not a vibe.
4. Which failures are acceptable to ship with a known-issues note (e.g. Firefox warning
   spam, iOS load-only)?
5. What evidence must be attached to the release record (build hash, browser versions,
   device specs, JSON metrics, screenshots, console logs, server logs)?

---

## 5. Options (cost / risk)

| Option | What it means | Cost | Risk | Verdict |
|---|---|---|---|---|
| **A. Do nothing** | Ship Chromium-only; label Firefox/Safari unsupported | 0 | High: CP5 gate explicitly requires Chrome/Firefox/Safari (`docs/ROADMAP.md:254`); Firefox/Safari users hit a boot or audio/lock failure with no signal | Reject |
| **B. Manual matrix** | Two people, C1–C5 + C8/C9, one pass per release candidate, checklist + screenshots | ~1–2 person-days per release; hardware owned by user | Human variance, no regression detection, easy to skip under deadline | **Minimum viable**; required regardless |
| **C. Automated matrix** | Playwright projects (Chromium + Firefox + WebKit) in CI: boot smoke, console budget, join, screenshot; JSON artifacts | ~3–5 engineer-days setup + CI minutes; no real GPU | Cannot measure real frame rate; WebKit ≠ Safari; Firefox headless WebGL2 unavailable here | **Do it for smoke**, not perf |
| **D. Device lab** | BrowserStack/Sauce for Safari/iOS/Android + one owned H1 laptop | ~$100–300/month + 1–2 days setup | Virtualised GPUs make perf numbers unreliable; still need H1 for 720p/60 | Use for **compatibility** on C4/C8/C9, not perf |
| **E. Self-hosted device rack** | Owned H1 + Mac mini + iPhone + Android, runner with display | Hardware cost + maintenance | Best fidelity, slowest to set up, single point of failure | Only if C+D cannot cover a blocker |

Recommended combination: **B for perf on H1/H2, C for boot/console smoke, D only for
Safari/iOS compatibility if no Apple hardware is available.** Do not let C or D produce the
720p/60 number.

---

## 6. Acceptance tests for the research answer

The research phase is done when:

1. **A1** Every cell in §2.2 has a browser version, OS, hardware spec and an owner.
2. **A2** Every threshold in §2.3 has a method a second person can run from a written
   command, with the expected output shape.
3. **A3** The automation recommendation names at least one **tested** path that renders
   WebGL2 in Firefox or Safari, or explicitly states that none exists and why.
4. **A4** The blocker list separates "cannot boot", "cannot play", "too slow", and
   "cosmetic warning".
5. **A5** Cost includes CI minutes and any device-lab subscription, with a monthly figure.
6. **A6** Fallbacks have a selection rule, a hysteresis rule, and a user-visible signal.
7. **A7** No claim violates §7.

### Falsification criteria

Reject an answer if any of these is true:

- It treats **Playwright WebKit on Linux as Safari** coverage.
- It treats **headless Playwright Firefox in this sandbox** as a Firefox gate (our probe
  shows `AllowWebgl2:false`; `docs/checkpoints/CP0.md:20` is stale on the cause).
- It quotes a frame rate from **SwiftShader/llvmpipe** as device evidence.
- It reports an **average FPS** without p95/p99 and stall counts.
- It measures with the HUD hidden, shadows off, or a smaller render scale without saying so.
- It claims reconnect works after only a **clean server shutdown** (TCP FIN), not a silent
  drop or 3 s blackhole.
- It claims mobile "works" while the build has no touch controls.
- It claims "no console errors" while ignoring warnings that are known WebGL failures.

---

## 7. Do not claim without measurement

- "60 fps at 720p on a low-end laptop" — no real-GPU browser number exists yet.
- "Firefox works" — only the missing-WebGL2 notice has been observed.
- "Safari/iOS works" — never run.
- "Loads in X seconds on 4G" — only cold localhost/SwiftShader was measured.
- "Memory is stable" — no 60 s sample, no iOS limit test.
- "Pointer lock recovers after tab switch" — focus-out release exists; re-acquire is a
  click, untested per browser.
- "Audio starts after first click" — no `AudioContext.state` check in the build.
- "Reconnect is seamless" — only unit/loopback tests, no browser socket drop.
- "Payload is under 25 MB" — true for gzip-on-disk, not for an arbitrary host; Brotli and
  CDN behaviour are unmeasured.
- "Firefox warnings are harmless" — untriaged (R8).

---

## 8. Proposed implementation sequence (after answers arrive)

No code in this phase; this is the order we will execute.

1. **Freeze the matrix** in this file (cells, thresholds, owners) and add a
   `docs/BROWSER-MATRIX.md` runbook with one checklist per cell and a JSON recording
   template.
2. **Add a measurement surface** (first code change): a `?perf=1` path that records
   navigation → engine start → first frame, rAF p50/p95/p99/max, long tasks, WASM heap,
   draw calls/tris, and emits one JSON blob (console + downloadable). Keep it inert in
   normal play.
3. **Expose degradation levers**: resolution scale, shadow distance/casters, MSAA, HUD
   throttle, remote-actor effects — all behind one quality tier with hysteresis (Q6).
4. **Add `tests/browser/` Playwright config**: projects `chromium` (gate), `firefox`
   (smoke only if WebGL2 is available), `webkit` (labelled "engine smoke, not Safari").
   Reuse `tools/serve.py` + `tools/dev.sh` and ephemeral ports.
5. **CI job `browser-smoke`**: build web once, start server + proxy, run Playwright, upload
   JSON/screenshots/console logs/traces. No perf gate in CI.
6. **Manual perf run**: H1 + H2, C1–C4/C10/C11, three runs each, recorded in
   `docs/checkpoints/CP5.md`.
7. **Device-lab pass** only for C4/C8/C9 if no owned Apple/Android hardware; record it as
   compatibility evidence, not performance.
8. **Promote to gates** after two consecutive releases with < 15 % run-to-run spread:
   M1/M2/M3/M8/M9/M10/M14 block; the rest warn.

---

## 9. Appendix — commands used for the evidence in this brief

```bash
# export + sizes (writes only gitignored build/)
./tools/godot --headless --path . --import
./tools/godot --headless --path . --export-release "Web" build/web/index.html
gzip -6 -c build/web/index.wasm | wc -c
gzip -6 -c build/web/index.pck  | wc -c

# serve the build without a game server
python3 tools/serve.py --root build/web --bind 127.0.0.1 --port 8399 --no-proxy

# browser capability + boot probe (Playwright 1.64.1)
PLAYWRIGHT_BROWSERS_PATH=/srv/opencode/pkg/playwright \
NODE_PATH=/srv/opencode/pkg/npm/lib/node_modules \
node /srv/opencode/tmp/opencode/l9-boot-probe.js
```

Raw probe output: `/srv/opencode/tmp/opencode/l9-boot.json` (not committed).
