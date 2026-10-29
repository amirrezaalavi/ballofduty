extends BodTestSuite
## Phase 2A class weapons: registry/profile table, per-class damage, charge
## hold/release, burst cadence, heat lockout and bot class assignment.

const DT := 1.0 / 30.0
const PORT := 9193

var _world: Node3D
var _a: PlayerController
var _b: PlayerController
var _combat: ServerCombat
var _entry: Dictionary
var _entry_b: Dictionary
var _net: Node
var _gm: Node


func after_test() -> void:
	if is_instance_valid(_net):
		_net.stop()
	if is_instance_valid(_gm):
		_gm.queue_free()
	if is_instance_valid(_world):
		_world.free()


func _setup(class_id: int) -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	col.shape = box
	floor_body.add_child(col)
	floor_body.position = Vector3(0, -0.55, 0)
	_world.add_child(floor_body)

	_a = (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_b = (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_world.add_child(_a)
	_world.add_child(_b)
	_a.make_server(1, class_id)
	_b.make_server(2, 1)
	_a.global_position = Vector3(0.0, 0.2, 0.0)
	_b.global_position = Vector3(0.0, 0.2, -3.5)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var fallback := load("res://resources/weapons/rifle_stats.tres") as WeaponStats
	_combat = ServerCombat.new(_world, fallback)
	_entry = {"id": 1, "class_id": class_id, "node": _a}
	_entry_b = {"id": 2, "class_id": 1, "node": _b}
	_combat.reset_player(_entry)
	_combat.reset_player(_entry_b)


func _body() -> HealthComponent:
	return _b.get_node("HealthComponent") as HealthComponent


func _body_target() -> Vector3:
	return (_b.get_node("BodyHurtbox/CollisionShape3D") as Node3D).global_position


func _aim_frame(fire: bool = true) -> PlayerInputFrame:
	var angles := ServerCombat.aim_angles(_a.global_position, _body_target())
	var frame := PlayerInputFrame.new()
	frame.yaw = angles.x
	frame.pitch = angles.y
	frame.fire = fire
	return frame


func _fire_once(wait_frames: int = 8) -> Dictionary:
	var shot := _combat.process(_entry, _a, _aim_frame(true), DT)
	for _i in wait_frames:
		await get_tree().physics_frame
	return shot


func _settle_shot(wait_frames: int = 8) -> void:
	for _i in wait_frames:
		await get_tree().physics_frame


func test_registry_matches_locked_class_map() -> void:
	expect(WeaponRegistry.count() == NetProtocol.CLASS_COUNT, "five class profiles")
	var expected := [
		&"knight_javelin", &"mage_staff", &"rogue_bow",
		&"rogue_hooded_crossbow", &"barbarian_axes",
	]
	var seen: Dictionary = {}
	for class_id in NetProtocol.CLASS_COUNT:
		var weapon := WeaponRegistry.stats_for(class_id)
		expect(weapon != null, "class %d has stats" % class_id)
		if weapon == null:
			continue
		expect(weapon.class_id == class_id, "class %d profile self-identifies" % class_id)
		expect(weapon.weapon_id == expected[class_id],
			"class %d is %s (got %s)" % [class_id, expected[class_id], weapon.weapon_id])
		expect(not seen.has(weapon.weapon_id), "weapon ids are unique")
		seen[weapon.weapon_id] = true
		expect(weapon.magazine_size > 0, "class %d has a magazine" % class_id)
	expect(WeaponRegistry.stats_for(-1) == null, "negative class has no profile")
	expect(WeaponRegistry.stats_for(NetProtocol.CLASS_COUNT) == null, "class 5 has no profile")
	var rifle := load("res://resources/weapons/rifle_stats.tres") as WeaponStats
	expect(rifle.weapon_id == &"rifle", "M4 stats resource is preserved")
	expect(not seen.has(rifle.weapon_id), "M4 is not in the class rotation")


func test_reset_player_seeds_per_class_state() -> void:
	await _setup(0)
	expect(int(_entry["ammo"]) == 3, "Knight resets to 3 javelins")
	expect(String(_entry["weapon_id"]) == "knight_javelin", "Knight weapon id installed")
	expect(float(_entry["heat"]) == 0.0, "Knight has no heat")
	expect(int(_entry["burst_left"]) == 0, "Knight has no burst")

	_entry["class_id"] = 1
	_combat.reset_player(_entry)
	expect(int(_entry["ammo"]) == 24, "Mage resets to 24 bolts")
	expect((_entry["stats"] as WeaponStats).heat_max == 6.0, "Mage has a 6-shot heat meter")

	_entry["class_id"] = 2
	_combat.reset_player(_entry)
	expect(int(_entry["ammo"]) == 1, "Rogue resets to one nocked arrow")
	expect((_entry["stats"] as WeaponStats).fire_mode == &"charge", "Rogue charges")

	_entry["class_id"] = 3
	_combat.reset_player(_entry)
	expect(int(_entry["ammo"]) == 12, "Rogue_Hooded resets to 12 bolts")
	expect((_entry["stats"] as WeaponStats).burst_count == 3, "Rogue_Hooded fires a 3-round burst")

	_entry["class_id"] = 4
	_combat.reset_player(_entry)
	expect(int(_entry["ammo"]) == 2, "Barbarian resets to two axes")


func test_knight_body_and_head_damage() -> void:
	await _setup(0)
	var shot := await _fire_once()
	expect(not shot.is_empty(), "Knight throw accepted")
	expect(is_equal_approx(float(shot.get("speed", 0.0)), 40.0), "Knight projectile is 40 m/s")
	expect(_body().current == 40, "Knight body hit deals 60 (hp %d)" % _body().current)

	_entry["cooldown"] = 0.0
	_combat.reset_player(_entry)
	_body().reset()
	var head := (_b.get_node("HeadHurtbox/CollisionShape3D") as Node3D).global_position
	var angles := ServerCombat.aim_angles(_a.global_position, head)
	var frame := PlayerInputFrame.new()
	frame.yaw = angles.x
	frame.pitch = angles.y
	frame.fire = true
	_combat.process(_entry, _a, frame, DT)
	await _settle_shot()
	expect(_body().current == 0, "Knight head hit deals 105 and kills (hp %d)" % _body().current)


func test_mage_body_damage_and_heat_lockout() -> void:
	await _setup(1)
	var shot := await _fire_once()
	expect(not shot.is_empty(), "Mage bolt accepted")
	expect(is_equal_approx(float(shot.get("speed", 0.0)), 64.0), "Mage bolt is 64 m/s")
	expect(_body().current == 72, "Mage direct body hit deals 28 (hp %d)" % _body().current)
	expect(_entry["overheated"] == false, "one shot is not an overheat")

	# Five more accepted shots fill the meter; the seventh intent is locked out.
	_body().reset()
	for _i in 5:
		_entry["cooldown"] = 0.0
		_combat.process(_entry, _a, _aim_frame(true), DT)
	await _settle_shot(12)
	expect(_entry["overheated"] == true, "six shots overheat the staff")
	expect(float(_entry["heat"]) == 6.0, "heat meter is full")
	var shots_before := _combat.shots_fired
	_entry["cooldown"] = 0.0
	var blocked := _combat.process(_entry, _a, _aim_frame(true), DT)
	expect(blocked.is_empty(), "overheated staff refuses to fire")
	expect(_combat.shots_fired == shots_before, "no round left the staff while locked")
	expect(_combat.blocked_heat >= 1, "heat rejection recorded")

	# Cooling clears the lockout without any input.
	for _i in 140:
		_combat.tick(_entry, DT)
	expect(_entry["overheated"] == false, "cooling clears the lockout")
	_entry["cooldown"] = 0.0
	var recovered := _combat.process(_entry, _a, _aim_frame(true), DT)
	expect(not recovered.is_empty(), "staff fires again after cooling")


func test_rogue_charge_hold_then_release() -> void:
	await _setup(2)
	# Press and hold: no round leaves the bow while drawing.
	for _i in 25:
		_combat.tick(_entry, DT)
		var held := _combat.process(_entry, _a, _aim_frame(true), DT)
		expect(held.is_empty(), "holding fire does not launch an arrow")
	expect(float(_entry["charge"]) >= 0.8, "charge accumulates while held")
	var shots_before := _combat.shots_fired

	var released := _combat.process(_entry, _a, _aim_frame(false), DT)
	expect(not released.is_empty(), "release launches the charged arrow")
	expect(_combat.shots_fired == shots_before + 1, "exactly one arrow on release")
	expect(float(released.get("speed", 0.0)) > 70.0,
		"full draw flies near 77 m/s (%.1f)" % float(released.get("speed", 0.0)))
	expect(int(released.get("damage", 0)) >= 70,
		"full draw deals near 75 (got %d)" % int(released.get("damage", 0)))
	await _settle_shot()
	expect(_body().current <= 30 and _body().current >= 20, "full-draw body hit deals about 75 (hp %d)" % _body().current)

	# A tap below the minimum draw ratio does not fire.
	_entry["cooldown"] = 0.0
	_entry["ammo"] = 1
	_combat.process(_entry, _a, _aim_frame(true), DT)
	var tap := _combat.process(_entry, _a, _aim_frame(false), DT)
	expect(tap.is_empty(), "release below the minimum draw does not fire")


func test_crossbow_burst_cadence_then_cooldown() -> void:
	await _setup(3)
	var press := _combat.process(_entry, _a, _aim_frame(true), DT)
	expect(not press.is_empty(), "first bolt leaves immediately on press")
	expect(_combat.shots_fired == 1, "one bolt on the press frame")

	var neutral := _aim_frame(false)
	var fired_at: Array[int] = []
	for tick in 20:
		_combat.tick(_entry, DT)
		_combat.process(_entry, _a, neutral, DT)
		if _combat.shots_fired > fired_at.size() + 1:
			fired_at.append(tick)
	expect(_combat.shots_fired == 3, "a press fires exactly three bolts (%d)" % _combat.shots_fired)
	expect(fired_at.size() == 2, "two follow-up bolts were scheduled")
	if fired_at.size() == 2:
		expect(fired_at[0] <= 4, "second bolt follows at the burst interval (tick %d)" % fired_at[0])
		expect(fired_at[1] - fired_at[0] <= 4,
			"third bolt follows at the burst interval (%d ticks)" % (fired_at[1] - fired_at[0]))
	# The cycle cooldown is still running right after the burst.
	var again := _combat.process(_entry, _a, _aim_frame(true), DT)
	expect(again.is_empty(), "a new press during the burst cycle is rejected")
	expect(_combat.blocked_cooldown >= 1, "cooldown rejection recorded for the crossbow")


func test_bots_use_their_class_weapon() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	col.shape = box
	floor_body.add_child(col)
	floor_body.position = Vector3(0, -0.55, 0)
	_world.add_child(floor_body)

	_net = load("res://scripts/networking/network_manager.gd").new()
	_gm = load("res://scripts/game/game_manager.gd").new()
	add_child(_net)
	add_child(_gm)
	_gm.net = _net
	expect(_gm.server_start(_world, PORT, 5) == OK, "server starts with five bots")
	var by_class: Dictionary = {}
	for peer_id in _gm._roster:
		var entry: Dictionary = _gm._roster[peer_id]
		var class_id := int(entry["class_id"])
		var weapon: WeaponStats = entry.get("stats", null)
		by_class[class_id] = true
		expect(weapon != null, "bot class %d has an installed profile" % class_id)
		if weapon:
			expect(weapon.class_id == class_id, "bot class %d uses its own profile" % class_id)
			expect(String(entry["weapon_id"]) == String(weapon.weapon_id),
				"bot class %d weapon id matches" % class_id)
	expect(by_class.size() == NetProtocol.CLASS_COUNT, "all five classes are represented")
	for _i in 90:
		await get_tree().physics_frame
	expect(int(_gm._combat.projectiles_fired) > 0, "class-armed bots fire projectiles")
	expect(int(_gm._combat.shots_by_weapon.size()) >= 3,
		"several distinct class weapons fired (%s)" % str(_gm._combat.shots_by_weapon.keys()))
