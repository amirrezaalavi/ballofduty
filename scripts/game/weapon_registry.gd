class_name WeaponRegistry
extends RefCounted
## Class -> WeaponStats lookup. The five profiles are preloaded so joining or
## respawning never hits the ResourceLoader mid-match and the server can resolve
## an entry's class_id synchronously. Order matches NetProtocol.CLASS_COUNT:
## 0 Knight, 1 Mage, 2 Rogue, 3 Rogue_Hooded, 4 Barbarian.
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


static func stats_for(class_id: int) -> WeaponStats:
	if class_id < 0 or class_id >= PROFILES.size():
		return null
	return PROFILES[class_id] as WeaponStats


static func count() -> int:
	return PROFILES.size()


static func class_ids() -> Array[int]:
	var out: Array[int] = []
	for i in PROFILES.size():
		out.append(int((PROFILES[i] as WeaponStats).class_id))
	return out
