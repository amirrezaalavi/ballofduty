# Content & Artifact Standard

**Status:** active. **Scope:** every external thing the game can load — maps,
classes/characters, weapons, collectibles, modes and cosmetics.

The rule is simple:

> **The game is the logic. Artifacts are data.**
> Gameplay, authority, prediction and networking live in `scripts/`. An artifact
> describes *what* exists, *where* it lives, and *what it is allowed to cost*.

This standard is map-agnostic and independent of the current quarry. The three
maps being built in the map session plug in through the same contract without
touching gameplay code.

---

## 1. What an artifact may and may not do

| Allowed | Not allowed |
|---|---|
| Reference an approved scene, `WeaponStats`, texture, mesh or audio file | Contain arbitrary gameplay scripts that change authority, prediction or the wire format |
| Add tuning values in exported resources | Hard-code map/class/weapon ids in `scripts/` |
| Reference approved components (`HealthComponent`, `HurtboxComponent`, …) | Open sockets, read files outside `res://`, or load remote code |
| Declare budgets, dependencies, credits and a stable id | Reuse or rename a released id / `wire_id` |
| Be disabled without deleting its files | Bypass `tools/validate_content.gd` in CI |

If a feature needs new behaviour, the behaviour is added to the game once (a
component or system) and then exposed as data. Artifacts do not fork the rules.

---

## 2. Kinds

| Kind | Primary resource | `wire_id` | Examples |
|---|---|---|---|
| `map` | `PackedScene` | local string id only (`-1`) | `core/quarry`, `maps/crater` |
| `class` | `PackedScene` (player/character scene) | **required**, `0..CLASS_COUNT-1` | `core/knight` |
| `weapon` | `WeaponStats` resource | **required** for a class weapon; `-1` for a standalone power weapon | `core/knight_javelin` |
| `collectible` | `PackedScene` | optional stable id if the server spawns it by id | `pickups/health`, `pickups/ammo` |
| `mode` | `PackedScene` or data resource | optional | `modes/ffa` |
| `cosmetic` | `PackedScene` or data resource | local only | `skins/…` |

Class ids are part of the wire protocol. Adding a sixth class means:

1. add the `class` + `weapon` entries with `wire_id = 5`;
2. bump `NetProtocol.CLASS_COUNT` to 6;
3. add the visual/weapon/animation mapping in `CharacterVisual`;
4. run the class, protocol and loopback suites.

The catalog rejects a class table that is not exactly `0..CLASS_COUNT-1`, so a
half-added class cannot reach a match.

---

## 3. Folder layout

```text
res://
├── resources/content/
│   ├── manifest.tres              # lists the packs
│   ├── packs/
│   │   ├── core.tres              # classes + weapons shipped today
│   │   └── maps.tres              # added when the three maps land
│   └── entries/
│       ├── class_knight.tres
│       ├── weapon_knight_javelin.tres
│       └── map_crater.tres
├── scenes/maps/arena_<id>.tscn
├── resources/weapons/class_<id>.tres
└── scenes/characters/player.tscn
```

One artifact = one entry file. Packs reference entries by path (not inline
copies), so editing an entry updates every pack that uses it.

`manifest.tres` is the only file the game opens by default. A pack that is not
listed there is not shipped to the match, even if its files are present.

---

## 4. Entry schema

`ContentEntry` (`scripts/content/content_entry.gd`):

| Field | Meaning |
|---|---|
| `id` | Stable `namespace/name`, lower-case `a-z 0-9 _` |
| `kind` | One of the kinds above |
| `display_name`, `description` | UI text; never used for lookup |
| `version` | Semver of this artifact |
| `enabled` | Kept in the pack for provenance, not offered at runtime |
| `path` | Primary `res://` resource |
| `resource_type` | Expected type: `PackedScene`, `WeaponStats`, … |
| `wire_id` | Stable network id, or `-1` |
| `dependencies` | Other entry ids this artifact needs |
| `tags` | Filtering/authoring tags (`core`, `map`, `class`, …) |
| `budgets` | Measured/declared cost metrics |
| `links` | Non-hierarchical references (`weapon`, `visual`, `projectile`, …) |
| `attribution`, `license` | Required for external art |
| `preload_on_load` | Load during manifest load instead of first use |

Example:

```tres
[gd_resource type="Resource" script_class="ContentEntry" format=3]
[ext_resource type="Script" path="res://scripts/content/content_entry.gd" id="1"]
[resource]
script = ExtResource("1")
id = &"core/knight"
kind = &"class"
display_name = "Knight"
path = "res://scenes/characters/player.tscn"
resource_type = &"PackedScene"
wire_id = 0
dependencies = Array[StringName]([&"core/knight_javelin"])
tags = Array[StringName]([&"core", &"class"])
budgets = {"nodes": 40, "triangles": 18000, "texture_mb": 8, "animation_players": 5}
links = {"weapon": &"core/knight_javelin", "visual": "res://assets/.../knight.scn"}
attribution = "KayKit Adventurers by Kay Lousberg"
license = "CC0"
```

---

## 5. Ids, versions and compatibility

- **Ids are forever.** Never rename or reuse a released `id` or `wire_id`.
  Deprecate with `enabled = false` and add a new entry.
- **Namespaces:** `core/` is the shipped set; `maps/`, `pickups/`, `season1/`
  are content packs. A third-party pack uses its own namespace.
- **Semver:** `major.minor.patch`. A breaking change to the artifact contract
  is a major bump; tuning is a minor/patch bump.
- **Pack compatibility:** `ContentPack.min_game_version` refuses an older game
  build. The manifest carries `game_version`.
- **Wire ids:** never renumber a class. `class` ids must stay contiguous
  `0..CLASS_COUNT-1`; collectible ids must be unique within `collectible`.
- **Map ids** are local strings. They are not sent on the wire; the server and
  client both resolve the same id from their own manifest.

---

## 6. Budgets (the optimized standard)

Budgets are declared per artifact and enforced by
`tools/validate_content.gd`. Exceeding the **target** is a warning; exceeding
the **hard cap** fails CI. Values are map-agnostic and should be re-measured on
the reference web build when a map or character changes.

| Kind / metric | Target | Hard cap |
|---|---:|---:|
| **Map** draw calls | 120 | 150 |
| Map triangles | 200k | 300k |
| Map colliders | 500 | 800 |
| Map texture memory | 30 MB | 40 MB |
| Map load (WASM) | 100 ms | 250 ms |
| Map nodes | 1,200 | 2,000 |
| Map spawns | 8 | 4 minimum |
| **Class** nodes | 40 | 60 |
| Class triangles | 18k | 30k |
| Class texture memory | 8 MB | 12 MB |
| Class animation players | 5 | 6 |
| **Weapon** nodes | 20 | 30 |
| Weapon triangles | 4k | 8k |
| Weapon texture memory | 2 MB | 4 MB |
| Weapon snapshot bytes | 0 | 0 |
| **Collectible** nodes | 20 | 30 |
| Collectible triangles | 1k | 2k |
| Collectible texture memory | 1 MB | 2 MB |
| Collectible snapshot bytes | 4 | 8 |

Per-match budgets (not per artifact) remain:

| Metric | Target |
|---|---:|
| Server tick p95, 8 actors | ≤ 6 ms |
| Server tick p95, 16 actors | ≤ 10 ms |
| Snapshot, 8 actors | ≤ 182 B |
| Snapshot, 16 actors | ≤ 300 B |
| Client frame p95, 720p integrated GPU | ≤ 16.6 ms |

A map that is inside target but causes a per-match budget regression is still a
failure. Measure, don't assume.

---

## 7. Authoring recipes

### 7.1 A map

1. Build the scene under `scenes/maps/arena_<id>.tscn`. If it is procedural,
   keep the generator deterministic and store the seed in the scene/resource.
2. Name at least 8 spawn markers `Spawn01`…`SpawnNN`, at least 22 m apart.
3. Add an entry `maps/<id>` with `kind = "map"`, `path = "res://scenes/maps/…"`,
   `resource_type = "PackedScene"`, `wire_id = -1`, and budgets:
   `draw_calls`, `triangles`, `colliders`, `texture_mb`, `load_ms`, `nodes`,
   `spawns`.
4. Add it to `resources/content/packs/maps.tres` and list that pack in
   `manifest.tres`.
5. Run `tools/validate_content.gd` and the map's own walkthrough.
6. **Do not edit `scripts/game/main.gd` to add a map.** The map registry is a
   thin adapter over the catalog (migration in §9).

### 7.2 A weapon

1. Create `resources/weapons/<name>.tres` (`WeaponStats`).
2. Point `projectile_scene` at an approved projectile scene.
3. Add a `weapon` entry with `path`, `resource_type = "WeaponStats"`, and the
   class `wire_id` it belongs to. Set `preload_on_load = true` so the server
   never hits the loader mid-match.
4. Link the class entry with `links.weapon = "<weapon id>"`.
5. Run the class weapon and loopback combat suites.

A standalone power weapon uses `wire_id = -1` and is not part of the class
rotation; it can still be picked up by a mode later.

### 7.3 A class / character

1. Add the visual variant and the weapon model to `CharacterVisual` (the only
   code change; the mapping is intentionally explicit).
2. Add a `class` entry with `wire_id = next id`, `path` to the player/character
   scene, `links.weapon`, `links.visual`, and the class budgets.
3. Add the matching `weapon` entry with the same `wire_id`.
4. Bump `NetProtocol.CLASS_COUNT` and run `test_class_weapons`,
   `test_net_protocol` and `test_loopback_combat`.

The catalog enforces the class/weapon wire-id match and full coverage.

### 7.4 A collectible

1. Build a scene with only approved components; the server owns spawning.
2. Add a `collectible` entry. If the server spawns it by id, give it a stable
   unique `wire_id` and declare `snapshot_bytes`.
3. Add the spawn rule to the mode/map data, not to a hard-coded script list.
4. Run the pickup/authority test for the mode.

### 7.5 A mode or cosmetic

Use `mode`/`cosmetic` entries. A mode that changes authority or the wire format
is a game-code change first; the entry only selects it.

---

## 8. Validation and CI

```bash
./tools/godot --headless --path . --import
./tools/godot --headless --path . --script tools/validate_content.gd
```

`tools/check.sh` runs the validator after import. It fails on:

- a missing manifest/pack/entry path, or a path outside `res://`;
- a non-`namespace/name` id, duplicate id, or duplicate `wire_id`;
- a `resource_type` mismatch;
- a class table that is not exactly `0..CLASS_COUNT-1`;
- a class whose linked weapon is missing or has a different `wire_id`;
- a missing dependency, self-dependency or dependency cycle;
- a budget above the hard cap or a map below the spawn minimum.

Warnings (not failures): above target but inside the hard cap, missing
attribution/license on non-core entries, unknown budget keys, missing optional
metadata.

Unit coverage: `tests/gdunit/test_content_catalog.gd`.

---

## 9. Runtime API

```gdscript
var catalog := ContentCatalog.shared()
var knight := catalog.entry(&"class", &"core/knight")
var scene := catalog.scene(&"class", &"core/knight")
var weapon := catalog.resolve(catalog.by_wire_id(&"weapon", 0))
```

- `entries(kind)` returns enabled entries sorted by `wire_id`, then id.
- `entries(kind, true)` includes disabled entries (for tooling).
- `resolve(entry)` loads and caches by path.
- `by_wire_id(kind, id)` is the network lookup.
- `report()` returns errors/warnings for diagnostics.

**Current adapters**

- `WeaponRegistry` now resolves the five class weapons from the catalog and
  falls back to the compiled table if the manifest is missing/invalid. It
  reports `WeaponRegistry.source() == "catalog"`.
- `MapRegistry` is still the map session's registry. When the three maps land,
  add `resources/content/packs/maps.tres` and make `MapRegistry` delegate to
  `ContentCatalog.entries(&"map")`; do not duplicate map metadata in two places.
- `main_menu.gd` still carries a `CLASSES` display table. Migrate it to the
  catalog's `class` entries after the map session's UI changes settle; the
  catalog already carries the same names, roles and wire ids.

---

## 10. Network contract

- Class `wire_id` is the class id; it must match `NetProtocol.CLASS_COUNT`.
- Weapon `wire_id` matches its class id; the server resolves the profile by
  class id, never by display name or path.
- Collectible `wire_id` is stable if the server spawns it; never reuse it.
- Map ids are local strings; both sides resolve the same manifest.
- Adding an artifact must not silently enlarge the snapshot. A new per-actor
  field is a protocol change with a layout test and a budget decision.

---

## 11. External packs and safety

The web build ships bundled packs only. Runtime loading of arbitrary remote
code is not supported.

- Packs are data/resources; scripts must live under `res://scripts/` and be
  approved by the game.
- Validation rejects absolute paths, `..`, backslashes and non-`res://` paths.
- A future mod pipeline should sign packs, load them into a namespace, and
  reject unsigned packs in ranked play. Do not add that before the bundled
  pipeline is green.
- Credits/license are part of the artifact, not a separate afterthought.

---

## 12. Review checklist

- [ ] `id` is namespaced, lower-case and new.
- [ ] `wire_id` is stable, unique and matches the class table.
- [ ] `path` exists, is `res://`, and the `resource_type` matches.
- [ ] Dependencies exist and have no cycle.
- [ ] Budgets are declared and inside the hard caps.
- [ ] Attribution/license are present for external art.
- [ ] The artifact is listed in a pack and the pack is in `manifest.tres`.
- [ ] `tools/validate_content.gd` passes.
- [ ] The relevant gameplay suite (map walkthrough, class weapon, loopback,
      pickup) passes.
- [ ] No gameplay id was hard-coded in `scripts/` to make the artifact work.
