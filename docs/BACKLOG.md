# Backlog & feedback log

Short-horizon changes and long-horizon recommendations. Roadmap phases and gates live in
[`ROADMAP.md`](./ROADMAP.md); this file is the working list so nothing gets lost.

Status: `todo` · `doing` · `done` · `deferred`

## Short term (next builds)

| # | Item | Decision / target | Status | Phase |
|---|---|---|---|---|
| S44 | Visible bullets | Long thin tracer: 0.018 m core, 2.2 m trail, 2.4 m rim; muzzle-grown so it never starts at the camera; pooled, 81 m/s | done | CP4c-fix |
| S43 | Speed retune | Walk 1.05 m/s (+5 %), sprint 2.751 m/s (+10 %), projectile 81 m/s (−10 %) | done | CP4c-fix |
| S45 | Remote smoothing | 2.5-tick virtual clock (83 ms), 1-tick damped extrapolation, render-offset decay, physics interpolation off on remotes, `_process` updates | done | CP4c-fix |
| S42 | Revised execution plan | Phase 0 trust/feel, Phase 1 three parallel agents, Phase 2 world, Phase 3 CP4d/CP5 — see `docs/PLAN.md` | done | next |
| S41 | Connection state truth | 6 s timeout, refused detection, HUD banner, offline fallback, ghost cleanup, one-origin `/ws` proxy | done | CP4c-fix |
| S40 | Combat telemetry | Server shots/projectiles/hits/deaths/blocked counters every 150 ticks | done | CP4c-fix |
| S39 | Gun/turn behavior | Gun welded to hand; additive spine aim ±70°; 8°/150 ms turn-then-shoot; ADS locks body; no idle aim overlay | done | CP4c-fix |
| S38 | Character rig + strafe | KayKit Adventurers 2.0 + Animations 1.1; five variants, merged shadowless skinned mesh, full walk/run/strafe/backpedal/aim/shoot/reload/hit/death map | done | CP5 |
| S37 | Rifle model | Quaternius CC0 M4; 3-surface wrapper, grip/muzzle contract preserved; gun welded to `handslot.r` | done | CP5 |
| S36 | Tracer/impact feel | Long contrast streak + pooled impact; muzzle flash mesh retained | done | CP4c-fix |
| S35 | First-shot hitch | Materials/nodes pooled (no per-shot allocation). Firefox audio/resume profile still pending | doing | CP4c-fix |
| S34 | Loading + quick menu | Animated `web/shell.html`, in-engine menu (name/host/port/join/solo/settings), one-origin `/ws` proxy, reconnect grace | done | CP5 |
| S33 | Firefox compatibility | Deprecated `try`, depth-filter/attrib-0/viewport WebGL warnings, `file://` security error, audio autoplay, background-tab throttle | deferred | CP5 |
| S59 | L2/L8 Step 1 | `CharacterBodyStats` + registry, five identical profiles, LOCAL/REMOTE/SERVER application, server camera/muzzle de-duplication, 10 parity tests; no headshots, 18 B snapshot unchanged | done | CP5 |
| S58 | L6 settings UI | Reusable panel, sensitivity/invert/scope/volume/quality, persistence/reset, both menu entry points; 7 tests | done | CP5 |
| S57 | Protocol v2 / 16 actors | 18 B row, 150 B @8 / 294 B @16, version handshake, 16-bot probe (p95 ~2–3 ms), 8-marker overflow rings, ring-aware respawn; 148 tests green | done | CP5 |
| S56 | Optimization batch 1 | HUD dirty flag; bullet-pool prewarm; single-buffer snapshot encode (49→20 µs) + health cache; O(1) roster id index + 10 Hz bot LOS; top-2 respawn rays (24→6); 143 tests green | done | CP5 |
| S55 | Content / artifact standard | Manifest + packs + entries, `ContentCatalog`, budget validation, `tools/validate_content.gd`, CI gate, catalog-backed `WeaponRegistry`; map/class/weapon/collectible recipes in `docs/CONTENT-STANDARD.md` | done | CP5 |
| S54 | Quick menu (all phases) | Esc overlay for menu / connecting / match / respawning / solo / match over; resume, cancel, leave, restart solo, settings placeholder, quit; pauses solo only | done | CP5 |
| S53 | First-load auto-join | `?join=1` now waits 3 rendered frames before opening the socket; the quarry's first software-WebGL frame was eating the 6 s connect budget (manual Join always worked) | done | CP5 |
| S52 | Damage/scope pass | Head hitbox + headshot multiplier removed; bleed/spread/effect/armour_pierce/gravity removed; flat rounds inherit shooter velocity (experimental); Knight 34, Mage 18 + 8 splash (mag 12), bow 60, crossbow 12, Barbarian 34 → 3-hit kills; Knight reload 1.4 s | done | CP5 |
| S51 | Class balance pass | Projectiles −30 % speed; Mage cycle +40 %, damage −20 %; crossbow 18/36; heavy gravity 12/10; pierce second-hurtbox fix | done | CP5 |
| S50 | Sunken Quarry arena | 150×150 m, 3×3 mesh chunks, heightmap/collision, 61 m double-wall cave, rock skirts, MultiMesh foliage, 8 spawns; 49 draw calls / 192,842 tris | done | CP5 |
| S54 | Map finish pass | Stone shading fixed after linear conversion; seamless gravel grain; 8 central cover clusters; 16 heightfield ring outcrops; cave/terrace screenshots refreshed | done | CP5 |
| S53 | Map QA walkthrough | Real-physics 35-section harness (chunks, cave, ramps, bridge, tower, lookout, spawns, edges, falls); fixed cave aprons, ramp lane blockers, bridge lip/east landing, lookout access, spawn slopes, cave floor z-fighting | done | CP5 |
| S49 | Class weapons v1 | Five class profiles, picker (`?class=`), per-class variants/models/animations/HUD; M4 retired for now; Quaternius CC0 spear/bow models | done | CP5 |
| S48 | Class weapons + bigger map research | Report + decisions at `docs/research/weapons-and-arena.md` / `WEAPONS-DECISIONS.md` | done | CP5 |
| S47 | Roster cap | Accepted **8 total actors** (humans + bots) for V1; soak covers 4+4 and 8+0. 8 clients + 4 bots would need MAX_PLAYERS=12 plus 4 more spawns and a 270 B snapshot row | done | CP4d |
| S46 | Remote death visuals | Death_A + red pool/shell marker now play for local and remote deaths; corpses stay visible until respawn | done | CP4c-fix |
| S32 | Playtest 2026-10-29 | Connection never reached `:9180`; see `docs/PLAYTEST-2026-10-29.md` | done | CP4c |
| S1 | Jump height +10 % | `jump_velocity` 7.00 → **7.34** (apex 1.23 m → **1.35 m**) | done | CP1 |
| S2 | Character 20 % smaller | Physical capsule, mesh, hurtboxes scaled to 0.8; camera framing unchanged for now | done | CP1 |
| S3 | Re-check camera after shrink | User accepted the current 3.6 m / 0.55 m / 1.55 m framing as-is | done | CP1 |
| S4 | Re-check speed after shrink | Keep 5.6 m/s after the size change; only revisit if CP2 playtests ask for it | done | CP1/CP2 |
| S5 | Map scale | Final map is the 150×150 m Sunken Quarry (`arena_quarry.tscn`); the 60×60 nature arena remains for experiments | done | CP3+ |
| S6 | Jump floatiness | Deferred by request. Current airtime is unchanged conceptually; fixing requires retuning gravity, jump velocity, air control and maybe fall curves together | deferred | CP3+ |
| S7 | Shadow/lighting verification | Headless software rendering does not show directional shadows; verify on real Chrome/desktop GPU before changing the lighting budget | doing | CP2/CP3 |
| S8 | Character model | Replaced the capsule with Kenney Blocky `character-a`, 1.36 m, animated idle/walk/sprint | done | CP2 |
| S9 | Log/stump collision | Logs and stumps now have solid box/cylinder colliders (were walk-through) | done | CP2 |
| S10 | Tree/rock collider fit | Tree trunk radius reduced from 0.36× to 0.12× scale; low-rock height corrected so invisible collision no longer feels spherical | done | CP2 |
| S11 | Gun attached to character | Gun/muzzle reparented from the player root to `Visual/GunMount`; mount copies camera pitch (+recoil); yaw inherited from the body. Now docks front-center in the mannequin's hands when still, shoulder when moving | done | CP3 |
| S16 | Server-authoritative spawn pose | `JOIN_OK` now carries spawn position + yaw; fixed a 22 m client/server mismatch and an inverted spawn yaw that faced players at the wall | done | CP4a |
| S31 | Bot difficulty | Bots have perfect aim and are aggressive; add reaction delay/spread after playtest | open | CP4c |
| S30 | Remote death presentation | Ghosts hide on hp 0; add a death clip/ragdoll later | open | CP5 |
| S29 | Combat authority | Server fire intent, canonical muzzle, events, death/respawn/protection, 4 bots | done | CP4c |
| S28 | Low-FPS input starvation | Max 4 physics steps; 2-tick extrapolation then freeze; ack pinned; regression freezes 16/40 ticks | done | CP4b/4d |
| S27 | Camera occlusion by players | Dither fade (instance uniform) is the chosen approach; deferred to CP5 polish | planned | CP5 |
| S26 | Jump scale after speed retune | 1.22 m apex at 1 m/s walk feels high; decide whether to scale jump/gravity | open | CP4c/CP5 |
| S25 | Playtest: camera at walls | Centred pivot, camera-side shoulder offset, 5 cm cast sphere, collapsing shoulder; regression test | done | CP4b |
| S24 | Playtest: gun mount | Gun follows `DEF-hand.R`, upper-body aim hold, filtered Pistol_Shoot overlay | done | CP4b |
| S23 | Playtest: movement axes | Independent view yaw, body turns to movement, aim strafe, deterministic 180° tie-break | done | CP4b |
| S22 | Playtest: speed scale | Walk 1.0 m/s / sprint 2.5 m/s; airborne sprint cannot start; animation scales retuned | done | CP4b |
| S21 | Playtest: border tree collision | Decorative diagonal trees lacked colliders; added trunk colliders (145 total) | done | CP4b |
| S20 | Upper-body shoot animation | Filtered second AnimationPlayer; upper body only, no leg snapping | done | CP4b |
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
| L1 | Proper jump physics pass | **Done:** `v=9.03`, rise `g=34`, fall `g×1.35=45.9`, terminal 30; apex stays 1.35 m, full airtime 0.67 → **0.50 s**; coyote 0.12 s, buffer 0.15 s, air accel 18. Analytic `v²/2g` / `2v/g` helpers + tests | done |
| L2 | Character scale system | **Step 1 done:** `CharacterBodyStats` + five identical profiles, applied on LOCAL/REMOTE/SERVER; per-class sizes deferred to Step 2 | done |
| L3 | Camera framing pass | Current framing accepted; later add ADS shoulder offset, collision smoothing and wide/tight presets | done |
| L4 | Larger map performance | Current map is 35 draw calls / 31k tris. A larger final map needs occlusion/LOD/fog decisions and a new budget measurement | todo |
| L5 | Movement set | Add slide/dash/roll later only if the core loop needs it; do not add before netcode so prediction scope stays small | deferred |
| L6 | Settings UI | **Done:** reusable panel from main menu + quick menu; sensitivity, invert Y, scope scale, master volume, LOW/MEDIUM/HIGH quality; persistence + reset; 7 tests | done |
| L7 | Animation / stride | Quaternius UAL landed (S15): real walk/sprint/jump/pistol clips. Remaining: strafe/back clips (only in the paid full set), AnimationTree layering, Pistol_Shoot/Pistol_Reload hooks, Death01 wiring | doing |
| L8 | Server parity | **Step 1 done:** capsule/hurtbox/camera/muzzle read the same profile on all roles; no headshots, no protocol change | done |
| L9 | Browser matrix | **Research:** 13-cell matrix and 7 questions in `docs/research/L9-QUESTIONS.md`; implementation gated on answers | doing |
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
