extends BodTestSuite
## Arena geometry regressions: every tree has a collider, and the third-person
## camera never ends up inside the cliff when the player hugs a wall.

var _arena: Node3D


func after_test() -> void:
	if is_instance_valid(_arena):
		_arena.free()


func _make_arena() -> void:
	_arena = (load("res://scenes/maps/arena_nature.tscn") as PackedScene).instantiate()
	add_child(_arena)
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_every_tree_has_a_collider() -> void:
	await _make_arena()
	var colliders: Array[Vector3] = []
	for node in _arena.find_children("PropCollider*", "StaticBody3D", true, false):
		colliders.append((node as Node3D).global_position)

	var trees: Array = _arena.tree_positions()
	for pos: Vector3 in trees:
		var found := false
		for c in colliders:
			if Vector2(c.x - pos.x, c.z - pos.z).length() < 0.35:
				found = true
				break
		expect(found, "tree at (%.2f, %.2f) has a trunk collider" % [pos.x, pos.z])
	expect(trees.size() > 30, "arena has a meaningful number of trees (%d)" % trees.size())


func test_camera_stays_out_of_the_cliff() -> void:
	await _make_arena()
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_arena.add_child(player)
	var rig := player.get_node("CameraPivot") as CameraRig
	# Cliff inner face is x = 29.15; the capsule can reach x ~= 28.96.
	player.global_position = Vector3(28.96, 0.5, 0.0)
	player.rotation.y = PI * 0.5   # face -X, camera behind toward +X
	player.set_view_yaw(PI * 0.5)
	player.set_physics_process(false)
	for _i in 12:
		await get_tree().process_frame
	var cam := rig.camera
	print("  camera at wall: x=%.3f hit=%.3f" % [cam.global_position.x, rig.spring_arm.get_hit_length()])
	expect(rig.spring_arm.get_hit_length() > 0.0, "spring arm finds the cliff")
	expect(cam.global_position.x < 29.14, "camera stays inside the arena (x %.3f)" % cam.global_position.x)
	expect(cam.global_position.x > 28.5, "camera does not collapse behind the player (x %.3f)" % cam.global_position.x)
