extends BodTestSuite
## Server-owned arena: JOIN_REQ carries the requested map, JOIN_OK echoes the
## authoritative one, and the server's spawns/respawns come from the loaded
## scene. The first human join picks an unpinned server's arena; later joins
## cannot move it.

const GM_SCRIPT := preload("res://scripts/game/game_manager.gd")
const MAP_DUNES := "dunes"
const MAP_CRATER := "crater"
const PORT := 9198
const SPAWN_RADIUS := 18.0


## Minimal transport: no socket, records packets, exposes every signal that
## GameManager connects to.
class FakeNet extends Node:
	signal peer_joined(peer_id, player_name, class_id, map_index)
	signal peer_left(peer_id)
	signal remote_input(peer_id, frame)
	signal join_accepted(player_id, spawn)
	signal join_denied(reason)
	signal roster_updated(entries)
	signal snapshot_received(tick, entries)
	signal event_received(event)
	signal score_received(entries)
	signal match_received(state)
	signal disconnected_from_server
	signal ping_updated(rtt_ms)
	signal connection_failed
	signal reconnect_started(attempt, delay_msec)
	signal reconnected

	var sent: Array = []
	var last_error: String = ""

	func start_server(_port: int) -> int:
		return OK

	func start_client(_host: String, _port: int) -> int:
		return OK

	func server_send(_peer_id: int, pkt: PackedByteArray) -> void:
		sent.append(pkt)

	func server_disconnect(_peer_id: int) -> void:
		pass

	func client_send(pkt: PackedByteArray) -> void:
		sent.append(pkt)

	func stop() -> void:
		pass

	func connection_status() -> int:
		return MultiplayerPeer.CONNECTION_DISCONNECTED

	func jitter_ticks() -> int:
		return 0


var _nodes: Array = []
var _worlds: Array = []


func after_test() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			if node.has_method("stop_all"):
				node.stop_all()
			node.queue_free()
	_nodes.clear()
	for world in _worlds:
		if is_instance_valid(world):
			world.free()
	_worlds.clear()


func test_join_request_and_ok_carry_the_map_id() -> void:
	var dunes := MapRegistry.index_of(MAP_DUNES)
	var req_pkt := NetProtocol.encode_join_request(
		"Maple", 2, NetProtocol.PROTOCOL_VERSION, dunes
	)
	var req := NetProtocol.decode_join_request(req_pkt)
	expect(req_pkt.size() == 5 + 5, "JOIN_REQ is 5 B + name (got %d)" % req_pkt.size())
	expect(int(req.get("map_index", -1)) == dunes,
		"JOIN_REQ roundtrips map index %d (got %d)" % [dunes, int(req.get("map_index", -1))])
	expect(int(req.get("class_id", -1)) == 2, "JOIN_REQ still carries the class")

	var ok_pkt := NetProtocol.encode_join_ok(
		3, 4242, Vector3(22.0, 0.3, -15.5), -1.2, 2,
		NetProtocol.PROTOCOL_VERSION, dunes
	)
	var ok := NetProtocol.decode_join_ok(ok_pkt)
	expect(ok_pkt.size() == 17, "JOIN_OK is 17 B (got %d)" % ok_pkt.size())
	expect(int(ok.get("map_index", -1)) == dunes,
		"JOIN_OK echoes map index %d (got %d)" % [dunes, int(ok.get("map_index", -1))])
	expect(int(ok.get("id", -1)) == 3 and int(ok.get("tick", -1)) == 4242,
		"JOIN_OK keeps the previous id/tick layout")
	var spawn: Vector3 = ok.get("spawn", Vector3.ZERO)
	expect(spawn.distance_to(Vector3(22.0, 0.3, -15.5)) < 0.01,
		"JOIN_OK keeps the spawn pose")


func test_out_of_range_map_id_falls_back_to_default() -> void:
	var default_index := MapRegistry.index_of(MapRegistry.DEFAULT_MAP)
	# Raw decoder path: a peer could put any byte on the wire.
	var raw := PackedByteArray([NetProtocol.Msg.JOIN_REQ, 3, 1, 0, 200, 65])
	var decoded := NetProtocol.decode_join_request(raw)
	expect(not decoded.is_empty(), "out-of-range map id still decodes")
	expect(int(decoded.get("map_index", -1)) == default_index,
		"out-of-range JOIN_REQ map id sanitizes to default (got %d)" % int(decoded.get("map_index", -1)))

	var ok_pkt := NetProtocol.encode_join_ok(
		1, 1, Vector3.ZERO, 0.0, 0, NetProtocol.PROTOCOL_VERSION, 0
	)
	ok_pkt[16] = 250
	var ok := NetProtocol.decode_join_ok(ok_pkt)
	expect(not ok.is_empty(), "out-of-range JOIN_OK still decodes")
	expect(int(ok.get("map_index", -1)) == default_index,
		"out-of-range JOIN_OK map id sanitizes to default (got %d)" % int(ok.get("map_index", -1)))
	expect(NetProtocol.decode_join_request(PackedByteArray([1, 3, 1, 0])) == {},
		"4 B JOIN_REQ (pre-v3 layout) is rejected")


func test_server_spawns_match_the_loaded_arena() -> void:
	var arena := (load(MapRegistry.scene_path(MAP_DUNES)) as PackedScene).instantiate()
	add_child(arena)
	_worlds.append(arena)
	var gm := _new_gm()
	expect(gm.server_start(
		arena, PORT, 0, MapRegistry.index_of(MAP_DUNES), true
	) == OK, "server starts on the loaded arena")

	var markers := arena.find_children("Spawn*", "Marker3D", true, false)
	markers.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	expect(not markers.is_empty(), "arena scene exposes spawn markers")
	expect(gm._spawns.size() == markers.size(),
		"spawn list has one entry per scene marker (%d vs %d)" % [gm._spawns.size(), markers.size()])
	for i in mini(gm._spawns.size(), markers.size()):
		var marker := markers[i] as Marker3D
		var spawn_point: Vector3 = gm._spawns[i]
		expect(spawn_point.distance_to(marker.global_position) < 0.001,
			"spawn %d comes from %s (got %s)" % [i, marker.global_position, spawn_point])


func test_first_join_picks_the_arena_and_bots_follow() -> void:
	var world := _make_world(8)
	var gm := _new_gm()
	var fake: FakeNet = gm.net
	var switched: Array = []
	gm.server_map_changed.connect(func(map_index: int) -> void:
		switched.append(map_index)
		# Stand in for main.gd's arena swap.
		for marker in world.find_children("Spawn*", "Marker3D", true, false):
			world.remove_child(marker)
			marker.free()
		_add_markers(world, 4, Vector3(100.0, 0.0, 100.0), 10.0))

	var boot_map := MapRegistry.index_of(MapRegistry.DEFAULT_MAP)
	expect(gm.server_start(world, PORT, 2, boot_map, false) == OK, "unpinned server starts")
	expect(gm.server_player_count() == 0, "bots wait for the first human join")
	expect(int(gm._pending_bots) == 2, "two bots are deferred")

	var dunes := MapRegistry.index_of(MAP_DUNES)
	gm._on_peer_joined(7, "Maple", 0, dunes)
	expect(switched == [dunes], "first join switches the arena once (got %s)" % str(switched))
	expect(int(gm._server_map_index) == dunes, "server adopts the first join's map")
	expect(int(gm._pending_bots) == 0, "deferred bots are released")
	expect(gm.server_player_count() == 3, "two bots and the first human are in the roster")
	expect(gm._spawns.size() == 4, "spawn list follows the swapped arena")

	var human_id := 0
	for peer_id in gm._roster:
		var entry: Dictionary = gm._roster[peer_id]
		var node := entry["node"] as Node3D
		var nearest := 999.0
		for spawn_point: Vector3 in gm._spawns:
			nearest = minf(nearest, node.global_position.distance_to(spawn_point))
		expect(nearest < 5.0,
			"actor %d spawns on the new arena (nearest marker %.2f m)" % [int(entry["id"]), nearest])
		if int(peer_id) > 0:
			human_id = int(entry["id"])
	expect(human_id > 0, "first human received an id")

	# A later join asks for another arena; the live session ignores it and the
	# JOIN_OK echoes the running arena.
	var crater := MapRegistry.index_of(MAP_CRATER)
	gm._on_peer_joined(8, "Rock", 0, crater)
	expect(int(gm._server_map_index) == dunes, "later join does not move the arena")
	expect(switched.size() == 1, "later join does not swap the scene")
	var join_ok := _last_packet(fake, NetProtocol.Msg.JOIN_OK)
	expect(not join_ok.is_empty(), "second join received JOIN_OK")
	if not join_ok.is_empty():
		expect(int(NetProtocol.decode_join_ok(join_ok).get("map_index", -1)) == dunes,
			"later JOIN_OK echoes the live map")


func test_client_adopts_the_join_ok_arena() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_nodes.append(main)
	var gm := _new_gm()
	gm.join_map_received.connect(main._on_authoritative_map)

	var requested := MapRegistry.index_of(MAP_CRATER)
	var authoritative := MapRegistry.index_of(MAP_DUNES)
	expect(gm.client_start(
		main, "127.0.0.1", PORT, "Maple", 0, requested
	) == OK, "client starts with its menu pick")
	expect(int(gm._wanted_map_index) == requested, "JOIN_REQ requests the menu map")
	expect(gm.client_map_id() == "", "no arena is adopted before JOIN_OK")

	gm._on_join_accepted(5, {
		"pos": Vector3(4.0, 0.2, -6.0), "yaw": 0.5, "class_id": 0,
		"tick": 1, "map_index": authoritative,
	})
	expect(int(gm.local_id) == 5, "JOIN_OK assigns the player id")
	expect(gm.client_map_id() == MAP_DUNES,
		"client adopts the server arena, not its request (got '%s')" % gm.client_map_id())
	expect(main._selected_map == MAP_DUNES,
		"main swaps to the server arena (got '%s')" % main._selected_map)
	var arena := main.get_node_or_null("Arena")
	expect(arena != null and String(arena.scene_file_path).ends_with("arena_dunes.tscn"),
		"loaded Arena scene is dunes")


func _new_gm() -> Node:
	var fake := FakeNet.new()
	add_child(fake)
	var gm := GM_SCRIPT.new()
	add_child(gm)
	gm.net = fake
	_nodes.append(fake)
	_nodes.append(gm)
	return gm


func _make_world(marker_count: int) -> Node3D:
	var world := Node3D.new()
	add_child(world)
	_worlds.append(world)
	_add_markers(world, marker_count, Vector3.ZERO, SPAWN_RADIUS)
	return world


func _add_markers(world: Node3D, count: int, origin: Vector3, radius: float) -> void:
	for i in count:
		var marker := Marker3D.new()
		marker.name = "Spawn%02d" % (i + 1)
		var angle := TAU * float(i) / float(count)
		marker.position = origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		world.add_child(marker)


func _last_packet(fake: FakeNet, msg_type: int) -> PackedByteArray:
	for i in range(fake.sent.size() - 1, -1, -1):
		var pkt: PackedByteArray = fake.sent[i]
		if NetProtocol.msg_type(pkt) == msg_type:
			return pkt
	return PackedByteArray()
