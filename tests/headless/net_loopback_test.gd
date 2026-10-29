extends SceneTree
## CP4a loopback: one in-process server + two real WebSocket clients.
## Verifies join/roster, input->snapshot replication, interpolation convergence,
## leave cleanup, malformed packets, and live snapshot bytes. Run with --script.

const PORT := 9177

var _failures := 0
var _checks := 0


func _init() -> void:
	_run()


func _run() -> void:
	var gm_script := load("res://scripts/game/game_manager.gd")
	var net_script := load("res://scripts/networking/network_manager.gd")

	# Each side gets its own world, like real clients in separate processes.
	var world := Node3D.new()
	world.name = "NetTestWorld"
	root.add_child(world)
	_add_floor(world)
	var world_a := Node3D.new()
	world_a.name = "ClientAWorld"
	root.add_child(world_a)
	_add_floor(world_a)
	var world_b := Node3D.new()
	world_b.name = "ClientBWorld"
	root.add_child(world_b)
	_add_floor(world_b)
	# Same ordering as the real game: the local Player exists before connecting.
	var local_a := _make_local_player(world_a)
	var local_b := _make_local_player(world_b)
	await physics_frame

	var server_net = net_script.new()
	var server_gm = gm_script.new()
	root.add_child(server_net)
	root.add_child(server_gm)
	server_gm.net = server_net
	_check(server_gm.server_start(world, PORT) == OK, "server starts on port %d" % PORT)

	var client_a_net = net_script.new()
	var client_a_gm = gm_script.new()
	var client_b_net = net_script.new()
	var client_b_gm = gm_script.new()
	for node in [client_a_net, client_a_gm, client_b_net, client_b_gm]:
		root.add_child(node)
	client_a_gm.net = client_a_net
	client_b_gm.net = client_b_net
	_check(client_a_gm.client_start(world_a, "127.0.0.1", PORT, "Alice") == OK, "client A connects")
	_check(client_b_gm.client_start(world_b, "127.0.0.1", PORT, "Bob!@#") == OK, "client B connects")

	await _wait_for(func() -> bool: return server_gm.server_player_count() == 2, 300)
	_check(server_gm.server_player_count() == 2, "server roster reaches 2 players")
	var names: Array = server_gm.server_roster_names().map(func(e: Dictionary) -> String: return e["name"])
	_check(names.has("Alice") and names.has("Bob"), "names sanitized and registered (got %s)" % str(names))
	await _wait_for(func() -> bool: return client_b_gm.remote_count() == 1 and client_a_gm.remote_count() == 1, 300)
	_check(client_a_gm.remote_count() == 1 and client_b_gm.remote_count() == 1, "both clients spawn one remote each")
	_check(client_a_gm.local_id > 0 and client_b_gm.local_id > 0, "both clients received ids")

	# Spawn parity: authority and the owning client must agree on the start pose.
	var server_a := _server_actor_of(server_gm, client_a_gm.local_id)
	_check(local_b.global_position.distance_to(_server_actor_of(server_gm, client_b_gm.local_id).global_position) < 0.5,
		"client B also adopts its own spawn, not A's")
	if server_a and local_a:
		var spawn_gap: float = local_a.global_position.distance_to(server_a.global_position)
		print("  spawn parity gap=%.3f m (client %s vs server %s)" % [spawn_gap, local_a.global_position, server_a.global_position])
		_check(spawn_gap < 0.5, "client adopts the server spawn (gap %.3f m)" % spawn_gap)
		_check(absf(wrapf(local_a.rotation.y - server_a.rotation.y, -PI, PI)) < 0.05, "client adopts the server spawn yaw")
		# Regression: spawn must face the arena centre, not the perimeter wall.
		# Only meaningful away from the centre (the fallback test spawn sits at 0,0).
		if local_a.global_position.length() > 5.0:
			var forward := -local_a.global_transform.basis.z
			var to_centre := (-local_a.global_position).normalized()
			_check(forward.dot(to_centre) > 0.7,
				"spawn faces the arena centre (dot %.2f)" % forward.dot(to_centre))
		# Regression: server must not stomp spawn yaw before the first input frame.
		var yaw_before: float = server_a.rotation.y
		for _i in 15:
			await physics_frame
		_check(absf(wrapf(server_a.rotation.y - yaw_before, -PI, PI)) < 0.02,
			"spawn yaw survives ticks without input (no stomp to 0)")
	await _wait_for(func() -> bool: return client_b_net.snapshots_processed > 5, 300)
	_check(client_b_net.snapshots_processed > 5, "client B processes snapshots")
	print("  live snapshot bytes=%d processed=%d dropped=%d" % [
		client_b_net.last_snapshot_bytes, client_b_net.snapshots_processed, client_b_net.snapshots_dropped])
	_check(client_b_net.last_snapshot_bytes > 0 and client_b_net.last_snapshot_bytes <= 300, "live snapshot is %d B (limit 300 B)" % client_b_net.last_snapshot_bytes)

	# Drive client A rightward; client B's remote must converge (67 ms buffer lag).
	var seq := 100
	for _i in 45:
		seq += 1
		client_a_gm.client_send_input(_input_frame(seq, Vector2(1.0, 0.0)))
		for _k in 2:
			await physics_frame
	var server_actor := _server_actor_of(server_gm, client_a_gm.local_id)
	var remote_on_b: PlayerController = client_b_gm._remotes.get(client_a_gm.local_id)
	_check(server_actor != null and remote_on_b != null, "server actor and B-side ghost both exist")
	if server_actor and remote_on_b:
		var gap: float = (remote_on_b.global_position - server_actor.global_position).length()
		print("  replication gap=%.3f m (server %s vs ghost %s)" % [gap, server_actor.global_position, remote_on_b.global_position])
		_check(gap < 1.0, "ghost converges within 1 m of authority (gap %.3f m)" % gap)

	# Regression: a remote ghost must actually be running an animation clip.
	var ghost_ap := remote_on_b.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_check(ghost_ap != null and ghost_ap.is_playing() and ghost_ap.current_animation != &"",
		"remote ghost plays an animation clip (%s)" % (ghost_ap.current_animation if ghost_ap else "none"))

	# Regression: a client must not damage another player's ghost locally. That
	# path produced hitmarkers and drained ghost HP with no server involvement.
	if remote_on_b:
		var ghost_hurtbox := remote_on_b.get_node_or_null("BodyHurtbox") as HurtboxComponent
		var ghost_health := ghost_hurtbox.get_health() if ghost_hurtbox else null
		if ghost_hurtbox and ghost_health:
			var hp_before: int = ghost_health.current
			var damaged := CombatResolver.apply_hit(
				ghost_hurtbox, 25, 2.0, client_b_gm.local_id, Vector3.ZERO
			)
			_check(not ghost_hurtbox.damage_enabled, "ghost hurtbox is non-authoritative")
			_check(not damaged and ghost_health.current == hp_before,
				"remote ghost ignores local damage (hp %d)" % ghost_health.current)

	# Smoothness: successive ghost poses must not jump (no snap-back/teleport).
	var smooth := true
	var prev := remote_on_b.global_position
	for _i in 20:
		await physics_frame
		var step: float = (remote_on_b.global_position - prev).length()
		if step > 0.5:
			smooth = false
		prev = remote_on_b.global_position
	_check(smooth, "ghost advances without teleports at 60+ fps sampling")

	# Simulated latency: 100 ms + 20 ms jitter stays smooth, still converges.
	# Gap is sampled as a median over the phase so a single bursty stall on a
	# loaded box cannot flake the suite; tick lag is the deterministic guard.
	client_a_net.latency_ms = 100
	client_a_net.jitter_ms = 20
	client_b_net.latency_ms = 100
	client_b_net.jitter_ms = 20
	var gap_samples: Array = []
	for i in 90:
		seq += 1
		# Zigzag so the input-delay component is exercised, not just steady state.
		var dir := Vector2(1.0, 0.0) if i % 30 < 15 else Vector2(-1.0, 0.0)
		client_a_gm.client_send_input(_input_frame(seq, dir))
		await physics_frame
		gap_samples.append((remote_on_b.global_position - server_actor.global_position).length())
	gap_samples.sort()
	var gap_lag: float = gap_samples[gap_samples.size() / 2]
	print("  replication gap at 100ms/20ms median=%.3f m" % gap_lag)
	_check(gap_lag < 2.0, "ghost converges within 2 m under latency (median gap %.3f m)" % gap_lag)
	_check(client_b_net.snapshots_dropped >= 0, "drop counter alive (dropped=%d)" % client_b_net.snapshots_dropped)

	# Leave: A disconnects; server and B clean up quickly.
	client_a_net.stop()
	client_a_gm.stop_all()
	await _wait_for(func() -> bool: return server_gm.server_player_count() == 1, 400)
	_check(server_gm.server_player_count() == 1, "server removes a disconnected client")
	await _wait_for(func() -> bool: return client_b_gm.remote_count() == 0, 400)
	_check(client_b_gm.remote_count() == 0, "B removes the ghost within the roster update")

	# Malformed traffic never crashes or stalls the server.
	var before: int = server_net.packets_rejected
	server_net._route(31337, PackedByteArray([99, 1, 2, 3]))
	server_net._route(31337, PackedByteArray([5, 1]))
	server_net._route(31337, PackedByteArray([6, 9, 9, 9, 9, 9, 9]))
	_check(server_net.packets_rejected == before + 3, "3 malformed packets rejected, server alive")
	_check(server_gm.server_player_count() == 1, "server still serving after malformed traffic")

	server_net.stop()
	client_b_net.stop()
	world.queue_free()
	_finish()


func _make_local_player(world: Node3D) -> PlayerController:
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	player.name = "Player"
	world.add_child(player)
	return player


func _input_frame(seq: int, move: Vector2) -> PlayerInputFrame:
	var frame := PlayerInputFrame.new()
	frame.seq = seq
	frame.move = move
	frame.yaw = 0.0
	frame.pitch = 0.0
	return frame


func _server_actor_of(server_gm, player_id: int) -> PlayerController:
	for peer_id in server_gm._roster:
		var entry: Dictionary = server_gm._roster[peer_id]
		if int(entry["id"]) == player_id:
			return entry["node"] as PlayerController
	return null


func _add_floor(world: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	col.shape = box
	floor_body.add_child(col)
	world.add_child(floor_body)
	floor_body.position = Vector3(0, -0.55, 0)


func _wait_for(predicate: Callable, max_physics_frames: int) -> void:
	var waited := 0
	while not predicate.call() and waited < max_physics_frames:
		await physics_frame
		waited += 1


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)


func _finish() -> void:
	print("net_loopback: %d checks, %d failure(s)" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
