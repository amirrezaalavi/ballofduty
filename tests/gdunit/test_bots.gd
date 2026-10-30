extends BodTestSuite
## CP4c bots: a headless server fills the roster with bots that move, shoot,
## damage each other, and respawn without a client.

const PORT := 9187

var _net: Node
var _gm: Node
var _world: Node3D


func after_test() -> void:
	if is_instance_valid(_net):
		_net.stop()
	if is_instance_valid(_world):
		_world.free()


func test_four_bots_play() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	col.shape = box
	floor_body.add_child(col)
	_world.add_child(floor_body)
	floor_body.position = Vector3(0, -0.55, 0)

	_net = load("res://scripts/networking/network_manager.gd").new()
	_gm = load("res://scripts/game/game_manager.gd").new()
	add_child(_net)
	add_child(_gm)
	_gm.net = _net
	expect(_gm.server_start(_world, PORT, 4) == OK, "server starts with four bots")
	expect(_gm.server_player_count() == 4, "four bots join the roster")
	expect(_gm._by_id.size() == 4, "roster id index holds one entry per bot")
	for peer_id in _gm._roster:
		var indexed: Dictionary = _gm._roster[peer_id]
		expect(_gm._entry_by_id(int(indexed["id"]))["id"] == indexed["id"],
			"id index resolves id %d" % int(indexed["id"]))

	var initial: Array[Vector3] = []
	for peer_id in _gm._roster:
		initial.append((_gm._roster[peer_id]["node"] as Node3D).global_position)
	var los_before := int(_gm.los_checks)
	for _i in 30:
		await get_tree().physics_frame
	var los_window := int(_gm.los_checks) - los_before
	print("  bots los window: %d checks in 30 frames (4 bots)" % los_window)
	expect(los_window <= 4 * 12,
		"bot LOS is staggered, not per tick (%d checks in 30 frames)" % los_window)
	expect(los_window > 0, "bots still evaluate target LOS")
	for _i in 60:
		await get_tree().physics_frame

	expect(_gm.server_player_count() == 4, "bots remain in the roster")
	expect(int(_gm._combat.projectiles_fired) > 0, "bots fire authoritative projectiles")
	var moved := false
	var index := 0
	for peer_id in _gm._roster:
		var node: Node = _gm._roster[peer_id]["node"]
		if is_instance_valid(node) and (node as Node3D).global_position.distance_to(initial[index]) > 0.4:
			moved = true
		index += 1
	expect(moved, "at least one bot moved from its spawn")
	var dead_or_damaged := false
	for peer_id in _gm._roster:
		var entry: Dictionary = _gm._roster[peer_id]
		var health := entry["node"].get_node("HealthComponent") as HealthComponent
		if int(entry["dead_until"]) > 0 or health.current < 100:
			dead_or_damaged = true
	expect(dead_or_damaged, "bots damage or kill each other")
