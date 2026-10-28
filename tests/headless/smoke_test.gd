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

	_check_scene("res://scenes/main.tscn", ["Arena", "Player"])
	_check_scene("res://scenes/characters/player.tscn",
		["CollisionShape3D", "Visual", "BodyHurtbox", "HeadHurtbox", "CameraPivot"])
	_check_scene("res://scenes/maps/arena_greybox.tscn", ["Floor", "Ramp", "Spawn01", "Spawn08"])

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
				_check(is_equal_approx(capsule.height, 1.2), "body hurtbox excludes the head")
				var body_bottom := body_shape.position.y - capsule.height * 0.5
				_check(body_bottom >= -0.01, "body hurtbox does not extend below the floor")

		if head_hurtbox:
			var head_shape := head_hurtbox.get_node("CollisionShape3D") as CollisionShape3D
			var sphere := head_shape.shape as SphereShape3D
			_check(sphere != null, "head hurtbox is a sphere")
			if sphere:
				var head_top := head_shape.position.y + sphere.radius
				_check(head_top <= 1.75, "head hurtbox is inside the avatar silhouette")

		_check_equal(player.collision_mask, 1, "player collides with world only (no predicted body collisions)")
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
