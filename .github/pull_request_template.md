## What changed

<!-- One or two sentences. Link the backlog item (L2, L6, L8, L9, S<n>) if there is one. -->

## Why

<!-- The player-visible or engineering reason. If this implements a research answer, name the doc. -->

## Verification

<!-- Paste the commands you ran and their summary lines. Do not paste claims you did not run. -->

- [ ] `./tools/gdcheck.sh <changed .gd files>`
- [ ] gdUnit suites for the touched area
- [ ] `./tools/check.sh` (or `--skip-export` for doc-only changes)
- [ ] Browser check, if the change touches UI/render/input/web shell

```text
<paste the summary lines here>
```

## Contract checklist

- [ ] No protocol change (snapshot row stays 18 B / 294 B at 16) — or the change is a deliberate, documented protocol bump
- [ ] No headshots / single body capsule preserved
- [ ] Client and server read the same gameplay data (`CharacterBodyStats`, `PlayerStats`, content catalog)
- [ ] Root `CharacterBody3D.scale` and `CollisionShape3D.scale` stay `Vector3.ONE`
- [ ] Web payload and per-map budgets checked if assets changed
- [ ] Docs updated (`STATUS.md`, `TESTING.md`, `BACKLOG.md` where relevant)
