# Ball of Duty

A lightweight, cute, web-first 3D third-person arena shooter. Eight players, one rifle, five minutes,
bragging rights.

**Status:** Phase 0 landed — visible bullets, speed retune, hand-locked gun/turn-to-fire, connection truth; awaiting retest
(CP0/CP1/CP2 accepted; CP3 combat feel review pending; CI first run pending a remote).
Tests run on gdUnit4 with JUnit XML; see [`docs/TESTING.md`](docs/TESTING.md).
See [`docs/ROADMAP.md`](docs/ROADMAP.md).

```bash
tools/godot --headless --path . -- --server --port 9180   # authority
tools/check.sh && tools/serve.sh 8099                     # web build
# open http://127.0.0.1:8099/?join=1&host=127.0.0.1&port=9180&name=You
```
**Engine:** Godot 4.7.2 (GDScript) · **Renderer:** Compatibility (WebGL 2) · **Netcode:** WebSocket,
Godot headless authoritative server, 30 Hz fixed tick.

## Quick start

```bash
# desktop run (windowed)
tools/godot --path . --editor        # open in the editor
tools/godot --path .                 # run the project

# headless server
tools/godot --headless --path . -- --server --port 9080

# full pipeline check (import, gdUnit4 suite, boots, exports, size)
tools/check.sh

# serve server + web build with pidfiles, then capture a screenshot
tools/dev.sh up
tools/capture.sh "http://127.0.0.1:8099/?solo=1" docs/checkpoints/shot.png
tools/dev.sh down

# version-exact API lookup and a fast parse gate
tools/api.sh WebSocketMultiplayerPeer get_peer
tools/gdcheck.sh
```

Requirements: Godot **4.7.2** with matching export templates. If the engine lives elsewhere, set
`GODOT_BIN`:

```bash
GODOT_BIN=/path/to/godot tools/godot --version
```

## Controls (current grey-box)

| Input | Action |
|---|---|
| `WASD` | Move |
| Mouse | Look |
| `RMB` (hold) | Scope (FOV 75 → 55) |
| `LMB` | Fire (from CP3) |
| `Space` | Jump |
| `Shift` | Sprint (from CP1) |
| `R` | Reload (from CP3) |
| `Tab` | Scoreboard (from CP5) |
| `Esc` | Release mouse |
| Click canvas | Capture mouse |
| `F3` | Debug overlay (FPS, tick, speed, camera) |

## Layout

```text
res://
├── scenes/{characters,weapons,ui,maps}
├── scripts/{autoload,components,networking,player,game,ui}
├── resources/{weapons,players}
├── assets/            # third-party low-poly assets + CREDITS.md
├── server/            # headless entry points
├── web/               # custom HTML shell
├── tests/             # gdUnit4 suites + headless probes
├── docs/              # roadmap, architecture, checkpoints, runbooks
└── tools/             # godot wrapper, pipeline check, deploy
```

## Docs

- [`docs/ROADMAP.md`](docs/ROADMAP.md) — revised sequencing, Phase 4 split, acceptance criteria
- [`docs/PLAN.md`](docs/PLAN.md) — execution plan, subagent usage, how you can help
- [`docs/BACKLOG.md`](docs/BACKLOG.md) — short-term feedback and long-term recommendations
- [`assets/CREDITS.md`](assets/CREDITS.md) — third-party asset licenses
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — authority model, layers, events, directories
- [`docs/TESTING.md`](docs/TESTING.md) — gdUnit4 suites, reports, dev tooling
- [`docs/DEPLOY.md`](docs/DEPLOY.md) — planned single-origin Caddy/WSS deployment

## License

Code: TBD. Third-party assets: see `assets/CREDITS.md` when assets land (CP2).
