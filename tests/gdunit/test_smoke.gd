extends BodTestSuite
## Headless project invariants: settings, autoloads, scenes, player rig, arena.

const REQUIRED_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "sprint", "reload", "scoreboard", "pause", "debug_overlay",
	"fire", "aim",
]


func test_project_settings() -> void:
	expect(
		int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")) == 30,
		"physics tick is 30 Hz"
	)
	expect(
		String(ProjectSettings.get_setting("rendering/renderer/rendering_method")) == "gl_compatibility",
		"renderer is Compatibility"
	)
	expect(
		bool(ProjectSettings.get_setting("physics/common/physics_interpolation")),
		"physics interpolation is enabled"
	)


func test_input_and_autoloads() -> void:
	for action: String in REQUIRED_ACTIONS:
		expect(InputMap.has_action(action), "input action exists: " + action)
	var expected := {
		"Settings": "*res://scripts/autoload/settings.gd",
		"EventBus": "*res://scripts/autoload/event_bus.gd",
		"AudioManager": "*res://scripts/autoload/audio_manager.gd",
		"NetworkManager": "*res://scripts/networking/network_manager.gd",
		"GameManager": "*res://scripts/game/game_manager.gd",
	}
	for name: String in expected:
		expect(
			String(ProjectSettings.get_setting("autoload/" + name, "")) == expected[name],
			"%s autoload is registered" % name
		)


func test_scenes_have_required_nodes() -> void:
	_check_scene("res://scenes/main.tscn", ["Arena", "Player", "HUD", "DebugOverlay"])
	_check_scene("res://scenes/characters/player.tscn",
		["CollisionShape3D", "Visual", "BodyHurtbox", "HeadHurtbox", "CameraPivot",
		"LocomotionComponent", "InputHandler", "HealthComponent"])
	_check_scene("res://scenes/maps/arena_greybox.tscn",
		["Floor", "Ramp", "PlatformA", "PlatformB", "CameraWall", "Spawn01", "Spawn08"])
	_check_scene("res://scenes/maps/arena_nature.tscn",
		["Floor", "PlatformA", "PlatformB", "CameraWall", "Props", "DummyA", "DummyB", "DummyC", "Spawn01", "Spawn08"])
	_check_scene("res://scenes/characters/training_dummy.tscn",
		["HealthComponent", "BodyHurtbox", "HeadHurtbox"])


func test_arena_spawns() -> void:
	var nature := (load("res://scenes/maps/arena_nature.tscn") as PackedScene).instantiate()
	var spawns: Array[Vector3] = []
	for child in nature.get_children():
		if child is Marker3D and child.name.begins_with("Spawn"):
			spawns.append((child as Marker3D).position)
	expect(spawns.size() == 8, "nature arena has 8 spawn points")
	var too_close := false
	for a in spawns.size():
		for b in range(a + 1, spawns.size()):
			if spawns[a].distance_to(spawns[b]) < 15.0:
				too_close = true
	expect(not too_close, "all spawn points are at least 15 m apart")
	nature.free()


func test_movement_tuning() -> void:
	var stats := load("res://resources/players/default_player.tres") as PlayerStats
	expect(stats != null, "default PlayerStats resource loads")
	if stats:
		expect(is_equal_approx(stats.move_speed, 1.05), "walk speed is 1.05 m/s for the 0.82 m avatar")
		expect(is_equal_approx(stats.sprint_multiplier, 2.62), "sprint multiplier gives 2.75 m/s")
		expect(stats.turn_speed > 0.0, "body turn speed is data-driven")
		expect(is_equal_approx(stats.jump_velocity, 7.34), "jump velocity is the +10% value")
		expect(stats.ground_acceleration > stats.air_acceleration, "air control is weaker than ground control")


func test_player_rig() -> void:
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate()

	var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
	expect(spring_arm != null, "player has SpringArm3D")
	if spring_arm:
		expect(spring_arm.collision_mask == 1, "spring arm collides with world only")

	var body_hurtbox := player.get_node_or_null("BodyHurtbox") as Area3D
	var head_hurtbox := player.get_node_or_null("HeadHurtbox") as Area3D
	expect(body_hurtbox != null and body_hurtbox.collision_layer == 8, "body hurtbox on hurtbox layer")
	expect(head_hurtbox != null and head_hurtbox.collision_layer == 8, "head hurtbox on hurtbox layer")

	if body_hurtbox:
		var body_shape := body_hurtbox.get_node("CollisionShape3D") as CollisionShape3D
		var capsule := body_shape.shape as CapsuleShape3D
		expect(capsule != null, "body hurtbox is a capsule")
		if capsule:
			expect(is_equal_approx(capsule.height, 0.58), "body hurtbox excludes the head")
			var body_bottom := body_shape.position.y - capsule.height * 0.5
			expect(body_bottom >= -0.01, "body hurtbox does not extend below the floor")

	if head_hurtbox:
		var head_shape := head_hurtbox.get_node("CollisionShape3D") as CollisionShape3D
		var sphere := head_shape.shape as SphereShape3D
		expect(sphere != null, "head hurtbox is a sphere")
		if sphere:
			var head_top := head_shape.position.y + sphere.radius
			expect(head_top <= 0.9, "head hurtbox is inside the 0.82 m avatar silhouette")

	expect(player.collision_mask == 1, "player collides with world only (no predicted body collisions)")

	var physical_shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
	expect(
		physical_shape != null and is_equal_approx(physical_shape.height, 0.82)
		and is_equal_approx(physical_shape.radius, 0.19),
		"character is 40% smaller (0.82 m capsule)"
	)
	var character := player.get_node_or_null("Visual/Character")
	expect(character != null, "animated character model is present")
	if character:
		var animation_player := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
		expect(animation_player != null, "character has an AnimationPlayer")
		expect(character.find_child("Skeleton3D", true, false) is Skeleton3D, "character is a skinned rig")
		if animation_player:
			for clip: StringName in [&"Idle_A", &"Walking_A", &"Walking_Backwards", &"Running_HoldingRifle", &"Running_Strafe_Left", &"Running_Strafe_Right", &"Jump_Start", &"Jump_Idle", &"Jump_Land", &"Ranged_2H_Aiming", &"Ranged_2H_Shoot", &"Ranged_2H_Reload", &"Hit_A", &"Death_A"]:
				expect(animation_player.has_animation(clip), "character has %s clip" % clip)

	var locomotion := player.get_node_or_null("LocomotionComponent") as LocomotionComponent
	expect(locomotion != null and locomotion.stats != null, "locomotion component has PlayerStats")
	expect(player.get_node_or_null("InputHandler") is InputHandler, "input handler is present")
	expect(player.get_node_or_null("HealthComponent") is HealthComponent, "health component is present")
	var weapon := player.get_node_or_null("WeaponController") as WeaponController
	expect(weapon != null and weapon.stats != null, "weapon controller has WeaponStats")
	if weapon and weapon.stats:
		expect(weapon.stats.projectile_scene != null, "weapon projectile scene is assigned")
	var rig := player.get_node_or_null("CameraPivot") as CameraRig
	expect(rig != null, "camera pivot uses CameraRig")
	if rig:
		expect(is_equal_approx(rig.spring_length, 2.3), "camera spring length is data-driven")
		expect(rig.scope_fov < rig.normal_fov, "scope FOV is tighter than hip FOV")
		expect(
			(rig.normal_fov - rig.scope_fov) >= (75.0 - 55.0) * 1.2,
			"scope zoom is at least 20% stronger than before"
		)
	var gun_mount := player.get_node_or_null("Visual/GunMount") as Node3D
	expect(gun_mount != null, "gun is mounted on the character visual")
	if gun_mount:
		var gun_local: Vector3 = gun_mount.position
		expect(
			absf(gun_local.x) < 0.45 and gun_local.y > 0.3 and gun_local.y < 0.9,
			"gun sits close to the body, not floating"
		)
		expect(
			player.get_node_or_null("Visual/GunMount/Muzzle") != null,
			"muzzle follows the gun mount"
		)
	player.free()


func test_greybox_ramp_collision() -> void:
	var arena := (load("res://scenes/maps/arena_greybox.tscn") as PackedScene).instantiate()
	var ramp_shape := arena.get_node("Ramp/CollisionShape3D") as CollisionShape3D
	expect(ramp_shape != null, "ramp has a collision shape")
	if ramp_shape:
		var ramp_box := ramp_shape.shape as BoxShape3D
		expect(ramp_box != null, "ramp uses a box shape")
		if ramp_box:
			expect(ramp_box.size == Vector3(10, 0.5, 10), "ramp collision matches the 10x10 m mesh")
	arena.free()


func _check_scene(path: String, required_nodes: Array) -> void:
	var packed := load(path) as PackedScene
	expect(packed != null, "scene loads: " + path)
	if packed == null:
		return
	var instance := packed.instantiate()
	for node_name: String in required_nodes:
		expect(instance.get_node_or_null(node_name) != null, "%s has node %s" % [path, node_name])
	instance.free()
