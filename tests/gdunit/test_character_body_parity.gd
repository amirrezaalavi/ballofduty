extends BodTestSuite
## L2/L8 Step 1: the shared CharacterBodyStats profile is the single source of
## truth for capsule, hurtbox, visual scale, camera and canonical muzzle data on
## LOCAL, REMOTE and headless SERVER actors. All five class profiles are still
## numerically identical to the pre-refactor 0.82 m rig.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")

var _world: Node3D
var _actors: Array[PlayerController] = []


func before_test() -> void:
	_world = Node3D.new()
	_world.name = "BodyParityWorld"
	add_child(_world)


func after_test() -> void:
	for actor in _actors:
		if is_instance_valid(actor):
			actor.free()
	_actors.clear()
	if is_instance_valid(_world):
		_world.free()


func _spawn(class_id: int, role: int) -> PlayerController:
	var actor := PLAYER_SCENE.instantiate() as PlayerController
	if role == CharacterBodyStats.Role.LOCAL:
		actor.class_id = class_id
	_world.add_child(actor)
	match role:
		CharacterBodyStats.Role.REMOTE:
			actor.make_remote(100 + class_id, class_id)
		CharacterBodyStats.Role.SERVER:
			actor.make_server(200 + class_id, class_id)
	actor.set_physics_process(false)
	_actors.append(actor)
	await get_tree().process_frame
	return actor


func _capsule(actor: PlayerController) -> CapsuleShape3D:
	return (actor.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D


func _hurtbox_capsule(actor: PlayerController) -> CapsuleShape3D:
	return (
		actor.get_node("BodyHurtbox/CollisionShape3D") as CollisionShape3D
	).shape as CapsuleShape3D


func _expect_capsule_matches(actor: PlayerController, profile: CharacterBodyStats, label: String) -> void:
	var node := actor.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := node.shape as CapsuleShape3D
	expect(capsule != null, "%s has a capsule" % label)
	if capsule:
		expect(is_equal_approx(capsule.radius, profile.capsule_radius), "%s radius" % label)
		expect(is_equal_approx(capsule.height, profile.capsule_height), "%s height" % label)
	expect(is_equal_approx(node.position.y, profile.capsule_offset), "%s offset" % label)


func test_all_five_profiles_load_and_validate() -> void:
	expect(CharacterBodyRegistry.count() == NetProtocol.CLASS_COUNT, "five body profiles")
	for class_id in NetProtocol.CLASS_COUNT:
		var profile := CharacterBodyRegistry.stats_for(class_id)
		expect(profile != null, "class %d profile loads" % class_id)
		if profile == null:
			continue
		expect(profile.class_id == class_id, "class %d profile self-identifies" % class_id)
		expect(profile.validate().is_empty(), "class %d profile validates: %s" % [
			class_id, ", ".join(profile.validate()),
		])
		expect(is_equal_approx(profile.capsule_height, 0.82), "class %d is still 0.82 m" % class_id)
		expect(is_equal_approx(profile.visual_scale, 0.32244), "class %d keeps the KayKit scale" % class_id)
	expect(CharacterBodyRegistry.stats_for(-1) == null, "negative class has no profile")
	expect(CharacterBodyRegistry.stats_for(NetProtocol.CLASS_COUNT) == null, "class 5 has no profile")
	expect(CharacterBodyRegistry.default_profile() != null, "default profile exists")


func test_actor_and_collision_shapes_keep_unit_scale() -> void:
	for role in [CharacterBodyStats.Role.LOCAL, CharacterBodyStats.Role.REMOTE, CharacterBodyStats.Role.SERVER]:
		var actor := await _spawn(2, role)
		var profile := CharacterBodyRegistry.stats_for(2)
		var capsule_node := actor.get_node("CollisionShape3D") as CollisionShape3D
		var hurtbox_node := actor.get_node("BodyHurtbox/CollisionShape3D") as CollisionShape3D
		expect(actor.scale.is_equal_approx(Vector3.ONE), "role %d actor root scale is ONE" % role)
		expect(capsule_node.scale.is_equal_approx(Vector3.ONE), "role %d capsule scale is ONE" % role)
		expect(hurtbox_node.scale.is_equal_approx(Vector3.ONE), "role %d hurtbox scale is ONE" % role)
		if role != CharacterBodyStats.Role.SERVER:
			var visual := actor.get_node("Visual") as Node3D
			expect(
				visual.scale.is_equal_approx(Vector3.ONE * profile.visual_scale),
				"role %d visual scale is profile-driven" % role
			)


func test_local_remote_and_server_capsules_match_profile() -> void:
	var profile := CharacterBodyRegistry.stats_for(2)
	for role in [CharacterBodyStats.Role.LOCAL, CharacterBodyStats.Role.REMOTE, CharacterBodyStats.Role.SERVER]:
		var actor := await _spawn(2, role)
		_expect_capsule_matches(actor, profile, "role %d capsule" % role)
		expect(actor.body_stats == profile, "role %d exposes its body profile" % role)


func test_hurtbox_matches_and_stays_inside_capsule() -> void:
	for class_id in NetProtocol.CLASS_COUNT:
		var profile := CharacterBodyRegistry.stats_for(class_id)
		var actor := await _spawn(class_id, CharacterBodyStats.Role.SERVER)
		var node := actor.get_node("BodyHurtbox/CollisionShape3D") as CollisionShape3D
		var capsule := node.shape as CapsuleShape3D
		expect(capsule != null, "class %d hurtbox is a capsule" % class_id)
		if capsule == null:
			continue
		expect(is_equal_approx(capsule.radius, profile.hurtbox_radius), "class %d hurtbox radius" % class_id)
		expect(is_equal_approx(capsule.height, profile.hurtbox_height), "class %d hurtbox height" % class_id)
		expect(is_equal_approx(node.position.y, profile.hurtbox_offset), "class %d hurtbox offset" % class_id)
		var capsule_bottom := profile.capsule_offset - profile.capsule_height * 0.5
		var capsule_top := profile.capsule_offset + profile.capsule_height * 0.5
		var hurtbox_bottom := node.position.y - capsule.height * 0.5
		var hurtbox_top := node.position.y + capsule.height * 0.5
		expect(hurtbox_bottom >= capsule_bottom - 0.001, "class %d hurtbox stays above the feet" % class_id)
		expect(hurtbox_top <= capsule_top + 0.001, "class %d hurtbox stays inside the capsule" % class_id)


func test_camera_values_match_profile_on_local_and_remote() -> void:
	var profile := CharacterBodyRegistry.stats_for(2)
	for role in [CharacterBodyStats.Role.LOCAL, CharacterBodyStats.Role.REMOTE]:
		var actor := await _spawn(2, role)
		var rig := actor.get_node("CameraPivot") as CameraRig
		expect(is_equal_approx(rig.position.y, profile.camera_pivot_height), "role %d pivot height" % role)
		expect(is_equal_approx(rig.spring_length, profile.camera_spring_length), "role %d spring length" % role)
		expect(is_equal_approx(rig.shoulder_offset, profile.camera_shoulder_offset), "role %d shoulder" % role)
		expect(is_equal_approx(rig.spring_arm.spring_length, profile.camera_spring_length), "role %d arm length" % role)
		expect(is_equal_approx(rig.spring_arm.margin, profile.camera_spring_margin), "role %d arm margin" % role)
		var probe := rig.spring_arm.shape as SphereShape3D
		expect(probe != null, "role %d camera probe exists" % role)
		if probe:
			expect(is_equal_approx(probe.radius, profile.camera_probe_radius), "role %d probe radius" % role)


func test_server_canonical_muzzle_and_camera_match_profile() -> void:
	var profile := CharacterBodyRegistry.stats_for(2)
	var actor := await _spawn(2, CharacterBodyStats.Role.SERVER)
	var yaw := 0.37
	var pitch := -0.21
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var expected_muzzle := (
		actor.global_position
		+ Vector3(0.0, profile.eye_height, 0.0)
		+ basis * profile.muzzle_offset
	)
	var expected_camera := (
		actor.global_position
		+ Vector3(0.0, profile.camera_pivot_height, 0.0)
		+ basis * Vector3(profile.camera_shoulder_offset, 0.0, profile.camera_spring_length)
	)
	var muzzle := ServerCombat.canonical_muzzle(actor.global_position, yaw, pitch, actor.body_stats)
	var camera := ServerCombat.camera_origin(actor.global_position, yaw, pitch, actor.body_stats)
	expect(muzzle.is_equal_approx(expected_muzzle), "server muzzle uses the profile")
	expect(camera.is_equal_approx(expected_camera), "server camera uses the profile")
	expect(
		ServerCombat.canonical_muzzle(actor.global_position, yaw, pitch).is_equal_approx(expected_muzzle),
		"legacy helper defaults to the class-0 profile"
	)


func test_server_visual_processing_is_disabled() -> void:
	var actor := await _spawn(2, CharacterBodyStats.Role.SERVER)
	var visual := actor.get_node("Visual") as Node3D
	expect(visual.process_mode == Node.PROCESS_MODE_DISABLED, "server Visual is disabled")
	expect(actor.get_node("CameraPivot/SpringArm3D/Camera3D").current == false, "server camera is not current")


func test_snapshot_row_stays_eighteen_bytes() -> void:
	expect(NetProtocol.SNAPSHOT_HEADER_BYTES == 6, "snapshot header stays 6 B")
	expect(NetProtocol.SNAPSHOT_ROW_BYTES == 18, "snapshot row stays 18 B")
	var entries: Array = []
	for i in NetProtocol.MAX_PLAYERS:
		entries.append({
			"id": i, "pos": Vector3(i, 0, 0), "yaw": 0.0, "state": 0,
			"vel": Vector3.ZERO, "on_floor": true, "hp": 100, "ack": i,
		})
	var packet := NetProtocol.encode_snapshot(1, entries)
	expect(packet.size() == 294, "16-actor snapshot stays 294 B (got %d)" % packet.size())
	var decoded := NetProtocol.decode_snapshot(packet)
	expect(decoded.get("entries", []).size() == NetProtocol.MAX_PLAYERS, "snapshot still decodes 16 rows")


func test_malformed_profile_validation_fails() -> void:
	var bad_radius := CharacterBodyStats.new()
	bad_radius.capsule_radius = -0.1
	expect(not bad_radius.validate().is_empty(), "negative capsule radius is rejected")

	var bad_hurtbox := CharacterBodyStats.new()
	bad_hurtbox.hurtbox_offset = 2.0
	expect(not bad_hurtbox.validate().is_empty(), "hurtbox outside the capsule is rejected")

	var bad_probe := CharacterBodyStats.new()
	bad_probe.camera_probe_radius = 0.2
	expect(not bad_probe.validate().is_empty(), "probe radius larger than the spring margin is rejected")

	var bad_class := CharacterBodyStats.new()
	bad_class.class_id = 9
	expect(not bad_class.validate().is_empty(), "unknown class id is rejected")


func test_no_headshot_or_head_volume_path() -> void:
	var actor := await _spawn(0, CharacterBodyStats.Role.LOCAL)
	expect(actor.get_node_or_null("HeadHurtbox") == null, "no HeadHurtbox node")
	var hurtboxes := actor.find_children("BodyHurtbox", "Area3D", true, false)
	expect(hurtboxes.size() == 1, "exactly one body hurtbox")
	expect((hurtboxes[0] as Area3D).collision_layer == 8, "body hurtbox remains on the hurtbox layer")
