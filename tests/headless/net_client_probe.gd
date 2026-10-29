extends SceneTree
## Cross-process client probe for CP4a. Runs as a real second client against a
## running server so a browser tab can be verified against a native peer.
##
##   tools/godot --headless --path . --script tests/headless/net_client_probe.gd \
##     -- --host 127.0.0.1 --port 9180 --name NativeBot --seconds 12

var _failures := 0
var _checks := 0


func _init() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var host := _arg(args, "--host", "127.0.0.1")
	var port := int(_arg(args, "--port", "9180"))
	var display_name := _arg(args, "--name", "NativeBot")
	var seconds := float(_arg(args, "--seconds", "12"))
	var walk_to := Vector2.ZERO
	var walk_target := _arg(args, "--walk-to", "")
	if walk_target != "":
		var bits := walk_target.split(",")
		if bits.size() == 2:
			walk_to = Vector2(float(bits[0]), float(bits[1]))

	# --script mode has no autoloads; build a transport + session locally. This is
	# still a separate OS process, so the wire path is real.
	var net = load("res://scripts/networking/network_manager.gd").new()
	var gm = load("res://scripts/game/game_manager.gd").new()
	root.add_child(net)
	root.add_child(gm)
	gm.net = net

	var packed := load("res://scenes/maps/arena_nature.tscn") as PackedScene
	var world := packed.instantiate()
	root.add_child(world)
	var player_scene := load("res://scenes/characters/player.tscn") as PackedScene
	var player := player_scene.instantiate() as PlayerController
	player.name = "Player"
	world.add_child(player)
	await physics_frame

	var err: int = gm.client_start(world, host, port, display_name)
	_check(err == OK, "probe client starts (err=%d)" % err)

	var waited := 0
	while gm.local_id == 0 and waited < 300:
		await physics_frame
		waited += 1
	_check(gm.local_id > 0, "probe joined with id=%d" % gm.local_id)
	print("probe: id=%d spawn=%s" % [gm.local_id, str(player.global_position.snapped(Vector3.ONE * 0.01))])

	# Either walk toward a world point (to enter another client's view) or circle
	# in place. Yaw is sent from the local body so server aim matches the client.
	var seq := 0
	var frames := int(seconds * 30.0)
	# Local prediction is not driven by sent frames in CP4a, so integrate a virtual
	# position to decide when the bot has arrived instead of walking forever.
	var virtual_pos := Vector2(player.global_position.x, player.global_position.z)
	for i in frames:
		seq += 1
		var t := float(i) / 30.0
		var frame := PlayerInputFrame.new()
		frame.seq = seq
		if walk_target != "":
			var delta := walk_to - virtual_pos
			var yaw := atan2(-delta.x, -delta.y)
			player.rotation.y = yaw
			frame.yaw = yaw
			var moving := delta.length() > 2.0
			frame.move = Vector2(0.0, -1.0) if moving else Vector2.ZERO
			frame.sprint = delta.length() > 12.0
			if moving:
				var speed := 7.56 if frame.sprint else 5.6
				virtual_pos += delta.normalized() * speed / 30.0
		else:
			frame.move = Vector2(sin(t * 0.6), -cos(t * 0.6))
			frame.yaw = player.rotation.y
		gm.client_send_input(frame)
		await physics_frame
		if i % 30 == 29:
			print("probe: t=%.0fs pos=%s remotes=%d snap=%d" % [
				t, str(player.global_position.snapped(Vector3.ONE * 0.01)),
				gm.remote_count(), int(net.snapshots_processed),
			])

	_check(int(net.snapshots_processed) > 10, "probe received snapshots (%d)" % int(net.snapshots_processed))
	_check(gm.remote_count() >= 1, "probe sees at least one remote (%d)" % gm.remote_count())
	_check(int(net.last_snapshot_bytes) <= 300, "live snapshot <= 300 B (%d)" % int(net.last_snapshot_bytes))

	gm.stop_all()
	world.queue_free()
	await process_frame
	_finish()


func _arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var index := args.find(key)
	if index >= 0 and index + 1 < args.size():
		return args[index + 1]
	return fallback


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)


func _finish() -> void:
	print("net_client_probe: %d checks, %d failure(s)" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
