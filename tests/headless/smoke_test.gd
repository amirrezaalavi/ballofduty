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
	for action: String in REQUIRED_ACTIONS:
		_check(InputMap.has_action(action), "input action exists: " + action)

	_check_scene("res://scenes/main.tscn", ["Arena", "Player"])
	_check_scene("res://scenes/characters/player.tscn",
		["CollisionShape3D", "BodyHurtbox", "HeadHurtbox", "CameraPivot"])
	_check_scene("res://scenes/maps/arena_greybox.tscn", ["Floor", "Spawn01", "Spawn08"])

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
		player.free()

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
