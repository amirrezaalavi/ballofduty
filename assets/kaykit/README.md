# KayKit Phase 1A assets

CC0 1.0 — see [`LICENSE.txt`](./LICENSE.txt).

## Roster

| net_id % 5 | Variant | Source | Merged tris | Height at 0.32244 |
|---:|---|---|---:|---:|
| 0 | Knight | `adventurers/knight.glb` | 5,800 | 0.820 m |
| 1 | Mage | `adventurers/mage.glb` | 6,668 | 0.856 m |
| 2 | Rogue | `adventurers/rogue.glb` | 7,562 | 0.703 m |
| 3 | Rogue_Hooded | `adventurers/rogue_hooded.glb` | 7,185 | 0.701 m |
| 4 | Barbarian | `adventurers/barbarian.glb` | 7,123 | 0.773 m |

All five use the uniform **0.32244** scale and a 180° yaw so they face the game forward axis
(−Z). The Knight is exactly 0.82 m; the other silhouettes differ because of hats, hoods and the
barbarian's build. The capsule and the unchanged head hurtbox remain 0.82 m / y 0.72 / r 0.115.

The local host (`net_id` 0) is the Knight. Remotes and bots use `abs(net_id) % 5`, so every client
picks the same variant for the same id. There is no separate bot subset.

## Merge

Each source character has 7–9 `MeshInstance3D` parts under one `Skeleton3D`, all sharing one
material and one 23-bone skin. They are concatenated into one indexed `ArrayMesh` surface (vertex,
normal, tangent, UV, bones, weights and re-based indices), keeping the original `Skin`. The nine
draws/shadow draws per character become **one** surface and character shadows are disabled.

`*.scn` is generated, not hand-edited. To rebuild after replacing a source GLB:

```bash
./tools/godot --headless --path . --script res://assets/kaykit/tools/build_assets.gd
```

The build script also regenerates:

- `animations/kaykit_medium.res` — 55 clips from the four Rig_Medium sets, loop modes baked,
  root translation tracks stripped (server-authoritative movement never gets root motion).
- `animations/kaykit_upper.res` — upper-body-only `Ranged_2H_Aiming`, `Ranged_2H_Shoot`,
  `Ranged_2H_Shooting`, `Ranged_2H_Reload`, `Hit_A`, `Hit_B`.
- `../weapons/rifle/rifle.scn` — the M4 wrapper.

## Textures

The imported atlases use `process/size_limit=512` (down from the source 1024), mipmaps on,
lossless compression. Five variants cost roughly **6.7 MB** of texture memory instead of
26.7 MB. The game uses one variant per actor, not a per-actor local/remote resolution split.

## Animation map

| Situation | Clip |
|---|---|
| still | `Idle_A` |
| walk forward | `Walking_A` (`Walking_B/C` available) |
| walk backward | `Walking_Backwards` |
| strafe | `Running_Strafe_Left` / `Running_Strafe_Right` (slowed) |
| sprint | `Running_HoldingRifle` |
| jump | `Jump_Start` → `Jump_Idle` → `Jump_Land` |
| aim (upper body) | `Ranged_2H_Aiming` loop |
| shoot (upper body) | `Ranged_2H_Shoot`, speed 6.5 (~0.16 s) |
| reload (upper body) | `Ranged_2H_Reload`, 1.60 s — matches `reload_time` |
| hit (upper body) | `Hit_A` / `Hit_B` |
| death (full body) | `Death_A` / `Death_B` |

Local players play the aim overlay while scoped or in the post-fire window (Phase 0 behaviour).
Remote ghosts intentionally hold `Ranged_2H_Aiming` because aim is not replicated. `force_anim`
still works for remotes and also selects strafe/backpedal from the observed velocity.

## Gun contract

`WeaponController.muzzle_path` remains `../Visual/GunMount/Muzzle`. `CharacterVisual` reparents
`GunMount` under a `BoneAttachment3D` targeting `handslot.r`; the world scale stays 1.0. The M4
wrapper is scaled 0.1 (the source child is 100×), rotated +90° so its barrel points −Z, and offset
so the pistol grip sits at the mount origin. `Muzzle` stays a `Marker3D` under `GunMount`.

## Budget

Measured headlessly with `arena_nature.tscn` + five players (one merged character + 3-surface M4
each, muzzle flash included): **70 surfaces / 76,532 triangles**. The Phase 1 gate is 150 draw
calls / 250k triangles.
