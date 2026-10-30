# Feature Branches — L2/L8, L9, L6

**Base:** `develop` at `1c20ae2` (protocol v2 / 16 actors + L6 settings UI + research briefs).
**Policy:** one feature per branch/worktree; no agent touches another worktree; the
integrator merges into `develop` only after tests pass.

| Feature | Branch | Worktree | Phase |
|---|---|---|---|
| L2 character scale + L8 server parity | `feature/l2-l8` | `../ballofduty-wt-l2l8` | **Step 1 merged** into `develop` (`34273aa`); Step 2 deferred |
| L9 browser matrix | `feature/l9` | `../ballofduty-wt-l9` | **research questions ready**, awaiting answers |
| L6 settings UI | `feature/l6` | `../ballofduty-wt-l6` | **merged** into `develop` (`83db67e`) |

## Research gate

L2/L8 and L9 are blocked on external research. Each agent writes:

- `docs/research/L2-L8-QUESTIONS.md`
- `docs/research/L9-QUESTIONS.md`

The integrator merges them into **`docs/research/FEATURE-QUESTIONS.md`** and gives
that single file to the user. The user returns the research answers; the
integrator forwards the relevant section to each agent, who then implements on
its own branch.

L6 is merged first. L2/L8 Step 1 is merged: all five profiles are numerically
identical to the old rig, and LOCAL/REMOTE/SERVER read the same profile. Step 2
(per-class sizes) is deferred. L6 browser evidence:
`docs/checkpoints/settings-panel.png` (panel opened from the main menu, quality
LOW and 15 % volume persisted after Apply/Close/reopen, 0 console errors).

## Merge order

1. `feature/l6` — independent UI; merge first.
2. `feature/l9` — test/tooling/docs after answers; merge second.
3. `feature/l2-l8` — resource/schema change after answers; merge last because it
   touches `PlayerStats`, the player scene, camera and server parity.

For each merge:

```bash
git checkout develop
git merge --no-ff <branch>
./tools/gdcheck.sh
./tools/check.sh --skip-export
```

Resolve conflicts against the latest `develop` (including any map-session work
that has landed). Do not merge a branch whose tests fail. After all three, run
the full `tools/check.sh` and update `docs/TESTING.md` / `docs/BACKLOG.md`.

## Conflict expectations

- **L6** touches `scripts/ui/main_menu.gd`, `scripts/ui/quick_menu.gd`,
  `scripts/game/main.gd`, new settings scene/script/tests. The map session also
  edits `main_menu.gd`/`main.gd`; expect small conflicts around menu wiring.
- **L9** should be mostly tests/docs/CI; low conflict risk.
- **L2/L8** touches `PlayerStats`, `player.tscn`, `player_controller.gd`,
  `camera_rig.gd`, `character_visual.gd`, `server_combat.gd`; expect conflicts
  with any camera/character work that lands first. Merge it last.
