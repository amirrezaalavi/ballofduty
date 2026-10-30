class_name WeaponRegistry
extends RefCounted
## Class -> WeaponStats lookup. The catalog is the source of truth: each weapon
## entry in resources/content declares a stable wire_id equal to its class_id.
## The compiled PROFILES table remains as a fallback so a missing or invalid
## manifest cannot brick the menu or the server.
##
## The legacy R-1 rifle is deliberately absent: it is not in the V1 rotation and
## is kept for the later M4 power-weapon pass.

const PROFILES: Array = [
	preload("res://resources/weapons/class_knight_javelin.tres"),
	preload("res://resources/weapons/class_mage_staff.tres"),
	preload("res://resources/weapons/class_rogue_bow.tres"),
	preload("res://resources/weapons/class_rogue_hooded_crossbow.tres"),
	preload("res://resources/weapons/class_barbarian_axes.tres"),
]

static var _resolved: Array = []
static var _source: String = ""


static func _profiles() -> Array:
	if not _resolved.is_empty():
		return _resolved
	var found: Array = []
	var catalog := ContentCatalog.shared()
	if catalog != null and catalog.is_ok():
		for class_id in NetProtocol.CLASS_COUNT:
			var entry := catalog.by_wire_id(&"weapon", class_id)
			if entry == null:
				found.clear()
				break
			var res := catalog.resolve(entry)
			if not res is WeaponStats:
				found.clear()
				break
			found.append(res)
	if found.size() == NetProtocol.CLASS_COUNT:
		_resolved = found
		_source = "catalog"
	else:
		_resolved = PROFILES.duplicate()
		_source = "fallback"
	return _resolved


static func stats_for(class_id: int) -> WeaponStats:
	var profiles := _profiles()
	if class_id < 0 or class_id >= profiles.size():
		return null
	return profiles[class_id] as WeaponStats


static func count() -> int:
	return _profiles().size()


static func class_ids() -> Array[int]:
	var out: Array[int] = []
	for profile in _profiles():
		out.append(int((profile as WeaponStats).class_id))
	return out


## "catalog" when the content manifest supplied the profiles, "fallback" when
## the compiled table was used. Diagnostics and tests read this.
static func source() -> String:
	_profiles()
	return _source


static func reset_cache() -> void:
	_resolved.clear()
	_source = ""
