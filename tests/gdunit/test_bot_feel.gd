extends BodTestSuite
## Phase 1 C bot feel: bounded reaction delay and persistent (not per-tick)
## aim error, while four bots on flat ground still trade real damage.

const DT := 1.0 / 30.0
const PORT := 9291
const GM_SCRIPT := preload("res://scripts/game/game_manager.gd")


var _world: Node3D
var _gm: Node
var _net: Node


func after_test() -> void:
	if is_instance_valid(_net):
		_net.stop()
	if is_instance_valid(_gm):
		_gm.stop_all()
	if is_instance_valid(_world):
		_world.free()
	_world = null
	_gm = null
	_net = null


func _flat_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.55, 0.0)
	_world.add_child(floor_body)


func _duel() -> Dictionary:
	await _flat_world()
	_gm = load("res://scripts/game/game_manager.gd").new()
	add_child(_gm)
	_gm._world = _world
	var a := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	var b := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_world.add_child(a)
	_world.add_child(b)
	a.make_server(1)
	b.make_server(2)
	a.global_position = Vector3(0.0, 0.2, 0.0)
	b.global_position = Vector3(0.0, 0.2, 3.0)
	await get_tree().physics_frame
	var entry_a: Dictionary = _gm._new_entry(1, "BOT 1", a, -1001)
	var entry_b: Dictionary = _gm._new_entry(2, "TARGET", b, -1002)
	_gm._roster = {-1001: entry_a, -1002: entry_b}
	return {"gm": _gm, "a": a, "b": b, "entry": entry_a}


func test_reaction_delay_and_bounded_spread() -> void:
	var duel := await _duel()
	var entry: Dictionary = duel["entry"]
	var actor: PlayerController = duel["a"]
	var target: PlayerController = duel["b"]

	# First frames: the bot has line of sight and a target in range, but the
	# reaction timer has not elapsed, so it must not fire.
	for _i in 5:
		var early: PlayerInputFrame = _gm._bot_frame(entry, actor, DT)
		expect(not early.fire, "bot holds fire during reaction delay")
		await get_tree().physics_frame
	expect(int(entry.get("bot_target_id", 0)) == 2, "bot acquired target id 2")
	var reaction := float(entry.get("bot_reaction_left", -1.0))
	expect(reaction >= 0.0 and reaction <= GM_SCRIPT.BOT_REACTION_MAX_SEC,
		"reaction timer stays bounded (%.2fs)" % reaction)

	var fired := false
	var samples := 0
	var max_error := 0.0
	var max_allowed := deg_to_rad(
		GM_SCRIPT.BOT_AIM_ERROR_BASE_DEG + GM_SCRIPT.BOT_AIM_ERROR_MOVING_DEG + 3.0
	)
	for i in 90:
		var frame: PlayerInputFrame = _gm._bot_frame(entry, actor, DT)
		fired = fired or frame.fire
		if i >= 30:
			var aim := ServerCombat.aim_angles(
				actor.global_position, target.global_position + Vector3(0.0, 0.45, 0.0)
			)
			var yaw_error := absf(wrapf(frame.yaw - aim.x, -PI, PI))
			max_error = maxf(max_error, yaw_error)
			samples += 1
		await get_tree().physics_frame
	expect(fired, "bot fires once the reaction delay elapses")
	expect(samples > 0, "collected aim samples")
	expect(max_error <= max_allowed,
		"aim error stays inside its bound (%.2f° <= %.2f°)" % [
			rad_to_deg(max_error),
			rad_to_deg(max_allowed),
		])
	expect(max_error > 0.0005,
		"aim is not perfect (max error %.2f°)" % rad_to_deg(max_error))


func test_four_bots_still_deal_damage() -> void:
	await _flat_world()
	_net = load("res://scripts/networking/network_manager.gd").new()
	_gm = load("res://scripts/game/game_manager.gd").new()
	add_child(_net)
	add_child(_gm)
	_gm.net = _net
	expect(_gm.server_start(_world, PORT, 4) == OK, "server starts with four bots")
	expect(_gm.server_player_count() == 4, "four bots join")

	for _i in 240:
		await get_tree().physics_frame

	expect(int(_gm._combat.shots_fired) > 0,
		"bots fire after reaction delays (%d shots)" % int(_gm._combat.shots_fired))
	expect(int(_gm._combat.projectiles_fired) > 0, "shots spawn authoritative projectiles")
	expect(int(_gm._hits_total) > 0,
		"bots still land hits with spread (%d hits, %d deaths)" % [
			int(_gm._hits_total), int(_gm._deaths_total)])
	var telemetry: String = _gm._combat.telemetry_line()
	expect(telemetry.contains("hit%"), "combat telemetry available")
	print("  bots: %s" % telemetry)
