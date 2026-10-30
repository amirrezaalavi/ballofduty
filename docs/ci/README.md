# CI

GitHub Actions runs a **light gate**. The full pipeline stays local because
exports and browser runs are slow and noisy on hosted runners.

## What GitHub runs

`.github/workflows/ci.yml` — triggers on pushes to `develop` and on every PR
targeting `develop`; cancels superseded runs.

1. `actions/checkout@v4`
2. `chickensoft-games/setup-godot@v2` — Godot **4.7.2**, no export templates
3. `tools/check.sh --light` — import (fail on `ERROR`/`SCRIPT ERROR`/`Parse
   Error`), content validation (`CONTENT_OK`), the full gdUnit suite
4. Uploads `reports/` (JUnit XML) for 7 days

Typical runtime: 2–3 minutes. `GODOT_BIN` is not set: `tools/godot` resolves
`godot` from `PATH` and still accepts an absolute path or a command name.

## What GitHub does not run

| Check | Why not | Where it runs |
|---|---|---|
| Web + Linux server export | Slow, template download, artifact churn | `tools/check.sh` locally |
| Arena budget, walkthroughs, 4-bot match, 16-actor probe | CPU-heavy, long | `tools/check.sh` locally |
| Browser smoke | SwiftShader results are not performance evidence | `tools/ci/browser_smoke.mjs` locally |
| Firefox/Xvfb smoke | Needs Xvfb + a green manual pass first | manual, see below |
| Real H1/H2/Safari/iOS | Needs physical hardware | [`BROWSER-MATRIX.md`](BROWSER-MATRIX.md) |

## Local full gate

```bash
./tools/check.sh              # everything, including exports and size report
./tools/check.sh --skip-export
./tools/check.sh --light      # exactly what CI runs
```

## Browser smoke (local)

```bash
mkdir -p build/web
./tools/godot --headless --path . --export-release "Web" build/web/index.html

python3 tools/serve.py --root build/web --port 8099 --no-proxy &
cd tools/ci && npm ci
PLAYWRIGHT_BROWSERS_PATH=/srv/opencode/pkg/playwright \
  node browser_smoke.mjs --url http://127.0.0.1:8099/index.html \
  --browser chromium --out ../../artifacts/browser-smoke
```

The harness writes `metrics_<browser>.json`, `console_<browser>.log` and
`screenshot_<browser>.png`. It fails on boot timeout, missing WebGL 2, or any
non-harmless console error. Details and the Firefox/Xvfb recipe:
[`../../tools/ci/README.md`](../../tools/ci/README.md).

## Firefox under Xvfb

Not enabled in CI. Validate once by hand, then uncomment the step:

```bash
sudo apt-get install -y xvfb
xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" \
  node tools/ci/browser_smoke.mjs --url http://127.0.0.1:8099/index.html \
  --browser firefox --headed --out artifacts/browser-smoke-firefox
```

## Serving the build

Godot 4 refuses to start outside a **secure context**: `http://127.0.0.1` and
`http://localhost` work, but a plain-HTTP LAN or public IP shows
"Secure Context - Check web server configuration (use HTTPS)". Use an SSH tunnel
(`ssh -L 8099:127.0.0.1:8099 host`) for remote testing, or terminate TLS in front
of `tools/serve.py` / `tools/dev.sh`.

## Release evidence

A release qualification run archives, per cell:

```text
artifacts/releases/<build_hash>/
├── MANIFEST.json                 # git hash, engine version, timestamp
├── metrics_<cell>.json
├── console_<cell>.log
├── screenshot_<cell>.png
└── server_<cell>.log
```

The cell list, pass thresholds and manual protocol are in
[`BROWSER-MATRIX.md`](BROWSER-MATRIX.md).
