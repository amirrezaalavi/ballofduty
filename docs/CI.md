# CI setup

The workflow is committed at `.github/workflows/ci.yml`. It has **not run on a
remote yet** because this workspace has no git remote; that is the only open CP0
item.

## What the workflow does

Triggers: push to `develop` and `main`, plus every pull request.

1. `pipeline` job: installs Godot **4.7.2** + matching export templates
   (`chickensoft-games/setup-godot@v2`).
2. Runs `tools/check.sh` (import → gdUnit4 suite → arena budget → client/server
   boot → Web export → Linux server export → server binary smoke). With
   `GODOT_BIN` unset, `tools/godot` uses the sandbox default and falls back to
   `godot` on `PATH`; a bare `GODOT_BIN` is also resolved through `command -v`.
   The old broken `GODOT_BIN: godot` env is gone.
3. Uploads `reports`, `build/web` and `build/server` as artifacts.
4. `browser-smoke` job (needs `pipeline`): downloads `build/web`, installs the
   pinned Playwright harness in `tools/ci`, installs Chromium, serves the build
   with `tools/serve.py --no-proxy`, and runs
   `tools/ci/browser_smoke.mjs --browser chromium`.
   It uploads `artifacts/browser-smoke`.
5. Firefox/Xvfb is documented in `tools/ci/README.md` and commented in
   `ci.yml`, but **not enabled**: it could not be validated here (no Xvfb).
   Enable it only after a green manual `xvfb-run` pass.

The browser job gates boot, WebGL 2, non-harmless console errors and (as a
warning) pointer lock. It does **not** gate framerate: GitHub runners use
SwiftShader. Real H1/H2/Safari/iOS evidence is manual — see
`docs/BROWSER-MATRIX.md`.

## Closing the CP0 item

```bash
# from the repo root, once you have created an empty remote
git remote add origin git@github.com:<you>/ballofduty.git
git push -u origin develop
```

Then open the Actions run and confirm:

- [ ] `pipeline` job is green.
- [ ] `browser-smoke` job is green and uploads `metrics_chromium.json`.
- [ ] `ballofduty-web` artifact downloads and loads via `tools/serve.sh` after unzipping.
- [ ] `ballofduty-server` artifact runs with `--headless -- --server`.

Record the run URL and artifact sizes in `docs/checkpoints/CP0.md`.

## Local equivalent

```bash
GODOT_BIN=/srv/opencode/pkg/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 tools/check.sh

# browser smoke (after the export above)
python3 tools/serve.py --root build/web --port 8099 --no-proxy &
cd tools/ci && npm ci
PLAYWRIGHT_BROWSERS_PATH=/srv/opencode/pkg/playwright \
  node browser_smoke.mjs --url http://127.0.0.1:8099/index.html \
  --browser chromium --out ../../artifacts/browser-smoke
```

If the remote is GitLab, port the same steps to `.gitlab-ci.yml`; the pipeline
script is runner-agnostic.
