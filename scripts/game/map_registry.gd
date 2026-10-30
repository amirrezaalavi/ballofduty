class_name MapRegistry
extends RefCounted
## Map candidates registry. Scene paths are strings on purpose so the menu and
## the main scene can reference maps that are still being built without breaking
## imports. Use scene_path() + load() at the swap site, never preload().
##
## Sizes are playable footprints (m). All candidates are > 90x90.

const MAPS := [
	{
		"id": "quarry",
		"display": "SUNKEN QUARRY",
		"scene": "res://scenes/maps/arena_quarry.tscn",
		"size": "150 x 150 m",
		"desc": "Sunken bowl, terraces, 61 m cave",
	},
	{
		"id": "dunes",
		"display": "DUNE CANYON",
		"scene": "res://scenes/maps/arena_dunes.tscn",
		"size": "120 x 120 m",
		"desc": "Desert dunes, slot canyon, ruined fort",
	},
	{
		"id": "crater",
		"display": "STARFALL CRATER",
		"scene": "res://scenes/maps/arena_crater.tscn",
		"size": "120 x 120 m",
		"desc": "Impact bowl, relay ring, crystal spires",
	},
	{
		"id": "jungle",
		"display": "JUNGLE RUINS",
		"scene": "res://scenes/maps/arena_jungle.tscn",
		"size": "120 x 120 m",
		"desc": "Temple plateau, river, vine tunnel",
	},
]

const DEFAULT_MAP := "quarry"


static func ids() -> Array:
	var out: Array = []
	for entry: Dictionary in MAPS:
		out.append(String(entry["id"]))
	return out


static func sanitize(map_id: String) -> String:
	var needle := map_id.strip_edges().to_lower()
	for entry: Dictionary in MAPS:
		if String(entry["id"]) == needle:
			return needle
	return DEFAULT_MAP


static func scene_path(map_id: String) -> String:
	var clean := sanitize(map_id)
	for entry: Dictionary in MAPS:
		if String(entry["id"]) == clean:
			return String(entry["scene"])
	return String(MAPS[0]["scene"])


static func display_name(map_id: String) -> String:
	var clean := sanitize(map_id)
	for entry: Dictionary in MAPS:
		if String(entry["id"]) == clean:
			return String(entry["display"])
	return String(MAPS[0]["display"])


static func index_of(map_id: String) -> int:
	var clean := sanitize(map_id)
	for i in MAPS.size():
		if String(MAPS[i]["id"]) == clean:
			return i
	return 0


static func id_at(index: int) -> String:
	return String(MAPS[clampi(index, 0, MAPS.size() - 1)]["id"])
