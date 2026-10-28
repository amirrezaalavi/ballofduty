# Execution Plan — CP0 onward

How I will build Ball of Duty, what I will verify myself, what I need from you, and where
subagents are used. Roadmap + acceptance criteria: [`ROADMAP.md`](./ROADMAP.md).

## Ground rules

- **One checkpoint at a time.** No Phase N+1 work until Phase N evidence is recorded.
- **Verification is part of the task.** Every claim gets a command, number, log, or screenshot.
- **The server never trusts the client.** Any feature touching movement, damage, or score is designed
  server-authoritative from the first commit — even while it runs locally.
- **No magic numbers in gameplay scripts.** Tuning lives in `.tres` resources.
- **Small commits, green builds.** Each commit leaves the project importable and `tools/check.sh` passing.
- **Internet assets get a license entry before they get used.**

## Toolchain (installed in this workspace)

| Tool | Version | Location |
|---|---|---|
| Godot editor + headless | 4.7.2-stable | `/srv/opencode/pkg/godot-4.7.2/` |
| Export templates | 4.7.2-stable | `~/.local/share/godot/export_templates/4.7.2.stable/` |
| Go (optional tooling/proxy later) | 1.26.5 | `/usr/local/bin/go` |
| Git | system | `/usr/bin/git` |

Wrapper scripts go in `tools/` so every command is reproducible:
`tools/godot` (editor/headless), `tools/check.sh` (import → headless boot → exports → tests).

## My work plan

### CP0 — Foundation (current)
1. Install/pin Godot + templates; verify `--headless` works with no display.
2. Project settings (`project.godot`), input map, collision layer table.
3. Grey-box arena with spawn markers; stub player and stub server.
4. Export presets (Web single-threaded, Linux server), custom HTML shell.
5. `tools/check.sh` + GitHub Actions build; initial commit.
6. Produce `docs/checkpoints/CP0.md` evidence with measured payload size and load test.

### CP1 — Movement & camera
Build components and controller; iterate on feel using recorded debug telemetry.
Deliver a desktop build + short capture for your sign-off. I tune numeric feel from your notes,
not from assumptions.

### CP2 — Arena & art
You pick the pack; I integrate, optimize, and enforce budgets. I will also produce a grey-box
layout proposal first so art is dressing, not level design.

### CP3 — Local combat
Resource-driven weapon, swept projectiles, hurtboxes, `CombatResolver`, HUD, FX/audio.
I will build an automated hit-test scene that fires at 5/15/30 m and reports tunneling/hit rates.

### CP4a–d — Multiplayer
Sequence is strict: pipe → movement prediction → combat authority → resilience. Each sub-phase has
its own evidence page. I will add a latency simulator (`--sim-latency 100 --sim-jitter 20`) so we can
test honestly without external tooling.

### CP5 — Match loop & release
Match state machine, scoreboard, settings, web hardening, Caddy config, deploy script, browser matrix.

## Subagent usage

I will use subagents for **independent, non-overlapping** work only, always reviewing their output
before it lands. Planned uses:

| Task | Agent | Why |
|---|---|---|
| Review roadmap/architecture for gaps | general | Independent critique, no file writes |
| Audit asset packs for scale/licenses | explore | Read-only research while I code |
| Draft CI/deploy config variants | general | Isolated files, reviewed before merge |
| Write test matrices / soak scripts | general | Parallel to feature code |
| Post-CP code review (GDScript, netcode) | general | Fresh eyes on diffs |

Guardrails: one writer per file; subagents work in reads or isolated new files; I own commits and
final verification. No subagent gets credentials or deploys.

## Where you help (highest leverage)

1. **CP1 feel sign-off** — camera distance/shoulder offset/FOV/speed/scope. I cannot judge feel from numbers.
2. **CP2 art direction** — choose the asset pack + palette, download `.glb` packs, approve the grey-box layout.
3. **CP4 latency playtest** — two machines/tabs on real network, tell me what feels wrong (not how to fix it).
4. **CP5 browser matrix** — Safari and a low-end laptop are the two environments I cannot faithfully emulate here.
5. **Hosting decisions** — domain, host, TLS/proxy preference for WSS.
6. **Scope calls** — when a phase slips, you decide cut vs. extend. My default: cut content, keep the loop.

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| Web export breaks late | Export smoke test in CP0 and CI on every push |
| Netcode debugging has too many unknowns | 4a→4d split; latency simulator; correction meters |
| Art blocks progress | Grey-box first; art is swappable dressing |
| Godot headless/templates mismatch | Pin 4.7.2; `tools/check.sh` validates both |
| Bandwidth/CPU at 8 players | Snapshot size + tick-time budgets enforced from 4a |
| TCP head-of-line stalls | ≤300 B snapshots + newest-wins draining; documented that retransmits still cause a hitch (no WebSocket fix) |
| Prediction divergence | Shared locomotion code; fixed tick; replay tests |
| Scope creep | Out-of-scope list in ROADMAP; change requires your call |

## Definition of done (every work session)

- [ ] Code imports cleanly (0 errors; warnings triaged) and `tools/check.sh` passes.
- [ ] Acceptance criteria for the active checkpoint are met or explicitly marked deferred.
- [ ] Evidence written to `docs/checkpoints/CPn.md`.
- [ ] Decisions/risks updated in this file or `ARCHITECTURE.md`.
- [ ] Commit pushed with a message referencing the checkpoint.
