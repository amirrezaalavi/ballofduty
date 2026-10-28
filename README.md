# Ball of Duty

A lightweight, cute, web-first 3D third-person arena shooter. Eight players, one rifle, five minutes,
bragging rights.

**Status:** CP2 implemented — nature arena and asset pass awaiting visual review (CP0/CP1 accepted; CI first run pending a remote). See [`docs/ROADMAP.md`](docs/ROADMAP.md).
**Engine:** Godot 4.7.2 (GDScript) · **Renderer:** Compatibility (WebGL 2) · **Netcode:** WebSocket,
Godot headless authoritative server, 30 Hz fixed tick.

## Quick start

```bash
# desktop run (windowed)
tools/godot --path . --editor        # open in the editor
tools/godot --path .                 # run the project

# headless server
tools/godot --headless --path . -- --server --port 9080

# full pipeline check (import, boot, exports, tests)
tools/check.sh

# serve the exported web build (http://127.0.0.1:8099)
tools/serve.sh
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
├── tests/             # GUT + headless integration
├── docs/              # roadmap, architecture, checkpoints, runbooks
└── tools/             # godot wrapper, pipeline check, deploy
```

## Docs

- [`docs/ROADMAP.md`](docs/ROADMAP.md) — revised sequencing, Phase 4 split, acceptance criteria
- [`docs/PLAN.md`](docs/PLAN.md) — execution plan, subagent usage, how you can help
- [`docs/BACKLOG.md`](docs/BACKLOG.md) — short-term feedback and long-term recommendations
- [`assets/CREDITS.md`](assets/CREDITS.md) — third-party asset licenses
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — authority model, layers, events, directories

## License

Code: TBD. Third-party assets: see `assets/CREDITS.md` when assets land (CP2).
