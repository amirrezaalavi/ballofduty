# Backlog & feedback log

Short-horizon changes and long-horizon recommendations. Roadmap phases and gates live in
[`ROADMAP.md`](./ROADMAP.md); this file is the working list so nothing gets lost.

Status: `todo` · `doing` · `done` · `deferred`

## Short term (next builds)

| # | Item | Decision / target | Status | Phase |
|---|---|---|---|---|
| S1 | Jump height +10 % | `jump_velocity` 7.00 → **7.34** (apex 1.23 m → **1.35 m**) | done | CP1 |
| S2 | Character 20 % smaller | Physical capsule, mesh, hurtboxes scaled to 0.8; camera framing unchanged for now | done | CP1 |
| S3 | Re-check camera after shrink | User accepted the current 3.6 m / 0.55 m / 1.55 m framing as-is | done | CP1 |
| S4 | Re-check speed after shrink | Keep 5.6 m/s after the size change; only revisit if CP2 playtests ask for it | done | CP1/CP2 |
| S5 | Map scale | CP2 nature arena keeps the 60×60 m playable footprint; final map is still expected to be larger (90–120 m or distinct arenas) | todo | CP3+ |
| S6 | Jump floatiness | Deferred by request. Current airtime is unchanged conceptually; fixing requires retuning gravity, jump velocity, air control and maybe fall curves together | deferred | CP3+ |
| S7 | Shadow/lighting verification | Headless software rendering does not show directional shadows; verify on real Chrome/desktop GPU before changing the lighting budget | doing | CP2/CP3 |

## Long term (record now, decide later)

| # | Item | Why / notes | Status |
|---|---|---|---|
| L1 | Proper jump physics pass | Derive height/airtime from `v²/2g` and `2v/g`; evaluate higher gravity + higher jump velocity, asymmetric fall, terminal velocity, coyote/buffer curves; aim for a snappy platformer-shooter feel without changing the +10 % height target | todo |
| L2 | Character scale system | Move capsule/mesh/hurtbox/camera dimensions into a `PlayerStats`/`CharacterBody` resource so size is data-driven and shared with the server | todo |
| L3 | Camera framing pass | Current framing accepted; later add ADS shoulder offset, collision smoothing and wide/tight presets | done |
| L4 | Larger map performance | Current map is 35 draw calls / 31k tris. A larger final map needs occlusion/LOD/fog decisions and a new budget measurement | todo |
| L5 | Movement set | Add slide/dash/roll later only if the core loop needs it; do not add before netcode so prediction scope stays small | deferred |
| L6 | Settings UI | Expose sensitivity, invert Y, scope scale, volume, quality in CP5; persistence already exists | todo |
| L7 | Animation / stride | Character shrink makes stride more visible; add run/jump/fall states from replicated state flags | todo |
| L8 | Server parity | Character scale, hurtboxes, camera-independent stats, jump values must come from the same resources on client and server | todo |
| L9 | Browser matrix | Real Firefox/Safari, low-end laptop, 720p/60 target (CP5) | todo |
| L10 | CI remote | GitHub/GitLab remote for the first green pipeline run | todo |

## Changelog

- **2026-10-28 — CP1 feedback:** jump apex +10 %; character −20 %; map-scale and jump-floatiness
  comments recorded. Camera/speed held constant so the next feel pass isolates the size change.
