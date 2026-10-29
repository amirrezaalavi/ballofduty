extends BodTestSuite
## CP4b prediction mechanics: replay determinism, divergence correction, and
## visual smoothing. No sockets here; the loopback suite covers the wire path.

const DT := 1.0 / 30.0

var _player: PlayerController
var _world: Node3D


func after_test() -> void:
	if is_instance_valid(_world):
		_world.free()


func _setup() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	col.shape = box
	floor_body.add_child(col)
	_world.add_child(floor_body)
	floor_body.position = Vector3(0, -0.55, 0)

	_player = (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_world.add_child(_player)
	_player.global_position = Vector3(0, 0.5, 0)
	for _i in 4:
		await get_tree().physics_frame
	# The suite drives ticks explicitly; the controller's own callback would add
	# neutral frames with a competing sequence.
	_player.set_physics_process(false)
	_player.enable_prediction()


## Simulate `count` forward frames from seq 1..count, recording the state after
## each one. Returns {frames, states, end}.
func _simulate_run(count: int) -> Dictionary:
	var frames: Array[PlayerInputFrame] = []
	var states: Array[Dictionary] = []
	for i in count:
		var frame := PlayerInputFrame.new()
		frame.seq = i + 1
		frame.move = Vector2(1.0, 0.0)
		_player.simulate_tick(frame, DT)
		frames.append(frame)
		states.append({
			"pos": _player.global_position,
			"vel": _player.velocity,
			"yaw": _player.rotation.y,
			"on_floor": _player.is_on_floor(),
		})
		await get_tree().physics_frame
	return {"frames": frames, "states": states, "end": _player.global_position}


func test_replay_is_deterministic() -> void:
	await _setup()
	var run := await _simulate_run(10)
	var frames: Array = run["frames"]
	var states: Array = run["states"]
	var predicted_end: Vector3 = run["end"]

	# Rewind to the state after input 5 and replay 6..10 from authority.
	var anchor: Dictionary = states[4]
	_player.accept_server_state({
		"ack": 5,
		"pos": anchor["pos"],
		"yaw": anchor["yaw"],
		"vel": anchor["vel"],
		"on_floor": anchor["on_floor"],
	})
	# Apply without simulating a new frame: the replay tail is 6..10, exactly the
	# inputs that were pending when the ack arrived.
	_player._apply_correction()

	var replay_end := _player.global_position
	print("  replay end delta=%.5f m (ack_err=%.5f)" % [
		replay_end.distance_to(predicted_end), _player.last_ack_error_m])
	expect(_player.last_acked_seq == 5, "ack applied (got %d)" % _player.last_acked_seq)
	expect(_player.replay_depth == 5, "replayed 5 unacked frames (got %d)" % _player.replay_depth)
	expect(_player.last_ack_error_m < 0.001, "authoritative state matches prediction at ack")
	expect(replay_end.distance_to(predicted_end) < 0.001, "replay is deterministic")
	expect(_player.corrections_total == 0, "deterministic replay needs no visual correction")


func test_divergence_corrects_and_smooths() -> void:
	await _setup()
	var run := await _simulate_run(10)
	var frames: Array = run["frames"]
	var states: Array = run["states"]
	var predicted_end: Vector3 = run["end"]

	# First authoritative ack is the spawn baseline and is applied as a snap.
	var baseline: Dictionary = states[1]
	_player.accept_server_state({
		"ack": 2, "pos": baseline["pos"], "yaw": baseline["yaw"],
		"vel": baseline["vel"], "on_floor": baseline["on_floor"],
	})
	_player._apply_correction()

	# Authority says the player is 50 cm to the right of what we predicted.
	var anchor: Dictionary = states[4]
	var server_pos: Vector3 = anchor["pos"] + Vector3(0.5, 0, 0)
	_player.accept_server_state({
		"ack": 5,
		"pos": server_pos,
		"yaw": anchor["yaw"],
		"vel": anchor["vel"],
		"on_floor": anchor["on_floor"],
	})
	_player._apply_correction()

	print("  divergent correction=%.3f m (total %d)" % [
		_player.last_position_error_m, _player.corrections_total])
	expect(_player.corrections_total == 1, "divergence is counted as one correction")
	expect(_player.last_position_error_m > 0.1, "correction magnitude is measured")
	expect(
		_player.global_position.distance_to(predicted_end + Vector3(0.5, 0, 0)) < 0.05,
		"body adopts the authoritative offset"
	)
	expect(_player.visual.position.distance_to(_player._visual_base) > 0.1,
		"render children hold the old pose while the body moves")

	# The offset decays over ~100 ms and the visual returns to its rest pose.
	# Drive fixed 60 Hz deltas: headless process frames are uncapped and tiny.
	for _i in 30:
		_player._decay_visual_offset(1.0 / 60.0)
	expect(_player.visual.position.distance_to(_player._visual_base) < 0.01,
		"visual offset decays back to rest")
	expect(_player.prediction_stats()["corrections"] == 1, "correction counter is stable")


func test_stale_ack_is_ignored() -> void:
	await _setup()
	var run := await _simulate_run(6)
	var states: Array = run["states"]
	var anchor: Dictionary = states[4]
	_player.accept_server_state({
		"ack": 5, "pos": anchor["pos"], "yaw": anchor["yaw"],
		"vel": anchor["vel"], "on_floor": anchor["on_floor"],
	})
	_player._apply_correction()
	var ack: int = _player.last_acked_seq
	var pos := _player.global_position

	# A delayed snapshot for an older input must not rewind the client.
	_player.accept_server_state({
		"ack": 3, "pos": Vector3(9, 9, 9), "yaw": 0.0,
		"vel": Vector3.ZERO, "on_floor": true,
	})
	_player._apply_correction()
	expect(_player.last_acked_seq == ack, "older ack is ignored")
	expect(_player.global_position.distance_to(pos) < 0.001, "older ack does not move the body")
