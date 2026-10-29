# KayKit character + rifle integration research (Phase 1, option B)

**Status:** research only. No files under `scripts/`, `scenes/`, `assets/`, `resources/`, or
`project.godot` were changed. All downloads used for inspection are in
`/srv/opencode/tmp/kaykit-research/` (outside the repo).

**Date:** 2026-10-29 · **Engine checked against:** Godot 4.7.2 stable (`ed1daf0bf`, the project's
`tools/godot` binary) · **Target:** Web/Compatibility, 8 players + 4 bots, 0.82 m capsule.

**Method note:** vendor pages, prices and license statements were read on the official pages on
2026-10-29. itch.io's direct file download was not reachable from this sandbox, so geometry and clip
measurements were taken from the same CC0 files in a public mirror of **The Complete KayKit
Collection v6** (`GeorgeQLe/assets-kaykit-3d-characters`, which cites the collection and ships the
original CC0 license). Re-check filenames/roster against the official free zip before committing.

---

## 0. Verdict

1. **Use the current Adventurers 2.0 free tier, not the 1.0 GitHub archive.** 2.0 characters are
   23-joint `Rig_Medium`, 341–409 KB per GLB, 5.8k–7.6k triangles, one 1024×1024 atlas. The old 1.0
   archive is a 41-joint IK rig, 3.6 MB per character, with 76 embedded clips; it is not the rig the
   free Character Animations pack is designed for.
2. **Use the free Character Animations 1.1 `Rig_Medium` sets** (`General`, `MovementBasic`,
   `MovementAdvanced`, `CombatRanged`). They are CC0 and contain every clip this game needs:
   idle, walk, run, **left/right strafe**, **backpedal**, jump/fall/land, **rifle aim, reload and
   shoot**, hit and death. No paid clip is required.
3. **The rigs match out of the box:** Adventurers 2.0 characters and Character Animations 1.1 both
   have 23 bones with identical names and parent chains. No retarget step is needed.
4. **Scale:** source height is **2.543 m** (helmet visor included). Scale by **0.32244** for a
   0.820 m character. The character faces **+Z** in Godot after import, so yaw **180°** (positive
   scale plus rotation, not negative scale).
5. **Biggest risks are draw calls, not file size.** Each character is **9 meshes** (9 draw calls,
   plus 9 shadow calls if shadows are on). 12 characters + guns + the 35-call map can exceed the
   150-draw-call budget. Merge the 9 character meshes to one skinned mesh (or disable character
   shadows and cap the player count).
6. **Head hurtbox mismatch:** the visual head spans roughly **y 0.35–0.82 m**, but the current head
   sphere is at **y 0.72, r 0.115** (covers only the helmet top). Either move/resize the head hurtbox
   (needs approval; changes hit feel) or accept that face-height shots count as body shots.
7. **Rifle recommendation:** Quaternius' CC0 **Assault Rifle (M4)** on Poly Pizza
   (`/m/Bgvuu4CUMV`, 1,930 tris, 3 materials), with the AK variant (`/m/fpLucho45C`, 1,388 tris,
   5 materials) or the cute period musket (`/m/neEjwx9bBJ`, 1,534 tris) as alternates. The KayKit
   Adventurers `shotgun.gltf` is the exact style match but is a shotgun and appears to be tied to the
   paid Engineer material, so verify its tier before using it.
8. **Web payload impact is negligible:** replacing the 1.1 MB UAL `.scn` with the character
   (166 KB) + four animation sets (1.26 MB) adds roughly **+0.33 MB** to the PCK, about **+0.1 MB
   gzipped** against the current 11.3 MB web build. Texture VRAM, not gzip size, is the thing to watch.

---

## 1. KayKit Character Pack: Adventurers

### 1.1 Official source and license

| Field | Value |
|---|---|
| Author | Kay Lousberg (KayKit) |
| Official page | <https://kaylousberg.itch.io/kaykit-adventurers> (accessed 2026-10-29) |
| Author site | <https://kaylousberg.com> |
| License | **CC0 1.0 Universal** (public domain dedication) |
| License URL | <https://creativecommons.org/publicdomain/zero/1.0/> |
| Formats | FBX, glTF/GLB, OBJ for props, PNG atlas; `.blend` source only in the paid SOURCE tier |
| Free tier | **5 characters** + 25+ weapons/accessories + basic movement animations |
| Paid tiers | **EXTRA $7.95** (Engineer, Druid, Large Barbarian + alternate textures); **SOURCE $11.95** (`.blend` files) |
| Godot guide | <https://youtu.be/sp_1WnJUDXM> (linked from the vendor page); longer version: <https://www.youtube.com/watch?v=4p7QaOd8SHE> |

License text from the official `LICENSE.txt` in the 1.0 archive (the current pack's license file is
also CC0; quote it from the zip you download):

> License: (Creative Commons Zero, CC0)
> http://creativecommons.org/publicdomain/zero/1.0/
>
> This content is free to use in personal, educational and commercial projects.
>
> Support me by using a brand resource provided in this pack or by crediting Kay Lousberg,
> www.kaylousberg.com (this is not mandatory)

The vendor page also says: *"Free for personal and commercial use, no attribution required. (CC0
Licensed)"* and *"These assets are CC0 so you can use them freely. But please don't resell unmodified
copies or claim them as your own."* The second sentence is a request, not an additional CC0 term.
Credit Kay Lousberg in `assets/CREDITS.md` anyway; it is cheap and accurate.

### 1.2 1.0 archive vs current 2.0 free tier

| | 1.0 GitHub archive | 2.0 current free tier |
|---|---|---|
| Source | <https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0> | <https://kaylousberg.itch.io/kaykit-adventurers> |
| Characters | 5 GLBs: Barbarian, Knight, Mage, Rogue, Rogue_Hooded | 5 free; EXTRA adds Engineer, Druid, Large Barbarian |
| Skeleton | **41 joints**, includes IK/control bones (`kneeIK`, `handIK`, `control-toe-roll`, …) | **23 joints**, `Rig_Medium`, no IK controls |
| Animations in character | **76 clips embedded** (75 advertised + T-pose) | **0 clips**; basic `General` + `MovementBasic` GLBs included; more in the free Character Animations pack |
| Knight triangles | 6,952 | **5,800** |
| Knight meshes | 6 | **9** |
| Knight GLB | 3,659,532 B (3.66 MB) | **341,688 B (342 KB)** |
| Knight imported `.scn` | not measured (old, large) | **166 KB** |
| Material | 1 (`knight_texture`, 1024 PNG) | 1 (`knight`, 1024 PNG) |
| Official animation compatibility | old rig; not the target of 1.1 | **"updated to be compatible with KayKit Character Animations"** (vendor page) |

**Do not start from the 1.0 archive.** It is useful as a historical reference and its clips are named
`1H_Ranged_*` / `2H_Ranged_*`, but its 3.6 MB GLB and 41-joint rig are the wrong trade for a web game.

### 1.3 2.0 character measurements (Godot 4.7.2 import)

All five 2.0 GLBs were imported headlessly with the project's Godot binary. Every character:

- has **23 bones**, names `root, hips, spine, chest, head, upperarm.r/l, lowerarm.r/l, wrist.r/l,
  hand.r/l, handslot.r/l, upperleg.r/l, lowerleg.r/l, foot.r/l, toes.r/l`;
- uses **one material** referencing a **1024×1024 PNG** atlas;
- is a single glTF scene with 7–9 `MeshInstance3D` children under `Rig_Medium/Skeleton3D`;
- has no `AnimationPlayer` (animations are separate);
- faces **+Z** (Knight visor max Z = +0.766; the face protrudes toward +Z).

| Character | Triangles | Mesh nodes | Material | 1024 atlas | GLB size | Imported `.scn` |
|---|---:|---:|---:|---:|---:|---:|
| Knight | 5,800 | 9 | 1 | 12,914 B | 341,688 B | 166 KB |
| Mage | 6,668 | 8 | 1 | 14,740 B | 352,472 B | — |
| Rogue | 7,562 | 7 | 1 | 15,026 B | 409,188 B | — |
| Rogue_Hooded | 7,185 | 8 | 1 | 15,026 B | 381,432 B | — |
| Barbarian | 7,123 | 7 | 1 | 14,424 B | 386,648 B | — |

These are the five base characters. The paid EXTRA Engineer/Druid/Large Barbarian were not
measured. The 2.0 mirror also contains a `Ranger.glb`, but the official page does not list Ranger in
the free/EXTRA text, so treat its tier as unverified.

Knight 2.0 world-space AABB after import: **1.9425 × 2.5431 × 1.3078 m**, feet at **y = 0**.
The tallest point is the helmet visor; the head mesh alone spans y = 1.2159–2.2842 m.

Scale for the existing 0.82 m capsule:

```
scale = 0.82 / 2.543104 = 0.32244
```

Resulting size: **0.820 m tall**, 0.626 m wide (arm span), 0.422 m deep. The existing capsule is
0.38 m wide, so the arms/head overhang the collision shape just as the current UAL mannequin does;
that is cosmetic, not a collision bug.

Visual Y ranges at 0.32244 scale (useful for hurtbox work):

| Part | Source Y | World Y |
|---|---|---:|
| Feet / legs | 0.000–0.529 | 0.000–0.171 |
| Torso | 0.376–1.301 | 0.121–0.420 |
| Head mesh | 1.216–2.284 | 0.392–0.737 |
| Helmet | 1.098–2.398 | 0.354–0.773 |
| Helmet visor (top) | 1.652–2.543 | 0.533–0.820 |
| Arms | 0.975–1.272 | 0.314–0.410 |

### 1.4 Material / texture setup in Godot

The imported Knight material is a `StandardMaterial3D` with:

- `albedo_texture` = the 1024×1024 `knight_texture.png`;
- `metallic = 0.0`, `roughness = 0.5`;
- `cull_mode = 2` (**disabled / double-sided**) because the glTF material is `doubleSided: true`;
- no normal map, no vertex-color-as-albedo.

Godot imports the embedded image as a separate `CompressedTexture2D` (lossless by default; **no VRAM
compression**, `compress/mode=0`). That matters for VRAM:

| Atlas resolution | VRAM per variant (RGBA8 + mips) | 5 variants |
|---|---:|---:|
| 1024×1024 | ~5.3 MB | ~26.7 MB |
| 512×512 | ~1.3 MB | ~6.7 MB |
| 256×256 | ~0.34 MB | ~1.7 MB |

Recommendation for web: import the atlas at **512×512** for the local player and **256×256** for
remote variants, mipmaps **on**, filter linear, no anisotropy. The vendor explicitly says the 1024
atlas can be downsampled to 128; 128 is too soft for the face at the 2.3 m camera, 512 is a good
compromise.

`doubleSided` means all 9 meshes render both faces (roughly 2× fragment work). It is only needed for
the cape and maybe the visor. If fill rate shows up in profiling, set `cull_mode = CULL_BACK` on the
shared body material and give the cape a separate double-sided material. This costs one extra
material/draw call but saves fill on the other 8 meshes. Low priority at 0.82 m character size.

---

## 2. KayKit Character Animations

### 2.1 Official source, license and versions

| Field | Value |
|---|---|
| Official page | <https://kaylousberg.itch.io/kaykit-character-animations> (accessed 2026-10-29) |
| License | **CC0 1.0** — all 161 humanoid animations are free for personal and commercial use, no attribution required |
| Paid tier | **SOURCE $14.99** — `.blend` source files only; not needed for this game |
| Formats | FBX and glTF/GLB |
| Rig split | `Rig_Medium` (regular KayKit characters, including Adventurers) and `Rig_Large` |
| Contents | General, Movement Basic/Advanced, Melee, Ranged, Simulation, Special, Tools |
| Version inspected | **1.1** (directory name in the CC0 mirror; page advertises 161 animations) |
| Godot guide | <https://youtu.be/sp_1WnJUDXM> |

License quote from the page:

> **Free for personal and commercial use**, no attribution required. (CC0 Licensed)
>
> These assets are CC0 so you can use them freely. But please don't resell unmodified copies or
> claim them as your own.

There is **no separate paid rifle animation pack**. The ranged clips are in the free
`Rig_Medium_CombatRanged.glb` set. Quaternius' "Animated Guns Pack" is a different product and
animates gun meshes, not characters.

### 2.2 Legacy pack — do not use for 2.0

<https://kaylousberg.itch.io/kaykit-animations> (accessed 2026-10-29) is explicitly the **legacy**
pack:

> This set of animations is intended only for older style KayKit characters (the ones without legs).
> … it won't be updated anymore.

Its list is small: Idle, Walk, Run, Hop, Jump, Defeat, Cheer, Wave, Laying Down Idle, Climbing,
Attack (1h), Heavy Attack, Block, Shoot (1h), Continuous Shooting (1h), Shoot (2h), Continuous
Shooting (2h), plus update 1.2 additions (spinning/combo/bow/pickup/throw/interact/dance/roll/dash).
It has **no strafe, no backpedal, no aim-idle, no reload** and the wrong rig. It cannot solve this
game's requirements.

### 2.3 Clip inventory for `Rig_Medium` 1.1

The four free sets needed here contain **59 clip entries** (including one `T-Pose` per set). All are
30 fps; Godot reports durations in multiples of 1/30 s. Godot imports every clip with
`loop_mode = 0` (no loop) — loop modes must be set by the game.

**General (`Rig_Medium_General.glb`, 15 clips):**

| Clip | Length | Use |
|---|---:|---|
| `Idle_A` | 1.07 s | default lower-body idle |
| `Idle_B` | 2.13 s | idle variation |
| `Hit_A` | 0.67 s | hit reaction |
| `Hit_B` | 0.87 s | stronger hit reaction |
| `Death_A` | 0.80 s | quick death |
| `Death_B` | 2.63 s | long death |
| `Death_A_Pose`, `Death_B_Pose` | 0.00 s | held death poses |
| `Spawn_Air` | 1.30 s | spawn from air; **has +2.0 m root-motion Y** |
| `Spawn_Ground` | 1.30 s | spawn on ground; in-place |
| `Interact` | 1.30 s | not used in V1 |
| `PickUp` | 1.30 s | not used in V1 |
| `Throw` | 1.37 s | not used in V1 |
| `Use_Item` | 1.60 s | not used in V1 |
| `T-Pose` | 0.00 s | discard |

**MovementBasic (`Rig_Medium_MovementBasic.glb`, 11 clips):**

| Clip | Length | Use |
|---|---:|---|
| `Walking_A` | 1.07 s | walk |
| `Walking_B` | 1.07 s | walk variation |
| `Walking_C` | 1.60 s | slow walk variation |
| `Running_A` | 0.80 s | sprint/run |
| `Running_B` | 0.80 s | sprint/run variation |
| `Jump_Start` | 0.60 s | takeoff |
| `Jump_Idle` | 1.07 s | airborne loop |
| `Jump_Land` | 0.67 s | landing |
| `Jump_Full_Short` | 1.17 s | complete short hop |
| `Jump_Full_Long` | 2.33 s | complete long jump |
| `T-Pose` | 0.00 s | discard |

**MovementAdvanced (`Rig_Medium_MovementAdvanced.glb`, 13 clips):**

| Clip | Length | Use |
|---|---:|---|
| `Running_Strafe_Left` | 0.80 s | **strafe left** (running; use slower speed_scale for walk) |
| `Running_Strafe_Right` | 0.80 s | **strafe right** |
| `Walking_Backwards` | 1.07 s | **backpedal** |
| `Running_HoldingRifle` | 0.80 s | rifle-carry run (full body) |
| `Running_HoldingBow` | 0.80 s | not used |
| `Crouching`, `Crawling`, `Sneaking` | 1.07–2.13 s | not used in V1 |
| `Dodge_Forward/Backward/Left/Right` | 0.40 s | **root motion 0.25–0.65 m**; not used in V1 |
| `T-Pose` | 0.00 s | discard |

**CombatRanged (`Rig_Medium_CombatRanged.glb`, 20 clips):**

| Clip | Length | Use |
|---|---:|---|
| `Ranged_2H_Aiming` | 1.60 s | rifle aim idle / upper-body hold |
| `Ranged_2H_Reload` | 1.60 s | rifle reload — **exactly matches `reload_time = 1.6`** |
| `Ranged_2H_Shoot` | 1.07 s | single rifle shot |
| `Ranged_2H_Shooting` | 1.07 s | repeated/auto rifle fire |
| `Ranged_1H_Aiming` | 1.07 s | pistol aim idle |
| `Ranged_1H_Reload` | 1.17 s | pistol reload |
| `Ranged_1H_Shoot` | 1.07 s | pistol shot |
| `Ranged_1H_Shooting` | 1.60 s | pistol auto fire |
| `Ranged_Bow_*` | 1.33–1.83 s | not used |
| `Ranged_Magic_*` | 0.67–4.30 s | not used |
| `T-Pose` | 0.00 s | discard |

**Not present in this pack:** a dedicated `Aim_Walk`, `Aim_Strafe`, or `Rifle_Idle` clip. Use
`Ranged_2H_Aiming` as an upper-body overlay on top of the locomotion clips. That is the intended
layering solution and is how the current game already handles `Pistol_Aim_Neutral` + `Walk`.

**Other sets, for completeness:** `CombatMelee` 22, `Simulation` 14, `Special` 15, `Tools` 29.
`Rig_Medium` totals **139 clip entries** (131 excluding the eight per-set `T-Pose` entries). The
`Rig_Large` sets add 34 entries. The vendor's "161 humanoid animations" count includes both rigs and
per-set T-pose entries; the exact number of unique clips is slightly lower.

### 2.4 Free vs paid

| Asset | Free | Paid |
|---|---|---|
| Adventurers characters | 5 (Knight, Mage, Rogue, Rogue_Hooded, Barbarian per the 1.0 archive; confirm the 2.0 free roster in the zip) | **EXTRA $7.95** (Engineer, Druid, Large Barbarian + alt textures); **SOURCE $11.95** (`.blend`) |
| Character Animations | **all clips**, including all locomotion/ranged/hit/death | **SOURCE $14.99** (`.blend` only) |
| Legacy animations | all clips (old rig) | none |
| Quaternius rifle | CC0 model on Poly Pizza | none |

No paid asset is required for the functionality in this report. The only reason to buy EXTRA is more
character variety; the only reason to buy SOURCE is editing the rig/animation in Blender.

---

## 3. Rig compatibility, hand bones and root motion

### 3.1 Out-of-the-box compatibility

Measured directly:

- Adventurers 2.0 Knight: **23 joints**.
- Character Animations 1.1 `Rig_Medium_CombatRanged`: **23 joints**.
- The two sets have the **same joint names and the same parent for every joint** (checked
  programmatically: `same set = True`, `all parents match`).
- Rest positions match, e.g. `head` rest global Y = **1.241425** on both; `handslot.r` rest origin =
  **(-0.883132, 1.049261, ~0)** on both.
- Godot track paths are `Rig_Medium/Skeleton3D:<bone>`; Godot binds them by name. No retargeting
  step, no `SkeletonProfile`, no `RetargetModifier3D` is needed.

The old 1.0 characters also share the 23 core bone names inside their 41-joint rig, but the extra IK
control bones are not present in the 1.1 clips. The vendor only guarantees the 2.0 characters. Use
2.0.

### 3.2 Bone names for hand attachment

Exact names (lowercase, dot, no `DEF-` prefix):

| Bone | Role |
|---|---|
| `hand.r` | right hand; use its origin if you want the palm |
| `handslot.r` | **preferred prop socket**; child of `hand.r`; rest origin ≈ (-0.883, 1.049, 0) in source, ≈ (-0.285, 0.338, 0) after 0.32244 scale |
| `wrist.r` | wrist |
| `lowerarm.r` | forearm |
| `hand.l`, `handslot.l`, `wrist.l`, `lowerarm.l` | left-side equivalents |

`handslot.r` local translation relative to `hand.r`: `[0, 0.0961, -0.0575]`. Its rest basis is
rotated (`X=(0,1,0)`, `Y=(-1,0,0)`, `Z=(0,0,1)`), because it is designed for KayKit's sword/axe
props. For a rifle, do **not** blindly parent the rifle to `handslot.r` and expect the barrel to
point forward; use `handslot.r` only as the position source, then orient the gun from the body/view
yaw as the current `CharacterVisual` already does. This keeps S39 (gun should follow the hand, not
the camera 1:1) as a separate tuning decision.

Uppercase `DEF-hand.R` from the UAL rig will **not** exist. Any code/filter using `DEF-` names must
be updated.

### 3.3 Root motion / in-place status

All clips this game needs are **in-place**. The root bone's translation track is constant (usually
two identical keys); the hips bob, but that is not root motion.

**Root-motion exceptions (strip the `root` translation track or consume it if used):**

| Clip | Root translation range |
|---|---|
| `Dodge_Backward` | Z −0.65 → 0 m |
| `Dodge_Forward` | Z 0 → +0.25 m |
| `Dodge_Left` | X 0 → +0.50 m |
| `Dodge_Right` | X −0.50 → 0 m |
| `Spawn_Air` | Y 0 → +2.00 m |
| `Skeletons_*` special clips | up to ~3.1 m |

`Death_A/B`, `Hit_A/B`, `Idle_A/B`, `Walking_*`, `Running_*`, `Running_Strafe_*`,
`Walking_Backwards`, all `Ranged_*`, and all `Jump_*` have **zero root translation**. Do not enable
`AnimationPlayer.root_motion` for normal locomotion; the server is authoritative and animation must
not move the body. For `Spawn_Air`, prefer `Spawn_Ground` or strip the root track.

---

## 4. Low-poly rifle candidates

### 4.1 Candidates and licenses

| Candidate | Source | License | Tris | Materials | Size / dimensions | Notes |
|---|---|---|---:|---:|---|---|
| **Quaternius Assault Rifle (M4)** | <https://poly.pizza/m/Bgvuu4CUMV> | **CC0 1.0** (model page) | **1,930** | **3** (`Main`, `MainDark`, `MainLight`) | 133,980 B GLB; 5.17 × 1.79 × 0.35 m at node scale 100 → scale 0.1 for ~0.52 m | **Recommended.** Clear pistol grip, magazine, stock and muzzle; familiar silhouette; all three materials are dark, so add a two-tone/accent override to read at 2.3 m. |
| Quaternius Assault Rifle (AK) | <https://poly.pizza/m/fpLucho45C> | **CC0 1.0** | **1,388** | **5** (`DarkMetal`, `Metal`, `Wood`, `Black`, `DarkWood`) | 78,616 B GLB; 5.49 × 1.60 × 0.20 m at scale 100 → scale 0.1 | Best silhouette/readability thanks to the brown wood furniture; 5 materials is the worst draw-call split. Merge to 2 (wood + metal) if used. |
| Quaternius Rifle (period musket) | <https://poly.pizza/m/neEjwx9bBJ> | **CC0 1.0** | **1,534** | not checked (FBX source) | not checked | Brown stock + steel barrel; the best pure style match for KayKit Adventurers. Anachronistic with a 30-round 10 rps rifle; choose only if the user wants the comedy/fantasy read. |
| KayKit Adventurers `shotgun.gltf` | Adventurers 2.0 `Assets/gltf/shotgun.gltf` | CC0 (pack) | **1,120** (1,357 verts) | **1** (`engineer`) | 0.459 × 0.582 × 1.668 m at source; ~0.54 m after 0.32244 | Exact style/palette match and one draw call. It is a **shotgun**, and its material is named `engineer`, so it may belong to the paid EXTRA Engineer. Verify before shipping. |
| Quaternius Sci-Fi Gun Pack | <https://quaternius.com/packs/scifigun.html> | **CC0** | not checked | not checked | 7 guns, FBX/OBJ/Blend | Sci-fi shapes; style mismatch with KayKit fantasy. |
| Quaternius Animated Guns Pack | <https://quaternius.com/packs/animatedguns.html> | **CC0** | not checked | not checked | 6 animated guns (P90, revolver, pistol, shotgun, sniper) | Animations are gun-slide/reload, not character clips; overkill. |
| Kenney Blaster Kit | <https://kenney.nl/assets/blaster-kit> | **CC0** (page says "Creative Commons CC0") | not checked | not checked | 40 files, version 2.1 | Sci-fi blasters; chunky and game-ready, but the shapes/palette fight the Adventurers' medieval look. Not recommended for this art switch. |
| Poly Pizza "Steampunk Rifle" | <https://poly.pizza/m/1aBSH8_oopt> | **CC-BY 3.0** | 5,472 | — | — | Style bridge, but CC-BY (attribution required) and high tri count; lower priority. |

**License verification:** the Poly Pizza model pages expose `"Licence":"CC0 1.0"` in their structured
data; the Quaternius pages state CC0; the Kenney page states Creative Commons CC0. Access date
2026-10-29.

### 4.2 Recommended pick

**Primary: Quaternius Assault Rifle (M4), `https://poly.pizza/m/Bgvuu4CUMV`.**

Why:

- CC0, so no attribution obligation and no license mixing.
- 1,930 triangles is trivial next to the 70k–90k triangle character budget; it reads as a rifle at
  2.3 m.
- Clear pistol grip and muzzle, plus a stock and magazine, so a `GripSocket` and `Muzzle` marker are
  easy to place.
- Only 3 materials, half the AK's split; still merge the near-black `Main`/`MainDark`/`MainLight`
  into one dark metal material and add one accent material if you want the cute two-tone look.

**Style alternate:** Quaternius period musket (`/m/neEjwx9bBJ`) if the user prefers the full
KayKit-fantasy read. **Gameplay alternate:** the AK (`/m/fpLucho45C`) if the brown furniture reads
better in the arena; merge its 5 surfaces to 2.

Do not use the M4 at its imported scale: it contains a child node with `scale = 100`, so the raw
model is **5.17 m long**. Set the **instanced scene root** to scale **0.1** (net ~0.52 m; or 0.31 if
nested under the 0.32244 character), then align the barrel to the character's forward axis.

### 4.3 Grip/muzzle contract

Keep the existing scene contract:

```text
Visual/
  GunMount/                  # reparented at runtime to BoneAttachment3D(handslot.r)
    Gun/                     # replace BoxMesh with the rifle GLB instance
      Muzzle                 # Marker3D; WeaponController.muzzle_path points here
```

- Put the rifle's grip at `GunMount` origin after scaling/rotating. If the model's origin is not the
  grip, insert a `RifleOffset` `Node3D` and keep `Muzzle` under it.
- Muzzle marker at the barrel tip, roughly `z = -0.36` for a 0.55 m rifle whose grip is at the
  origin. The current box gun's muzzle is at `z = -0.28`; update the local position.
- The **server** does not use the skeleton or `Muzzle` marker: `ServerCombat.canonical_muzzle()`
  derives the origin from actor position + eye height + shoulder. So a cosmetic muzzle mismatch
  cannot change hit authority. Keep the client tracer aligned for looks only.

---

## 5. Godot 4.7 web risks and budgets

### 5.1 Current web payload (baseline)

Measured in `build/web/` on 2026-10-29:

| File | Raw | Gzip |
|---|---:|---:|
| `index.wasm` | 39,514,754 B | 10,142,423 B |
| `index.pck` | 1,427,644 B | 1,361,675 B |
| `index.js` | 279,815 B | 68,668 B |
| `index.html` | 6,125 B | 2,453 B |
| **Total gzip** | — | **11,303 KB** |

The budget in `docs/ROADMAP.md` is **≤ 20 MB gzipped**, so there is ~8.7 MB of headroom.

### 5.2 Asset size delta

| Item | Raw / imported | Note |
|---|---:|---|
| Current UAL `animation_library.glb` | 6,671,104 B GLB / **1.1 MB `.scn`** | 13,744 tris, 1 mesh, 2 untextured materials |
| KayKit character (Knight) | 341,688 B GLB / **166 KB `.scn`** | 5,800 tris, 9 meshes, 1 1024 atlas |
| 4 animation sets | 3,252,344 B GLB / **1,261 KB `.scn`** | includes 4 mannequin meshes; could be stripped |
| Rifle (M4) | 133,980 B GLB / **61 KB `.scn`** (AK: 34 KB; shotgun: 42 KB) | 1,930 tris |
| **Net vs UAL** | **+~0.33 MB PCK raw** | roughly **+0.1 MB gzip** |

Even keeping the UAL temporarily during the switch (both assets in the PCK) adds ~1.4 MB raw /
~1.3 MB gzip, still far below 20 MB. File size is **not** the blocker.

### 5.3 Draw calls — the real risk

Current character: **1 mesh / 2 surfaces = 2 draw calls**, 13,744 tris, no texture.
Current gun: **1 draw call** (box mesh). Current map: **35 draw calls / 31k tris** (recorded in
`docs/BACKLOG.md` L4).

New character: **9 meshes = 9 draw calls**, 5,800 tris, 1 texture.
New gun: **3 draw calls** (M4) or **5** (AK) before merging.

| Scenario | Main pass | With character shadows |
|---|---:|---:|
| 12 characters (8 players + 4 bots), 9 meshes each, 3-call gun, map 35 | 12×9 + 12×3 + 35 = **179** | +108 = **287** |
| Same, character meshes merged to 1 surface, gun 3 calls | 12 + 36 + 35 = **83** | +12 = **95** |
| 8 players only, 9 meshes, 3-call gun, no bots | 72 + 24 + 35 = **131** | +72 = **203** |
| 8 players only, merged, 3-call gun | 8 + 24 + 35 = **67** | +8 = **75** |

The Phase 2/CP2 budget is **≤ 150 draw calls**. With bots, the unmerged 9-mesh character busts it
even before shadows. Recommendations, in order:

1. **Merge the 9 character meshes into one skinned mesh** (one material, one surface). All nine share
   the same material and skin. Do this once per character variant:
   - Blender: import the GLB, join the nine meshes, keep the armature modifier and vertex groups,
     export GLB. This is the lowest-risk route; Blender was not installed in this sandbox.
   - Or a one-time Godot editor script: concatenate the surface arrays (`ARRAY_VERTEX`,
     `ARRAY_NORMAL`, `ARRAY_TEX_UV`, `ARRAY_BONES`, `ARRAY_WEIGHTS`, `ARRAY_INDEX`) into one
     `ArrayMesh`, assign the existing `Skin`, and replace the nine `MeshInstance3D` nodes. Do not do
     this per frame/per player; bake it into the asset.
2. **Turn off shadow casting on characters** (`cast_shadow = 0`) or enable it only on the local
   player. The lighting budget is one directional light with low-res/no shadows; character shadows
   are not worth 108 extra draw calls.
3. **Merge the rifle surfaces by material** to 1–2 draw calls. A single `material_override` on a
   5-surface mesh does not merge surfaces; you still pay 5 draws. Merge the geometry or accept 2–3.
4. If you cannot merge and must ship 9-mesh characters, cap the match at **8 players and no bots**
   for the Phase 1 acceptance run and document the draw-call number; do not silently exceed 150 with
   bots.

Triangles are fine: 12 × 5.8k–7.6k = **70k–91k**, well under the 250k budget. The problem is draw
calls and shadow passes, not geometry.

### 5.4 Texture memory

The UAL character has **no albedo texture** (two untextured materials, vertex/material colors), so
KayKit adds new VRAM:

- 1024² RGBA8 + mips ≈ 5.3 MB per variant; 5 variants ≈ **26.7 MB**.
- 512² ≈ 1.3 MB; 5 variants ≈ **6.7 MB**.
- 256² ≈ 0.34 MB; 5 variants ≈ **1.7 MB**.

The CP2 budget is ≤ 100 MB texture memory, so 1024 is technically allowed, but 512 for the local
player and 256 for remotes is the safer web/low-end choice. The atlas is a gradient palette; 256
still reads at 2.3 m, and the face is the only detail that suffers.

### 5.5 Godot/Compatibility-specific risks

| Risk | Detail | Mitigation |
|---|---|---|
| Animation library duplication | Each animation GLB ships its own `Skeleton3D` + 6 mannequin meshes. Instancing four GLBs **per character** would add 4 skeletons and 24 hidden meshes per player. | Extract the clips into shared `AnimationLibrary` resources once; assign the same library to every character's `AnimationPlayer`. Do not instance the animation GLBs per player. |
| Per-character filtered clips | `CharacterVisual._filtered_clip()` currently duplicates clips at runtime for each character. With 59 clips × 12 characters that is a lot of duplicated `Animation` data. | Bake the upper/lower-body filtered clips once into `resources/animations/*.tres` and share them. |
| Track path/root node | glTF tracks are `Rig_Medium/Skeleton3D:<bone>`; the imported `AnimationPlayer.root_node` is `..`. If you move the library to a different node, the paths must still resolve. | Put the `AnimationPlayer` on the `Character` scene root (or `Visual`) with `root_node` pointing at the node that contains `Rig_Medium`; keep the node name `Rig_Medium`. Test one clip before wiring all. |
| Loop modes | glTF has no loop flag; Godot imports every clip with `loop_mode = 0`. | Set loops in code/resources: `Idle_A`, `Idle_B`, `Walking_*`, `Running_*`, `Running_Strafe_*`, `Walking_Backwards`, `Jump_Idle`, `Ranged_2H_Aiming`. One-shots: jump start/land, shoot, reload, hit, death, spawn. |
| T-pose flash | A remote ghost with no clip plays the bind pose. | On `_ready`, play `Idle_A` (base) + `Ranged_2H_Aiming` (overlay); on remote spawn, set `force_anim = STILL` immediately (current code already does). |
| Double-sided material | All 9 meshes import with `cull_mode = 2` (disabled) because the source is `doubleSided`. | Keep for the cape; optionally split the cape material and set back-face culling on the body. |
| Shadow pass | Each of the 9 meshes can add a shadow draw call. | `cast_shadow = 0` on characters/rifle; local-only if needed. |
| First-use shader hitch | Five character variants + rifle materials compile on first sight; Firefox already showed a first-shot hitch. | Preload/pre-warm all variants and the rifle material during the loading screen; keep a hidden instance of each variant for one frame. |
| Texture compression | Default import is lossless RGBA (`compress/mode=0`); 1024² is 4 MB VRAM each. | Downsample to 512/256; optionally VRAM-compress (ETC2) if the web target supports it, and verify in Chromium/Firefox. |
| Root motion | Dodge/Spawn clips have root translation; enabling `root_motion` would fight server authority. | Keep `root_motion` off; strip the `root` track for any clip with translation, or don't use Dodge/Spawn_Air. |
| Bone names with dots | `hand.r`, `handslot.r` are valid Godot bone names; track paths use `Skeleton3D:handslot.r`. | Verified in Godot 4.7.2; no escaping needed. |
| 1.0 vs 2.0 mix-up | 1.0 is 41 joints and 3.6 MB; 1.1 clips target 23. | Use 2.0 characters; keep 1.0 out of the repo. |

---

## 6. Hurtboxes and capsule: what to keep

Current shapes in `scenes/characters/player.tscn`:

| Shape | Current | Recommendation |
|---|---|---|
| Movement capsule | `CapsuleShape3D` r 0.19, h 0.82, node y 0.41 | **Keep exactly.** This is the movement/netcode contract; the visual is scaled to 0.82 to match. |
| Body hurtbox | `CapsuleShape3D` r 0.19, h 0.58, node y 0.29 | **Keep for Phase 1.** Covers legs + torso; the KayKit torso at 0.12–0.42 m sits inside it. |
| Head hurtbox | `SphereShape3D` r 0.115, node y 0.72 | **Do not keep as-is if headshots matter.** Visual head/helmet spans ~0.35–0.82 m; the current sphere covers 0.605–0.835 m, i.e. only the top of the helmet. Face-height shots hit the body. |

The visual head is **much larger and lower** than the UAL mannequin's head. At 0.32244 scale the
face is around y 0.50–0.70, while the head sphere is centered at 0.72. A shot at the face will be
resolved against the body capsule (25 damage), not the head (50 damage).

Two options:

**A. Art-only Phase 1 (no gameplay change):** keep all hurtboxes; accept that headshots only
register on the top of the helmet until a later pass. This preserves the current TTK and server
parity, but the hit feedback will feel wrong on a chibi character with a huge head. Document it as a
known limitation.

**B. Fit the hurtboxes to the new silhouette (recommended, needs approval):**

- Keep the movement capsule 0.82 / r 0.19.
- Keep the body capsule at r 0.19, h 0.58, y 0.29 **or** shorten it slightly to h 0.52 / y 0.26 if
  the head sphere overlaps too much.
- Move the head sphere to **y ≈ 0.58–0.60, r ≈ 0.15–0.17**. This covers the face/helmet
  (0.43–0.75) and overlaps the body capsule only in the neck region.
- Re-run the CP3 acceptance test (20/20 headshots at 5/15/30 m) and a body-shot test; check that the
  resolver does not double-hit when the spheres overlap.
- This changes only hit detection, not movement, prediction, snapshots, or server reconciliation.

Do **not** scale the character up to make the old head sphere fit: the 0.82 m capsule and camera
framing are accepted, and a 1.5 m character would break the existing feel and the hitbox contract.

---

## 7. Recommended file layout

Keep the asset family together and keep the license files next to the assets:

```text
res://
├── assets/
│   └── kaykit/
│       ├── adventurers/
│       │   ├── knight.glb
│       │   ├── mage.glb
│       │   ├── rogue.glb
│       │   ├── rogue_hooded.glb
│       │   ├── barbarian.glb
│       │   └── LICENSE.txt
│       ├── animations/
│       │   ├── rig_medium_general.glb
│       │   ├── rig_medium_movement_basic.glb
│       │   ├── rig_medium_movement_advanced.glb
│       │   ├── rig_medium_combat_ranged.glb
│       │   └── LICENSE.txt
│       └── weapons/
│           ├── quat_assault_rifle.glb
│           └── LICENSE.txt
├── resources/
│   └── animations/
│       ├── kaykit_medium_base.tres        # Idle/Walk/Run/Strafe/Back/Jump
│       ├── kaykit_medium_upper_aim.tres   # Ranged_2H_Aiming, upper-body only
│       ├── kaykit_medium_actions.tres     # Shoot/Reload/Hit/Death (filtered copies)
│       └── README.md                      # source URLs + clip provenance
├── scenes/characters/player.tscn          # structure preserved
└── docs/research/kaykit-character.md      # this report
```

Keep the source `.zip` files out of the repo (`.gitignore` or `assets/kaykit/_src/` ignored). Commit
the license text and a `CREDITS.md` entry before the assets, per the project's existing rule.

---

## 8. Proposed animation state map

### 8.1 Design: lower body from `AnimState`, upper body always rifle-ready

The current game attaches the gun to the hand at all times, so the character should always be in a
rifle-carry pose. Trying to play a full-body "idle" with arms down would make the gun float. The
clean split is:

- **Base layer:** legs + hips only, driven by `NetProtocol.AnimState` and local velocity.
- **Upper layer:** `Ranged_2H_Aiming` loop, filtered to spine/chest/head/arms/hands.
- **Action layer:** `Ranged_2H_Shoot`, `Ranged_2H_Reload`, `Hit_A/B` on the upper body; `Death_A/B`
  full body.

This is the same overlay architecture `CharacterVisual` already uses for `Pistol_Aim_Neutral` and
`Pistol_Shoot`; only the bone names and clip names change.

### 8.2 Byte → clip map

`NetProtocol.AnimState` is unchanged: `STILL = 0`, `WALK = 1`, `SPRINT = 2`, `AIR = 3`.

| Byte | Enum | Condition | Base clip (lower body) | Loop | speed_scale |
|---:|---|---|---|---|---|
| 0 | `STILL` | speed < 0.15, grounded | `Idle_A` | yes | 1.0 |
| 1 | `WALK` | 0.15 ≤ speed ≤ 1.9, forward | `Walking_A` (variation `Walking_B/C`) | yes | `clamp(speed / 1.05, 0.7, 1.4)` |
| 1 | `WALK` | moving backward (local z > +0.3) | `Walking_Backwards` | yes | `clamp(speed / 1.05, 0.7, 1.2)` |
| 1 | `WALK` | moving sideways (`abs(local x) > abs(local z)`) | `Running_Strafe_Left` / `Running_Strafe_Right` | yes | `clamp(speed / 1.6, 0.6, 1.1)` (clip is a run; slow it for walk) |
| 2 | `SPRINT` | speed > 1.9, forward | `Running_A` or `Running_HoldingRifle` | yes | `clamp(speed / 2.75, 0.8, 1.3)` |
| 2 | `SPRINT` | sideways | `Running_Strafe_Left` / `Running_Strafe_Right` | yes | `clamp(speed / 2.75, 0.8, 1.3)` |
| 3 | `AIR` | not on floor | `Jump_Start` → `Jump_Idle` → `Jump_Land` | start/land no, idle yes | 1.0 |

**Upper layer (always, while alive):** `Ranged_2H_Aiming`, loop. If scoped, keep the same clip; the
camera zoom and gun pitch do the aiming. There is no separate aim-walk/strafe clip, so this overlay
is how aim + movement is represented.

**One-shot overlays (upper body unless noted):**

| Action | Clip | Length | Trigger |
|---|---|---:|---|
| Shoot | `Ranged_2H_Shoot` | 1.07 s | `WeaponController.shot_fired`; for 10 rps, play a trimmed 0.12–0.15 s slice or `Ranged_2H_Shooting` at high speed and restart. Validate visually. |
| Reload | `Ranged_2H_Reload` | 1.60 s | reload start; **matches `reload_time = 1.6` exactly** |
| Hit | `Hit_A` / `Hit_B` | 0.67 / 0.87 s | hit event |
| Death | `Death_A` / `Death_B` | 0.80 / 2.63 s | death event; full body; disable overlays; after the clip, hold `Death_A_Pose`/`Death_B_Pose` or hide |
| Respawn | `Spawn_Ground` | 1.30 s | respawn; strip root track (or use `Spawn_Air` only if you want the +2 m drop) |

Priority: **death > hit > reload > shoot > air > locomotion**. A hit during reload should cancel the
reload overlay; a death cancels everything. The upper aim overlay is muted while a one-shot action
plays, then resumes.

### 8.3 Representing strafe without a protocol change

The snapshot already carries velocity (`vel`) and yaw; `NetworkInterpolator.push_sample()` stores
`vel`. It currently drops it in `sample()`. Expose it once:

```gdscript
# NetworkInterpolator.sample(): add the velocity to the returned dictionary
return {"pos": pos, "yaw": yaw, "state": state, "vel": newest.get("vel", Vector3.ZERO)}
```

Then derive local direction:

```gdscript
# local player: body.velocity; remote: set body.velocity from sample["vel"] (no move_and_slide)
var local_vel := body.transform.basis.inverse() * Vector3(body.velocity.x, 0.0, body.velocity.z)
var strafing := absf(local_vel.x) > maxf(0.25, absf(local_vel.z) * 1.2)
var backward := local_vel.z > 0.3
var side := 1 if local_vel.x > 0.0 else -1   # +X is right when facing -Z
```

Use hysteresis (e.g. 0.25 m/s enter, 0.15 m/s exit) to avoid clip flicker at the diagonal. Choose
strafe only when lateral dominates; otherwise forward/back.

**No wire change is needed for strafing.** The only thing missing for remotes is the code path that
passes `vel` through; the data is already in the 22-byte snapshot.

**Aim state is not in the snapshot.** Remote ghosts cannot know if a player is scoped. For Phase 1,
keep every remote in the rifle-ready upper-body pose (`Ranged_2H_Aiming`). If you later want remotes
to show a scoped pose, use one of the free bits in the snapshot flags byte (bit 1, currently unused)
and document it; the packet size does not change. Do not repurpose the four state bytes.

### 8.4 Filtered bone list

Replace the current `DEF-` list with:

```text
spine, chest, head,
upperarm.l, upperarm.r, lowerarm.l, lowerarm.r,
wrist.l, wrist.r, hand.l, hand.r, handslot.l, handslot.r
```

Exclude `root`, `hips`, `upperleg.*`, `lowerleg.*`, `foot.*`, `toes.*`. The current
`_filtered_clip()` uses `path.contains(bone)`; keep that in mind, but prefer exact bone-name matching
over substring matching when you rewrite the filter.

---

## 9. Step-by-step Phase 1 import plan

### Step 1 — Acquire (free tiers only)

1. Download the **free** Adventurers pack from <https://kaylousberg.itch.io/kaykit-adventurers>
   ("No thanks, just take me to the downloads" is fine). Do not buy or download the EXTRA/SOURCE
   tiers for this phase.
2. Download the **free** Character Animations pack from
   <https://kaylousberg.itch.io/kaykit-character-animations>. The SOURCE tier is optional and not
   needed.
3. Keep both zips outside the repo; copy only the files listed in the layout above.
4. Copy `LICENSE.txt` from each pack into `assets/kaykit/.../LICENSE.txt` and add the entries to
   `assets/CREDITS.md` **before** committing assets.

### Step 2 — Character import settings

For each `assets/kaykit/adventurers/*.glb`, select the `.glb` in the Import dock and set:

| Setting | Value | Why |
|---|---|---|
| `meshes/generate_lods` | **off** | No LOD popping; smaller import. |
| `meshes/create_shadow_meshes` | **off** | No shadow pass; see draw-call budget. |
| `meshes/ensure_tangents` | **off** | No normal maps. |
| `meshes/light_baking` | **off/disabled** | Dynamic characters; no UV2. |
| `animation/import` | **off** | 2.0 characters have no clips. |
| `materials/extract` | **off** (embedded) | One material per character; keep it simple. |
| `gltf/embedded_image_handling` | **Extract Textures** | Lets you set the atlas size/compression in the texture Import dock. |
| `skins/use_named_skins` | **on** | Keeps the `Skin` resource. |

Then select the extracted `*_texture.png` and set:

| Setting | Value |
|---|---|
| `process/size_limit` | **512** (local), **256** (remote variants) |
| `mipmaps/generate` | **on** |
| `compress/mode` | lossless first; try VRAM/ETC2 only after a browser check |
| `process/fix_alpha_border` | **on** |

Place the character in `player.tscn` with:

```text
Character (instance of knight.glb)
  transform: rotation.y = PI (180°), scale = 0.32244 uniform
```

Do **not** use negative X/Z scale (the current UAL scene does that as a mirror trick). A positive
uniform scale + 180° yaw gives the same facing without inverted normals. Verify the AABB is
1.94 × 2.54 × 1.31 × 0.32244 = **0.626 × 0.820 × 0.422 m**, feet at y = 0.

### Step 3 — Animation import settings

For each `rig_medium_*.glb`:

| Setting | Value | Why |
|---|---|---|
| `animation/import` | **on** | Clips. |
| `animation/fps` | **30** | Source is 30 fps; durations are exact. |
| `animation/trimming` | **off** | Don't cut anticipation. |
| `animation/remove_immutable_tracks` | **on** | Smaller clips. |
| `animation/import_rest_as_RESET` | **off** | No extra RESET clip. |
| `meshes/generate_lods` | **off** | The mannequin mesh is a donor only. |
| `meshes/create_shadow_meshes` | **off** | Same. |

Extract the clips into shared resources:

1. Open `rig_medium_general.glb`, select its `AnimationPlayer`, open the Animation panel.
2. Use **Manage Animations → Save** (or `Animation → Save to file`) to save the library as
   `resources/animations/kaykit_medium_base.tres`.
3. Repeat for the other three sets, or copy the four libraries into one `AnimationLibrary` and
   delete the donor `Skeleton3D`/`MeshInstance3D` nodes from the saved scene.
4. Create filtered copies once:
   - base: remove all tracks whose path contains `spine`, `chest`, `head`, `upperarm`, `lowerarm`,
     `wrist`, `hand`, `handslot`;
   - upper: keep only those bones (and `chest`/`spine`), remove `root`, `hips`, legs, feet, toes.
5. Assign the libraries to the character's `AnimationPlayer` (do not instance the animation GLBs
   per player). Set `root_node` to the node that contains `Rig_Medium`.

### Step 4 — Wire the character

In `scenes/characters/player.tscn` (structure preserved):

1. Replace the `Character` instance with the KayKit character.
2. Add an `AnimationPlayer` on `Visual` (or on `Character`) with the shared libraries; set
   `root_node` so tracks resolve to `Rig_Medium/Skeleton3D`.
3. Update `CharacterVisual` constants:
   - `HAND_BONE = "handslot.r"` (or `"hand.r"` if you prefer the palm);
   - `UPPER_BODY_BONES` = the KayKit list above;
   - loop list = `Idle_A`, `Walking_*` (see map), `Running_*`, `Running_Strafe_*`,
     `Walking_Backwards`, `Jump_Idle`, `Ranged_2H_Aiming`;
   - `_play_forced` map = `STILL → Idle_A`, `WALK → Walking_A`/strafe/back, `SPRINT → Running_A`,
     `AIR → Jump_Idle`;
   - `_setup_overlays` = `Ranged_2H_Aiming` hold + `Ranged_2H_Shoot` action;
   - add `Ranged_2H_Reload`, `Hit_A/B`, `Death_A/B` when those events exist.
4. Keep the `BoneAttachment3D` external-skeleton pattern; it works with `handslot.r`.
5. Re-tune the gun socket offset: the KayKit hand is at ~0.338 m world Y after scale; the current
   `+ Vector3(0, 0.02, 0)` may need a small forward/up offset. Verify the rifle is in the palm, not
   floating at the wrist.

### Step 5 — Rifle

1. Add `quat_assault_rifle.glb` under `Visual/GunMount/Gun` (replace the `BoxMesh`).
2. Set the instanced rifle scene root to scale **0.1** (it contains a 100× child), rotate so the
   barrel points **-Z**, and offset so the pistol grip sits at `GunMount` origin.
3. Merge the 3 near-black surfaces into one material (or keep 2 with an accent), set
   `cast_shadow = 0`.
4. Move `Muzzle` to the barrel tip (about `z = -0.36` for a 0.55 m rifle), keep the node name so
   `WeaponController.muzzle_path` still resolves.
5. Add a `GripSocket` marker at the pistol grip for future two-handed IK; not required in Phase 1.

### Step 6 — Measure and gate

Run the existing checks and record numbers in the Phase 1 evidence file:

- Character height 0.820 ± 0.02 m; feet at y 0; faces -Z.
- All four `AnimState` transitions; strafe L/R; backpedal; jump start/idle/land; aim overlay; shoot;
  reload; hit; death.
- No T-pose on spawn/remote; no floating gun; muzzle flash at the tip.
- `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` ≤ 150 with 8 players + 4 bots; triangles ≤ 250k;
  texture memory ≤ 100 MB.
- 20/20 headshots at 5/15/30 m **or** a documented decision to keep the old head hurtbox.
- 10-minute soak; no animation errors, no missing-bone warnings, no memory growth.
- Web build gzip ≤ 20 MB; expected ~11.4 MB.
- Firefox + Chromium: no new console errors; first-spawn shader hitch measured.

### Step 7 — Cleanup

- Remove the UAL `animation_library.glb` and its `.import` once the KayKit set is accepted, or keep it
  behind a feature flag for one release.
- Keep the 1.0 archive out of the repo.
- Add the exact source URLs, versions and access dates to `assets/CREDITS.md`.

---

## 10. References (all accessed 2026-10-29)

1. KayKit Adventurers (official): <https://kaylousberg.itch.io/kaykit-adventurers>
2. KayKit Character Animations (official): <https://kaylousberg.itch.io/kaykit-character-animations>
3. KayKit legacy animations (official): <https://kaylousberg.itch.io/kaykit-animations>
4. Official 1.0 Adventurers archive: <https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0>
5. 1.0 `LICENSE.txt`: <https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/main/LICENSE.txt>
6. 1.0 `README.md`: <https://raw.githubusercontent.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/main/README.md>
7. Kay Lousberg: <https://kaylousberg.com>
8. Godot setup video linked by the vendor: <https://youtu.be/sp_1WnJUDXM> and <https://www.youtube.com/watch?v=4p7QaOd8SHE>
9. CC0 1.0: <https://creativecommons.org/publicdomain/zero/1.0/>
10. Kenney Blaster Kit: <https://kenney.nl/assets/blaster-kit>
11. Quaternius Sci-Fi Gun Pack: <https://quaternius.com/packs/scifigun.html>
12. Quaternius Animated Guns Pack: <https://quaternius.com/packs/animatedguns.html>
13. Quaternius modular guns: <https://quaternius.com/packs/scifimodularguns.html>
14. Quaternius Assault Rifle (M4) on Poly Pizza: <https://poly.pizza/m/Bgvuu4CUMV>
15. Quaternius Assault Rifle (AK) on Poly Pizza: <https://poly.pizza/m/fpLucho45C>
16. Quaternius Rifle (musket) on Poly Pizza: <https://poly.pizza/m/neEjwx9bBJ>
17. Quaternius Steampunk Rifle on Poly Pizza: <https://poly.pizza/m/1aBSH8_oopt>
18. CC0 mirror used for geometry/clip measurement (not a replacement for the official download):
    <https://github.com/GeorgeQLe/assets-kaykit-3d-characters>

---

## Open questions for the user

1. **Asset version:** approve using the current **Adventurers 2.0 free tier** (5 characters,
   23-joint rig, 342–409 KB GLBs) and deleting the old 1.0 archive from consideration? This is the
   only version officially compatible with the free 1.1 animations.
2. **Head hurtbox:** approve moving the head sphere from `y 0.72, r 0.115` to about `y 0.58–0.60,
   r 0.15–0.17` (and optionally shortening the body capsule), or keep the art switch strictly
   cosmetic and accept that face shots count as body shots until a later pass?
3. **Rifle choice:** primary Quaternius M4 (1,930 tris, 3 materials), AK (1,388 tris, 5 materials,
   better contrast), or the period musket (1,534 tris, best KayKit style but anachronistic)? If you
   want the KayKit shotgun instead, confirm it is in the free tier (its material is named
   `engineer`).
4. **Draw-call strategy:** merge the 9 character meshes to one skinned mesh (Blender or a one-time
   Godot editor script), or accept 9 meshes and cap the match at 8 players/no bots with character
   shadows off? The 150-call budget cannot be met with 12 unmerged characters plus shadows.
5. **Remote aim state:** keep all remote ghosts in the rifle-ready pose (no protocol change), or add
   an aim bit to the snapshot flags byte so remotes can show scoped aim? Strafing itself needs no
   protocol change, only exposing the already-sent `vel` in `NetworkInterpolator.sample()`.
6. **Character roster:** which free variants should be used for the local player vs bots/remotes
   (Knight, Mage, Rogue, Rogue_Hooded, Barbarian), and do you want a per-player texture variant or a
   single shared variant for Phase 1?
7. **Texture size:** 512×512 for the local player and 256×256 for remotes (recommended), or 1024
   everywhere for maximum face detail at the cost of ~27 MB VRAM for five variants?
8. **Gun behavior:** keep the current camera-driven gun orientation for Phase 1 (S39 is a separate
   fix), or switch to hand/body-driven orientation as part of this art pass? The rig supports either,
   but the socket offsets differ.
9. **Paid content:** confirm no purchase is desired. The free packs cover every required clip and
   five characters; EXTRA ($7.95) is only for Engineer/Druid/Large Barbarian, and SOURCE
   ($11.95/$14.99) is only for `.blend` editing.
