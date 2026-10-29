# Research prompt — class weapons + larger playground

**Asked by:** manager (Ball of Duty)
**For:** research/brainstorm agent (external or subagent)
**Type:** research + design only. Do **not** implement code, scenes, or assets.
**Output:** write the report to `docs/research/weapons-and-arena.md` and list any decisions that
need the user.

---

## Project context

Ball of Duty is a **web-first, third-person, server-authoritative arena shooter** in Godot 4.7.2
(Compatibility renderer, single-threaded web export, 30 Hz server, 60 fps target, snapshots ≤300 B).
Current build:

- 5 playable KayKit Adventurers 2.0 characters on the shared `Rig_Medium` skeleton:
  **Knight (0.82 m), Mage (0.856 m), Rogue (0.703 m), Rogue_Hooded (0.701 m), Barbarian (0.773 m)**.
- One weapon: Quaternius M4 rifle, 81 m/s projectile, 25 body / 50 head damage, 30-round magazine,
  1.6 s reload. Server-authoritative projectiles. Bots use the same weapon.
- The character animation library already contains:
  `Throw`, `Ranged_1H_Aiming/Shoot/Shooting/Reload`, `Ranged_2H_Aiming/Shoot/Shooting/Reload`,
  `Ranged_Bow_Aiming_Idle/Draw/Draw_Up/Release/Release_Up`, `Ranged_Magic_Raise/Shoot/
  Spellcasting/Spellcasting_Long/Summon`, `Running_HoldingBow`, `Running_HoldingRifle`,
  strafes/backpedal/jump/hit/death. **No new animation pack is required for the concepts below.**
- KayKit Adventurers free tier includes **25+ weapons/accessories** (swords, shields, axes, bow,
  crossbows, arrows, staff, wand). Verify exact file names/scales from the official zip:
  <https://kaylousberg.itch.io/kaykit-adventurers> and
  <https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0>
- Animations: <https://kaylousberg.itch.io/kaykit-character-animations> (CC0, `Rig_Medium`).

The game currently has a single rifle archetype; the user wants **class-flavoured ranged weapons**
with different powers/effects (to be implemented later), animations, ranges and cooldowns.

## Part A — weapons per character (main deliverable)

Design **one long-range weapon per character**, keeping all five distinct and readable in third
person. Starting concepts (change them if research suggests better):

| Character | Starting concept | Existing clips |
|---|---|---|
| Knight | thrown spear / javelin | `Throw` (1.37 s), `Ranged_2H_*` |
| Mage | wand / staff, arcane bolt | `Ranged_Magic_Shoot`, `Ranged_Magic_Spellcasting` |
| Rogue | bow + arrow, draw/charge | `Ranged_Bow_Draw` → `Ranged_Bow_Release` |
| Rogue_Hooded | hand crossbow / throwing knives | `Ranged_1H_Shoot`, `Throw` |
| Barbarian | throwing axe / boulder | `Throw` |

For each weapon provide:

1. **Fantasy/role** in one sentence; why this character carries it.
2. **Model candidate** with exact asset name, pack, source URL, license, triangle count if known,
   material count, and a proposed scale factor for the 0.70–0.86 m characters. Prefer the
   KayKit Adventurers weapons; if a model is missing, give a CC0 alternative (Kenney, Quaternius,
   Poly Pizza) with a verified link.
3. **Animation map**: which existing clip(s) for idle, aim, fire, reload, and any charge/hold;
   note whether an upper-body overlay is needed and whether a new clip from `CombatMelee`,
   `Tools`, or the 1.1 sets is worth importing.
4. **Combat profile (seed values, not final balance):** projectile type, speed (m/s), effective
   range (m), damage (body/head), fire/charge cooldown (s), magazine/ammo/reload or mana, spread,
   projectile lifetime, and whether it is hitscan or travelling.
5. **Signature effect for later:** e.g. pierce, arcane splash, bleed/mark, chain, knockback,
   gravity arc, shield break. Keep the V1 implementation simple (one projectile + one effect hook).
6. **Counterplay/weakness:** why it is not strictly better than the rifle.
7. **Networking cost:** projectile count/size, effect replication needs, whether the existing
   `SHOT`/`HIT` events and `WeaponStats` resource can carry it, and any protocol change.
8. **UI/feel:** crosshair, scope/ADS, charge indicator, hitmarker, audio placeholder.

Also propose the **weapon-selection model**: weapon tied to character variant (`net_id % 5`) vs a
pre-match class picker; how bots choose; what happens on respawn; whether players can pick up or
swap weapons later.

Deliver a comparison table and a short “recommended V1 kit”. Flag any concept that would require
new animation work or a protocol change.

## Part B — bigger playground (mountains, caves, blockers)

Current arena is 60×60 m, 50 draw calls / 32.5k tris, 8 spawn points, 145 colliders. Target:
a larger map (suggest 120–200 m across) with **mountains, caves, verticality, and blocking cover**
that still runs on low-end WebGL 2.

Research and recommend:

1. **Asset packs with verified links/licenses**: low-poly forest/nature (trees, rocks, cliffs),
   modular cave/dungeon walls, ruins/blockers. Candidates to verify:
   - KayKit Forest Nature Pack: <https://kaylousberg.itch.io/kaykit-forest>
   - KayKit Dungeon Remastered: <https://kaylousberg.itch.io/kaykit-dungeon-remastered>
   - Quaternius nature packs: <https://quaternius.com/>
   - Kenney Nature Kit / Survival Kit: <https://kenney.nl/assets/nature-kit>,
     <https://kenney.nl/assets/survival-kit>
   - Poly Haven CC0 textures: <https://polyhaven.com/>
   - Poly Pizza CC0 individual meshes: <https://poly.pizza/>
   For each: license, format, scale, poly counts, texture sizes, and web-suitability.
2. **Terrain strategy for web/Compatibility**: chunked mesh heightfields vs a single mesh vs
   plugins. Explicitly evaluate `Terrain3D` (<https://github.com/TokisanGames/Terrain3D>) and state
   whether it works without compute shaders/RenderingDevice. Recommend collision (`HeightMapShape3D`
   / trimesh), LOD/visibility ranges, fog, and a triangle/draw-call budget for 8 actors.
3. **Caves**: modular tunnel/rock pieces, entrances, occlusion, collision, and how to stop players
   seeing through seams. Verify pack coverage.
4. **Layout concepts** (2–3): spawn placement, sightlines, high ground, cave routes, cover lanes,
   and how mountains block bullets and create hiding spots. Include a rough top-down sketch in text.
5. **Performance plan**: target draw calls/triangles/VRAM, instancing/MultiMesh, texture budget,
   collision complexity, and a staged implementation path (greybox → art pass).

## Constraints

- Web/Compatibility, single-threaded; no compute-shader-only plugins.
- CC0/free assets only; no paid packs unless explicitly flagged.
- Keep the 0.82 m character scale; weapons and props must fit the existing hands/camera.
- Server-authoritative combat; no client-side damage.
- Do not change the 8-actor V1 cap in this report; note if a larger map needs more spawn points.

## Output format

`docs/research/weapons-and-arena.md`:

1. Executive summary + recommended V1 kit.
2. Weapon matrix (the 8 columns above) + asset table with links/licenses/scale.
3. Animation map per weapon, noting any missing clips.
4. Playground asset table + terrain/cave strategy + 2–3 layout concepts.
5. Performance budget and staged plan.
6. Open questions for the user, each with a recommended default.
7. Source links with access dates; mark anything you could not verify.
