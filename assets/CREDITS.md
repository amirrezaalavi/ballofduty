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
