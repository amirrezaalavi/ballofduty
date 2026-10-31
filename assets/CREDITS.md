# Third-party assets

The game code is licensed under the Apache License 2.0 (see `LICENSE` and `NOTICE`). The assets
below keep their own licenses.

## Kenney Nature Kit 2.1

- **Author:** Kenney (https://kenney.nl)
- **Source:** https://kenney.nl/assets/nature-kit
- **License:** Creative Commons Zero (CC0) — see [`kenney_nature/License.txt`](./kenney_nature/License.txt)
- **Used:** 22 GLB models (trees, rocks, cliffs, foliage, logs) under `kenney_nature/models/`
- **Modifications:** scaled, rotated and placed at runtime; no mesh edits.

CC0 requires no attribution, but credit is included here as good practice.

## Future assets

Add an entry here **before** committing any downloaded asset. Record author, source URL,
license (with a local copy of the license text), and what was modified.

## Kenney Blocky Characters 2.0

- **Author:** Kenney (https://kenney.nl)
- **Source:** https://kenney.nl/assets/blocky-characters
- **License:** Creative Commons Zero (CC0) — see [`kenney_blocky/License.txt`](./kenney_blocky/License.txt)
- **Used:** `character-a.glb` + `Textures/texture-a.png`
- **Modifications:** scaled to 1.36 m, rotated to face the player forward axis, animation state driven by
  `CharacterVisual` (idle/walk/sprint). No mesh edits.
- **Note:** the GLB references its palette texture as an external URI; the texture is applied explicitly in
  `CharacterVisual` because the Godot importer does not bind it automatically.

## KayKit Adventurers 2.0 (free tier)

- **Author:** Kay Lousberg / KayKit (https://kaylousberg.com)
- **Source:** https://kaylousberg.itch.io/kaykit-adventurers
- **License:** Creative Commons Zero (CC0 1.0) — see [`kaykit/LICENSE.txt`](./kaykit/LICENSE.txt)
- **Used:** Knight, Mage, Rogue, Rogue_Hooded, Barbarian (`kaykit/adventurers/*.glb`)
- **Modifications:** the seven-to-nine character parts are merged into one skinned surface per
  character, scaled ×0.32244, yawed 180°, character shadows disabled; atlases downsampled to
  512×512. Generated scenes are `kaykit/adventurers/*.scn`.

## KayKit Character Animations 1.1 (Rig_Medium, free tier)

- **Author:** Kay Lousberg / KayKit (https://kaylousberg.com)
- **Source:** https://kaylousberg.itch.io/kaykit-character-animations
- **License:** Creative Commons Zero (CC0 1.0) — see [`kaykit/LICENSE.txt`](./kaykit/LICENSE.txt)
- **Used:** `General`, `MovementBasic`, `MovementAdvanced`, `CombatRanged` sets
  (`kaykit/animations/rig_medium_*.glb`)
- **Modifications:** clips extracted into the shared `kaykit_medium.res`; loop modes baked; root
  translation tracks stripped; upper-body filtered copies in `kaykit_upper.res`.

## Quaternius Assault Rifle (M4)

- **Author:** Quaternius (https://quaternius.com)
- **Source:** https://poly.pizza/m/Bgvuu4CUMV
- **License:** Creative Commons Zero (CC0 1.0) — see [`weapons/rifle/LICENSE.txt`](./weapons/rifle/LICENSE.txt)
- **Used:** `weapons/rifle/quat_assault_rifle.glb`
- **Modifications:** wrapper scaled ×0.1, yawed +90° so the barrel points −Z, grip offset applied,
  shadows disabled. Generated scene: `weapons/rifle/rifle.scn`.

## KayKit Adventurers 2.0 — Phase 2A class weapons

- **Author:** Kay Lousberg / KayKit (https://kaylousberg.com)
- **Source:** https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0
  (`addons/kaykit_character_pack_adventures/Assets/gltf/`)
- **License:** Creative Commons Zero (CC0 1.0) — local copy in
  [`weapons/class/LICENSE.txt`](./weapons/class/LICENSE.txt); the upstream repo ships the same CC0 text.
- **Used:** `staff.gltf`, `crossbow_1handed.gltf`, `axe_1handed.gltf`, `arrow.gltf` plus the
  `mage_texture.png`, `rogue_texture.png` and `barbarian_texture.png` atlases in
  `weapons/class/source/`.
- **Generated:** `weapons/class/mage_staff.scn` (staff ×0.36, laid forward, grip at y=−0.15,
  0.776 m), `hooded_crossbow.scn` (×0.55, yawed 180°, 0.672 m), `barbarian_axe.scn`
  (×0.50, laid forward, 0.622 m). All weapons use the hand-grip origin and point down −Z;
  shadows disabled at runtime. Rebuild with `assets/weapons/class/build_weapons.gd`.

## Quaternius — Phase 2A spear and bow

- **Author:** Quaternius (https://quaternius.com)
- **Sources:** [Spear](https://poly.pizza/m/fH1zmvjPNx) and
  [Wooden Bow](https://poly.pizza/m/QnpqjLSKFU) on Poly Pizza; part of the CC0
  Ultimate RPG Items Bundle / LowPoly Medieval Weapons pack.
- **License:** Creative Commons Zero (CC0 1.0) — see
  [`weapons/class/QUATERNIUS-LICENSE.txt`](./weapons/class/QUATERNIUS-LICENSE.txt).
- **Used:** `spear.glb` (3.6k verts, 4 materials) and `bow.glb` (2k verts).
- **Modifications:** spear scaled ×0.15 to a 1.46 m javelin, laid forward (−Z), grip at the
  balance point; bow scaled ×0.36 to a 0.71 m recurve, yawed 90°, with the KayKit arrow nocked.
  Shadows disabled. Generated scenes: `knight_spear.scn`, `rogue_bow.scn`.



## Sunken Quarry & Cavern Pass (Phase 2B)

- **Author:** project code, no new third-party download.
- **Used:** the existing Kenney Nature Kit GLBs listed above (trees, rocks, cliffs, foliage),
  plus runtime-generated `ArrayMesh`/`BoxMesh` terrain, cave lining, ruins, bridge and a
  128 × 128 procedural gravel detail texture (`FastNoiseLite`, fixed seed).
- **License:** assets remain CC0 as recorded above; generated geometry/texture is project-owned.
