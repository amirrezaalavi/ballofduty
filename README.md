# Ball of Duty

A lightweight, cute, web-first 3D third-person arena shooter. Up to 16 players,
five classes, five minutes, bragging rights.

**Status:** playable vertical slice — five classes, three arena maps (Sunken
Quarry, Starfall Crater, Dune Canyon, Jungle Ruins), protocol v2 (8 default /
16-actor capability), quick menu, settings UI, data-driven content standard,
opt-in performance probe and a browser smoke gate.
**172 tests green** on `develop`; `tools/check.sh` passes. Remaining work is
tracked in [`docs/STATUS.md`](docs/STATUS.md).

```bash
tools/godot --headless --path . -- --server --port 9180   # authority
tools/check.sh && tools/serve.sh 8099                     # web build
# open http://127.0.0.1:8099/?join=1&host=127.0.0.1&port=9180&name=You
```

**Engine:** Godot 4.7.2 (GDScript) · **Renderer:** Compatibility (WebGL 2) ·
**Netcode:** WebSocket, headless authoritative server, 30 Hz fixed tick ·
**Platform:** web first, desktop supported.

## Quick start

```bash
# desktop run
tools/godot --path . --editor        # open in the editor
tools/godot --path .                 # run the project

# headless server
tools/godot --headless --path . -- --server --port 9080

# full pipeline check (import, content, gdUnit4, walkthroughs, probes, exports)
tools/check.sh
tools/check.sh --skip-export         # faster loop, no web/server export

# serve server + web build, then capture a screenshot
tools/dev.sh up
tools/capture.sh "http://127.0.0.1:8099/?join=1&name=You" docs/development/evidence/shot.png
tools/dev.sh down

# version-exact API lookup and a fast parse gate
tools/api.sh WebSocketMultiplayerPeer get_peer
tools/gdcheck.sh
```

Requirements: Godot **4.7.2** with matching export templates. If the engine lives
elsewhere, set `GODOT_BIN` (a path or a command name on `PATH`):

```bash
GODOT_BIN=/path/to/godot tools/godot --version
```

## Controls

| Input | Action |
|---|---|
| `WASD` | Move |
| Mouse | Look |
| `RMB` (hold) | Scope (FOV 75 → 55) |
| `LMB` | Fire |
| `Space` | Jump |
| `Shift` | Sprint (ground only) |
| `R` | Reload |
| `Esc` | Quick menu (resume / settings / leave / restart) · releases mouse |
| Click canvas | Capture mouse |
| `F3` | Debug overlay (FPS, tick, speed, camera) |

## Layout

```text
res://
├── scenes/{characters,weapons,ui,maps}
├── scripts/{autoload,components,networking,player,game,ui,content}
├── resources/{weapons,players,content}
├── assets/            # third-party low-poly assets + CREDITS.md
├── server/            # headless entry points
├── web/               # custom HTML shell
├── tests/             # gdUnit4 suites + headless probes
├── docs/              # see docs/README.md
└── tools/             # godot wrapper, pipeline check, browser smoke
```

## Docs

Start at [`docs/README.md`](docs/README.md). The short version:

- [`docs/STATUS.md`](docs/STATUS.md) — where the project is, how stable, what is left
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — sequencing and acceptance criteria
- [`docs/BACKLOG.md`](docs/BACKLOG.md) — open items and decisions
- [`docs/development/`](docs/development/) — setup, architecture, testing, checkpoints
- [`docs/data/`](docs/data/) — content standard, weapons, bodies, maps
- [`docs/ci/`](docs/ci/) — pipeline, browser matrix, deployment
- [`docs/research/`](docs/research/) — source research reports and decision summaries

## License

Code: TBD. Third-party assets: see [`assets/CREDITS.md`](assets/CREDITS.md).
