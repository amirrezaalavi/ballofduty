# CP3 — Combat, HUD & audio

- **Date:** 2026-10-29
- **Build:** `eb161f7`
- **Status:** implementation complete — **awaiting combat feel review**
- **Engine:** Godot 4.7.2, Compatibility, 30 Hz physics

## What landed

- **Rifle resource** (`resources/weapons/rifle_stats.tres`): 25 body / 50 head damage, 10 rps,
  30-round magazine, 1.6 s reload, 90 m/s projectile, 0.3° spread, 0.7° recoil, infinite reserve.
- **Swept projectiles**: a ray from the previous to the new position each tick, so 90 m/s at 30 Hz
  cannot tunnel through hurtboxes.
- **Hurtboxes**: `HurtboxComponent` on head/body; `CombatResolver` is the only writer of health.
- **Weapon controller**: ammo, fire-rate gate, auto-reload, manual `R` reload, muzzle flash, recoil,
  projectile exclusion for the shooter's own colliders, synthesized SFX.
- **HUD**: crosshair with bloom/hitmarker, health bar, ammo/reserve, reload state, damage vignette,
  kill feed stub, headshot-coloured hitmarker.
- **Training dummies**: 3 in the arena (2 static, 1 strafing), head/body hurtboxes, floating health,
  death → 2 s hide → full reset.
- **Avatar/gun**: Blocky character with idle/walk/sprint animation and a simple rifle mesh at the muzzle.
- **Fixes from your review**: log/stump colliders, tighter tree/rock hitboxes, camera up-pitch clamp
  (no more camera going under the floor), pointer-lock look guard, buffered click-to-fire.

## Automated evidence

`tests/headless/combat_test.gd` → **204 checks, 0 failures**

| Check | Result |
|---|---|
| Data-driven damage / rate / mag / reload | pass (25, 2×, 10 rps, 30, 1.6 s) |
| Projectile hits 20/20 at **5 m** (head) | pass |
| Projectile hits 20/20 at **15 m** (head) | pass |
| Projectile hits 20/20 at **30 m** (head) | pass |
| Body damage / head damage | **75 hp / 50 hp** remaining (25 / 50 damage) |
| Head/body hitbox reporting | pass |
| Firing consumes one round | pass |
| Fire-rate blocks an immediate second shot | pass |
| Reload starts / finishes / refills to 30 | pass |
| No shooter self-hit | exclusion RIDs on aim + projectile |

Other gates:

- `smoke_test.gd`: **88 checks, 0 failures**
- `movement_test.gd`: **14 checks, 0 failures**
- `arena_stats.gd`: **50 draw calls, 32,544 triangles**, 0 blocked spawns, log solid
- Web payload: **10,213 KB gzip**
- Web boot: 0 console errors; HUD, character, dummies and labels render

Screenshot: [`cp3-combat-hud.png`](./cp3-combat-hud.png)

## Awaiting your feel test

1. **Shooting**: 10 rps, recoil, spread, muzzle flash, tracer speed; does it feel responsive?
2. **TTK**: 4 body shots or 2 headshots to down a dummy.
3. **HUD**: health/ammo placement, crosshair gap, hitmarker, reload text.
4. **Reload**: `R`, auto-reload at 0, 1.6 s.
5. **Dummies**: hit feedback, death, 2 s respawn, strafing target.
6. **Audio**: synthesized shoot/hit/reload/death; is the mix acceptable?
7. **Camera**: up-pitch clamp and capture-click no longer fling the view.

## Known gaps

- No enemy can damage the player yet, so the damage vignette and health decrease are code-only until
  CP4c bots.
- Kill feed is a single “TARGET DOWN” stub; names/weapon icons arrive with the CP5 scoreboard.
- The rifle is a simple mesh viewed mostly end-on from the third-person camera; a proper hand-held
  viewmodel/pose is backlog **L13**.
- The Blocky avatar is shirtless (`character-a`); variants/team colours are backlog **L12**.
- Headless test harness is clean of gameplay errors; no exit-time leak warnings after the projectile
  spawn-toggle fix.
- Real-GPU FPS/shadows remain CP2/CP5 review items.
