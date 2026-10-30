class_name CharacterBodyRegistry
extends RefCounted
## class_id -> CharacterBodyStats. The five profiles are compiled in so the
## headless server and a web client resolve exactly the same resource without a
## runtime file lookup. Step 1 keeps all five numerically identical to the old
## 0.82 m rig; Step 2 will tune individual profiles without touching this API.

const PROFILES: Array = [
	preload("res://resources/players/body_knight.tres"),
	preload("res://resources/players/body_mage.tres"),
	preload("res://resources/players/body_rogue.tres"),
	preload("res://resources/players/body_rogue_hooded.tres"),
	preload("res://resources/players/body_barbarian.tres"),
]


static func stats_for(class_id: int) -> CharacterBodyStats:
	if class_id < 0 or class_id >= PROFILES.size():
		return null
	return PROFILES[class_id] as CharacterBodyStats


static func default_profile() -> CharacterBodyStats:
	return PROFILES[0] as CharacterBodyStats


static func count() -> int:
	return PROFILES.size()
