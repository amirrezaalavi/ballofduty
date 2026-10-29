# CI setup

The workflow is committed at `.github/workflows/ci.yml`. It has **not run yet** because this workspace has
no git remote; that is the only open CP0 item.

## What the workflow does

1. Installs Godot **4.7.2** + matching export templates (`chickensoft-games/setup-godot@v2`).
2. Runs `tools/check.sh` with `GODOT_BIN=godot` (import → gdUnit4 suite → arena budget → client/server boot →
   Web export → Linux server export → server binary smoke).
3. Uploads `build/web` and `build/server` as artifacts.

## Closing the CP0 item

```bash
# from the repo root, once you have created an empty remote
git remote add origin git@github.com:<you>/ballofduty.git
git push -u origin main
```

Then open the Actions run and confirm:

- [ ] `Pipeline` job is green.
- [ ] `ballofduty-web` artifact downloads and loads via `tools/serve.sh` after unzipping.
- [ ] `ballofduty-server` artifact runs with `--headless -- --server`.

Record the run URL and artifact sizes in `docs/checkpoints/CP0.md`.

## Local equivalent

```bash
GODOT_BIN=/srv/opencode/pkg/godot-4.7.2/Godot_v4.7.2-stable_linux.x86_64 tools/check.sh
```

If the remote is GitLab, port the same steps to `.gitlab-ci.yml`; the pipeline script is runner-agnostic.
