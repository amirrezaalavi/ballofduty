class_name ContentPack
extends Resource
## A versioned bundle of ContentEntry resources. A pack is the unit an external
## author ships: maps in one pack, a weapon set in another, a seasonal cosmetic
## pack in another. Packs may depend on other packs by id.

@export var pack_id: StringName = &""
@export var display_name: String = ""
@export var version: String = "1.0.0"
## Refuse to load this pack on an older game build.
@export var min_game_version: String = ""
@export var dependencies: Array[StringName] = []
@export var entries: Array[Resource] = []


func content_entries() -> Array[ContentEntry]:
	var out: Array[ContentEntry] = []
	for item in entries:
		if item is ContentEntry:
			out.append(item)
	return out
