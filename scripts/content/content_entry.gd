class_name ContentEntry
extends Resource
## One external artifact: a map, class/character, weapon, collectible, mode or
## cosmetic. The game owns behaviour; this resource only describes *what* the
## artifact is, where it lives and what it is allowed to cost.
##
## Entries are authored as .tres files under res://resources/content/entries/ and
## referenced by a ContentPack. See docs/CONTENT-STANDARD.md.

const KINDS: Array[StringName] = [
	&"map", &"class", &"weapon", &"collectible", &"mode", &"cosmetic",
]

## Stable, namespaced id: "<namespace>/<name>", lower-case a-z, 0-9 and "_".
## Never rename or reuse an id after release; add a new entry instead.
@export var id: StringName = &""
## map | class | weapon | collectible | mode | cosmetic
@export var kind: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Semver for this artifact, independent of the game version.
@export var version: String = "1.0.0"
## Disabled entries stay in the pack for provenance but are not offered at runtime.
@export var enabled: bool = true
## Primary resource path. PackedScene for maps/classes/collectibles, or a
## data resource such as WeaponStats. Always res://, never absolute or "..".
@export var path: String = ""
## Expected script/class name: "PackedScene", "WeaponStats", etc.
@export var resource_type: StringName = &""
## Stable network id for kinds that cross the wire. -1 means local-only.
## class ids must be 0..NetProtocol.CLASS_COUNT-1 and are never reused.
@export_range(-1, 255, 1) var wire_id: int = -1
## Other entry ids this artifact needs. Cycles are rejected.
@export var dependencies: Array[StringName] = []
@export var tags: Array[StringName] = []
## Budget metrics, validated against ContentCatalog.BUDGETS. Keys are
## draw_calls, triangles, colliders, texture_mb, nodes, load_ms, spawns,
## animation_players, snapshot_bytes.
@export var budgets: Dictionary = {}
## Non-hierarchical references, e.g. {"weapon": &"core/knight_javelin",
## "visual": "res://assets/.../knight.scn", "projectile": "res://..."}.
@export var links: Dictionary = {}
## Required for external art: human-readable credit and license.
@export var attribution: String = ""
@export var license: String = ""
## Network-critical entries (weapons, class stats) can be loaded during the
## manifest load instead of on first use.
@export var preload_on_load: bool = false


func kind_is_known() -> bool:
	return KINDS.has(kind)
