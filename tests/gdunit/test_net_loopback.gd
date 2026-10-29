extends BodTestSuite
## CP4a loopback: one in-process server + two real WebSocket clients.
## Verifies join/roster, spawn parity, input->snapshot replication, interpolation
## convergence, monotonic smoothness, leave cleanup, and malformed packets.
##
## This stays a single integration test: the value is the real socket path and
## the shared tick, and re-establishing three peers per assertion would triple
## the runtime without testing anything new.

const PORT := 9177

var _server_net: Node
var _client_a_net: Node
var _client_b_net: Node
var _worlds: Array[Node] = []


func after_test() -> void:
	for net in [_server_net, _client_a_net, _client_b_net]:
		if is_instance_valid(net):
			net.stop()
	for world in _worlds:
		if is_instance_valid(world):
			world.queue_free()
	_worlds.clear()


func test_replication_pipeline() -> void:
	var gm_script := load("res://scripts/game/game_manager.gd")
	var net_script := load("res://scripts/networking/network_manager.gd")

	# Each side gets its own world, like real clients in separate processes.
	var world := _add_world("NetTestWorld")
	var world_a := _add_world("ClientAWorld")
	var world_b := _add_world("ClientBWorld")
	# Same ordering as the real game: the local Player exists before connecting.
	var local_a := _make_local_player(world_a)
	var local_b := _make_local_player(world_b)
	await get_tree().physics_frame

	_server_net = net_script.new()
	var server_gm = gm_script.new()
	add_child(_server_net)
	add_child(server_gm)
	server_gm.net = _server_net
	expect(server_gm.server_start(world, PORT) == OK, "server starts on port %d" % PORT)

	_client_a_net = net_script.new()
	var client_a_gm = gm_script.new()
	_client_b_net = net_script.new()
	var client_b_gm = gm_script.new()
	for node in [_client_a_net, client_a_gm, _client_b_net, client_b_gm]:
		add_child(node)
	client_a_gm.net = _client_a_net
	client_b_gm.net = _client_b_net
	expect(client_a_gm.client_start(world_a, "127.0.0.1", PORT, "Alice") == OK, "client A connects")
	expect(client_b_gm.client_start(world_b, "127.0.0.1", PORT, "Bob!@#") == OK, "client B connects")

	await wait_for(func() -> bool: return server_gm.server_player_count() == 2, 300)
	expect(server_gm.server_player_count() == 2, "server roster reaches 2 players")
	var names: Array = server_gm.server_roster_names().map(func(e: Dictionary) -> String: return e["name"])
	expect(names.has("Alice") and names.has("Bob"), "names sanitized and registered (got %s)" % str(names))
	await wait_for(func() -> bool: return client_b_gm.remote_count() == 1 and client_a_gm.remote_count() == 1, 300)
	expect(
		client_a_gm.remote_count() == 1 and client_b_gm.remote_count() == 1,
		"both clients spawn one remote each"
	)
	expect(client_a_gm.local_id > 0 and client_b_gm.local_id > 0, "both clients received ids")

	# Spawn parity: authority and the owning client must agree on the start pose.
	var server_a := _server_actor_of(server_gm, client_a_gm.local_id)
	expect(
		local_b.global_position.distance_to(_server_actor_of(server_gm, client_b_gm.local_id).global_position) < 0.5,
		"client B also adopts its own spawn, not A's"
	)
	if server_a and local_a:
		var spawn_gap: float = local_a.global_position.distance_to(server_a.global_position)
		print("  spawn parity gap=%.3f m (client %s vs server %s)" % [spawn_gap, local_a.global_position, server_a.global_position])
		expect(spawn_gap < 0.5, "client adopts the server spawn (gap %.3f m)" % spawn_gap)
		expect(absf(wrapf(local_a.rotation.y - server_a.rotation.y, -PI, PI)) < 0.05, "client adopts the server spawn yaw")
		# Regression: spawn must face the arena centre, not the perimeter wall.
		if local_a.global_position.length() > 5.0:
			var forward := -local_a.global_transform.basis.z
			var to_centre := (-local_a.global_position).normalized()
			expect(
				forward.dot(to_centre) > 0.7,
				"spawn faces the arena centre (dot %.2f)" % forward.dot(to_centre)
			)
		# Regression: server must not stomp spawn yaw before the first input frame.
		var yaw_before: float = server_a.rotation.y
		for _i in 15:
			await get_tree().physics_frame
		expect(
			absf(wrapf(server_a.rotation.y - yaw_before, -PI, PI)) < 0.02,
			"spawn yaw survives ticks without input (no stomp to 0)"
		)

	await wait_for(func() -> bool: return _client_b_net.snapshots_processed > 5, 300)
	expect(_client_b_net.snapshots_processed > 5, "client B processes snapshots")
	print("  live snapshot bytes=%d processed=%d dropped=%d" % [
		_client_b_net.last_snapshot_bytes, _client_b_net.snapshots_processed, _client_b_net.snapshots_dropped])
	expect(
		_client_b_net.last_snapshot_bytes > 0 and _client_b_net.last_snapshot_bytes <= 300,
		"live snapshot is %d B (limit 300 B)" % _client_b_net.last_snapshot_bytes
	)

	# Drive the same local tick the real game uses: predict + send, one input per
	# physics tick. Idle phases must keep sending, because a client that stops
	# sending predicts nothing while the server repeats the last frame.
	local_a.set_process(false)
	# seq continues from whatever the controller already sampled (normally 0,
	# because the helper disables its physics callback before any tick).
	var seq := local_a.last_seq
	var drive_errors: Array = []

	# Drive client A rightward; client B's remote must converge (67 ms buffer lag).
	for _i in 45:
		seq += 1
		await _tick_client_a(local_a, client_a_gm, _input_frame(seq, Vector2(1.0, 0.0)))
		var drive_stats: Dictionary = local_a.prediction_stats()
		# Skip the spawn baseline (first ack) so p95 measures steady-state replay.
		var drive_err := float(drive_stats["ack_error_m"])
		if int(drive_stats["ack"]) > 5 and drive_err >= 0.0:
			drive_errors.append(drive_err)
	var server_actor := _server_actor_of(server_gm, client_a_gm.local_id)
	var remote_on_b: PlayerController = client_b_gm._remotes.get(client_a_gm.local_id)
	expect(server_actor != null and remote_on_b != null, "server actor and B-side ghost both exist")
	if server_actor and remote_on_b:
		var gap: float = (remote_on_b.global_position - server_actor.global_position).length()
		print("  replication gap=%.3f m (server %s vs ghost %s)" % [gap, server_actor.global_position, remote_on_b.global_position])
		expect(gap < 1.0, "ghost converges within 1 m of authority (gap %.3f m)" % gap)

	# Regression: a remote ghost must actually be running an animation clip.
	var ghost_ap := remote_on_b.find_child("AnimationPlayer", true, false) as AnimationPlayer
	expect(
		ghost_ap != null and ghost_ap.is_playing() and ghost_ap.current_animation != &"",
		"remote ghost plays an animation clip (%s)" % (ghost_ap.current_animation if ghost_ap else "none")
	)

	# Regression: a client must not damage another player's ghost locally.
	var ghost_hurtbox := remote_on_b.get_node_or_null("BodyHurtbox") as HurtboxComponent
	var ghost_health := ghost_hurtbox.get_health() if ghost_hurtbox else null
	if ghost_hurtbox and ghost_health:
		var hp_before: int = ghost_health.current
		var damaged := CombatResolver.apply_hit(ghost_hurtbox, 25, 2.0, client_b_gm.local_id, Vector3.ZERO)
		expect(not ghost_hurtbox.damage_enabled, "ghost hurtbox is non-authoritative")
		expect(
			not damaged and ghost_health.current == hp_before,
			"remote ghost ignores local damage (hp %d)" % ghost_health.current
		)

	# CP4b: the owning client must reconcile, not just simulate locally.
	var pred: Dictionary = local_a.prediction_stats()
	print("  prediction ack=%d pending=%d replay=%d ack_err=%.3f m corr=%d" % [
		int(pred["ack"]), int(pred["pending"]), int(pred["replay_depth"]),
		float(pred["ack_error_m"]), int(pred["corrections"])])
	expect(bool(pred["enabled"]), "client prediction is enabled after join")
	expect(int(pred["ack"]) > 0, "server acked client input")
	expect(
		float(pred["ack_error_m"]) >= 0.0 and float(pred["ack_error_m"]) < 0.05,
		"predicted state at ack matches authority (%.3f m)" % float(pred["ack_error_m"])
	)
	expect(int(pred["replay_depth"]) <= 8, "replay depth stays bounded (%d frames)" % int(pred["replay_depth"]))
	drive_errors.sort()
	var drive_p95: float = drive_errors[int(float(drive_errors.size() - 1) * 0.95)] if not drive_errors.is_empty() else -1.0
	print("  loopback ack error p95=%.4f m over %d samples" % [drive_p95, drive_errors.size()])
	expect(drive_p95 >= 0.0 and drive_p95 < 0.02, "loopback ack error p95 < 2 cm (%.4f m)" % drive_p95)
	var server_stats: Dictionary = server_gm.server_player_stats(client_a_gm.local_id)
	expect(int(server_stats.get("displacements", 0)) == 0, "no impossible displacement under normal input")

	# Forced divergence: reconciliation must pull the client back to authority.
	var corrections_before := int(pred["corrections"])
	local_a.global_position += Vector3(2.0, 0.0, 0.0)
	for _i in 12:
		seq += 1
		await _tick_client_a(local_a, client_a_gm, _input_frame(seq, Vector2.ZERO))
	var after: Dictionary = local_a.prediction_stats()
	expect(int(after["corrections"]) > corrections_before, "reconciliation counts a correction")
	var recovered_gap: float = local_a.global_position.distance_to(server_actor.global_position)
	print("  divergence recovery gap=%.3f m (corrections %d)" % [recovered_gap, int(after["corrections"])])
	expect(recovered_gap < 0.5, "client snaps back to authority (gap %.3f m)" % recovered_gap)

	# Smoothness: successive ghost poses must not jump (idle input still sent).
	var smooth := true
	var prev := remote_on_b.global_position
	for _i in 20:
		seq += 1
		await _tick_client_a(local_a, client_a_gm, _input_frame(seq, Vector2.ZERO))
		var step: float = (remote_on_b.global_position - prev).length()
		if step > 0.5:
			smooth = false
		prev = remote_on_b.global_position
	expect(smooth, "ghost advances without teleports at 60+ fps sampling")

	# Simulated latency: 100 ms + 20 ms jitter stays smooth, still converges.
	_client_a_net.latency_ms = 100
	_client_a_net.jitter_ms = 20
	_client_b_net.latency_ms = 100
	_client_b_net.jitter_ms = 20
	var gap_samples: Array = []
	var ack_errors: Array = []
	for i in 90:
		seq += 1
		var dir := Vector2(1.0, 0.0) if i % 30 < 15 else Vector2(-1.0, 0.0)
		await _tick_client_a(local_a, client_a_gm, _input_frame(seq, dir))
		gap_samples.append((remote_on_b.global_position - server_actor.global_position).length())
		var ack_err := float(local_a.prediction_stats()["ack_error_m"])
		if ack_err >= 0.0:
			ack_errors.append(ack_err)
	gap_samples.sort()
	ack_errors.sort()
	var gap_lag: float = gap_samples[gap_samples.size() / 2]
	var ack_err_median: float = ack_errors[ack_errors.size() / 2] if not ack_errors.is_empty() else -1.0
	var ack_err_p95: float = ack_errors[int(float(ack_errors.size() - 1) * 0.95)] if not ack_errors.is_empty() else -1.0
	print("  replication gap at 100ms/20ms median=%.3f m · ack error median=%.3f p95=%.3f m" % [gap_lag, ack_err_median, ack_err_p95])
	expect(gap_lag < 2.0, "ghost converges within 2 m under latency (median gap %.3f m)" % gap_lag)
	expect(ack_err_median >= 0.0 and ack_err_median < 0.05, "ack error under latency (median %.3f m)" % ack_err_median)
	expect(ack_err_p95 >= 0.0 and ack_err_p95 < 0.05, "ack error under latency p95 < 5 cm (%.3f m)" % ack_err_p95)
	expect(_client_b_net.snapshots_dropped >= 0, "drop counter alive (dropped=%d)" % _client_b_net.snapshots_dropped)

	# Leave: A disconnects; server and B clean up quickly.
	_client_a_net.stop()
	client_a_gm.stop_all()
	await wait_for(func() -> bool: return server_gm.server_player_count() == 1, 400)
	expect(server_gm.server_player_count() == 1, "server removes a disconnected client")
	await wait_for(func() -> bool: return client_b_gm.remote_count() == 0, 400)
	expect(client_b_gm.remote_count() == 0, "B removes the ghost within the roster update")

	# Malformed traffic never crashes or stalls the server.
	var before: int = _server_net.packets_rejected
	_server_net._route(31337, PackedByteArray([99, 1, 2, 3]))
	_server_net._route(31337, PackedByteArray([5, 1]))
	_server_net._route(31337, PackedByteArray([6, 9, 9, 9, 9, 9, 9]))
	expect(_server_net.packets_rejected == before + 3, "3 malformed packets rejected, server alive")
	expect(server_gm.server_player_count() == 1, "server still serving after malformed traffic")

	# CP4b input intake: ordered consumption, duplicate rejection, rate limiting.
	var peer_b := 0
	for peer_id in server_gm._roster:
		if int(server_gm._roster[peer_id]["id"]) == client_b_gm.local_id:
			peer_b = int(peer_id)
	var b_stats: Dictionary = server_gm.server_player_stats(client_b_gm.local_id)
	var base_seq := int(b_stats["last_seq"])
	var ordered := NetProtocol.encode_input(base_seq + 1, Vector2.ZERO, false, false, false, 0.0, 0.0)
	_server_net._route(peer_b, ordered)
	await get_tree().physics_frame
	b_stats = server_gm.server_player_stats(client_b_gm.local_id)
	expect(int(b_stats["ack"]) == base_seq + 1, "queued input is consumed in order (ack %d)" % int(b_stats["ack"]))
	var dropped_before := int(b_stats["dropped"])
	_server_net._route(peer_b, ordered)
	await get_tree().physics_frame
	b_stats = server_gm.server_player_stats(client_b_gm.local_id)
	expect(int(b_stats["dropped"]) == dropped_before + 1, "duplicate input seq is rejected")

	# Starved client: one input every 5 ticks. The server may extrapolate two
	# ticks, then must freeze instead of running ahead indefinitely.
	var starve_seq := int(b_stats["last_seq"])
	for _i in 8:
		starve_seq += 1
		_server_net._route(peer_b, NetProtocol.encode_input(
			starve_seq, Vector2.ZERO, false, false, false, 0.0, 0.0))
		for _k in 5:
			await get_tree().physics_frame
	b_stats = server_gm.server_player_stats(client_b_gm.local_id)
	print("  starvation: starved=%d frozen=%d ack=%d last_seq=%d" % [
		int(b_stats["starved"]), int(b_stats["frozen"]),
		int(b_stats["ack"]), int(b_stats["last_seq"])])
	expect(int(b_stats["frozen"]) > 0, "starved client freezes after bounded extrapolation")
	expect(int(b_stats["displacements"]) == 0, "starvation does not reject legitimate steps")

	var flood_before := int(b_stats["dropped"])
	for i in 120:
		_server_net._route(peer_b, NetProtocol.encode_input(
			base_seq + 2 + i, Vector2.ZERO, false, false, false, 0.0, 0.0))
	await get_tree().physics_frame
	b_stats = server_gm.server_player_stats(client_b_gm.local_id)
	expect(int(b_stats["dropped"]) > flood_before + 20, "input flood is rate-limited (%d dropped)" % int(b_stats["dropped"]))
	expect(server_gm.server_player_count() == 1, "server still serving after an input flood")

	_server_net.stop()
	_client_b_net.stop()
	await get_tree().process_frame


## One client tick: predict, send, advance one physics frame. Mirrors
## PlayerController._physics_process minus the real Input sampling.
func _tick_client_a(local: PlayerController, gm, frame: PlayerInputFrame) -> void:
	local.simulate_tick(frame, 1.0 / 30.0)
	gm.client_send_input(frame)
	await get_tree().physics_frame


func _add_world(world_name: String) -> Node3D:
	var world := Node3D.new()
	world.name = world_name
	add_child(world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	col.shape = box
	floor_body.add_child(col)
	world.add_child(floor_body)
	floor_body.position = Vector3(0, -0.55, 0)
	_worlds.append(world)
	return world


func _make_local_player(world: Node3D) -> PlayerController:
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	player.name = "Player"
	world.add_child(player)
	# The suite drives explicit frames; the controller's own callback would
	# record unsent predictions with a competing sequence.
	player.set_physics_process(false)
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
