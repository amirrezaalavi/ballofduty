# CP4c — Combat authority & bots

- **Date:** 2026-10-29
- **Status:** implemented — **awaiting gameplay test**
- **Engine:** Godot 4.7.2, 30 Hz server, binary WebSocket
- **Depends on:** CP4b (prediction/reconciliation)

## What landed

- **Fire intent over the wire.** `INPUT` bits 3/4 are fire/reload. The server mirrors cooldown,
  magazine and reload from `WeaponStats`; fire rate and ammo are validated server-side.
- **Canonical muzzle + aim.** The server derives origin from root + 0.62 m eye + shoulder offset
  (never a skeleton bone, which is not animated headlessly). It traces the view ray to the first
  world/actor hit, then aims the projectile from the muzzle at that point — the same parallax
  correction the client uses. Without it, close headshots missed because the muzzle sits off-centre.
- **Authoritative projectiles.** `ServerCombat` spawns the existing swept `Projectile` in the
  server world. Hits flow through `CombatResolver` → `EventBus`; the client never applies damage.
- **Events** (`Msg.EVENT`): SHOT (shooter, origin, direction), HIT (target, shooter, damage,
  headshot/killed, position), DEATH (victim, killer, position), RESPAWN (id, pose). Clients show a
  hitmarker **only** on a server HIT; the local shot is a cosmetic tracer with no damage.
- **Death/respawn.** 3 s respawn, server chooses the spawn with the greatest distance from living
  enemies (LOS bonus), resets health/ammo/position, and grants 1.5 s spawn protection. Firing cancels
  protection. The client gets a `RESPAWNING` overlay and teleports on the RESPAWN event.
- **HP authority.** Snapshot rows carry the actor's real HP; the local client observes it (no local
  damage). Dead rows send hp 0 and remote ghosts hide.
- **Cosmetic tracers.** Local shots and remote SHOT events spawn a thin 0.9 m tracer; no collision.
- **Bots.** `--bots N` spawns server-driven `PlayerController`s with the same movement/combat code.
  Chase → strafe/attack at ≤7 m, fire when in range and LOS, obstacle feeler, respawn. No navmesh
  in V1 (open arena + feelers); `NavigationAgent3D` + a pre-baked mesh is recorded for CP4d.
- **Dev default:** `tools/dev.sh` starts with **4 bots** (`BOTS=0` disables, `BOTS=2` softens).

## Bugs found while building it

| Bug | Symptom | Fix |
|---|---|---|
| Fire bits not sent | Server never saw fire | `client_send_input` passed sequence/move/aim but not `frame.fire/reload` |
| Muzzle parallax | Body shots worked, close headshots missed | Aim from the muzzle at the view-ray hit point, not parallel to the view |
| Timers advanced only on input | Starved server rejected otherwise valid fire-rate shots | Split `ServerCombat.tick()` (wall clock) from `process()` (intent) |
| Death HP race | Client stayed at pre-death HP while `RESPAWNING` | Observe snapshot HP before the dead guard |
| Freed roster node | Typed `Node = entry["node"]` on a freed actor raised during teardown | Variant + `is_instance_valid` before cast |
| Roster to bots | Negative bot peer ids got server sends | Broadcast only to `peer_id > 0` |

## Automated evidence

| Suite | Result |
|---|---|
| `test_server_combat.gd` | **5 cases** — body/head damage, fire rate, ammo/reload, spawn protection, death attribution |
| `test_loopback_combat.gd` | **1 case** — fire intent → projectile → HIT → death → respawn; spoofed EVENT rejected; cosmetic-only client |
| `test_bots.gd` | **1 case** — 4 bots move, fire, damage/kill each other, stay in roster |
| `test_net_protocol.gd` | **8 cases** — fire/reload bits and all four event roundtrips |
| Full suite | **47 test cases · 0 failures** |

Live evidence (4 bots + 1 browser): 5-player snapshot **116 B**, remotes=4, bots killed the AFK
tester and the client showed `RESPAWNING` with 0 HP, then respawned at full health.

## Acceptance criteria

| Criterion | Status |
|---|---|
| Client cannot deal damage directly; fake damage has no effect | **Pass** — EVENT from a client rejected; local weapon is cosmetic |
| Fire rate > spec rejected; ammo cannot go negative | **Pass** — unit test |
| Headshots 2× server-side; kill attributed | **Pass** — 50 damage; victim/killer in DEATH |
| 8 players / 4 bots 10 min, no desync | **Partial** — 4-bot smoke passes; 10-minute soak is CP4d |
| At 100 ms RTT hitmarkers only on server confirmation | **Pass by design** — cosmetic tracer, server HIT only; feel test pending |
| Spawn protection 1.5 s, cancels on fire; spawn ≥10 m | **Pass** — unit + loopback |
| **Your sign-off** | Pending |

## How to test

```bash
tools/check.sh && tools/dev.sh up     # 4 bots by default
# http://127.0.0.1:8099/?join=1&port=9180&name=You
```

Try: shoot a bot (TARGET DOWN on kill), let a bot kill you (RESPAWNING → 3 s → full HP and a spawn
≥10 m away), and fight near cover. `BOTS=2 tools/dev.sh up` gives a calmer match.

## Known gaps

- No rewind/lag compensation (deliberate V1 decision); lead the projectile.
- Bots have perfect aim and are aggressive; tune reaction/spread after the feel test.
- Remote ghosts hide on death rather than play a death animation.
- Scoreboard, match timer, and scoring UI are CP5; respawn/reconnect resilience is CP4d.
