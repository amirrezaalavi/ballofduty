extends BodTestSuite
## Net resilience under unstable clients: the server must extrapolate briefly and
## then idle (never hard-freeze), keep the ack pinned, and the client must stop
## predicting once it is too far ahead of the server.
##
## Context: 50-150 ms RTT is normal, tabs get throttled to 1 FPS, and low-end
## GPUs drop physics catch-up. None of that may turn into a permanent desync.

const DT := 1.0 / 30.0

var _gm: Node
var _player: PlayerController
var _world: Node3D


func before_test() -> void:
	_gm = load("res://scripts/game/game_manager.gd").new()
	add_child(_gm)


func after_test() -> void:
	if is_instance_valid(_world):
		_world.free()
		_world = null
	if is_instance_valid(_gm):
		_gm.free()
		_gm = null


func _entry(seq: int = 7) -> Dictionary:
	var last := PlayerInputFrame.new()
	last.seq = seq
	last.move = Vector2(1.0, 0.0)
	last.yaw = 0.5
	last.pitch = -0.2
	return {
		"queue": [],
		"last_frame": last,
		"ack": seq,
		"last_seq": seq,
		"has_input": true,
		"starved_ticks": 0,
		"idle_ticks": 0,
		"idle_frame": PlayerInputFrame.new(),
	}


# --- server intake -------------------------------------------------------

func test_server_repeats_last_input_for_two_ticks() -> void:
	var entry := _entry()
	var first: PlayerInputFrame = _gm._pick_server_frame(entry)
	var second: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(first.seq == 7, "first miss repeats the last input")
	expect(second.seq == 7, "second miss still repeats")
	expect(first.move.x == 1.0, "extrapolated input keeps the movement")
	expect(int(entry["ack"]) == 7, "ack stays pinned to the received input")
	expect(int(entry["idle_ticks"]) == 0, "no idle ticks during the grace window")


func test_server_idles_after_the_grace_window() -> void:
	var entry := _entry()
	_gm._pick_server_frame(entry)
	_gm._pick_server_frame(entry)
	var third: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(third.move == Vector2.ZERO, "third miss stops inventing movement")
	expect(third.jump == false, "idle frame never jumps")
	expect(third.seq == 7, "idle frame keeps the last sequence")
	expect(is_equal_approx(third.yaw, 0.5), "idle frame keeps the view yaw")
	expect(int(entry["idle_ticks"]) == 1, "idle counter advanced")
	expect(int(entry["ack"]) == 7, "ack is still pinned while idle")


func test_server_never_freezes_the_simulation() -> void:
	# The old policy returned simulate=false after two misses, which also stopped
	# gravity. The intake now always yields a frame to simulate.
	var entry := _entry()
	for _i in 120:
		var frame: PlayerInputFrame = _gm._pick_server_frame(entry)
		expect(frame != null, "an intake frame always exists")
	expect(int(entry["idle_ticks"]) == 118, "two extrapolated ticks, then idle")
	expect(int(entry["starved_ticks"]) == 120, "starve counter keeps counting")


func test_server_resumes_on_the_next_input() -> void:
	var entry := _entry()
	for _i in 5:
		_gm._pick_server_frame(entry)
	var fresh := PlayerInputFrame.new()
	fresh.seq = 8
	fresh.move = Vector2(0.0, 1.0)
	(entry["queue"] as Array).append(fresh)
	var frame: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(frame.seq == 8, "queued input wins immediately")
	expect(int(entry["ack"]) == 8, "ack advances to the received input")
	expect(int(entry["starved_ticks"]) == 0, "starve counter reset")
	expect(int(entry["idle_ticks"]) == 0, "idle counter reset")


func test_idle_frame_is_reused() -> void:
	var entry := _entry()
	_gm._pick_server_frame(entry)
	_gm._pick_server_frame(entry)
	var a: PlayerInputFrame = _gm._pick_server_frame(entry)
	var b: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(a == b, "idle frame is a reused instance, not a per-tick allocation")


# --- client backlog ------------------------------------------------------

func _setup_player() -> void:
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
	_player.set_physics_process(false)
	_player.enable_prediction()


func test_client_backlog_blocks_past_the_limit() -> void:
	await _setup_player()
	_player.last_seq = 100
	_player.last_acked_seq = 100 - PlayerController.MAX_UNACKED_INPUTS
	expect(not _player.input_backlog_blocked(), "at the limit the client keeps predicting")
	_player.last_acked_seq = 100 - PlayerController.MAX_UNACKED_INPUTS - 1
	expect(_player.input_backlog_blocked(), "past the limit the client holds")


func test_client_backlog_is_ignored_without_prediction() -> void:
	await _setup_player()
	_player.disable_prediction()
	_player.last_seq = 500
	_player.last_acked_seq = 1
	expect(not _player.input_backlog_blocked(), "no prediction, no clamp")


func test_reset_prediction_drops_history_and_snaps_next_state() -> void:
	await _setup_player()
	for i in 5:
		var frame := PlayerInputFrame.new()
		frame.seq = i + 1
		frame.move = Vector2(1.0, 0.0)
		_player.simulate_tick(frame, DT)
		await get_tree().physics_frame
	expect(not _player._prediction.is_empty(), "history recorded")
	_player.reset_prediction()
	expect(_player._prediction.is_empty(), "history dropped")
	expect(_player.last_acked_seq == _player.last_seq, "baseline adopts the current seq")
	expect(_player._snap_next, "next snapshot snaps instead of easing")
	expect(not _player.input_backlog_blocked(), "reset cannot trip the backlog clamp")
	expect(_player.prediction_stats()["unacked"] == 0, "backlog reads zero after the reset")


func test_clamp_still_applies_the_pending_ack() -> void:
	# Regression: the clamp used to return before the correction path, so the ack
	# that clears the clamp was never consumed (a slow client stayed stuck).
	await _setup_player()
	for i in 40:
		var frame := PlayerInputFrame.new()
		frame.seq = i + 1
		frame.move = Vector2(1.0, 0.0)
		_player.simulate_tick(frame, DT)
		await get_tree().physics_frame
	_player.last_acked_seq = 1
	expect(_player.input_backlog_blocked(), "client is past the backlog limit")
	_player.accept_server_state({
		"ack": 40,
		"pos": _player.global_position,
		"yaw": 0.0,
		"vel": Vector3.ZERO,
		"on_floor": true,
	})
	_player.local_tick(DT)
	expect(not _player.input_backlog_blocked(), "one tick consumes the ack and clears the clamp")
	expect(int(_player.prediction_stats()["unacked"]) <= 1, "backlog drained")
	expect(_player.stalled_ticks == 0, "input generation resumed instead of holding")


func test_ack_latency_is_measured() -> void:
	await _setup_player()
	var frame := PlayerInputFrame.new()
	frame.seq = 1
	frame.move = Vector2(1.0, 0.0)
	_player.simulate_tick(frame, DT)
	await get_tree().physics_frame
	_player.accept_server_state({
		"ack": 1,
		"pos": _player.global_position,
		"yaw": 0.0,
		"vel": Vector3.ZERO,
		"on_floor": true,
	})
	var next := PlayerInputFrame.new()
	next.seq = 2
	_player.simulate_tick(next, DT)
	expect(_player.ack_latency_ms >= 0.0, "ack latency is a real measurement")
	expect(_player.prediction_stats()["ack_latency_ms"] >= 0.0, "exposed to the HUD")


func test_stats_expose_resilience_fields() -> void:
	await _setup_player()
	_player.last_seq = 40
	_player.last_acked_seq = 35
	var stats := _player.prediction_stats()
	expect(stats.has("unacked"), "unacked is exposed")
	expect(stats.has("ack_latency_ms"), "ack latency is exposed")
	expect(stats.has("stalled_ticks"), "stalled ticks are exposed")
	expect(int(stats["unacked"]) == 5, "unacked is computed from seq - ack")

