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
| S8 | Character model | Replaced the capsule with Kenney Blocky `character-a`, 1.36 m, animated idle/walk/sprint | done | CP2 |
| S9 | Log/stump collision | Logs and stumps now have solid box/cylinder colliders (were walk-through) | done | CP2 |
| S10 | Tree/rock collider fit | Tree trunk radius reduced from 0.36× to 0.12× scale; low-rock height corrected so invisible collision no longer feels spherical | done | CP2 |
| S11 | Gun attached to character | Gun/muzzle reparented from the player root to `Visual/GunMount`; mount copies camera pitch (+recoil); yaw inherited from the body. Now docks front-center in the mannequin's hands when still, shoulder when moving | done | CP3 |
| S16 | Server-authoritative spawn pose | `JOIN_OK` now carries spawn position + yaw; fixed a 22 m client/server mismatch and an inverted spawn yaw that faced players at the wall | done | CP4a |
| S19 | Client prediction & reconciliation | Input queue + ack, snapshot velocity/ground flags, replay of unacked frames, ~100 ms visual correction smoothing, displacement rejection | done | CP4b |
| S18 | Ghosts were locally damageable | Shooting a remote ghost applied client-side damage and showed a false hitmarker; added `HurtboxComponent.damage_enabled` and disabled it on ghosts | done | CP4a |
| S17 | Remote ghost animation | Snapshot state byte drives Walk/Sprint/Jump/Pistol_Idle on remotes; fixed a shared-state bug that left ghosts in T-pose | done | CP4a |
| S15 | Real animation set (Quaternius UAL) | Blocky avatar replaced by the UAL mannequin (CC0): Pistol_Idle hold at rest, Pistol_Aim_Neutral when scoped still, Walk/Sprint, reversed-Walk backwards (no sprint), Jump_Start/Jump/Jump_Land air chain. Full Standard set (Crouch/Hit/Death/Pistol_Reload…) staged for later | done | CP3 |
| S12 | Backwards/jump animation states | Backwards plays the walk cycle reversed and never sprints; airborne gets separate `air_move`/`air_idle` states with a procedural rise/fall lean (pack has no jump clip) | done | CP3 |
| S13 | Character 40 % smaller | Capsule 1.36 m → **0.82 m**, hurtboxes/head/camera-shoulder scaled ×0.6; camera spring 3.6 m → **2.3 m** | done | CP3 |
| S14 | Scope zoom stronger | Scope FOV 55 → **48** (75→48 = 27° of zoom vs 20° before, +35 %) | done | CP3 |

## Long term (record now, decide later)

| # | Item | Why / notes | Status |
|---|---|---|---|
| L1 | Proper jump physics pass | Derive height/airtime from `v²/2g` and `2v/g`; evaluate higher gravity + higher jump velocity, asymmetric fall, terminal velocity, coyote/buffer curves; aim for a snappy platformer-shooter feel without changing the +10 % height target | todo |
| L2 | Character scale system | Move capsule/mesh/hurtbox/camera dimensions into a `PlayerStats`/`CharacterBody` resource so size is data-driven and shared with the server | todo |
| L3 | Camera framing pass | Current framing accepted; later add ADS shoulder offset, collision smoothing and wide/tight presets | done |
| L4 | Larger map performance | Current map is 35 draw calls / 31k tris. A larger final map needs occlusion/LOD/fog decisions and a new budget measurement | todo |
| L5 | Movement set | Add slide/dash/roll later only if the core loop needs it; do not add before netcode so prediction scope stays small | deferred |
| L6 | Settings UI | Expose sensitivity, invert Y, scope scale, volume, quality in CP5; persistence already exists | todo |
| L7 | Animation / stride | Quaternius UAL landed (S15): real walk/sprint/jump/pistol clips. Remaining: strafe/back clips (only in the paid full set), AnimationTree layering, Pistol_Shoot/Pistol_Reload hooks, Death01 wiring | doing |
| L8 | Server parity | Character scale, hurtboxes, camera-independent stats, jump values must come from the same resources on client and server | todo |
| L9 | Browser matrix | Real Firefox/Safari, low-end laptop, 720p/60 target (CP5) | todo |
| L10 | CI remote | GitHub/GitLab remote for the first green pipeline run | todo |
| L11 | 3D terrain & mountains | Future map: heightfield/terrain with climbable mountains, surfaces that block bullets and create hiding spots. Area target ≥15× the current 60×60 m (~232×232 m). Needs chunked terrain, LOD, occlusion/visibility ranges, collision streaming and a new performance budget — the Minecraft-style rendering limit. Do not start before V1 netcode is stable. | deferred |
| L12 | Character variants | Remote players need distinct Blocky Characters textures/colors; same animation rig. Add in CP4a roster work. | todo |
| L13 | Weapon viewmodel polish | Gun is now hand-held at rest via Pistol_Idle. Still to do: rifle mesh instead of box, muzzle light, impact decals, damage numbers, richer kill feed, Pistol_Shoot/Pistol_Reload hooks. | todo |
| L14 | Player damage feedback | Damage vignette/health loss are wired but untestable until CP4c bots can shoot back. Validate then. | todo |

## Changelog

- **2026-10-28 — CP1 feedback:** jump apex +10 %; character −20 %; map-scale and jump-floatiness
  comments recorded. Camera/speed held constant so the next feel pass isolates the size change.
- **2026-10-29 — CP2 feedback:** Blocky character with animations replaces the capsule; log/stump
  collision fixed; tree/rock collider shapes tightened. Long-term 3D mountain/terrain map with
  Minecraft-style chunk limits recorded as **L11**.
- **2026-10-29 — CP3:** rifle/projectile/damage/HUD/audio/training dummies landed. Combat test covers
  20/20 headshots at 5/15/30 m. Weapon viewmodel and player damage feedback recorded as **L13/L14**.
- **2026-10-29 — animation/feel pass:** gun shoulder-mounted + aim-pitched (S11); backwards-reversed
  and air-lean states (S12); character ×0.6 → 0.82 m with 2.3 m camera (S13); scope FOV 48 (S14).
  Animation-pack candidates for real jump/back/strafe clips: Kenney character hub
  (https://kenney.nl/assets/tag:character), Animated Characters Survivors
  (https://kenney.nl/assets/animated-characters-survivors), Quaternius Ultimate Animated Character Pack
  (https://quaternius.com/packs/ultimatedanimatedcharacter.html), Quaternius Universal Animation Library
  (https://quaternius.com/packs/universalanimationlibrary.html), KayKit Character Animations
  (https://kaylousberg.itch.io/kaykit-character-animations), KayKit Adventurers
  (https://kaylousberg.itch.io/kaykit-adventurers), Mixamo
  (https://www.mixamo.com/), Quaternius pack on the Godot asset store
  (https://store.godotengine.org/asset/quaternius/universal-animation-library/).
