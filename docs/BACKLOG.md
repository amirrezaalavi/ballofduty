# Backlog & feedback log

Short-horizon changes and long-horizon recommendations. Roadmap phases and gates live in
[`ROADMAP.md`](./ROADMAP.md); this file is the working list so nothing gets lost.

Status: `todo` · `doing` · `done` · `deferred`

## Short term (next builds)

| # | Item | Decision / target | Status | Phase |
|---|---|---|---|---|
| S1 | Jump height +10 % | `jump_velocity` 7.00 → **7.34** (apex 1.23 m → **1.35 m**) | done | CP1 |
| S2 | Character 20 % smaller | Physical capsule, mesh, hurtboxes scaled to 0.8; camera framing unchanged for now | done | CP1 |
| S3 | Re-check camera after shrink | Character is smaller at the same 3.6 m / 1.55 m framing — decide whether to lower pivot to ~1.35 m and shorten arm to ~3.2 m | doing | CP1 |
| S4 | Re-check speed after shrink | 5.6 m/s on a 1.36 m character reads faster; only change if feel demands it | todo | CP1/CP2 |
| S5 | Map scale | Grey-box 60×60 m is a test arena, **not** final scale. Design the CP2 arena larger (target 90–120 m playable, or a layout with distinct arenas); keep current for feel tests | todo | CP2 |
| S6 | Jump floatiness | Deferred by request. Current airtime is unchanged conceptually; fixing requires retuning gravity, jump velocity, air control and maybe fall curves together | deferred | CP2 |

## Long term (record now, decide later)

| # | Item | Why / notes | Status |
|---|---|---|---|
| L1 | Proper jump physics pass | Derive height/airtime from `v²/2g` and `2v/g`; evaluate higher gravity + higher jump velocity, asymmetric fall, terminal velocity, coyote/buffer curves; aim for a snappy platformer-shooter feel without changing the +10 % height target | todo |
| L2 | Character scale system | Move capsule/mesh/hurtbox/camera dimensions into a `PlayerStats`/`CharacterBody` resource so size is data-driven and shared with the server | todo |
| L3 | Camera framing pass | After character shrink: distance, shoulder, pivot height, ADS shoulder offset, collision smoothing, FOV feel; keep a “wide” and “tight” preset | doing |
| L4 | Larger map performance | Bigger arena affects draw calls, occlusion, LOD, fog, spawn distances and web load budget; measure with CP2 reference device | todo |
| L5 | Movement set | Add slide/dash/roll later only if the core loop needs it; do not add before netcode so prediction scope stays small | deferred |
| L6 | Settings UI | Expose sensitivity, invert Y, scope scale, volume, quality in CP5; persistence already exists | todo |
| L7 | Animation / stride | Character shrink makes stride more visible; add run/jump/fall states from replicated state flags | todo |
| L8 | Server parity | Character scale, hurtboxes, camera-independent stats, jump values must come from the same resources on client and server | todo |
| L9 | Browser matrix | Real Firefox/Safari, low-end laptop, 720p/60 target (CP5) | todo |
| L10 | CI remote | GitHub/GitLab remote for the first green pipeline run | todo |

## Changelog

- **2026-10-28 — CP1 feedback:** jump apex +10 %; character −20 %; map-scale and jump-floatiness
  comments recorded. Camera/speed held constant so the next feel pass isolates the size change.
