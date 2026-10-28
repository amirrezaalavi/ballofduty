extends SceneTree
## Headless project invariants. Run:
##   tools/godot --headless --path . --script tests/headless/smoke_test.gd
## Exits non-zero on failure.

const REQUIRED_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right",
	"jump", "sprint", "reload", "scoreboard", "pause", "debug_overlay",
	"fire", "aim",
]

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	_check_equal(
		int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")), 30,
		"physics tick is 30 Hz"
	)
	_check_equal(
		String(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"gl_compatibility",
		"renderer is Compatibility"
	)
	_check(
		bool(ProjectSettings.get_setting("physics/common/physics_interpolation")),
		"physics interpolation is enabled"
	)
	for action: String in REQUIRED_ACTIONS:
		_check(InputMap.has_action(action), "input action exists: " + action)

	_check_equal(
		String(ProjectSettings.get_setting("autoload/Settings", "")),
		"*res://scripts/autoload/settings.gd",
		"Settings autoload is registered"
	)
	_check_equal(
		String(ProjectSettings.get_setting("autoload/EventBus", "")),
		"*res://scripts/autoload/event_bus.gd",
		"EventBus autoload is registered"
	)
	_check_equal(
		String(ProjectSettings.get_setting("autoload/AudioManager", "")),
		"*res://scripts/autoload/audio_manager.gd",
		"AudioManager autoload is registered"
	)

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

	var nature_scene := load("res://scenes/maps/arena_nature.tscn") as PackedScene
	if nature_scene:
		var nature := nature_scene.instantiate()
		var spawns: Array[Vector3] = []
		for child in nature.get_children():
			if child is Marker3D and child.name.begins_with("Spawn"):
				spawns.append((child as Marker3D).position)
		_check(spawns.size() == 8, "nature arena has 8 spawn points")
		var too_close := false
		for a in spawns.size():
			for b in range(a + 1, spawns.size()):
				if spawns[a].distance_to(spawns[b]) < 15.0:
					too_close = true
		_check(not too_close, "all spawn points are at least 15 m apart")
		nature.free()

	var stats := load("res://resources/players/default_player.tres") as PlayerStats
	_check(stats != null, "default PlayerStats resource loads")
	if stats:
		_check(is_equal_approx(stats.move_speed, 5.6), "move speed comes from PlayerStats")
		_check(is_equal_approx(stats.jump_velocity, 7.34), "jump velocity is the +10% value")
		_check(stats.ground_acceleration > stats.air_acceleration, "air control is weaker than ground control")

	var player_scene := load("res://scenes/characters/player.tscn") as PackedScene
	if player_scene:
		var player := player_scene.instantiate()
		var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
		_check(spring_arm != null, "player has SpringArm3D")
		if spring_arm:
			_check_equal(spring_arm.collision_mask, 1, "spring arm collides with world only")
		var body_hurtbox := player.get_node_or_null("BodyHurtbox") as Area3D
		var head_hurtbox := player.get_node_or_null("HeadHurtbox") as Area3D
		_check(body_hurtbox != null and body_hurtbox.collision_layer == 8, "body hurtbox on hurtbox layer")
		_check(head_hurtbox != null and head_hurtbox.collision_layer == 8, "head hurtbox on hurtbox layer")

		if body_hurtbox:
			var body_shape := body_hurtbox.get_node("CollisionShape3D") as CollisionShape3D
			var capsule := body_shape.shape as CapsuleShape3D
			_check(capsule != null, "body hurtbox is a capsule")
			if capsule:
				_check(is_equal_approx(capsule.height, 0.96), "body hurtbox excludes the head")
				var body_bottom := body_shape.position.y - capsule.height * 0.5
				_check(body_bottom >= -0.01, "body hurtbox does not extend below the floor")

		if head_hurtbox:
			var head_shape := head_hurtbox.get_node("CollisionShape3D") as CollisionShape3D
			var sphere := head_shape.shape as SphereShape3D
			_check(sphere != null, "head hurtbox is a sphere")
			if sphere:
				var head_top := head_shape.position.y + sphere.radius
				_check(head_top <= 1.4, "head hurtbox is inside the 1.36 m avatar silhouette")

		_check_equal(player.collision_mask, 1, "player collides with world only (no predicted body collisions)")

		var physical_shape := (player.get_node("CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D
		_check(
			physical_shape != null and is_equal_approx(physical_shape.height, 1.36)
			and is_equal_approx(physical_shape.radius, 0.32),
			"character is 20% smaller (1.36 m capsule)"
		)
		var character := player.get_node_or_null("Visual/Character")
		_check(character != null, "animated character model is present")
		if character:
			var animation_player := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
			_check(animation_player != null, "character has an AnimationPlayer")
			if animation_player:
				_check(animation_player.has_animation(&"idle"), "character has idle animation")
				_check(animation_player.has_animation(&"walk"), "character has walk animation")
				_check(animation_player.has_animation(&"sprint"), "character has sprint animation")

		var locomotion := player.get_node_or_null("LocomotionComponent") as LocomotionComponent
		_check(locomotion != null and locomotion.stats != null, "locomotion component has PlayerStats")
		_check(player.get_node_or_null("InputHandler") is InputHandler, "input handler is present")
		_check(player.get_node_or_null("HealthComponent") is HealthComponent, "health component is present")
		var weapon := player.get_node_or_null("WeaponController") as WeaponController
		_check(weapon != null and weapon.stats != null, "weapon controller has WeaponStats")
		if weapon and weapon.stats:
			_check(weapon.stats.projectile_scene != null, "weapon projectile scene is assigned")
		var rig := player.get_node_or_null("CameraPivot") as CameraRig
		_check(rig != null, "camera pivot uses CameraRig")
		if rig:
			_check(is_equal_approx(rig.spring_length, 3.6), "camera spring length is data-driven")
			_check(rig.scope_fov < rig.normal_fov, "scope FOV is tighter than hip FOV")
		player.free()

	var arena_scene := load("res://scenes/maps/arena_greybox.tscn") as PackedScene
	if arena_scene:
		var arena := arena_scene.instantiate()
		var ramp_shape := arena.get_node("Ramp/CollisionShape3D") as CollisionShape3D
		_check(ramp_shape != null, "ramp has a collision shape")
		if ramp_shape:
			var ramp_box := ramp_shape.shape as BoxShape3D
			_check(ramp_box != null, "ramp uses a box shape")
			if ramp_box:
				_check(ramp_box.size == Vector3(10, 0.5, 10), "ramp collision matches the 10x10 m mesh")
		arena.free()

	print("smoke: %d checks, %d failure(s)" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_scene(path: String, required_nodes: Array) -> void:
	var packed := load(path) as PackedScene
	_check(packed != null, "scene loads: " + path)
	if packed == null:
		return
	var instance := packed.instantiate()
	for node_name: String in required_nodes:
		_check(instance.get_node_or_null(node_name) != null, "%s has node %s" % [path, node_name])
	instance.free()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (got %s, expected %s)" % [label, actual, expected])
