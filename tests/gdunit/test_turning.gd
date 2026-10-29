extends BodTestSuite
## CP4b movement model: camera-relative input, body faces movement, aiming locks
## facing to the view (strafe), and the view yaw itself is not the body yaw.

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
	_player.set_physics_process(false)


func _reset(body_yaw: float, view_yaw: float) -> void:
	_player.global_position = Vector3(0, 0.05, 0)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = body_yaw
	_player.view_yaw = view_yaw
	_player.locomotion.jump_buffer_left = 0.0
	_player.locomotion.coyote_left = 0.0


func _tick(seq: int, move: Vector2, view_yaw: float, aim: bool = false) -> void:
	var frame := PlayerInputFrame.new()
	frame.seq = seq
	frame.move = move
	frame.yaw = view_yaw
	frame.aim = aim
	_player.simulate_tick(frame, DT)


func test_body_turns_to_movement() -> void:
	await _setup()
	_reset(0.0, 0.0)
	# View yaw stays 0 (camera forward -Z); pressing right must turn the body to
	# +X and move there, not strafe sideways with the back to the camera.
	for i in 24:
		_tick(i + 1, Vector2(1.0, 0.0), 0.0)
		await get_tree().physics_frame
	expect(absf(wrapf(_player.rotation.y - -PI * 0.5, -PI, PI)) < 0.08,
		"body faces +X after pressing D (yaw %.2f)" % _player.rotation.y)
	expect(_player.global_position.x > 0.3, "body moves in the input direction (x %.2f)" % _player.global_position.x)
	expect(absf(_player.global_position.z) < 0.08, "no sideways slide while turning")
	expect(absf(_player.view_yaw) < 0.001, "view yaw did not change with movement")


func test_view_yaw_rotates_movement() -> void:
	await _setup()
	# Camera turned 90 degrees: forward input must travel -X even though the body
	# started facing -Z.
	_reset(0.0, PI * 0.5)
	for i in 24:
		_tick(i + 1, Vector2(0.0, -1.0), PI * 0.5)
		await get_tree().physics_frame
	expect(absf(wrapf(_player.rotation.y - PI * 0.5, -PI, PI)) < 0.08,
		"body turns to the view-relative forward (yaw %.2f)" % _player.rotation.y)
	expect(_player.global_position.x < -0.3, "forward input follows the camera yaw (x %.2f)" % _player.global_position.x)
	expect(absf(_player.global_position.z) < 0.08, "movement stays on the camera axis")


func test_aim_strafes_without_turning() -> void:
	await _setup()
	_reset(0.0, 0.0)
	for i in 24:
		_tick(i + 1, Vector2(1.0, 0.0), 0.0, true)
		await get_tree().physics_frame
	expect(absf(wrapf(_player.rotation.y, -PI, PI)) < 0.05, "aiming keeps facing the view")
	expect(_player.global_position.x > 0.3, "aiming allows strafing (x %.2f)" % _player.global_position.x)
	expect(absf(_player.global_position.z) < 0.08, "strafe stays perpendicular to the view")


func test_180_turn_is_deterministic_across_quantized_yaw() -> void:
	# The client's body yaw comes back quantized from snapshots while the server's
	# stays full precision. A 180-degree turn can then resolve to opposite
	# directions. Both bodies here straddle PI by 0.1 mrad and must turn the same way.
	var stats := load("res://resources/players/default_player.tres") as PlayerStats
	var a := CharacterBody3D.new()
	var b := CharacterBody3D.new()
	add_child(a)
	add_child(b)
	var la := LocomotionComponent.new()
	var lb := LocomotionComponent.new()
	la.stats = stats
	lb.stats = stats
	a.add_child(la)
	b.add_child(lb)
	a.rotation.y = 0.0001
	b.rotation.y = -0.0001

	var frame := PlayerInputFrame.new()
	frame.move = Vector2(0.0, 1.0)   # backwards => target yaw = PI
	la.simulate(a, frame, DT, 1, 0.0)
	lb.simulate(b, frame, DT, 1, 0.0)
	print("  180-turn deltas: %.4f / %.4f" % [a.rotation.y, b.rotation.y])
	expect(a.rotation.y > 0.01 and b.rotation.y > 0.01,
		"both sides choose the same 180-degree direction")
	expect(absf(a.rotation.y - b.rotation.y) < 0.001, "both bodies end at the same yaw")
	a.free()
	b.free()
