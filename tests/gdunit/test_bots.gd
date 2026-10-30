extends BodTestSuite
## CP4c bots: a headless server fills the roster with bots that move, shoot,
## damage each other, and respawn without a client.

const PORT := 9187
const PORT_16 := 9196
## Matches GameManager.BOT_PEER_BASE; the spawn ring is keyed by peer id.
const BOT_PEER_BASE := -1000

var _net: Node
var _gm: Node
var _world: Node3D


func after_test() -> void:
	if is_instance_valid(_gm):
		_gm.stop_all()
	if is_instance_valid(_net):
		_net.stop()
	if is_instance_valid(_world):
		_world.free()
	_world = null
	_gm = null
	_net = null


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


## Protocol v2 allows 16 actors, but the shipping maps expose only 8 spawn
## markers. Overflow actors reuse a marker; they must land on a ring around it
## instead of stacking at the exact same origin.
func test_sixteen_bots_on_eight_spawns_do_not_stack() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	col.shape = box
	floor_body.add_child(col)
	floor_body.position = Vector3(0, -0.55, 0)
	_world.add_child(floor_body)

	# Exactly eight markers, as the shipping maps expose, on a 20 m ring.
	var markers: Array[Vector3] = []
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var marker := Marker3D.new()
		marker.name = "Spawn%02d" % (i + 1)
		marker.position = Vector3(cos(angle) * 20.0, 0.2, sin(angle) * 20.0)
		_world.add_child(marker)
		markers.append(marker.position)

	_net = load("res://scripts/networking/network_manager.gd").new()
	_gm = load("res://scripts/game/game_manager.gd").new()
	add_child(_net)
	add_child(_gm)
	_gm.net = _net
	expect(_gm.server_start(_world, PORT_16, 16) == OK, "server starts with sixteen bots")
	expect(_gm.server_player_count() == 16,
		"sixteen bots join the roster (got %d)" % _gm.server_player_count())
	expect(_gm._used_slots.size() == 8,
		"only the eight markers are claimed (got %d)" % _gm._used_slots.size())
	expect(_gm._spawn_ring.size() == 16,
		"every actor has a spawn ring entry (got %d)" % _gm._spawn_ring.size())

	var positions: Array[Vector3] = []
	for peer_id in _gm._roster:
		positions.append((_gm._roster[peer_id]["node"] as Node3D).global_position)
	expect(positions.size() == 16, "collected sixteen actor positions")

	var stacked := 0
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) <= 0.1:
				stacked += 1
	expect(stacked == 0, "no two actors stack (%d overlapping pairs)" % stacked)

	var far_from_marker := 0
	for pos in positions:
		var nearest := INF
		for marker_pos in markers:
			nearest = minf(nearest, pos.distance_to(marker_pos))
		if nearest > 5.0:
			far_from_marker += 1
	expect(far_from_marker == 0,
		"every actor spawns within 5 m of a marker (%d far)" % far_from_marker)

	# The first eight keep their own marker (ring 0); only the overflow is
	# offset, so eight-player behaviour is unchanged.
	for i in 8:
		expect(int(_gm._spawn_ring[BOT_PEER_BASE - i]) == 0,
			"bot %d keeps ring 0" % i)
	for i in range(8, 16):
		expect(int(_gm._spawn_ring[BOT_PEER_BASE - i]) == 1,
			"bot %d reuses a marker on overflow ring 1" % i)
