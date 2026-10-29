extends Node
## CP4a session orchestrator (autoload). OFFLINE preserves the exact solo
## behavior. SERVER simulates roster actors from network inputs and broadcasts
## binary snapshots at 30 Hz. CLIENT forwards local inputs, poses remotes from
## snapshots, and keeps the local game fully playable.

enum NetMode { OFFLINE, SERVER, CLIENT }

# Preloaded so joining never hits the resource loader mid-match.
const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player.tscn")
## CP4b input intake: one frame is consumed per server tick, so a jitter burst
## queues instead of overwriting. Oldest frames are dropped past the cap.
const MAX_INPUT_QUEUE := 16
const INPUT_RATE_LIMIT := 90

var net_mode: NetMode = NetMode.OFFLINE
## Dev-server console stats (1 line/s/player); enabled with --net-stats.
var net_stats := OS.get_cmdline_user_args().has("--net-stats")

# Server state: peer_id -> {id, name, node, frame: PlayerInputFrame, ack: int}
var _roster: Dictionary = {}
var _free_ids: Array = []
var _next_id: int = 1
var _server_tick: int = 0
var _world: Node
var _spawns: Array = [] # Array[Vector3]
var _used_slots: Dictionary = {} # slot -> peer_id

# Client state.
var local_id: int = 0
var local_name: String = "Player"
## Test hook: explicit transport. Production leaves this null so the
## /root/NetworkManager autoload is used; the loopback test injects its own.
var net: Node = null:
	set(value):
		net = value
		if is_node_ready():
			_connect_bus(value)
var _remotes: Dictionary = {} # id -> PlayerController
var _join_sent: bool = false
var _wanted_name: String = "Player"


func _net() -> Node:
	if net != null:
		return net
	return get_node_or_null("/root/NetworkManager")


func _ready() -> void:
	_connect_bus(_net())


func _connect_bus(bus: Node) -> void:
	if bus == null:
		return
	if not bus.peer_joined.is_connected(_on_peer_joined):
		bus.peer_joined.connect(_on_peer_joined)
	if not bus.peer_left.is_connected(_on_peer_left):
		bus.peer_left.connect(_on_peer_left)
	if not bus.remote_input.is_connected(_on_remote_input):
		bus.remote_input.connect(_on_remote_input)
	if not bus.join_accepted.is_connected(_on_join_accepted):
		bus.join_accepted.connect(_on_join_accepted)
	if not bus.join_denied.is_connected(_on_join_denied):
		bus.join_denied.connect(_on_join_denied)
	if not bus.roster_updated.is_connected(_on_roster_updated):
		bus.roster_updated.connect(_on_roster_updated)
	if not bus.snapshot_received.is_connected(_on_snapshot_received):
		bus.snapshot_received.connect(_on_snapshot_received)
	if not bus.disconnected_from_server.is_connected(_on_transport_down):
		bus.disconnected_from_server.connect(_on_transport_down)


func _on_transport_down() -> void:
	if net_mode == NetMode.CLIENT:
		stop_all()


func is_net_client() -> bool:
	return net_mode == NetMode.CLIENT


func is_net_server() -> bool:
	return net_mode == NetMode.SERVER


func remote_jitter_ticks() -> int:
	var transport := _net()
	return int(transport.jitter_ticks()) if transport else 0


# --- server ---------------------------------------------------------------

func server_start(world: Node, port: int) -> int:
	_reset()
	var net := _net()
	if net == null:
		return ERR_UNAVAILABLE
	var err: int = net.start_server(port)
	if err != OK:
		return err
	net_mode = NetMode.SERVER
	_world = world
	_spawns = collect_spawn_points(world)
	_free_ids = range(1, NetProtocol.MAX_PLAYERS + 1)
	_next_id = 1
	return OK


func server_player_count() -> int:
	return _roster.size()


func server_roster_names() -> Array:
	var out: Array = []
	for peer_id in _roster:
		out.append({"id": _roster[peer_id]["id"], "name": _roster[peer_id]["name"]})
	return out


func _on_peer_joined(peer_id: int, player_name: String) -> void:
	if net_mode != NetMode.SERVER:
		return
	var net := _net()
	if _roster.has(peer_id):
		return
	if _roster.size() >= NetProtocol.MAX_PLAYERS:
		net.server_send(peer_id, NetProtocol.encode_deny(NetProtocol.DenyReason.FULL))
		# Give the deny packet a tick to flush; closing immediately can drop it.
		get_tree().create_timer(0.3).timeout.connect(
			func() -> void:
				if net_mode == NetMode.SERVER:
					net.server_disconnect(peer_id)
		)
		return
	var assigned: int = _free_ids.pop_front() if not _free_ids.is_empty() else _next_id
	_next_id = maxi(_next_id, assigned + 1)
	var slot := _claim_slot(peer_id)
	var node := _spawn_server_actor(assigned, slot)
	# The client must start where authority put it, or every other player sees it
	# 20+ m away from where its owner does.
	var spawn_pos := node.global_position
	var spawn_yaw := node.rotation.y
	var initial := PlayerInputFrame.new()
	initial.yaw = spawn_yaw
	_roster[peer_id] = {
		"id": assigned, "name": player_name, "node": node,
		"last_frame": initial, "queue": [], "last_seq": 0, "ack": 0,
		"has_input": false, "inputs_dropped": 0, "rate_window_msec": 0,
		"rate_count": 0, "displacements": 0,
		}
	print("BALL_OF_DUTY net join id=%d name=%s peers=%d spawn=%s" % [assigned, player_name, _roster.size(), str(spawn_pos.snapped(Vector3.ONE * 0.01))])
	net.server_send(peer_id, NetProtocol.encode_join_ok(assigned, _server_tick, spawn_pos, spawn_yaw))
	_broadcast_roster()


func _on_peer_left(peer_id: int) -> void:
	if net_mode != NetMode.SERVER:
		return
	if not _roster.has(peer_id):
		return
	var entry: Dictionary = _roster[peer_id]
	print("BALL_OF_DUTY net leave id=%d name=%s peers=%d" % [int(entry["id"]), String(entry["name"]), _roster.size() - 1])
	var node := entry["node"] as Node
	if is_instance_valid(node):
		node.queue_free()
	_roster.erase(peer_id)
	_free_ids.append(int(entry["id"]))
	_free_ids.sort()
	_release_slot(peer_id)
	_broadcast_roster()


func _on_remote_input(peer_id: int, frame: Dictionary) -> void:
	if net_mode != NetMode.SERVER or not _roster.has(peer_id):
		return
	var stored: Dictionary = _roster[peer_id]

	# Token window: a client cannot buy simulation time by flooding frames.
	var now := Time.get_ticks_msec()
	if now - int(stored["rate_window_msec"]) >= 1000:
		stored["rate_window_msec"] = now
		stored["rate_count"] = 0
	stored["rate_count"] = int(stored["rate_count"]) + 1
	if int(stored["rate_count"]) > INPUT_RATE_LIMIT:
		stored["inputs_dropped"] = int(stored["inputs_dropped"]) + 1
		return

	var seq := int(frame["seq"])
	# WebSocket delivery is ordered, but a duplicate or replayed seq must still
	# never be simulated twice.
	if seq <= int(stored["last_seq"]):
		stored["inputs_dropped"] = int(stored["inputs_dropped"]) + 1
		return

	var converted := PlayerInputFrame.new()
	converted.seq = seq
	converted.move = frame["move"]
	converted.jump = bool(frame["jump"])
	converted.sprint = bool(frame["sprint"])
	converted.aim = bool(frame["scoped"])
	converted.yaw = float(frame["yaw"])
	converted.pitch = float(frame["pitch"])
	stored["last_seq"] = seq

	var queue: Array = stored["queue"]
	queue.append(converted)
	if queue.size() > MAX_INPUT_QUEUE:
		queue.pop_front()
		stored["inputs_dropped"] = int(stored["inputs_dropped"]) + 1


func _physics_process(delta: float) -> void:
	if net_mode != NetMode.SERVER:
		_poll_client_connection()
		return
	_server_tick += 1
	var entries: Array = []
	for peer_id in _roster:
		var entry: Dictionary = _roster[peer_id]
		var actor := entry["node"] as PlayerController
		if not is_instance_valid(actor):
			continue
		# Consume exactly one input per tick. If the queue is empty, repeat the
		# last frame but keep the ack pinned, so the client knows what was applied.
		var frame: PlayerInputFrame = entry["last_frame"]
		var queue: Array = entry["queue"]
		if not queue.is_empty():
			frame = queue.pop_front()
			entry["last_frame"] = frame
			entry["ack"] = frame.seq
			entry["has_input"] = true
		var before := actor.global_position
		actor.server_step(frame, delta, bool(entry.get("has_input", false)))
		if _check_displacement(entry, before, actor.global_position, delta):
			# Reject the step: impossible travel is rolled back, horizontal
			# velocity zeroed, and the tick continues from the last good pose.
			actor.global_position = before
			actor.velocity = Vector3(0.0, actor.velocity.y, 0.0)
		entries.append({
			"id": int(entry["id"]),
			"pos": actor.global_position,
			"yaw": actor.rotation.y,
			"state": actor.anim_state_byte(),
			"vel": actor.velocity,
			"on_floor": actor.is_on_floor(),
			"hp": 100,
			"ack": int(entry["ack"]),
		})
	if net_stats and _server_tick % 30 == 0:
		for peer_id in _roster:
			var e: Dictionary = _roster[peer_id]
			print("BALL_OF_DUTY stat id=%d ack=%d last_seq=%d queue=%d dropped=%d" % [
				int(e["id"]), int(e["ack"]), int(e["last_seq"]),
				(e["queue"] as Array).size(), int(e["inputs_dropped"]),
			])
	var net := _net()
	if net and not entries.is_empty():
		var snapshot := NetProtocol.encode_snapshot(_server_tick, entries)
		for peer_id in _roster:
			net.server_send(peer_id, snapshot)


## CP4b displacement guard: every step is authoritative simulation from clamped
## input, so a legitimate step can never exceed sprint speed. A violated step is
## rejected (rolled back by the caller); CP4d can escalate repeated attempts.
func _check_displacement(entry: Dictionary, before: Vector3, after: Vector3, delta: float) -> bool:
	var moved := Vector2(after.x - before.x, after.z - before.z).length()
	var max_step := 8.6 * delta
	if moved <= max_step:
		return false
	entry["displacements"] = int(entry["displacements"]) + 1
	if int(entry["displacements"]) % 30 == 1:
		print("BALL_OF_DUTY displacement id=%d moved=%.3f max=%.3f rejected" % [
			int(entry["id"]), moved, max_step,
		])
	return true


func server_player_stats(player_id: int) -> Dictionary:
	for peer_id in _roster:
		var entry: Dictionary = _roster[peer_id]
		if int(entry["id"]) == player_id:
			return {
				"ack": int(entry["ack"]),
				"queued": (entry["queue"] as Array).size(),
				"last_seq": int(entry["last_seq"]),
				"dropped": int(entry["inputs_dropped"]),
				"displacements": int(entry["displacements"]),
			}
	return {}


func _spawn_server_actor(assigned_id: int, slot: int) -> PlayerController:
	var actor := PLAYER_SCENE.instantiate() as PlayerController
	actor.name = "ServerPlayer_%d" % assigned_id
	_world.add_child(actor)
	actor.make_server(assigned_id)
	var pos := Vector3(0.0, 0.2, 0.0)
	var yaw := 0.0
	if slot >= 0 and slot < _spawns.size():
		pos = _spawns[slot] + Vector3(0.0, 0.2, 0.0)
		# Forward is -Z, so to look at the arena centre the yaw is atan2(x, z).
		# The negated form points players at the perimeter wall instead.
		yaw = atan2(pos.x, pos.z)
	actor.global_position = pos
	actor.rotation.y = yaw
	return actor


func _claim_slot(peer_id: int) -> int:
	for i in _spawns.size():
		if not _used_slots.has(i):
			_used_slots[i] = peer_id
			return i
	return -1


func _release_slot(peer_id: int) -> void:
	for slot in _used_slots:
		if int(_used_slots[slot]) == peer_id:
			_used_slots.erase(slot)
			return


func _broadcast_roster() -> void:
	var net := _net()
	if net == null:
		return
	var roster := NetProtocol.encode_roster(server_roster_names())
	for peer_id in _roster:
		net.server_send(peer_id, roster)


static func collect_spawn_points(world: Node) -> Array:
	var markers := world.find_children("Spawn*", "Marker3D", true, false)
	markers.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	var points: Array = []
	for marker in markers:
		points.append((marker as Marker3D).global_position)
	if points.is_empty():
		for i in NetProtocol.MAX_PLAYERS:
			points.append(Vector3(float(i) * 2.0, 0.2, 0.0))
	return points


# --- client ---------------------------------------------------------------

func client_start(world: Node, host: String, port: int, display_name: String) -> int:
	_reset()
	var net := _net()
	if net == null:
		return ERR_UNAVAILABLE
	var err: int = net.start_client(host, port)
	if err != OK:
		return err
	net_mode = NetMode.CLIENT
	_world = world
	_wanted_name = NetProtocol.sanitize_name(display_name)
	_join_sent = false
	var local := _world.get_node_or_null("Player") as PlayerController
	if local:
		local.net_id = 0
	return OK


func client_send_input(frame: PlayerInputFrame) -> void:
	if net_mode != NetMode.CLIENT or local_id <= 0:
		return
	var net := _net()
	if net == null:
		return
	net.client_send(NetProtocol.encode_input(
		frame.seq, frame.move, frame.jump, frame.sprint, frame.aim,
		frame.yaw, frame.pitch
	))


func remote_count() -> int:
	return _remotes.size()


func _poll_client_connection() -> void:
	if net_mode != NetMode.CLIENT or _join_sent:
		return
	var net := _net()
	if net == null:
		return
	var peer_status: int = net.connection_status()
	if peer_status == MultiplayerPeer.CONNECTION_CONNECTED:
		_join_sent = true
		net.send_join_request(_wanted_name)


func _on_join_accepted(player_id: int, spawn: Dictionary) -> void:
	if net_mode != NetMode.CLIENT:
		return
	local_id = player_id
	var local := _world.get_node_or_null("Player") as PlayerController if _world else null
	if local:
		local.net_id = local_id
		# Adopt the authoritative spawn pose so this client and every other
		# client agree on where this player is standing from tick one.
		if spawn.has("pos"):
			local.global_position = spawn["pos"]
			local.rotation.y = float(spawn["yaw"])
			local.velocity = Vector3.ZERO
			local.reset_physics_interpolation()
		local.enable_prediction()
	# A snapshot can arrive before JOIN_OK; drop any ghost we made of ourselves.
	if _remotes.has(local_id):
		var self_ghost := _remotes[local_id] as Node
		if is_instance_valid(self_ghost):
			self_ghost.queue_free()
		_remotes.erase(local_id)


func _on_join_denied(_reason: int) -> void:
	stop_all()


func _on_roster_updated(entries: Array) -> void:
	if net_mode != NetMode.CLIENT:
		return
	var seen: Dictionary = {}
	for entry in entries:
		var rid := int(entry["id"])
		if rid == local_id:
			continue
		seen[rid] = true
		if not _remotes.has(rid):
			_spawn_remote(rid, String(entry["name"]))
	if local_id > 0:
		seen[local_id] = true
	for rid in _remotes.keys():
		if not seen.has(rid):
			var node := _remotes[rid] as Node
			if is_instance_valid(node):
				node.queue_free()
			_remotes.erase(rid)


func _on_snapshot_received(_tick: int, entries: Array) -> void:
	if net_mode != NetMode.CLIENT:
		return
	var local := _world.get_node_or_null("Player") as PlayerController if _world else null
	for entry in entries:
		var rid := int(entry["id"])
		if rid == local_id:
			# The owning client reconciles instead of rendering a ghost of itself.
			if local:
				local.accept_server_state(entry)
			continue
		if not _remotes.has(rid):
			_spawn_remote(rid, "Player%d" % rid)
		var remote := _remotes[rid] as PlayerController
		if not is_instance_valid(remote):
			continue
		var interp := remote.get_node_or_null("NetworkInterpolator") as NetworkInterpolator
		if interp:
			var pos: Vector3 = entry["pos"]
			interp.push_sample(_tick, pos, float(entry["yaw"]), int(entry["state"]))


func _spawn_remote(rid: int, display_name: String) -> void:
	if _world == null or rid == local_id:
		return
	var remote := PLAYER_SCENE.instantiate() as PlayerController
	remote.name = "Remote_%d" % rid
	_world.add_child(remote)
	remote.make_remote(rid)
	remote.visible = false
	_remotes[rid] = remote


func stop_all() -> void:
	if _world:
		var local := _world.get_node_or_null("Player") as PlayerController
		if local:
			local.disable_prediction()
	var net := _net()
	if net:
		net.stop()
	for rid in _remotes.keys():
		var node := _remotes[rid] as Node
		if is_instance_valid(node):
			node.queue_free()
	_remotes.clear()
	_reset()


func _reset() -> void:
	net_mode = NetMode.OFFLINE
	local_id = 0
	_roster.clear()
	_remotes.clear()
	_free_ids.clear()
	_next_id = 1
	_server_tick = 0
	_world = null
	_spawns.clear()
	_used_slots.clear()
	_join_sent = false
