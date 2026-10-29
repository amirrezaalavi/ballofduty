# Third-party assets

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

## Quaternius Universal Animation Library (Standard) 1.0

- **Author:** Quaternius (https://quaternius.com)
- **Source:** https://opengameart.org/content/universal-animation-library (Standard version, 45 animations)
- **License:** Creative Commons Zero (CC0) — see [`quaternius_ual/License.txt`](./quaternius_ual/License.txt)
- **Used:** `animation_library.glb` (Godot version: rigged mannequin + 46 clips incl. T-pose)
- **Modifications:** scaled ×0.448 to fit the 0.82 m capsule, yaw-flipped to face −Z.
  `CharacterVisual` maps Idle→Pistol_Idle, still-scoped→Pistol_Aim_Neutral, Walk/Sprint,
  Walk-reversed for backwards, Jump_Start/Jump/Jump_Land for air. No mesh edits.
- **Phase 1 status:** replaced by the KayKit layer below; the file remains in the repo until the
  Phase 1 integration removes it.

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
