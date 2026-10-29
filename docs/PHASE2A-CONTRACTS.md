# Phase 2A — class weapons & picker contracts

- **Start:** 2026-10-29, after Phase 1 sign-off
- **Owner/integrator:** manager
- **Agents:** D (server combat), E (client visual/UI)
- **Merge order:** D → E (E may start UI/assets in parallel against this contract)

## Locked class map

| class_id | Character | Weapon | Model | Animation |
|---:|---|---|---|---|
| 0 | Knight | Heavy thrown javelin | KayKit spear | `Throw` + `Ranged_2H_Aiming` |
| 1 | Mage | Arcane staff / plasma bolt | KayKit staff/wand | `Ranged_Magic_Spellcasting` + `Ranged_Magic_Shoot` |
| 2 | Rogue | Recurve longbow | KayKit bow + arrow | `Ranged_Bow_Draw` → `Ranged_Bow_Release` |
| 3 | Rogue_Hooded | Repeating hand crossbow | KayKit crossbow/bolts | `Ranged_1H_Aiming` + `Ranged_1H_Shoot` |
| 4 | Barbarian | Dual heavy throwing axes | KayKit axe | `Throw` + `Ranged_1H_Aiming` |

The M4 is **not** in the V1 class rotation; keep its asset/stats for a later power-weapon pass.

## Frozen interfaces (already in main)

- `NetProtocol.CLASS_COUNT = 5`, `sanitize_class()`.
- `JOIN_REQ` / `JOIN_OK` / `ROSTER` carry `class_id`.
- `PlayerController.class_id` (set on local join, server actor, remote ghost).
- `GameManager` entries carry `"class_id"`; bots are assigned `index % 5`.
- Local `client_start(..., class_id)` sets the local class before connect.

## Agent D — server combat

Own:
- `scripts/weapons/weapon_stats.gd`
- `scripts/game/server_combat.gd`
- `scripts/weapons/projectile.gd`
- new `scripts/game/weapon_registry.gd`, class projectile/effect scripts
- `resources/weapons/class_*.tres`
- `tests/gdunit/test_class_weapons.gd`, `test_projectile_effects.gd`

Must not touch `game_manager.gd`, `net_protocol.gd`, `player_controller.gd`, `character_visual.gd`, UI, or client weapon code.

Implement:
1. `WeaponRegistry.stats_for(class_id)` with five profiles (seed values from the report):
   - Knight 58 m/s, 60/105, steep drop, pierce/knockback, 1.3 s cycle.
   - Mage 92 m/s, 35/55 + 15 splash in 1.4 m, 6-shot heat, fast cycle.
   - Rogue 0.85 s charge, 45–110 m/s, 20–75 / 40–150, armour pierce.
   - Rogue_Hooded 82 m/s, 3-round burst, 22/44, poison/bleed.
   - Barbarian 52 m/s, parabolic arc, 50/80, slow/knockback.
2. Per-entry weapon state: ammo/heat, cooldown, reload, charge, burst, `fire_prev` edge detection.
   Charge weapons fire on release; burst weapons fire a burst on press; automatic rifle behavior remains for
   the retired M4 only.
3. `ServerCombat.process` uses the entry's `class_id`; no `GameManager` changes. `reset_player(entry)` reads it.
4. Projectile effects: gravity/drop, pierce count, splash radius, knockback/slow/bleed hooks. Keep the existing
   `SHOT`/`HIT` events; splash/pierce resolve on the server with normal physics queries.
5. Bots use their class automatically (class id already on entries).
6. Add stats fields needed by the client (charge/heat/burst/effect/clip names) to `WeaponStats`.
7. Tests: per-class damage/ballistics, charge hold/release, burst cadence, heat lockout, pierce, splash,
   bot class weapon. Run `test_class_weapons`, `test_server_combat`, `test_bots`, `test_loopback_combat`.

Commit to `phase2-d`; report commit, stats table, test output, and risks.

## Agent E — client visual/UI

Own:
- `scripts/game/main.gd`, menu/loading scenes and scripts
- `scripts/player/character_visual.gd`, `scenes/characters/player.tscn` visual subtree
- `assets/weapons/class/**`, `assets/CREDITS.md`
- `scripts/weapons/weapon_controller.gd`, `scripts/ui/hud.gd`
- tests `test_class_picker.gd`, `test_class_weapon_visual.gd`

Must not touch `game_manager.gd`, `net_protocol.gd`, `player_controller.gd`, `server_combat.gd`.

Implement:
1. **Class picker** in the main menu: five cards (Knight/Mage/Rogue/Rogue_Hooded/Barbarian) with weapon name
   and short role; selection persists while the menu is open; Join passes `class_id` to
   `gm.client_start(..., class_id)`. Auto-join links may take `?class=0..4`; default Knight.
2. **Variant by class, not net_id**: `CharacterVisual` selects the five KayKit variants from
   `body.class_id`; remotes use the roster class. Default Knight before join.
3. **Five weapon models** from the KayKit Adventurers free tier (spear, staff/wand, bow+arrow, crossbow,
   axe). Scale/offset for the 0.70–0.86 m characters; keep `GunMount`/`Muzzle` contract and hand attachment.
   If a model cannot be fetched, use a clearly marked low-poly proxy and report the missing asset.
4. **Per-class animation maps** for aim/hold/shoot/reload/charge using the existing clips; keep the
   Phase 0 spine aim and hand-locked gun. Bots/remotes must show their class weapon.
5. **HUD**: class weapon name, ammo/heat/charge state, reload/charge indicator; keep the existing
   hitmarker/kill feed. Use `stats.get("...", default)` so the branch compiles before D merges.
6. Load per-class stats at runtime from `res://resources/weapons/class_*.tres`; fall back to the rifle
   resource if absent. Do not hard-code damage client-side.
7. Tests: picker state/URL, class→variant mapping, five weapon/muzzle attachments, animation map,
   HUD charge/heat labels. Run targeted tests + `./tools/check.sh --skip-export` if D's resources are present.

Commit to `phase2-e`; report commit, asset source/license/scale, test output, and risks.

## Acceptance

- Class picker → match; local and remotes show the chosen class/weapon; bots use all five.
- All five weapons fire server-authoritatively with distinct ballistics/effects; no protocol changes beyond
  `class_id`.
- Existing rifle/M4 code and tests remain green or are explicitly retired.
- No animation gaps, no floating weapons, no client-side damage.
- Web export remains under 20 MB gzip and 60 fps target.
