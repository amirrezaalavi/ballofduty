class_name ContentCatalog
extends RefCounted
## Loads, indexes and validates external artifacts. The game only asks for a
## kind + id; it never hard-codes a map list, a class table or a weapon path.
##
## Validation is intentionally strict because a bad artifact must fail at build
## time, not mid-match. `tools/validate_content.gd` is the CI entry point; the
## runtime `shared()` instance falls back to the compiled defaults if the
## manifest is missing, so a broken pack cannot brick the menu.

const DEFAULT_MANIFEST := "res://resources/content/manifest.tres"
const KINDS: Array[StringName] = ContentEntry.KINDS
## Per-kind budget limits: [target, hard]. Exceeding target is a warning;
## exceeding hard is an error. Values are deliberately map-agnostic.
const BUDGETS := {
	&"map": {
		"draw_calls": [120.0, 150.0],
		"triangles": [200000.0, 300000.0],
		"colliders": [500.0, 800.0],
		"texture_mb": [30.0, 40.0],
		"load_ms": [100.0, 250.0],
		"nodes": [1200.0, 2000.0],
	},
	&"class": {
		"nodes": [40.0, 60.0],
		"triangles": [18000.0, 30000.0],
		"texture_mb": [8.0, 12.0],
		"animation_players": [5.0, 6.0],
	},
	&"weapon": {
		"nodes": [20.0, 30.0],
		"triangles": [4000.0, 8000.0],
		"texture_mb": [2.0, 4.0],
		"snapshot_bytes": [0.0, 0.0],
	},
	&"collectible": {
		"nodes": [20.0, 30.0],
		"triangles": [1000.0, 2000.0],
		"texture_mb": [1.0, 2.0],
		"snapshot_bytes": [4.0, 8.0],
	},
	&"mode": {},
	&"cosmetic": {
		"nodes": [20.0, 30.0],
		"triangles": [2000.0, 4000.0],
		"texture_mb": [1.0, 2.0],
	},
}
## Minimums where more is better (maps must expose enough spawns).
const MINIMUMS := {
	&"map": {"spawns": [8.0, 4.0]},  # [target, hard minimum]
}

static var _shared: ContentCatalog

var manifest: ContentManifest
var packs: Array[ContentPack] = []
var errors: Array[String] = []
var warnings: Array[String] = []

var _entries: Dictionary = {}  # kind -> id -> ContentEntry
var _wire: Dictionary = {}     # kind -> wire_id -> ContentEntry
var _all_ids: Dictionary = {}  # id -> ContentEntry
var _pack_by_id: Dictionary = {}
var _cache: Dictionary = {}    # path -> Resource


static func shared() -> ContentCatalog:
	if _shared == null:
		_shared = ContentCatalog.new()
		_shared.load_manifest(DEFAULT_MANIFEST)
	return _shared


static func reset_shared() -> void:
	_shared = null


func clear() -> void:
	manifest = null
	packs.clear()
	errors.clear()
	warnings.clear()
	_entries.clear()
	_wire.clear()
	_all_ids.clear()
	_pack_by_id.clear()
	_cache.clear()


func load_manifest(path: String = DEFAULT_MANIFEST) -> bool:
	clear()
	if not _valid_path(path):
		errors.append("manifest path must be res:// and must not contain '..': %s" % path)
		return false
	if not ResourceLoader.exists(path):
		errors.append("manifest not found: %s" % path)
		return false
	var res: Resource = ResourceLoader.load(path)
	if not res is ContentManifest:
		errors.append("manifest is not a ContentManifest: %s" % path)
		return false
	manifest = res as ContentManifest
	for pack_path in manifest.pack_paths:
		if not _valid_path(pack_path):
			errors.append("pack path must be res:// and must not contain '..': %s" % pack_path)
			continue
		if not ResourceLoader.exists(pack_path):
			errors.append("pack not found: %s" % pack_path)
			continue
		var pack_res: Resource = ResourceLoader.load(pack_path)
		if not pack_res is ContentPack:
			errors.append("pack is not a ContentPack: %s" % pack_path)
			continue
		add_pack(pack_res as ContentPack)
	var ok := validate()
	_preload_marked()
	return ok and errors.is_empty()


func add_pack(pack: ContentPack) -> void:
	if pack == null:
		errors.append("cannot add a null pack")
		return
	packs.append(pack)


## Rebuilds the index and checks every contract. Safe to call repeatedly.
func validate() -> bool:
	errors.clear()
	warnings.clear()
	_entries.clear()
	_wire.clear()
	_all_ids.clear()
	_pack_by_id.clear()

	if manifest == null:
		errors.append("no manifest loaded")
		return false
	if manifest.game_version.strip_edges() == "":
		errors.append("manifest.game_version is empty")
	if manifest.pack_paths.is_empty() and packs.is_empty():
		warnings.append("manifest lists no packs")

	for pack in packs:
		_validate_pack(pack)

	# Pack dependency cycles and missing pack ids.
	for pack in packs:
		for dep: StringName in pack.dependencies:
			if not _pack_by_id.has(dep):
				errors.append("pack %s depends on missing pack %s" % [pack.pack_id, dep])
	_validate_pack_cycles()

	for entry in _all_ids.values():
		_validate_entry_links(entry)
		_validate_dependencies(entry)

	_validate_entry_cycles()
	_validate_class_coverage()
	return errors.is_empty()


func error_count() -> int:
	return errors.size()


func warning_count() -> int:
	return warnings.size()


func is_ok() -> bool:
	return errors.is_empty()


func entries(kind: StringName, include_disabled: bool = false) -> Array[ContentEntry]:
	var out: Array[ContentEntry] = []
	var bucket: Dictionary = _entries.get(kind, {})
	for entry: ContentEntry in bucket.values():
		if include_disabled or entry.enabled:
			out.append(entry)
	out.sort_custom(func(a: ContentEntry, b: ContentEntry) -> bool:
		var aw := a.wire_id if a.wire_id >= 0 else 999
		var bw := b.wire_id if b.wire_id >= 0 else 999
		if aw == bw:
			return String(a.id) < String(b.id)
		return aw < bw
	)
	return out


func entry(kind: StringName, id: StringName) -> ContentEntry:
	var bucket: Dictionary = _entries.get(kind, {})
	return bucket.get(id) as ContentEntry


func has_entry(kind: StringName, id: StringName) -> bool:
	return entry(kind, id) != null


func by_wire_id(kind: StringName, wire_id: int) -> ContentEntry:
	var bucket: Dictionary = _wire.get(kind, {})
	return bucket.get(wire_id) as ContentEntry


func wire_id(kind: StringName, id: StringName) -> int:
	var found := entry(kind, id)
	return found.wire_id if found != null else -1


func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in _all_ids:
		out.append(key)
	out.sort()
	return out


## Loads the entry's primary resource once and caches it by path.
func resolve(found: ContentEntry) -> Resource:
	if found == null or found.path == "":
		return null
	if _cache.has(found.path):
		return _cache[found.path] as Resource
	if not ResourceLoader.exists(found.path):
		return null
	var res: Resource = ResourceLoader.load(found.path)
	_cache[found.path] = res
	return res


func scene(kind: StringName, id: StringName) -> PackedScene:
	var res := resolve(entry(kind, id))
	return res as PackedScene


func report() -> Dictionary:
	return {
		"ok": is_ok(),
		"packs": packs.size(),
		"entries": _all_ids.size(),
		"errors": errors.duplicate(),
		"warnings": warnings.duplicate(),
	}


# --- validation -----------------------------------------------------------

func _validate_pack(pack: ContentPack) -> void:
	var pid := String(pack.pack_id)
	if pid.strip_edges() == "":
		errors.append("pack has an empty pack_id")
	elif _pack_by_id.has(pack.pack_id):
		errors.append("duplicate pack_id: %s" % pid)
	else:
		_pack_by_id[pack.pack_id] = pack
	if pack.version.strip_edges() == "":
		warnings.append("pack %s has no version" % pid)
	if pack.min_game_version != "" and not _version_at_least(
		manifest.game_version, pack.min_game_version
	):
		errors.append("pack %s needs game >= %s (manifest is %s)" % [
			pid, pack.min_game_version, manifest.game_version,
		])
	if pack.entries.is_empty():
		warnings.append("pack %s has no entries" % pid)
	for item in pack.entries:
		if not item is ContentEntry:
			errors.append("pack %s contains a non-ContentEntry resource" % pid)
			continue
		_validate_entry(item as ContentEntry, pid)


func _validate_entry(entry: ContentEntry, pack_id: String) -> void:
	var eid := String(entry.id)
	if not _valid_id(eid):
		errors.append("invalid entry id '%s' in pack %s (use namespace/name)" % [eid, pack_id])
	if not entry.kind_is_known():
		errors.append("entry %s has unknown kind '%s'" % [eid, entry.kind])
	if entry.display_name.strip_edges() == "":
		warnings.append("entry %s has no display_name" % eid)
	if not _valid_version(entry.version):
		warnings.append("entry %s has non-semver version '%s'" % [eid, entry.version])

	if _all_ids.has(entry.id):
		errors.append("duplicate entry id: %s" % eid)
	else:
		_all_ids[entry.id] = entry
		if not _entries.has(entry.kind):
			_entries[entry.kind] = {}
		var bucket: Dictionary = _entries[entry.kind]
		if bucket.has(entry.id):
			errors.append("duplicate %s entry: %s" % [entry.kind, eid])
		else:
			bucket[entry.id] = entry

	if entry.wire_id < -1 or entry.wire_id > 255:
		errors.append("entry %s wire_id %d is outside -1..255" % [eid, entry.wire_id])
	elif entry.wire_id >= 0:
		if not _wire.has(entry.kind):
			_wire[entry.kind] = {}
		var wire_bucket: Dictionary = _wire[entry.kind]
		if wire_bucket.has(entry.wire_id):
			var other := wire_bucket[entry.wire_id] as ContentEntry
			errors.append("%s wire_id %d collides: %s and %s" % [
				entry.kind, entry.wire_id, other.id, eid,
			])
		else:
			wire_bucket[entry.wire_id] = entry

	if entry.kind == &"class" and entry.wire_id < 0:
		errors.append("class %s needs a stable wire_id >= 0" % eid)
	if entry.kind == &"map" and entry.wire_id >= 0:
		warnings.append("map %s has a wire_id; maps are local and use string ids" % eid)

	if entry.path == "":
		if entry.kind in [&"map", &"class", &"weapon", &"collectible"]:
			errors.append("%s %s has no path" % [entry.kind, eid])
	else:
		if not _valid_path(entry.path):
			errors.append("entry %s path must be res:// without '..': %s" % [eid, entry.path])
		elif not ResourceLoader.exists(entry.path):
			errors.append("entry %s path does not exist: %s" % [eid, entry.path])
		elif entry.resource_type != &"":
			var res: Resource = ResourceLoader.load(entry.path)
			var actual := _actual_type(res)
			if actual != String(entry.resource_type):
				errors.append("entry %s expects %s, path is %s" % [
					eid, entry.resource_type, actual,
				])

	if entry.attribution.strip_edges() == "" and not entry.tags.has(&"core"):
		warnings.append("entry %s has no attribution" % eid)
	if entry.license.strip_edges() == "" and not entry.tags.has(&"core"):
		warnings.append("entry %s has no license" % eid)

	_validate_budgets(entry)


func _validate_budgets(entry: ContentEntry) -> void:
	var limits: Dictionary = BUDGETS.get(entry.kind, {})
	for key: String in entry.budgets:
		var raw: Variant = entry.budgets[key]
		if not (raw is int or raw is float):
			errors.append("entry %s budget '%s' must be a number" % [entry.id, key])
			continue
		var value := float(raw)
		if value < 0.0:
			errors.append("entry %s budget '%s' is negative" % [entry.id, key])
			continue
		if limits.has(key):
			var pair: Array = limits[key]
			var target := float(pair[0])
			var hard := float(pair[1])
			if value > hard:
				errors.append("entry %s %s=%.1f exceeds hard cap %.1f" % [
					entry.id, key, value, hard,
				])
			elif value > target:
				warnings.append("entry %s %s=%.1f is above target %.1f" % [
					entry.id, key, value, target,
				])
		elif not MINIMUMS.get(entry.kind, {}).has(key):
			warnings.append("entry %s uses unknown budget '%s'" % [entry.id, key])
	var minimums: Dictionary = MINIMUMS.get(entry.kind, {})
	for key: String in minimums:
		var pair: Array = minimums[key]
		var target := float(pair[0])
		var hard := float(pair[1])
		var value := float(entry.budgets.get(key, 0.0))
		if value < hard:
			errors.append("entry %s %s=%.1f is below hard minimum %.1f" % [
				entry.id, key, value, hard,
			])
		elif value < target:
			warnings.append("entry %s %s=%.1f is below target %.1f" % [
				entry.id, key, value, target,
			])


func _validate_dependencies(entry: ContentEntry) -> void:
	for dep: StringName in entry.dependencies:
		if dep == entry.id:
			errors.append("entry %s depends on itself" % entry.id)
		elif not _all_ids.has(dep):
			errors.append("entry %s depends on missing entry %s" % [entry.id, dep])


func _validate_entry_links(entry: ContentEntry) -> void:
	if entry.kind == &"class":
		var weapon_id: StringName = entry.links.get("weapon", &"")
		if weapon_id == &"":
			errors.append("class %s needs links.weapon" % entry.id)
		else:
			var weapon := self.entry(&"weapon", weapon_id)
			if weapon == null:
				errors.append("class %s links missing weapon %s" % [entry.id, weapon_id])
			elif weapon.wire_id != entry.wire_id:
				errors.append("class %s wire_id %d does not match weapon %s wire_id %d" % [
					entry.id, entry.wire_id, weapon_id, weapon.wire_id,
				])
	var visual := String(entry.links.get("visual", ""))
	if visual != "" and not ResourceLoader.exists(visual):
		errors.append("entry %s links missing visual %s" % [entry.id, visual])
	var projectile := String(entry.links.get("projectile", ""))
	if projectile != "" and not ResourceLoader.exists(projectile):
		errors.append("entry %s links missing projectile %s" % [entry.id, projectile])


func _validate_class_coverage() -> void:
	var classes := entries(&"class", true)
	if classes.is_empty():
		return
	var got: Array[int] = []
	for cls in classes:
		got.append(cls.wire_id)
	got.sort()
	var expected: Array[int] = []
	for i in NetProtocol.CLASS_COUNT:
		expected.append(i)
	if got != expected:
		errors.append("class wire ids must be exactly 0..%d (got %s)" % [
			NetProtocol.CLASS_COUNT - 1, str(got),
		])


func _validate_pack_cycles() -> void:
	var visiting: Dictionary = {}
	var done: Dictionary = {}
	for pack in packs:
		_visit_pack(pack, visiting, done, [])


func _visit_pack(pack: ContentPack, visiting: Dictionary, done: Dictionary, stack: Array) -> void:
	if done.has(pack.pack_id):
		return
	if visiting.has(pack.pack_id):
		errors.append("pack dependency cycle: %s" % " -> ".join(stack + [String(pack.pack_id)]))
		return
	visiting[pack.pack_id] = true
	for dep: StringName in pack.dependencies:
		var next := _pack_by_id.get(dep) as ContentPack
		if next != null:
			_visit_pack(next, visiting, done, stack + [String(pack.pack_id)])
	visiting.erase(pack.pack_id)
	done[pack.pack_id] = true


func _validate_entry_cycles() -> void:
	var visiting: Dictionary = {}
	var done: Dictionary = {}
	for entry: ContentEntry in _all_ids.values():
		_visit_entry(entry, visiting, done, [])


func _visit_entry(entry: ContentEntry, visiting: Dictionary, done: Dictionary, stack: Array) -> void:
	if done.has(entry.id):
		return
	if visiting.has(entry.id):
		errors.append("entry dependency cycle: %s" % " -> ".join(stack + [String(entry.id)]))
		return
	visiting[entry.id] = true
	for dep: StringName in entry.dependencies:
		var next := _all_ids.get(dep) as ContentEntry
		if next != null:
			_visit_entry(next, visiting, done, stack + [String(entry.id)])
	visiting.erase(entry.id)
	done[entry.id] = true


func _preload_marked() -> void:
	for entry: ContentEntry in _all_ids.values():
		if not entry.enabled or not entry.preload_on_load:
			continue
		var res := resolve(entry)
		if res == null:
			errors.append("preload failed for %s: %s" % [entry.id, entry.path])


# --- helpers --------------------------------------------------------------

func _valid_path(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("..") and not path.contains("\\")


func _valid_id(id: String) -> bool:
	var parts := id.split("/")
	if parts.size() != 2:
		return false
	for part in parts:
		if part.is_empty():
			return false
		for c in part:
			if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
				return false
	return true


func _valid_version(version: String) -> bool:
	var parts := version.split(".")
	if parts.size() != 3:
		return false
	for part in parts:
		if part.is_empty() or not part.is_valid_int():
			return false
	return true


func _version_at_least(current: String, required: String) -> bool:
	var a := _version_tuple(current)
	var b := _version_tuple(required)
	for i in maxi(a.size(), b.size()):
		var av := a[i] if i < a.size() else 0
		var bv := b[i] if i < b.size() else 0
		if av > bv:
			return true
		if av < bv:
			return false
	return true


func _version_tuple(version: String) -> Array[int]:
	var out: Array[int] = []
	for part in version.split("."):
		out.append(int(part) if part.is_valid_int() else 0)
	return out


func _actual_type(res: Resource) -> String:
	if res == null:
		return "<null>"
	var script: Script = res.get_script() as Script
	if script != null:
		return String(script.get_global_name())
	return res.get_class()
