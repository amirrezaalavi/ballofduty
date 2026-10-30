extends BodTestSuite
## Content standard: the core manifest is valid, the catalog is the live weapon
## source, and every contract (ids, paths, types, wire ids, budgets, deps) fails
## closed with a useful message.

const PLAYER_SCENE := "res://scenes/characters/player.tscn"
const KNIGHT_WEAPON := "res://resources/weapons/class_knight_javelin.tres"


func after_test() -> void:
	ContentCatalog.reset_shared()
	WeaponRegistry.reset_cache()


func test_core_manifest_is_valid_and_matches_the_weapon_registry() -> void:
	var catalog := ContentCatalog.new()
	var ok := catalog.load_manifest(ContentCatalog.DEFAULT_MANIFEST)
	expect(ok, "core manifest loads: %s" % str(catalog.errors))
	expect(catalog.error_count() == 0, "core manifest has no errors")
	expect(catalog.entries(&"class").size() == NetProtocol.CLASS_COUNT, "five classes")
	expect(catalog.entries(&"weapon").size() == NetProtocol.CLASS_COUNT, "five weapons")

	for class_id in NetProtocol.CLASS_COUNT:
		var cls := catalog.by_wire_id(&"class", class_id)
		var weapon := catalog.by_wire_id(&"weapon", class_id)
		expect(cls != null, "class wire id %d exists" % class_id)
		expect(weapon != null, "weapon wire id %d exists" % class_id)
		if cls == null or weapon == null:
			continue
		expect(String(cls.links.get("weapon", "")) == String(weapon.id),
			"class %d links its weapon" % class_id)
		expect(cls.wire_id == weapon.wire_id, "class and weapon wire ids agree")
		expect(catalog.resolve(weapon) is WeaponStats, "weapon entry resolves to WeaponStats")
		expect(catalog.resolve(cls) is PackedScene, "class entry resolves to PackedScene")

	WeaponRegistry.reset_cache()
	expect(WeaponRegistry.source() == "catalog", "registry uses the catalog")
	for class_id in NetProtocol.CLASS_COUNT:
		var stats := WeaponRegistry.stats_for(class_id)
		expect(stats != null and stats.class_id == class_id,
			"registry profile %d comes from the catalog" % class_id)


func test_invalid_ids_paths_and_types_fail() -> void:
	var catalog := _catalog()
	var bad_id := _entry("Bad Id", &"weapon", KNIGHT_WEAPON, 0)
	var bad_path := _entry("test/missing", &"weapon", "res://missing.tres", 1)
	var bad_type := _entry("test/type", &"weapon", PLAYER_SCENE, 2)
	bad_type.resource_type = &"WeaponStats"
	var unsafe := _entry("test/unsafe", &"weapon", "user://outside.tres", 3)
	_set_entries(catalog, [bad_id, bad_path, bad_type, unsafe])

	expect(not catalog.validate(), "invalid entries fail validation")
	expect(_has_error(catalog, "invalid entry id"), "bad id is reported")
	expect(_has_error(catalog, "path does not exist"), "missing path is reported")
	expect(_has_error(catalog, "expects WeaponStats"), "type mismatch is reported")
	expect(_has_error(catalog, "must be res://"), "non-res path is reported")


func test_duplicate_ids_and_wire_collisions_fail() -> void:
	var catalog := _catalog()
	var a := _entry("test/dupe", &"weapon", KNIGHT_WEAPON, 0)
	var b := _entry("test/dupe", &"weapon", KNIGHT_WEAPON, 1)
	var c := _entry("test/collision", &"weapon", KNIGHT_WEAPON, 0)
	_set_entries(catalog, [a, b, c])

	expect(not catalog.validate(), "duplicates fail")
	expect(_has_error(catalog, "duplicate entry id"), "duplicate id is reported")
	expect(_has_error(catalog, "wire_id 0 collides"), "wire collision is reported")


func test_class_coverage_and_weapon_links_fail() -> void:
	var catalog := _catalog()
	var weapon := _entry("test/weapon", &"weapon", KNIGHT_WEAPON, 0)
	var cls := _entry("test/class", &"class", PLAYER_SCENE, 0)
	cls.links = {"weapon": &"test/weapon"}
	_set_entries(catalog, [weapon, cls])

	expect(not catalog.validate(), "a partial class table fails")
	expect(_has_error(catalog, "class wire ids must be exactly 0..4"),
		"class coverage is enforced")

	var missing_link := _entry("test/class2", &"class", PLAYER_SCENE, 0)
	_set_entries(catalog, [missing_link])
	expect(not catalog.validate(), "a class without a weapon fails")
	expect(_has_error(catalog, "needs links.weapon"), "missing weapon link is reported")


func test_budget_targets_and_hard_caps() -> void:
	var catalog := _catalog()
	var map := _entry("test/map", &"map", PLAYER_SCENE)
	map.budgets = {"draw_calls": 999, "triangles": 250000, "spawns": 8}
	_set_entries(catalog, [map])

	expect(not catalog.validate(), "hard budget cap fails")
	expect(_has_error(catalog, "draw_calls=999.0 exceeds hard cap"), "hard cap is reported")
	expect(_has_warning(catalog, "triangles=250000.0 is above target"), "soft target warns")

	var ok_map := _entry("test/map_ok", &"map", PLAYER_SCENE)
	ok_map.budgets = {"draw_calls": 100, "triangles": 180000, "spawns": 8}
	_set_entries(catalog, [ok_map])
	expect(catalog.validate(), "a map inside target passes")

	var no_spawns := _entry("test/map_spawns", &"map", PLAYER_SCENE)
	no_spawns.budgets = {"spawns": 2}
	_set_entries(catalog, [no_spawns])
	expect(not catalog.validate(), "too few spawns fails")
	expect(_has_error(catalog, "spawns=2.0 is below hard minimum"), "spawn minimum is reported")


func test_dependency_cycles_and_missing_dependencies_fail() -> void:
	var catalog := _catalog()
	var a := _entry("test/a", &"mode")
	var b := _entry("test/b", &"mode")
	a.dependencies = [b.id]
	b.dependencies = [a.id]
	_set_entries(catalog, [a, b])

	expect(not catalog.validate(), "dependency cycle fails")
	expect(_has_error(catalog, "dependency cycle"), "cycle is reported")

	var missing := _entry("test/missing_dep", &"mode")
	missing.dependencies = [&"test/nope"]
	_set_entries(catalog, [missing])
	expect(not catalog.validate(), "missing dependency fails")
	expect(_has_error(catalog, "depends on missing entry"), "missing dependency is reported")


func test_disabled_entries_are_indexed_but_not_offered() -> void:
	var catalog := _catalog()
	var off := _entry("test/off", &"weapon", KNIGHT_WEAPON, 0)
	off.enabled = false
	_set_entries(catalog, [off])

	expect(catalog.validate(), "disabled entry is still structurally valid")
	expect(catalog.entries(&"weapon").is_empty(), "disabled entry is not offered")
	expect(catalog.entries(&"weapon", true).size() == 1, "disabled entry is still indexed")
	expect(catalog.has_entry(&"weapon", &"test/off"), "disabled entry is resolvable by id")


func test_resolve_caches_by_path() -> void:
	var catalog := ContentCatalog.new()
	expect(catalog.load_manifest(ContentCatalog.DEFAULT_MANIFEST), "manifest loads")
	var entry := catalog.entry(&"weapon", &"core/knight_javelin")
	expect(entry != null, "core weapon exists")
	var first := catalog.resolve(entry)
	var second := catalog.resolve(entry)
	expect(first != null and first == second, "resolve returns the cached resource")


# --- helpers --------------------------------------------------------------

func _catalog() -> ContentCatalog:
	var catalog := ContentCatalog.new()
	catalog.manifest = ContentManifest.new()
	catalog.manifest.game_version = "0.1.0"
	var pack := ContentPack.new()
	pack.pack_id = &"test"
	pack.version = "1.0.0"
	catalog.add_pack(pack)
	return catalog


func _set_entries(catalog: ContentCatalog, entries: Array) -> void:
	catalog.packs[0].entries.clear()
	for item in entries:
		catalog.packs[0].entries.append(item)


func _entry(id: String, kind: StringName, path: String = "", wire_id: int = -1) -> ContentEntry:
	var entry := ContentEntry.new()
	entry.id = StringName(id)
	entry.kind = kind
	entry.display_name = id
	entry.path = path
	entry.wire_id = wire_id
	entry.tags = [&"core"]
	entry.attribution = "test"
	entry.license = "test"
	return entry


func _has_error(catalog: ContentCatalog, needle: String) -> bool:
	for message in catalog.errors:
		if message.contains(needle):
			return true
	return false


func _has_warning(catalog: ContentCatalog, needle: String) -> bool:
	for message in catalog.warnings:
		if message.contains(needle):
			return true
	return false
