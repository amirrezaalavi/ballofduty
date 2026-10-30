# Checkpoint history

Short record of what each checkpoint delivered and whether it was accepted.
The full write-ups (including screenshots) remain in git history; this file is
the forward-looking summary.

| CP | Date | Build | Scope | Status |
|---|---|---|---|---|
| CP0 | 2026-10-28 | `d8fbd67` | Import/boot pipeline, headless client + server, smoke gate | accepted (foundation) |
| CP1 | 2026-10-28 | `34b354e` | Movement, camera, jump feel, 0.82 m avatar | accepted by user |
| CP2 | 2026-10-28 | `f3bbd7d` | Sunken Quarry arena, Nature Kit, lighting | accepted by user |
| CP3 | 2026-10-29 | `eb161f7` | Combat, HUD, audio, swept projectiles | implemented; feel folded into CP4c |
| CP4a | 2026-10-29 | — | WebSocket transport, replication, two clients | implemented; superseded by CP4b tuning |
| CP4b | 2026-10-29 | — | Input queue, prediction, reconciliation, 1.05 / 2.751 m/s | implemented |
| CP4c | 2026-10-29 | — | Server-authoritative combat, class weapons, bots | implemented |
| CP5 | — | — | Browser matrix, deployment, release audit | **in progress** |

## What CP5 still needs

- Real-browser evidence on H1/H2 (Chrome, Edge, Firefox, Safari) — see
  [`../ci/BROWSER-MATRIX.md`](../ci/BROWSER-MATRIX.md).
- A first deployment target and rollback drill — see [`../ci/DEPLOY.md`](../ci/DEPLOY.md).
- Map integration (crater / dunes / jungle) and the match-end flow — see
  [`../STATUS.md`](../STATUS.md).

## Evidence

Current browser screenshots live in [`evidence/`](evidence/):
`quick-menu.png`, `settings-panel.png`, `hud-batch1.png`, `l2l8-step1.png`.

Older checkpoint screenshots were removed in the 2026-10-30 restructure; they are
recoverable from git history before commit `chore/repo-restructure`.
