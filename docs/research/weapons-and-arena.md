I've completed the research and design report for class weapons and the playground expansion, saved directly to `docs/research/weapons-and-arena.md`.

### Core Highlights & Recommended V1 Architecture

* **Class Weapons (1:1 Character Mapping):**
* **Knight (0.82 m):** *Heavy Thrown Javelin* (58 m/s, steep ballistic drop, 60 body / 105 head, shield break / knockback hook, uses `Throw` + `Ranged_2H_Aiming`).
* **Mage (0.856 m):** *Arcane Staff & Plasma Bolt* (92 m/s linear, 35 body / 55 head + 15 splash in 1.4 m radius, 6-shot heat meter, uses `Ranged_Magic_Spellcasting` + `Ranged_Magic_Shoot`).
* **Rogue (0.703 m):** *Recurve Longbow* (0.85 s charge-to-draw, 45–110 m/s, 20–75 body / 40–150 head, armor pierce hook, uses `Ranged_Bow_Draw` + `Ranged_Bow_Release`).
* **Rogue_Hooded (0.701 m):** *Repeating Hand Crossbow* (82 m/s, 3-round rapid burst, 22 body / 44 head per bolt, poison bleed/mark hook, uses `Ranged_1H_Aiming` + `Ranged_1H_Shoot`).
* **Barbarian (0.773 m):** *Dual Heavy Throwing Axes* (52 m/s, parabolic arc, 50 body / 80 head, concussive cripple/slow hook, uses `Throw` + `Ranged_1H_Aiming`).
* *Zero Animation Gaps:* All 5 weapons map directly to existing, verified clips in the project's KayKit animation library (`Rig_Medium`) without requiring new animation imports.
* *Zero Protocol Changes:* Reuses the existing `SHOT` intent and `HIT` event packets; splash and pierce resolve strictly on the 30 Hz server via standard physics shape queries.


* **Playground Expansion (Sunken Quarry & Cavern Pass, 150×150 m):**
* *Terrain Architecture:* `Terrain3D` was evaluated and **rejected** due to GDExtension, WebGL 2 texture-array limits, and compute shader dependencies. The recommended path is a modular 3×3 grid of 50×50 m low-poly mesh chunks with a static Godot `HeightMapShape3D` ground collider and primitive convex colliders for cliffs.
* *Cave & Light Leaking Strategy:* Double-walled modular cave tunnel pieces (minimum 3.8 m interior clearance to prevent third-person spring-arm clipping), overlapping exterior "rock skirts" to block seam light leaks, and an `Area3D` sunlight fade trigger.
* *Performance & Web Budget:* Foliage grouped into 5 `MultiMeshInstance3D` nodes, global gradient atlas sharing (under 18 MB texture VRAM), keeping draw calls between 85–105 and triangles under 74k at 60 fps.



---

### Decisions Needing User Sign-Off

1. **Weapon Assignment Model:**
* *Recommended Default:* **Class-Locked Variant** (`net_id % 5` or lobby selection). Each character variant carries their signature weapon. This establishes instant visual threat recognition, requires no ground-weapon network replication, and avoids animation clipping.
* *Alternative:* Pre-match custom loadout picker, or neutral arena weapon spawn pads.


2. **Bot Weapon Loadouts:**
* *Recommended Default:* **Bots use their assigned character's class weapon.** The server-authoritative projectile system already handles ballistics identically for bots and players, providing a balanced playground test matrix.
* *Alternative:* Bots retain the baseline Quaternius M4 rifle.


3. **Arena Scale:**
* *Recommended Default:* **150×150 m.** This provides adequate space for a 60 m underground bypass route and vertical cliff terraces while keeping 8 players within frequent combat contact.
* *Alternative:* 120×120 m (faster combat pacing) or 180×180 m (more expansive exploration).


4. **Quaternius M4 Rifle Role:**
* *Recommended Default:* **Central Arena Power Weapon.** Place the M4 rifle on a central quarry pedestal with a 60-second respawn timer and limited ammo, turning the existing weapon into a contested map objective.
* *Alternative:* Retire the M4 entirely in favor of the 5 fantasy class weapons.
