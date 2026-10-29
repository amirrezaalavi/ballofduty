extends SceneTree
## Phase 1 C headless soak. Runs one authoritative server plus N real WebSocket
## clients in this process (ephemeral port, never the live 9180), with M server
## bots. Measures tick rate, physics frame time, process CPU, RSS, node count,
## snapshot bytes, ack/starve/frozen counters and combat/projectile telemetry.
##
##   tools/godot --headless --path . --script tests/headless/soak_runner.gd \
##     -- --seconds 120 --clients 4 --bots 4 --port 9255
##
## The server roster is capped by NetProtocol.MAX_PLAYERS (frozen, manager
## owned). When clients + bots exceeds the cap the runner reports SOAK_CAP and
## runs the largest feasible mixed match. Pass --require-full to make that a
## failure once the cap is raised.
##
## Every line of the machine-readable report starts with "SOAK ".

const DT := 1.0 / 30.0
const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const ARENA := preload("res://scenes/maps/arena_nature.tscn")

var _server_net: Node
var _server_gm: Node
var _bus: Node
var _sessions: Array = []
var _worlds: Array = []

var _seconds := 120.0
var _requested_clients := 8
var _requested_bots := 4
var _port := 9255
var _require_full := false
var _effective_clients := 0
var _damage_signals := 0


func _init() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_seconds = float(_arg(args, "--seconds", "120"))
	_requested_clients = int(_arg(args, "--clients", "8"))
	_requested_bots = int(_arg(args, "--bots", "4"))
	_port = int(_arg(args, "--port", "9255"))
	_require_full = args.has("--require-full")

	seed(20261029)
	await _boot(args)
	if _server_gm == null:
		print("SOAK result=FAIL reason=boot")
		quit(1)
		return

	var joins := await _join_clients()
	if joins < _effective_clients:
		print("SOAK warn joined=%d expected=%d" % [joins, _effective_clients])

	var metrics := await _measure()
	_report(metrics, joins)

	if _server_gm:
		_server_gm.stop_all()
	for session: Dictionary in _sessions:
		(session["gm"] as Node).stop_all()
	await process_frame
	await process_frame
	quit(0 if bool(metrics["pass"]) else 1)


func _boot(args: PackedStringArray) -> void:
	# --script mode has no autoloads; the authoritative death/hit path needs the
	# same EventBus the real game uses.
	_bus = load("res://scripts/autoload/event_bus.gd").new()
	_bus.name = "EventBus"
	root.add_child(_bus)
	_bus.damage_dealt.connect(
		func(_target: int, _source: int, _amount: int, _pos: Vector3) -> void:
			_damage_signals += 1
	)

	var server_world := ARENA.instantiate() as Node3D
	server_world.name = "SoakAuthorityWorld"
	root.add_child(server_world)
	_worlds.append(server_world)
	await physics_frame

	_server_net = load("res://scripts/networking/network_manager.gd").new()
	_server_gm = load("res://scripts/game/game_manager.gd").new()
	root.add_child(_server_net)
	root.add_child(_server_gm)
	_server_gm.net = _server_net

	var err: int = _server_gm.server_start(server_world, _port, _requested_bots)
	if err != OK:
		print("SOAK result=FAIL reason=server_start err=%d port=%d" % [err, _port])
		return

	var cap := NetProtocol.MAX_PLAYERS
	_effective_clients = clampi(_requested_clients, 0, maxi(0, cap - _requested_bots))
	var requested := _requested_clients + _requested_bots
	print("SOAK config requested_clients=%d requested_bots=%d max_players=%d effective_clients=%d port=%d" % [
		_requested_clients, _requested_bots, cap, _effective_clients, _port,
	])
	if _requested_clients + _requested_bots > cap:
		print("SOAK_CAP roster=%d requested=%d cap=%d — raise NetProtocol.MAX_PLAYERS to %d (snapshot then %dB, still under 300B)" % [
			cap, requested, cap, requested, 6 + requested * 22,
		])
		if _require_full:
			print("SOAK result=FAIL reason=roster_cap")

	# Give the server a frame to register bots before clients join.
	for _i in 3:
		await physics_frame


func _join_clients() -> int:
	for i in _effective_clients:
		_sessions.append(_make_client(i))
	var joined := 0
	for _i in 900:
		joined = 0
		for session: Dictionary in _sessions:
			if int((session["gm"] as Node).local_id) > 0:
				joined += 1
		if joined >= _effective_clients:
			break
		await physics_frame
	return joined


func _make_client(index: int) -> Dictionary:
	var world := Node3D.new()
	world.name = "SoakClientWorld_%d" % index
	root.add_child(world)
	_worlds.append(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.55, 0.0)
	world.add_child(floor_body)

	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.name = "Player"
	world.add_child(player)
	# Drive explicit frames, exactly like a browser client, so the soak does not
	# depend on Input actions being configured in headless mode.
	player.set_physics_process(false)

	var net: Node = load("res://scripts/networking/network_manager.gd").new()
	var gm: Node = load("res://scripts/game/game_manager.gd").new()
	root.add_child(net)
	root.add_child(gm)
	gm.net = net
	var err: int = gm.client_start(world, "127.0.0.1", _port, "Soak%02d" % index)
	if err != OK:
		print("SOAK warn client=%d start_err=%d" % [index, err])
	return {
		"net": net, "gm": gm, "world": world, "player": player,
		"seq": 0, "tick": index * 7, "phase": float(index) * 0.9,
		"shots_seen": 0, "snap_start": 0, "drops_start": 0,
	}


func _measure() -> Dictionary:
	var start_msec := Time.get_ticks_msec()
	var duration_msec := int(_seconds * 1000.0)
	var warmup_msec := mini(10000, int(_seconds * 1000.0 * 0.15))
	var last_sample_msec := start_msec
	var last_tick := int(_server_gm._server_tick)
	var last_cpu := _cpu_ticks()

	var tick_rates: Array[float] = []
	var engine_frame_times: Array[float] = []
	var snapshot_sizes: Array[int] = []
	var node_samples: Array[int] = []
	var rss_samples: Array[int] = []
	var cpu_samples: Array[float] = []
	var peak_nodes := 0
	var peak_rss := 0
	var baseline_set := false
	var node_base := 0
	var rss_base := 0
	var ticks_below_28 := 0
	var max_snapshots_dropped := 0
	var progress_at := start_msec

	for session: Dictionary in _sessions:
		session["snap_start"] = int((session["net"] as Node).snapshots_processed)
		session["drops_start"] = int((session["net"] as Node).snapshots_dropped)

	while true:
		var now := Time.get_ticks_msec()
		if now - start_msec >= duration_msec:
			break
		_drive_clients(now - start_msec)
		await physics_frame

		# Engine physics CPU (smoothed monitor; reported separately from the
		# authoritative tick period because it includes the in-process clients).
		engine_frame_times.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)))
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		peak_nodes = maxi(peak_nodes, nodes)

		var now_after := Time.get_ticks_msec()
		if now_after - last_sample_msec < 1000:
			continue
		var elapsed := float(now_after - last_sample_msec) / 1000.0
		var ticks := int(_server_gm._server_tick) - last_tick
		var tick_rate := float(ticks) / maxf(elapsed, 0.001)
		tick_rates.append(tick_rate)
		if tick_rate < 28.0:
			ticks_below_28 += 1
		last_tick = int(_server_gm._server_tick)
		last_sample_msec = now_after

		var snap := 0
		var snaps := 0
		for session: Dictionary in _sessions:
			var value := int((session["net"] as Node).last_snapshot_bytes)
			if value > 0:
				snapshot_sizes.append(value)
				snap = maxi(snap, value)
			snaps += int((session["net"] as Node).snapshots_processed)
			max_snapshots_dropped = maxi(
				max_snapshots_dropped,
				int((session["net"] as Node).snapshots_dropped) - int(session["drops_start"])
			)

		var cpu_now := _cpu_ticks()
		var cpu_pct := 100.0 * float(cpu_now - last_cpu) / 100.0 / maxf(elapsed, 0.001)
		last_cpu = cpu_now
		cpu_samples.append(cpu_pct)

		node_samples.append(nodes)
		var rss := _rss_kb()
		rss_samples.append(rss)
		peak_rss = maxi(peak_rss, rss)

		if not baseline_set and now_after - start_msec >= warmup_msec:
			baseline_set = true
			node_base = nodes
			rss_base = rss

		if now_after - progress_at >= 10000:
			progress_at = now_after
			print("SOAK progress t=%.0fs tick=%.1f rectick=%d fps=%d snap=%dB rss=%dKB nodes=%d" % [
				float(now_after - start_msec) / 1000.0, tick_rate, int(_server_gm._server_tick),
				Engine.get_frames_per_second(), snap, rss, nodes,
			])

	if not baseline_set:
		node_base = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		rss_base = _rss_kb()

	# End-of-run counters.
	var stats := Callable(_server_gm, "server_player_stats")
	var frozen_total := 0
	var starved_total := 0
	var ack_lag_max := 0
	var alive := 0
	var snapshots_processed := 0
	for session: Dictionary in _sessions:
		var gm: Node = session["gm"]
		var net: Node = session["net"]
		snapshots_processed += int(net.snapshots_processed) - int(session["snap_start"])
		if int(gm.local_id) > 0 and bool(gm.is_net_client()):
			alive += 1
		var player_stats: Dictionary = stats.call(int(gm.local_id)) if int(gm.local_id) > 0 else {}
		if not player_stats.is_empty():
			frozen_total += int(player_stats.get("frozen", 0))
			starved_total += int(player_stats.get("starved", 0))
			ack_lag_max = maxi(ack_lag_max, int(session["seq"]) - int(player_stats.get("ack", 0)))

	var combat: ServerCombat = _server_gm._combat
	var spawned := combat.projectiles_fired
	var resolved := combat.projectile_hits + combat.projectile_world_impacts + combat.projectile_expired
	var active := combat.projectiles_active()

	tick_rates.sort()
	engine_frame_times.sort()
	snapshot_sizes.sort()
	var tick_avg := _mean(tick_rates)
	var tick_min := tick_rates[0] if not tick_rates.is_empty() else 0.0
	var periods: Array[float] = []
	for rate in tick_rates:
		if rate > 0.0:
			periods.append(1000.0 / rate)
	periods.sort()
	var period_avg := 1000.0 / maxf(tick_avg, 0.001)
	var period_p95 := _percentile(periods, 0.95)
	var engine_cpu_avg_ms := _mean(engine_frame_times) * 1000.0
	var engine_cpu_p95_ms := _percentile(engine_frame_times, 0.95) * 1000.0
	var snap_avg := _mean_int(snapshot_sizes)
	var snap_max := snapshot_sizes[-1] if not snapshot_sizes.is_empty() else 0
	var node_end := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var rss_end := _rss_kb()
	var rss_growth := 100.0 * float(rss_end - rss_base) / float(maxi(rss_base, 1))
	var node_growth := node_end - node_base
	var duration := float(Time.get_ticks_msec() - start_msec) / 1000.0

	var reasons: Array[String] = []
	if _requested_clients + _requested_bots > NetProtocol.MAX_PLAYERS:
		if _require_full:
			reasons.append("roster_cap")
	if tick_min < 28.0:
		reasons.append("tick_collapse")
	if period_p95 > 45.0:
		reasons.append("physics_period")
	if _mean(cpu_samples) > 90.0:
		reasons.append("cpu")
	if alive < _effective_clients:
		reasons.append("client_lost")
	if rss_growth > 10.0 and rss_end - rss_base > 32 * 1024:
		reasons.append("rss_growth")
	if node_growth > 200:
		reasons.append("node_growth")
	if spawned != resolved + active:
		reasons.append("projectile_accounting")
	if combat.shots_fired != spawned:
		reasons.append("shot_accounting")

	return {
		"pass": reasons.is_empty(),
		"reasons": reasons,
		"tick_avg": tick_avg, "tick_min": tick_min, "ticks_below_28": ticks_below_28,
		"period_avg": period_avg, "period_p95": period_p95,
		"engine_cpu_avg_ms": engine_cpu_avg_ms, "engine_cpu_p95_ms": engine_cpu_p95_ms,
		"cpu_avg": _mean(cpu_samples),
		"rss_base": rss_base, "rss_end": rss_end, "rss_growth": rss_growth,
		"rss_peak": peak_rss,
		"nodes_base": node_base, "nodes_end": node_end, "nodes_peak": peak_nodes,
		"snap_avg": snap_avg, "snap_max": snap_max,
		"alive": alive, "frozen": frozen_total, "starved": starved_total,
		"ack_lag_max": ack_lag_max, "snapshots_processed": snapshots_processed,
		"snapshots_dropped": max_snapshots_dropped,
		"shots": combat.shots_fired, "spawned": spawned, "resolved": resolved,
		"active": active, "hits": combat.projectile_hits,
		"world_impacts": combat.projectile_world_impacts,
		"expired": combat.projectile_expired, "damage_hits": combat.damage_hits,
		"damage_signals": _damage_signals,
		"deaths": int(_server_gm._deaths_total), "damage_events": int(_server_gm._hits_total),
		"telemetry": combat.telemetry_line(),
		"duration": duration, "clients": _effective_clients,
	}


func _drive_clients(elapsed_msec: int) -> void:
	for session: Dictionary in _sessions:
		var gm: Node = session["gm"]
		if int(gm.local_id) <= 0 or not bool(gm.is_net_client()):
			continue
		var player: PlayerController = session["player"]
		var seq := int(session["seq"]) + 1
		session["seq"] = seq
		var tick := int(session["tick"]) + 1
		session["tick"] = tick
		var phase := float(session["phase"])

		var frame := PlayerInputFrame.new()
		frame.seq = seq
		var target := _nearest_remote(gm, player)
		var moving := tick % 240 < 180
		if moving:
			var t := float(tick) / 30.0
			frame.move = Vector2(sin(t * 0.55 + phase), -cos(t * 0.55 + phase))
			frame.sprint = tick % 240 < 45
		if target != null:
			var aim := ServerCombat.aim_angles(
				player.global_position, target.global_position + Vector3(0.0, 0.45, 0.0)
			)
			frame.yaw = aim.x
			frame.pitch = aim.y
			var dist := player.global_position.distance_to(target.global_position)
			frame.aim = dist < 14.0
			frame.fire = dist < 26.0 and (tick % 90) < 42
		else:
			frame.yaw = player.rotation.y
			frame.fire = false
		player.simulate_tick(frame, DT)
		gm.client_send_input(frame)


func _nearest_remote(gm: Node, player: PlayerController) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for remote_id in gm._remotes:
		var node_ref: Variant = gm._remotes[remote_id]
		if not is_instance_valid(node_ref):
			continue
		var remote := node_ref as PlayerController
		if remote == null or remote.net_dead:
			continue
		var dist := player.global_position.distance_to(remote.global_position)
		if dist < best_dist:
			best_dist = dist
			best = remote
	return best


func _report(m: Dictionary, joined: int) -> void:
	var reasons: Array[String] = m["reasons"]
	var ul_kib := float(m["snap_avg"]) * float(m["clients"]) * float(m["tick_avg"]) / 1024.0
	print("SOAK tick avg=%.2fHz min=%.2fHz below28=%d" % [
		m["tick_avg"], m["tick_min"], m["ticks_below_28"],
	])
	print("SOAK frame period avg=%.2fms p95=%.2fms (30Hz target=33.3ms)" % [
		m["period_avg"], m["period_p95"],
	])
	print("SOAK cpu process_avg=%.1f%% (server+%d clients, 1 core=100%%)" % [
		m["cpu_avg"], m["clients"],
	])
	print("SOAK rss start=%dKB end=%dKB peak=%dKB growth=%.1f%%" % [
		m["rss_base"], m["rss_end"], m["rss_peak"], m["rss_growth"],
	])
	print("SOAK nodes start=%d end=%d peak=%d growth=%d" % [
		m["nodes_base"], m["nodes_end"], m["nodes_peak"], int(m["nodes_end"]) - int(m["nodes_base"]),
	])
	print("SOAK snapshot avg=%dB max=%dB clients=%d uplink~=%.1fKiB/s" % [
		m["snap_avg"], m["snap_max"], m["clients"], ul_kib,
	])
	print("SOAK clients joined=%d alive=%d snapshots=%d dropped=%d ack_lag_max=%d" % [
		joined, m["alive"], m["snapshots_processed"], m["snapshots_dropped"], m["ack_lag_max"],
	])
	print("SOAK stall starved=%d frozen=%d" % [m["starved"], m["frozen"]])
	var stats_call := Callable(_server_gm, "server_player_stats")
	for session: Dictionary in _sessions:
		var cgm: Node = session["gm"]
		var cnet: Node = session["net"]
		var cid := int(cgm.local_id)
		var s: Dictionary = stats_call.call(cid) if cid > 0 else {}
		print("SOAK client id=%d seq=%d ack=%d queue=%d dropped=%d starved=%d frozen=%d snaps=%d" % [
			cid, int(session["seq"]), int(s.get("ack", -1)), int(s.get("queued", -1)),
			int(s.get("dropped", -1)), int(s.get("starved", -1)), int(s.get("frozen", -1)),
			int(cnet.snapshots_processed),
		])
	print("SOAK combat shots=%d spawned=%d resolved=%d active=%d hits=%d world=%d expired=%d dmg=%d deaths=%d" % [
		m["shots"], m["spawned"], m["resolved"], m["active"], m["hits"],
		m["world_impacts"], m["expired"], m["damage_hits"], m["deaths"],
	])
	print("SOAK telemetry %s" % m["telemetry"])
	print("SOAK duration=%.1fs result=%s%s" % [
		m["duration"], "PASS" if bool(m["pass"]) else "FAIL",
		"" if reasons.is_empty() else " reasons=" + ",".join(reasons),
	])


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var index := args.find(key)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback


func _cpu_ticks() -> int:
	var file := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if file == null:
		return 0
	var line := file.get_line()
	file.close()
	# comm may contain spaces; everything after the final ')' is fixed-position.
	var close := line.rfind(")")
	if close < 0:
		return 0
	var fields := line.substr(close + 2).split(" ", false)
	# fields[0] is state (field 3); utime is field 14, stime field 15.
	if fields.size() < 13:
		return 0
	return int(fields[11]) + int(fields[12])


func _rss_kb() -> int:
	var file := FileAccess.open("/proc/self/status", FileAccess.READ)
	if file == null:
		return 0
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("VmRSS:"):
			file.close()
			var bits := line.split(" ", false)
			return int(bits[1]) if bits.size() >= 2 else 0
	file.close()
	return 0


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _mean_int(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var total := 0
	for value in values:
		total += value
	return int(round(float(total) / float(values.size())))


func _percentile(values: Array, p: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(int(float(values.size() - 1) * p), 0, values.size() - 1)
	return float(values[index])
