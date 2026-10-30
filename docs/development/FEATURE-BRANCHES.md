# Branches & pull requests

**Source of truth:** `https://github.com/amirrezaalavi/ballofduty` — one clone,
no side-by-side worktrees.
**Integration branch:** `develop` (protected: no force-push, no deletion, PR
required).
**Release branch:** `main` (kept as a marker; not used for daily work).

## Daily loop

```bash
git checkout develop && git pull --ff-only
git checkout -b feature/<short-name>

# ... work ...

./tools/gdcheck.sh <changed .gd files>
./tools/check.sh --skip-export        # full gate before a PR

git add -A && git commit -m "<area>: <what changed>"
git push -u origin feature/<short-name>
gh pr create --base develop --fill   # body from .github/pull_request_template.md
```

Merge with **squash** for small branches, **merge commit** when the branch has
meaningful history. Delete the branch after merge (`gh pr merge --squash --delete-branch`).

## Rules

- Never commit directly to `develop`; admins can, but do not.
- One feature per branch. If a branch touches more than ~3 unrelated areas,
  split it.
- No agent writes to another agent's branch. Parallel work uses separate
  branches from the same `develop`.
- A branch merges only when the PR checklist is filled with real command output.
- Research-gated work lands only after the answer summary is committed
  (`docs/research/*-ANSWER-SUMMARY.md`), including what was rejected.

## Current branches

| Branch | Scope | State |
|---|---|---|
| `develop` | integration | 172 tests green |
| `feature/l9-browser-matrix` | L9 web surface + harness + docs restructure | in review |
| `maps-candidates` | map-session snapshot (`d6c942d`) | historical |
| `maps-candidates-wip` | three arena maps, uncommitted map-session work preserved | merged via PR |

## CI

GitHub Actions runs a light gate on `develop` pushes and PRs: Godot 4.7.2
install → `--import` → content validation → gdUnit. It does **not** export web or
run the browser job; `tools/check.sh` remains the full local gate. Details:
[`../ci/README.md`](../ci/README.md).
