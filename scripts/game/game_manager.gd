extends Node
## CP4a session orchestrator (autoload). OFFLINE preserves the exact solo
## behavior. SERVER simulates roster actors from network inputs and broadcasts
## binary snapshots at 30 Hz. CLIENT forwards local inputs, poses remotes from
## snapshots, and keeps the local game fully playable.

enum NetMode { OFFLINE, SERVER, CLIENT }

signal server_hit(headshot: bool, killed: bool)
signal server_death(victim_id: int, killer_id: int)
signal server_respawn(player_id: int, position: Vector3, yaw: float)
signal server_shot(shooter_id: int, origin: Vector3, direction: Vector3)

# Preloaded so joining never hits the resource loader mid-match.
const PLAYER_SCENE: PackedScene = preload("res://scenes/characters/player.tscn")
const RIFLE_STATS: WeaponStats = preload("res://resources/weapons/rifle_stats.tres")
## CP4b input intake: one frame is consumed per server tick, so a jitter burst
## queues instead of overwriting. Oldest frames are dropped past the cap.
const MAX_INPUT_QUEUE := 16
const INPUT_RATE_LIMIT := 90
## If a client cannot feed 30 inputs/s, extrapolate at most this many server
## ticks, then freeze the actor until input arrives. The ack stays pinned to the
## last input actually received, so the client never replays against a state the
## server invented. (Advancing the ack on a repeat would have no client-side
## state to compare and would force a snap.)
const MAX_EXTRAPOLATION_TICKS := 2
const RESPAWN_DELAY_MSEC := 3000
const SPAWN_PROTECTION_MSEC := 1500
const BOT_PEER_BASE := -1000

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
var _combat: ServerCombat
var _client_error: String = ""
var _hits_total: int = 0
var _deaths_total: int = 0

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
	if not bus.event_received.is_connected(_on_server_event):
		bus.event_received.connect(_on_server_event)
	if not bus.disconnected_from_server.is_connected(_on_transport_down):
		bus.disconnected_from_server.connect(_on_transport_down)


func _on_transport_down() -> void:
	if net_mode == NetMode.CLIENT:
		var net := _net()
		var reason: String = net.last_error if net else ""
		stop_all()
		_client_error = reason if reason != "" else "connection lost"


func is_net_client() -> bool:
	return net_mode == NetMode.CLIENT


func client_error_text() -> String:
	return _client_error


func clear_client_error() -> void:
	_client_error = ""


func is_net_server() -> bool:
	return net_mode == NetMode.SERVER


func remote_jitter_ticks() -> int:
	var transport := _net()
	return int(transport.jitter_ticks()) if transport else 0


# --- server ---------------------------------------------------------------

func server_start(world: Node, port: int, bots: int = 0) -> int:
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
	var stats := load("res://resources/weapons/rifle_stats.tres") as WeaponStats
	_combat = ServerCombat.new(world, stats)
	_hits_total = 0
	_deaths_total = 0
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		if not bus.damage_dealt.is_connected(_on_server_damage):
			bus.damage_dealt.connect(_on_server_damage)
		if not bus.player_died.is_connected(_on_server_death):
			bus.player_died.connect(_on_server_death)
	for i in bots:
		_spawn_bot(i)
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
	_roster[peer_id] = _new_entry(assigned, player_name, node, peer_id)
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
	var node_ref: Variant = entry["node"]
	if is_instance_valid(node_ref):
		(node_ref as Node).queue_free()
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
	converted.fire = bool(frame.get("fire", false))
	converted.reload = bool(frame.get("reload", false))
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
	var now := Time.get_ticks_msec()
	var entries: Array = []
	for peer_id in _roster:
		var entry: Dictionary = _roster[peer_id]
		# Variant first: assigning a freed instance to a typed Node raises before
		# is_instance_valid can inspect it (teardown between ticks).
		var node_ref: Variant = entry["node"]
		if not is_instance_valid(node_ref):
			continue
		var actor := node_ref as PlayerController
		if actor == null:
			continue

		# Dead players stay in the roster/snapshot with hp 0 until respawn.
		if int(entry["dead_until"]) > 0:
			if now >= int(entry["dead_until"]):
				_respawn(entry)
			entries.append(_snapshot_entry(entry, actor, true))
			continue

		if int(entry["protected_until"]) > 0 and now >= int(entry["protected_until"]):
			entry["protected_until"] = 0
			_set_hurtboxes(actor, true)
		if _combat:
			_combat.tick(entry, delta)

		var frame: PlayerInputFrame = entry["last_frame"]
		var simulate := true
		if bool(entry["is_bot"]):
			frame = _bot_frame(entry, actor, delta)
			entry["last_frame"] = frame
			entry["ack"] = frame.seq
			entry["has_input"] = true
		else:
			var queue: Array = entry["queue"]
			if not queue.is_empty():
				frame = queue.pop_front()
				entry["last_frame"] = frame
				entry["ack"] = frame.seq
				entry["has_input"] = true
				entry["starved_ticks"] = 0
			elif bool(entry["has_input"]):
				entry["starved_ticks"] = int(entry["starved_ticks"]) + 1
				if int(entry["starved_ticks"]) > MAX_EXTRAPOLATION_TICKS:
					entry["frozen_ticks"] = int(entry["frozen_ticks"]) + 1
					simulate = false
			else:
				entry["starved_ticks"] = 0

		if simulate:
			var shot := _combat.process(entry, actor, frame, delta) if _combat else {}
			if not shot.is_empty():
				# Firing cancels spawn protection.
				entry["protected_until"] = 0
				_set_hurtboxes(actor, true)
				_broadcast_event(NetProtocol.encode_event_shot(
					int(shot["shooter_id"]), shot["origin"], shot["direction"]
				))
			var before := actor.global_position
			actor.server_step(frame, delta)
			if _check_displacement(entry, before, actor.global_position, delta):
				actor.global_position = before
				actor.velocity = Vector3(0.0, actor.velocity.y, 0.0)
		entries.append(_snapshot_entry(entry, actor))

	if net_stats and _server_tick % 30 == 0:
		for peer_id in _roster:
			var e: Dictionary = _roster[peer_id]
			print("BALL_OF_DUTY stat id=%d ack=%d last_seq=%d queue=%d dropped=%d starved=%d frozen=%d hp=%d ammo=%d" % [
				int(e["id"]), int(e["ack"]), int(e["last_seq"]),
				(e["queue"] as Array).size(), int(e["inputs_dropped"]),
				int(e["starved_ticks"]), int(e["frozen_ticks"]),
				_health(e["node"]).current if _health(e["node"]) else 0,
				int(e["ammo"]),
			])
	if net_stats and _combat and _server_tick % 150 == 0:
		print("BALL_OF_DUTY combat shots=%d projectiles=%d hits=%d deaths=%d blocked_cd=%d blocked_reload=%d blocked_ammo=%d" % [
			_combat.shots_fired, _combat.projectiles_fired, _hits_total, _deaths_total,
			_combat.blocked_cooldown, _combat.blocked_reload, _combat.blocked_ammo,
		])
	var net := _net()
	if net and not entries.is_empty():
		var snapshot := NetProtocol.encode_snapshot(_server_tick, entries)
		for peer_id in _roster:
			if int(peer_id) > 0:
				net.server_send(peer_id, snapshot)


func _new_entry(player_id: int, player_name: String, node: PlayerController, peer_id: int) -> Dictionary:
	var initial := PlayerInputFrame.new()
	initial.yaw = node.rotation.y
	var entry := {
		"id": player_id, "name": player_name, "node": node,
		"last_frame": initial, "queue": [], "last_seq": 0, "ack": 0,
		"has_input": false, "inputs_dropped": 0, "rate_window_msec": 0,
		"rate_count": 0, "displacements": 0, "starved_ticks": 0, "frozen_ticks": 0,
		"protected_until": Time.get_ticks_msec() + SPAWN_PROTECTION_MSEC,
		"dead_until": 0, "is_bot": peer_id < 0, "bot_seq": 0,
		"bot_strafe": 1.0, "bot_strafe_ticks": 0, "kills": 0, "deaths": 0,
	}
	if _combat:
		_combat.reset_player(entry)
	_set_hurtboxes(node, false)
	return entry


func _set_hurtboxes(node: Node, enabled: bool) -> void:
	for path: String in ["BodyHurtbox", "HeadHurtbox"]:
		var hurtbox := node.get_node_or_null(path) as HurtboxComponent
		if hurtbox:
			hurtbox.damage_enabled = enabled


func _health(node: Node) -> HealthComponent:
	return node.get_node_or_null("HealthComponent") as HealthComponent if node else null


func _snapshot_entry(entry: Dictionary, actor: PlayerController, dead: bool = false) -> Dictionary:
	var health := _health(actor)
	return {
		"id": int(entry["id"]),
		"pos": actor.global_position,
		"yaw": actor.rotation.y,
		"state": NetProtocol.AnimState.STILL if dead else int(actor.anim_state_byte()),
		"vel": Vector3.ZERO if dead else actor.velocity,
		"on_floor": actor.is_on_floor(),
		"hp": health.current if health else (0 if dead else 100),
		"ack": int(entry["ack"]),
	}


func _on_server_damage(target_id: int, source_id: int, damage: int, hitbox: StringName, position: Vector3) -> void:
	if net_mode != NetMode.SERVER:
		return
	var target := _entry_by_id(target_id)
	if target.is_empty():
		return
	var health := _health(target["node"])
	_hits_total += 1
	var killed := health != null and health.current <= 0
	_broadcast_event(NetProtocol.encode_event_hit(
		target_id, source_id, damage, String(hitbox) == "head", killed, position
	))


func _on_server_death(victim_id: int, killer_id: int, position: Vector3) -> void:
	if net_mode != NetMode.SERVER:
		return
	var victim := _entry_by_id(victim_id)
	if victim.is_empty() or int(victim["dead_until"]) > 0:
		return
	victim["dead_until"] = Time.get_ticks_msec() + RESPAWN_DELAY_MSEC
	victim["deaths"] = int(victim["deaths"]) + 1
	_deaths_total += 1
	var node: Node = victim["node"]
	if is_instance_valid(node):
		(node as PlayerController).velocity = Vector3.ZERO
		_set_hurtboxes(node, false)
	var killer := _entry_by_id(killer_id)
	if not killer.is_empty():
		killer["kills"] = int(killer["kills"]) + 1
	print("BALL_OF_DUTY death victim=%d killer=%d" % [victim_id, killer_id])
	_broadcast_event(NetProtocol.encode_event_death(victim_id, killer_id, position))


func _respawn(entry: Dictionary) -> void:
	var node_ref: Variant = entry["node"]
	if not is_instance_valid(node_ref):
		return
	var actor := node_ref as PlayerController
	var spawn := _choose_respawn(entry)
	actor.global_position = spawn["pos"]
	actor.rotation.y = spawn["yaw"]
	actor.velocity = Vector3.ZERO
	actor.reset_physics_interpolation()
	var health := _health(actor)
	if health:
		health.reset()
	if _combat:
		_combat.reset_player(entry)
	entry["dead_until"] = 0
	entry["protected_until"] = Time.get_ticks_msec() + SPAWN_PROTECTION_MSEC
	entry["starved_ticks"] = 0
	entry["has_input"] = false
	entry["ack"] = 0
	entry["last_seq"] = 0
	(entry["queue"] as Array).clear()
	var initial := PlayerInputFrame.new()
	initial.yaw = spawn["yaw"]
	entry["last_frame"] = initial
	_set_hurtboxes(actor, false)
	_broadcast_event(NetProtocol.encode_event_respawn(int(entry["id"]), spawn["pos"], spawn["yaw"]))


func _choose_respawn(entry: Dictionary) -> Dictionary:
	var best_pos: Vector3 = _spawns[0] + Vector3(0.0, 0.2, 0.0) if not _spawns.is_empty() else Vector3(0, 0.2, 0)
	var best_score := -1.0
	for spawn_point: Vector3 in _spawns:
		var pos := spawn_point + Vector3(0.0, 0.2, 0.0)
		var nearest := 999.0
		var clear := true
		for other_peer in _roster:
			var other: Dictionary = _roster[other_peer]
			if int(other["id"]) == int(entry["id"]) or int(other["dead_until"]) > 0:
				continue
			var other_ref: Variant = other["node"]
			if not is_instance_valid(other_ref):
				continue
			var other_node := other_ref as Node3D
			var dist: float = pos.distance_to(other_node.global_position)
			nearest = minf(nearest, dist)
			if dist < 25.0:
				var query := PhysicsRayQueryParameters3D.create(
					pos + Vector3(0.0, 0.6, 0.0),
					(other_node as Node3D).global_position + Vector3(0.0, 0.45, 0.0),
					1
				)
				if not actor_world(_world).direct_space_state.intersect_ray(query).is_empty():
					clear = false
		var score := nearest + (5.0 if clear else 0.0)
		if score > best_score:
			best_score = score
			best_pos = pos
	return {"pos": best_pos, "yaw": atan2(best_pos.x, best_pos.z)}


func actor_world(node: Node) -> World3D:
	return (node as Node3D).get_world_3d() if node is Node3D else null


func _spawn_bot(index: int) -> void:
	if _free_ids.is_empty() or _roster.size() >= NetProtocol.MAX_PLAYERS:
		return
	var id: int = _free_ids.pop_front()
	var peer_id := BOT_PEER_BASE - index
	var slot := _claim_slot(peer_id)
	var node := _spawn_server_actor(id, slot)
	_roster[peer_id] = _new_entry(id, "BOT %d" % (index + 1), node, peer_id)
	print("BALL_OF_DUTY bot id=%d name=BOT %d" % [id, index + 1])


func _bot_frame(entry: Dictionary, actor: PlayerController, _delta: float) -> PlayerInputFrame:
	entry["bot_seq"] = int(entry["bot_seq"]) + 1
	var frame := PlayerInputFrame.new()
	frame.seq = int(entry["bot_seq"])
	var target := _nearest_enemy(entry)
	if target.is_empty():
		frame.yaw = actor.rotation.y
		return frame
	var target_node: Node = target["node"]
	if not is_instance_valid(target_node):
		frame.yaw = actor.rotation.y
		return frame
	var target_actor := target_node as PlayerController
	var aim_point := target_actor.global_position + Vector3(0.0, 0.45, 0.0)
	var flat := aim_point - actor.global_position
	flat.y = 0.0
	var dist := flat.length()
	# Use the same third-person camera framing the client aims from, otherwise
	# the bots' close-range shots drift from the crosshair.
	var aim := ServerCombat.aim_angles(actor.global_position, aim_point)
	frame.yaw = aim.x
	frame.pitch = aim.y
	frame.fire = dist < 20.0 and _has_los(actor, target_actor)
	if dist > 7.0:
		frame.move = Vector2(0.0, -1.0)
		frame.sprint = dist > 14.0
	else:
		frame.aim = true
		frame.move = Vector2(float(entry["bot_strafe"]), 0.0)
		entry["bot_strafe_ticks"] = int(entry["bot_strafe_ticks"]) + 1
		if int(entry["bot_strafe_ticks"]) % 45 == 0:
			entry["bot_strafe"] = -float(entry["bot_strafe"])
	# Feelers: sidestep instead of walking into a trunk or cliff.
	var forward := -actor.global_transform.basis.z
	var feeler := PhysicsRayQueryParameters3D.create(
		actor.global_position + Vector3(0.0, 0.45, 0.0),
		actor.global_position + Vector3(0.0, 0.45, 0.0) + forward * 1.3,
		1
	)
	if not actor.get_world_3d().direct_space_state.intersect_ray(feeler).is_empty():
		frame.move = Vector2(float(entry["bot_strafe"]), 0.0)
		frame.aim = true
	return frame


func _nearest_enemy(entry: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for other_peer in _roster:
		var other: Dictionary = _roster[other_peer]
		if int(other["id"]) == int(entry["id"]) or int(other["dead_until"]) > 0:
			continue
		var node_ref: Variant = other["node"]
		if not is_instance_valid(node_ref):
			continue
		var node := node_ref as Node3D
		var dist: float = node.global_position.distance_to((entry["node"] as Node3D).global_position)
		if dist < best_dist:
			best_dist = dist
			best = other
	return best


func _has_los(from_actor: PlayerController, to_actor: PlayerController) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		from_actor.global_position + Vector3(0.0, 0.6, 0.0),
		to_actor.global_position + Vector3(0.0, 0.45, 0.0),
		1
	)
	return from_actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _entry_by_id(player_id: int) -> Dictionary:
	for peer_id in _roster:
		var entry: Dictionary = _roster[peer_id]
		if int(entry["id"]) == player_id:
			return entry
	return {}


func _broadcast_event(pkt: PackedByteArray) -> void:
	var net := _net()
	if net == null:
		return
	for peer_id in _roster:
		if int(peer_id) > 0:
			net.server_send(peer_id, pkt)


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
				"starved": int(entry["starved_ticks"]),
				"frozen": int(entry["frozen_ticks"]),
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
		if int(peer_id) > 0:
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
	_client_error = ""
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
		local.dead = false
		var weapon := local.get_node_or_null("WeaponController") as WeaponController
		if weapon:
			# Damage is server-authoritative from CP4c; local fire is cosmetic.
			weapon.spawn_projectiles = false
	return OK


func client_send_input(frame: PlayerInputFrame) -> void:
	if net_mode != NetMode.CLIENT or local_id <= 0:
		return
	var net := _net()
	if net == null:
		return
	net.client_send(NetProtocol.encode_input(
		frame.seq, frame.move, frame.jump, frame.sprint, frame.aim,
		frame.yaw, frame.pitch, frame.fire, frame.reload
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
	_client_error = ""
	local_id = player_id
	var local_player := _world.get_node_or_null("Player") as PlayerController if _world else null
	if local_player:
		local_player.dead = false
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
			local.set_view_yaw(float(spawn["yaw"]))
		local.enable_prediction()
	# A snapshot can arrive before JOIN_OK; drop any ghost we made of ourselves.
	if _remotes.has(local_id):
		var self_ghost: Node = _remotes[local_id]
		if is_instance_valid(self_ghost):
			self_ghost.queue_free()
		_remotes.erase(local_id)


func _on_join_denied(_reason: int) -> void:
	_client_error = "server is full"
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


func _on_server_event(event: Dictionary) -> void:
	if net_mode != NetMode.CLIENT:
		return
	match int(event.get("type", 0)):
		NetProtocol.EventType.SHOT:
			var shooter := int(event["shooter_id"])
			server_shot.emit(shooter, event["origin"], event["direction"])
			if shooter != local_id:
				BulletField.spawn(
					_world, event["origin"], event["direction"],
					RIFLE_STATS.projectile_speed, false
				)
		NetProtocol.EventType.HIT:
			if int(event["shooter_id"]) == local_id:
				server_hit.emit(bool(event["headshot"]), bool(event["killed"]))
				var audio := get_node_or_null("/root/AudioManager")
				if audio:
					audio.play_hit()
		NetProtocol.EventType.DEATH:
			server_death.emit(int(event["victim_id"]), int(event["killer_id"]))
			if int(event["victim_id"]) == local_id:
				var local := _world.get_node_or_null("Player") as PlayerController if _world else null
				if local:
					local.set_dead(true)
		NetProtocol.EventType.RESPAWN:
			var pid := int(event["player_id"])
			server_respawn.emit(pid, event["position"], float(event["yaw"]))
			if pid == local_id:
				var local := _world.get_node_or_null("Player") as PlayerController if _world else null
				if local:
					local.respawn_at(event["position"], float(event["yaw"]))
			elif _remotes.has(pid):
				var remote := _remotes[pid] as PlayerController
				if is_instance_valid(remote):
					remote.global_position = event["position"]
					remote.rotation.y = float(event["yaw"])
					remote.net_dead = false
					remote.visible = true
					var interp := remote.get_node_or_null("NetworkInterpolator") as NetworkInterpolator
					if interp:
						interp.reset()
					remote.reset_remote_smoothing()


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
		var remote_node: Node = _remotes[rid]
		if not is_instance_valid(remote_node):
			continue
		var remote := remote_node as PlayerController
		var interp := remote.get_node_or_null("NetworkInterpolator") as NetworkInterpolator
		if interp:
			var pos: Vector3 = entry["pos"]
			interp.push_sample(
				_tick, pos, float(entry["yaw"]), int(entry["state"]),
				entry.get("vel", Vector3.ZERO)
			)


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
	var local := _world.get_node_or_null("Player") as PlayerController if _world else null
	if local:
		local.dead = false
		var weapon := local.get_node_or_null("WeaponController") as WeaponController
		if weapon:
			weapon.spawn_projectiles = true
	var net := _net()
	if net:
		net.stop()
	for rid in _remotes.keys():
		var node: Node = _remotes[rid]
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
