extends BodTestSuite
## Phase 0: tuning, turn-then-shoot gating, and the render-rate interpolator.

const DT := 1.0 / 60.0


func test_tuned_speeds_and_projectile() -> void:
	var stats := load("res://resources/players/default_player.tres") as PlayerStats
	var weapon := load("res://resources/weapons/rifle_stats.tres") as WeaponStats
	expect(is_equal_approx(stats.move_speed, 1.05), "walk is 1.05 m/s")
	expect(is_equal_approx(stats.move_speed * stats.sprint_multiplier, 2.751),
		"sprint is 2.75 m/s (got %.3f)" % (stats.move_speed * stats.sprint_multiplier))
	expect(is_equal_approx(weapon.projectile_speed, 81.0), "projectile is 81 m/s")


func test_turn_then_shoot() -> void:
	# Intent shaping only reads view_yaw/rotation/aim state; no tree needed, so
	# the visual layer never creates deferred overlays during this test.
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	player.rotation.y = 0.0
	player.view_yaw = PI * 0.5

	var first := PlayerInputFrame.new()
	first.fire = true
	first.yaw = player.view_yaw
	player._shape_combat_intent(first)
	expect(not first.fire, "shot is held while the body faces away")
	expect(first.aim, "firing requests aim lock")

	player.rotation.y = player.view_yaw
	var second := PlayerInputFrame.new()
	second.fire = true
	second.yaw = player.view_yaw
	player._shape_combat_intent(second)
	expect(second.fire, "shot fires once the body is aligned")
	expect(player.aim_hold_until_msec > Time.get_ticks_msec(), "body stays aimed after firing")
	player.free()


func test_interpolator_is_smooth_and_teleports() -> void:
	var interp := NetworkInterpolator.new()
	add_child(interp)
	for tick in 10:
		interp.push_sample(
			tick, Vector3(float(tick) * 0.03, 0.0, 0.0), 0.0,
			NetProtocol.AnimState.WALK, Vector3(0.9, 0.0, 0.0)
		)
	var last := Vector3.ZERO
	var max_step := 0.0
	for _i in 30:
		var sample: Dictionary = interp.sample(DT)
		var pos: Vector3 = sample["pos"]
		max_step = maxf(max_step, pos.distance_to(last))
		last = pos
	expect(max_step < 0.06, "interpolated render never jumps (max step %.3f m)" % max_step)
	expect(last.x > 0.2, "interpolator advances through the samples (x %.3f)" % last.x)

	interp.push_sample(20, Vector3(10.0, 0.0, 0.0), 0.0, NetProtocol.AnimState.STILL, Vector3.ZERO)
	expect(interp.consume_teleport(), "a >4 m move is flagged as a teleport")
	var after: Dictionary = interp.sample(DT)
	expect((after["pos"] as Vector3).distance_to(Vector3(10.0, 0.0, 0.0)) < 0.2,
		"teleport snaps instead of sliding")
	interp.queue_free()
	await get_tree().process_frame


func test_client_timeout_reports_failure() -> void:
	var net: Node = (load("res://scripts/networking/network_manager.gd") as GDScript).new()
	add_child(net)
	expect(net.start_client("127.0.0.1", 9199) == OK, "client socket starts")
	# Pretend the handshake has been pending for longer than the 6 s budget.
	net._client_started_msec = Time.get_ticks_msec() - 7000
	await get_tree().process_frame
	await get_tree().process_frame
	expect(net.last_error != "", "unreachable server records a reason")
	expect(net.mode == net.Mode.OFFLINE, "failed connection returns to offline")
	net.queue_free()
	await get_tree().process_frame


func test_death_pose_and_red_marker() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20, 1, 20)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	floor_body.position = Vector3(0, -0.55, 0)

	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	add_child(player)
	player.global_position = Vector3(0, 0.2, 0)
	var cv := player.visual as CharacterVisual
	for _i in 60:
		await get_tree().physics_frame
		if cv._grip_calibrated:
			break
	for _i in 2:
		await get_tree().process_frame
	player.net_dead = true
	for _i in 5:
		await get_tree().process_frame
	expect(cv._dead, "remote death enters the death pose")
	expect(cv.animation_player.current_animation == &"Death_A", "Death_A plays")
	expect(cv._death_marker != null and cv._death_marker.visible, "red death marker is shown")
	player.net_dead = false
	for _i in 5:
		await get_tree().process_frame
	expect(not cv._dead, "respawn exits the death pose")
	expect(not cv._death_marker.visible, "red death marker is hidden on respawn")
	player.queue_free()
	floor_body.free()
	for _i in 3:
		await get_tree().process_frame
