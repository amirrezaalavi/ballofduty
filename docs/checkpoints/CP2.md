# CP2 — Arena, assets & lighting

- **Date:** 2026-10-28
- **Build:** `f3bbd7d` (post-review patch)
- **Status:** visual review patch applied — **awaiting re-check**
- **Engine:** Godot 4.7.2, Compatibility, 30 Hz physics

## Asset audit

| Item | Value |
|---|---|
| Pack | **Kenney Nature Kit 2.1** |
| License | **CC0** (license text: `assets/kenney_nature/License.txt`) |
| Source | https://kenney.nl/assets/nature-kit |
| Models used | 22 GLB files (trees, rocks, cliffs, bushes, grass, flowers, mushrooms, log, stump) |
| Textures | none — material colors only, **~0 MB texture memory** |
| Style | one low-poly family, bright greens + warm stone, restyled palette applied to GLB surface materials |
| Character pack | **Kenney Blocky Characters 2.0**, CC0 — `character-a` + palette texture |
| Credits | `assets/CREDITS.md` |

## Arena

- Playable footprint **60×60 m** (visual floor 72×72 m), invisible boundary walls at ±30.5 m,
  a 3 m segmented rock wall just outside, and a 20-tree inner line to hide the boundary.
- **8 spawn markers** on a 22 m radius; minimum pairwise distance **≈16.8 m** (smoke test enforces ≥15 m).
  None are blocked by geometry (physics query in `arena_stats.gd`).
- 2 raised stone platforms (4×4 m, 0.8 m high) separated by a **2 m gap** for the CP1 movement check.
- A 3 m stone wall for camera-collision testing.
- Browser arena: 12 hero trees + 11 rock formations + logs/stumps, hand-placed for cover;
  decorative foliage (bushes/grass/flowers/mushrooms) scattered deterministically.
- Runtime scatter uses a fixed seed (`20261028`) with spawn/center/platform exclusion; client and server
  build the same layout.
- One `DirectionalLight3D` (shadowed, 80 m range), sky + warm ambient color, Filmic tonemap;
  no SSAO, SSR, volumetric fog, or GI.

## Post-review fixes

- **Avatar:** replaced the capsule/primitive face with an animated Kenney Blocky character
  (`character-a`, 1.36 m). `CharacterVisual` drives idle/walk/sprint from movement speed and scales the
  animation rate to the character's actual speed. The GLB's external palette texture is applied
  explicitly because the importer does not bind the URI.
- **Fallen log:** now has a rotated box collider (was walk-through); stumps got cylinder colliders too.
- **Tree/rock hitboxes:** tree trunk radius reduced from `0.36×scale` to `0.12×scale`; the low-rock
  cylinder height was cut from `0.45×scale` to `0.30×scale`, removing the oversized "sphere" feel.
  `arena_stats.gd` now asserts the log is solid and spawns are unblocked.

## Budget evidence

`tools/godot --headless --path . --script tests/headless/arena_stats.gd`:

```text
arena_stats: draw_calls=35 triangles=31092 prop_instances=281 colliders=114 blocked_spawns=0 log_solid=true
```

| Metric | Budget | Result |
|---|---|---|
| Draw calls | ≤ 150 | **35** |
| Triangles | ≤ 250k | **31,092** |
| Texture memory | ≤ 100 MB | **~0 MB** (no textures) |
| Directional lights | 1 | **1** |
| Spawn blockage | 0 | **0** |
| Web payload (gzip) | ≤ 20 MB | **10,189 KB** (was 10,042) |

MultiMesh is used per prop type; 281 visible props cost 35 draw calls. Collision is analytic
(cylinders/boxes), not per-triangle, so the 60×60 playable space stays cheap.

## Verification run

- `smoke_test.gd`: **76 checks, 0 failures** (nature scene, 8 spawns, ≥15 m spacing, character + animations, autoload).
- `arena_stats.gd`: budget pass, **0 blocked spawns**.
- `movement_test.gd`: **14 checks, 0 failures**.
- `tools/check.sh`: import → smoke → arena → movement → client/server boot → Web + Linux export → server smoke.
- Web boots in Chromium with **0 console errors**; screenshot:
  [`cp2-nature-arena.png`](./cp2-nature-arena.png).

## Still needs your eyes / real GPU

1. **Avatar**: does the Blocky character read well from behind? (Variants/team colours are backlog L12.)
2. **Log/stump collision** and the tighter tree hitboxes — walk into them.
3. **Visual layout**: density, colour palette, boundary wall, sightlines, cover placement.
4. **Stuck spots / fall-throughs**: walk the perimeter, platform edges, rock clusters.
5. **60 FPS at 1280×720** on the reference low-end machine. Headless Chromium is software-rendered
   (the screenshot shows ~54 FPS with the debug overlay), so this is not a hardware verdict.
6. **Shadows**: the DirectionalLight is shadowed, but the sandbox renderer shows almost no grounded
   shadows. Confirm on a real GPU before changing the lighting budget.

## Notes

- The 60×60 playable size is deliberate for now; the larger final map remains backlog item **S5/L4**.
- Future terrain/mountains with bullet-blocking surfaces, hiding spots and ≥15× area plus chunked
  LOD/occlusion limits is recorded as backlog **L11** (not in V1).
- Fixed seed means the server and clients generate identical prop placement; the arena is not baked.
- Adding props is cheap visually (MultiMesh) but each large collider adds a StaticBody3D; re-run
  `arena_stats.gd` after map changes.

## Commands

```bash
tools/check.sh
tools/serve.sh        # http://127.0.0.1:8099
tools/godot --headless --path . --script tests/headless/arena_stats.gd
tools/godot --path .  # desktop, F3 overlay
```
