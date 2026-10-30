# Browser smoke harness (L9)

Playwright harness for the exported Godot **Compatibility / WebGL 2** build. It
gates the things a software-GPU CI runner can actually prove — boot, WebGL 2,
console budget, pointer lock, optional in-match bridge — and deliberately does
**not** claim frame-rate or real-GPU results.

## Files

| File | Purpose |
|---|---|
| `browser_smoke.mjs` | CI gate: boot + WebGL 2 + console + pointer lock + optional `?join=1` bridge |
| `firefox_probe.js` | Q3a **CI feasibility probe** only; not a release gate |
| `package.json` / `package-lock.json` | Pinned Playwright 1.64.1 |

## Install

```bash
cd tools/ci
npm ci                 # or: npm install --offline when the npm cache has the tarballs
npx playwright install chromium
# optional, CI/display machines only:
npx playwright install firefox
```

The sandbox keeps browsers outside the default cache:

```bash
export PLAYWRIGHT_BROWSERS_PATH=/srv/opencode/pkg/playwright
```

## Local usage

```bash
# 1. build and serve the web export
./tools/godot --headless --path . --export-release "Web" build/web/index.html
python3 tools/serve.py --root build/web --port 8099 --no-proxy &

# 2. boot smoke (Chromium, software WebGL)
cd tools/ci
node browser_smoke.mjs \
  --url http://127.0.0.1:8099/index.html \
  --browser chromium \
  --out ../../artifacts/browser-smoke
```

Artifacts written to `--out`:

- `metrics_<browser>.json` — boot/first-frame ms, console counts, WebGL version,
  pointer lock, in-match, `__bod_state`, and `fps_p50/p95/p99` when the probe
  bridge is present.
- `console_<browser>.log` — every console message and pageerror, tagged
  `[harmless]` when it matches the research doc's known-harmless patterns.
- `screenshot_<browser>.png` — viewport screenshot after boot/join.

Exit code is non-zero **only** for a boot timeout, a missing WebGL 2 context, or
a non-harmless console error / pageerror. A failed pointer lock is reported as
`pointerLock: false` and is not fatal (headless Chromium often refuses it).

### With the performance probe

Add `?perf=1` to the URL. The harness waits for the bridge's frame counter and
records draw calls, primitives and JS heap bytes:

```bash
node browser_smoke.mjs \
  --url "http://127.0.0.1:8099/index.html?perf=1" \
  --browser chromium --out ../../artifacts/browser-smoke-perf
```

`frame_ms_p50/p95/p99` stay `0` for the first 10 s because the probe discards a
10 s warm-up. Use a manual 3 × 60 s run (see `docs/ci/BROWSER-MATRIX.md`) for
framerate qualification; the smoke only proves the bridge is alive.

### With an in-match join

Run the headless server and the proxy, then use `?join=1&perf=1`. The harness
waits for `window.__bod_state.in_game === true` and falls back to a fixed 15 s
wait when the bridge is absent.

```bash
./tools/godot --headless --path . -- --server --port 9180 &
python3 tools/serve.py --root build/web --port 8099 --upstream 127.0.0.1:9180 --ws-path /ws &

cd tools/ci
node browser_smoke.mjs \
  --url "http://127.0.0.1:8099/index.html?join=1&perf=1" \
  --browser chromium --out ../../artifacts/browser-smoke-join
```

## CI usage

`.github/workflows/ci.yml` runs the Chromium smoke after the export job and
uploads `artifacts/browser-smoke`. GitHub-hosted runners have no GPU, so
Chromium uses SwiftShader; this gate is boot/console only.

### Firefox (needs Xvfb)

Firefox refuses WebGL 2 in a container without a display. Run it **headed**
inside Xvfb with the research doc's software-WebRender preferences (already in
`browser_smoke.mjs` for `--browser firefox`):

```bash
sudo apt-get update && sudo apt-get install -y xvfb
xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" \
  node tools/ci/browser_smoke.mjs \
    --url http://127.0.0.1:8099/index.html \
    --browser firefox --headed \
    --out artifacts/browser-smoke-firefox
```

This path is documented but **not enabled** in `ci.yml` yet: it could not be
validated in this workspace (no Xvfb, no local display). Enable it only after a
green manual `xvfb-run` pass.

The minimal feasibility probe is separate:

```bash
xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" \
  node tools/ci/firefox_probe.js --url http://127.0.0.1:8099/index.html
```

## WebKit is not Safari

`--browser webkit` runs Playwright's WebKit MiniBrowser (GTK/WPE, Cairo) on
Linux. It is a **layout/JS/WASM smoke test**, not Safari: it does not exercise
Metal, iOS Jetsam memory limits, CoreAudio gesture policy or iOS viewport
behaviour. Never mark C4/C9 (Safari macOS/iOS) as passed from Linux WebKit.
Playwright WebKit is also not installed in this workspace, so it is untested
here.

## Known harmless lines

`TexImage: filter LINEAR`, WebAssembly `try`/`try_table` deprecation,
`Vertex attribute 0`, and viewport/destination-rect warnings are counted in
`harmless_warnings` and never fail the run. Everything else of type `error`
(and every pageerror) does.
