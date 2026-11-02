extends BodTestSuite
## Latest-wins input intake: the server must apply the newest frame it has every
## tick, never a backlog. Sticky one-shot edges keep jump/fire/reload from being
## lost when a newer packet overwrites the one the tick has not read yet.
##
## Context: the old queue capped at 16 and consumed one frame per tick. Because
## the client produces and the server consumes at the same 30 Hz, a join burst
## (physics catch-up) left a permanent ~267 ms offset (reports/playtest-2026-11-02
## section 2), with zero dropped inputs.

const GM_SCRIPT := preload("res://scripts/game/game_manager.gd")
const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")

var _gm: Node
var _world: Node3D
var _actor: PlayerController


func before_test() -> void:
	_gm = GM_SCRIPT.new()
	add_child(_gm)


func after_test() -> void:
	if is_instance_valid(_world):
		_world.free()
		_world = null
	if is_instance_valid(_gm):
		_gm.free()
		_gm = null


func _entry(seq: int = 0) -> Dictionary:
	var last := PlayerInputFrame.new()
	last.seq = seq
	last.move = Vector2(0.5, 0.0)
	last.yaw = 0.25
	last.pitch = -0.1
	return {
		"pending_frame": null,
		"edge_jump": false, "edge_fire": false, "edge_reload": false,
		"last_frame": last,
		"ack": seq,
		"last_seq": seq,
		"has_input": false,
		"starved_ticks": 0,
		"idle_ticks": 0,
		"idle_frame": PlayerInputFrame.new(),
	}


## Wire-shaped frame, exactly what NetProtocol.decode_input hands the manager.
func _wire(
	seq: int, move: Vector2, jump: bool = false, fire: bool = false, reload: bool = false
) -> Dictionary:
	return {
		"seq": seq, "move": move, "jump": jump, "sprint": false,
		"scoped": false, "fire": fire, "reload": reload, "yaw": 0.0, "pitch": 0.0,
	}


## Register the hand-built entry as peer 1 so _on_remote_input accepts frames.
func _attach(entry: Dictionary) -> void:
	_gm.net_mode = GM_SCRIPT.NetMode.SERVER
	entry["rate_window_msec"] = Time.get_ticks_msec()
	entry["rate_count"] = 0
	entry["inputs_dropped"] = 0
	_gm._roster[1] = entry


# --- latest wins ---------------------------------------------------------

func test_burst_applies_only_the_newest_frame() -> void:
	var entry := _entry()
	_attach(entry)
	for i in 8:
		_gm._on_remote_input(1, _wire(i + 1, Vector2(float(i + 1) / 8.0, 0.0)))
	expect(entry["pending_frame"] != null, "the burst leaves exactly one pending frame")

	var frame: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(frame.seq == 8, "the newest seq is applied (got %d)" % frame.seq)
	expect(is_equal_approx(frame.move.x, 1.0), "the newest held state is applied")
	expect(entry["pending_frame"] == null, "one tick drains the burst, no backlog")
	expect(int(entry["last_seq"]) == 8, "last_seq tracks the newest received packet")
	expect(int(entry["inputs_dropped"]) == 0, "overwriting a pending frame is not a drop")


func test_ack_is_the_newest_applied_seq() -> void:
	var entry := _entry()
	_attach(entry)
	for i in 8:
		_gm._on_remote_input(1, _wire(i + 1, Vector2.ZERO))
	_gm._pick_server_frame(entry)
	expect(int(entry["ack"]) == 8, "ack is the newest applied seq, not the oldest (got %d)" % int(entry["ack"]))


func test_duplicate_and_old_sequences_are_dropped() -> void:
	var entry := _entry()
	_attach(entry)
	_gm._on_remote_input(1, _wire(5, Vector2(1.0, 0.0)))
	_gm._on_remote_input(1, _wire(5, Vector2(0.0, 1.0)))
	_gm._on_remote_input(1, _wire(4, Vector2(0.0, 1.0)))
	expect(int(entry["inputs_dropped"]) == 2, "duplicate and old seqs count as dropped")

	var frame: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(frame.seq == 5, "the first copy of seq 5 stays applied")
	expect(is_equal_approx(frame.move.x, 1.0), "a stale duplicate never overwrites the frame")


# --- sticky one-shot edges ----------------------------------------------

func test_jump_survives_an_overwriting_frame() -> void:
	var entry := _entry()
	_attach(entry)
	_gm._on_remote_input(1, _wire(1, Vector2(1.0, 0.0), true))
	_gm._on_remote_input(1, _wire(2, Vector2(0.0, 1.0), false))

	var frame: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(frame.seq == 2, "the newest held state wins")
	expect(is_equal_approx(frame.move.y, 1.0), "newest move wins")
	expect(frame.jump, "a jump overwritten before the tick still fires")
	expect(not bool(entry["edge_jump"]), "the edge clears after one apply")

	# The next real frame must not inherit the action: the edge is one-shot.
	_gm._on_remote_input(1, _wire(3, Vector2.ZERO))
	var next: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(not next.jump, "the edge does not leak into later frames")


func test_fire_and_reload_survive_an_overwriting_frame() -> void:
	var entry := _entry()
	_attach(entry)
	_gm._on_remote_input(1, _wire(1, Vector2.ZERO, false, true, true))
	_gm._on_remote_input(1, _wire(2, Vector2(1.0, 0.0), false, false, false))

	var frame: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(frame.fire, "a fire overwritten before the tick still fires")
	expect(frame.reload, "a reload overwritten before the tick still reloads")
	expect(not bool(entry["edge_fire"]) and not bool(entry["edge_reload"]), "both edges clear after one apply")


# --- starvation ----------------------------------------------------------

func test_starvation_idles_after_the_grace_window() -> void:
	var entry := _entry()
	_attach(entry)
	_gm._on_remote_input(1, _wire(1, Vector2(1.0, 0.0)))
	var applied: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(applied.seq == 1 and is_equal_approx(applied.move.x, 1.0), "the input applies")

	for _i in GM_SCRIPT.MAX_EXTRAPOLATION_TICKS:
		var repeat: PlayerInputFrame = _gm._pick_server_frame(entry)
		expect(repeat.seq == 1, "the grace window repeats the last input")
		expect(int(entry["ack"]) == 1, "ack never advances without a real input")

	var idle: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(idle.move == Vector2.ZERO, "after the grace window the server idles")
	expect(int(entry["ack"]) == 1, "idle still leaves the ack pinned")
	expect(int(entry["idle_ticks"]) == 1, "idle counter advanced")


# --- respawn cleanup -----------------------------------------------------

func test_respawn_clears_pending_and_edges() -> void:
	_world = Node3D.new()
	add_child(_world)
	_actor = PLAYER_SCENE.instantiate() as PlayerController
	_world.add_child(_actor)
	_actor.set_physics_process(false)
	_gm._world = _world

	var entry := _entry(9)
	entry["id"] = 1
	entry["node"] = _actor
	entry["dead_until"] = 0
	entry["protected_until"] = 0
	entry["has_input"] = true
	entry["pending_frame"] = PlayerInputFrame.new()
	entry["edge_jump"] = true
	entry["edge_fire"] = true
	entry["edge_reload"] = true
	_attach(entry)

	_gm._respawn(entry)
	expect(entry["pending_frame"] == null, "respawn drops the stale pending frame")
	expect(
		not bool(entry["edge_jump"]) and not bool(entry["edge_fire"]) and not bool(entry["edge_reload"]),
		"respawn clears every sticky edge"
	)
	expect(int(entry["ack"]) == 0, "respawn resets the ack")

	_gm._on_remote_input(1, _wire(1, Vector2(0.0, 1.0)))
	var frame: PlayerInputFrame = _gm._pick_server_frame(entry)
	expect(frame.seq == 1, "the first frame after respawn applies")
	expect(is_equal_approx(frame.move.y, 1.0), "the new frame's state reaches the tick")
	expect(not frame.jump, "the cleared edge does not fire on the respawn frame")
