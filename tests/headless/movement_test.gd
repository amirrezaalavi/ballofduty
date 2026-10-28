extends SceneTree
## CP1 locomotion checks. Pure component math, no physics world required.
## Run: tools/godot --headless --path . --script tests/headless/movement_test.gd

const DT := 1.0 / 30.0

var _failures: int = 0
var _checks: int = 0


func _init() -> void:
	var stats := load("res://resources/players/default_player.tres") as PlayerStats
	_check(stats != null, "PlayerStats loads")
	if stats == null:
		_finish()
		return

	_test_horizontal(stats)
	_test_jump(stats)
	_test_jump_assists(stats)
	_test_settings()

	_finish()


func _test_horizontal(stats: PlayerStats) -> void:
	var loco := LocomotionComponent.new()
	loco.stats = stats

	# 3 seconds of held forward input, starting from rest.
	var velocity := Vector3.ZERO
	var distance := 0.0
	for _i in 90:
		velocity = loco.horizontal_velocity(velocity, Vector3(1, 0, 0), false, true, DT)
		distance += velocity.length() * DT
	_check(is_equal_approx(velocity.length(), stats.move_speed), "ground speed settles at move_speed")
	_check(distance > 16.0 and distance < 17.0, "3 s travel distance is ~16.6 m (got %.2f)" % distance)
	print("  travel_3s=%.2f m  speed=%.2f m/s" % [distance, velocity.length()])

	# Diagonal input must not be faster than cardinal input.
	var cardinal := Vector3.ZERO
	var diagonal := Vector3.ZERO
	for _i in 30:
		cardinal = loco.horizontal_velocity(cardinal, Vector3(1, 0, 0), false, true, DT)
		diagonal = loco.horizontal_velocity(diagonal, Vector3(1, 0, 1), false, true, DT)
	_check(
		absf(cardinal.length() - diagonal.length()) < 0.001,
		"diagonal input is not faster (%.3f vs %.3f)" % [cardinal.length(), diagonal.length()]
	)
	print("  cardinal=%.2f m/s  diagonal=%.2f m/s" % [cardinal.length(), diagonal.length()])

	# Release: ground acceleration stops the player in a few ticks.
	for _i in 10:
		velocity = loco.horizontal_velocity(velocity, Vector3.ZERO, false, true, DT)
	_check(velocity.length() < 0.001, "release stops the player at 60 m/s²")

	# Sprint multiplier.
	var sprint := Vector3.ZERO
	for _i in 30:
		sprint = loco.horizontal_velocity(sprint, Vector3.FORWARD, true, true, DT)
	_check(
		is_equal_approx(sprint.length(), stats.move_speed * stats.sprint_multiplier),
		"sprint reaches move_speed * sprint_multiplier"
	)
	print("  sprint=%.2f m/s" % sprint.length())

	loco.free()


func _test_jump(stats: PlayerStats) -> void:
	var loco := LocomotionComponent.new()
	loco.stats = stats

	var takeoff := loco.vertical_velocity(0.0, true, true, DT)
	_check(is_equal_approx(takeoff, stats.jump_velocity), "jump starts at jump_velocity")

	var height := 0.0
	var vy := takeoff
	var peak := 0.0
	for _i in 90:
		height += vy * DT
		peak = maxf(peak, height)
		vy = maxf(vy - stats.gravity * DT, -stats.max_fall_speed)
	_check(peak > 1.25 and peak < 1.45, "jump apex is ~1.35 m (got %.2f)" % peak)
	print("  jump_apex=%.2f m" % peak)

	loco.free()


func _test_jump_assists(stats: PlayerStats) -> void:
	# Coyote time: jump one tick after walking off a ledge.
	var loco := LocomotionComponent.new()
	loco.stats = stats
	loco.vertical_velocity(0.0, false, true, DT)
	var coyote_jump := loco.vertical_velocity(0.0, true, false, DT)
	_check(
		is_equal_approx(coyote_jump, stats.jump_velocity),
		"coyote time allows a jump just after leaving the floor"
	)
	loco.free()

	# Coyote expires.
	var late := LocomotionComponent.new()
	late.stats = stats
	late.vertical_velocity(0.0, false, true, DT)
	for _i in 5:
		late.vertical_velocity(-1.0, false, false, DT)
	var late_jump := late.vertical_velocity(-1.0, true, false, DT)
	_check(late_jump < stats.jump_velocity, "coyote time expires")
	late.free()

	# Jump buffer: press in the air, land, jump fires on landing.
	var buffered := LocomotionComponent.new()
	buffered.stats = stats
	buffered.vertical_velocity(-1.0, true, false, DT)
	var landing_jump := buffered.vertical_velocity(-1.0, false, true, DT)
	_check(
		is_equal_approx(landing_jump, stats.jump_velocity),
		"jump buffer fires on landing"
	)
	buffered.free()


func _test_settings() -> void:
	var script := load("res://scripts/autoload/settings.gd")
	var first := script.new() as Node
	first.settings_path = "user://cp1_settings_test.cfg"
	first.sensitivity = 0.0031
	first.invert_y = true
	first.master_volume = 0.5
	first.save_settings()

	var second := script.new() as Node
	second.settings_path = first.settings_path
	second.load_settings()
	_check(is_equal_approx(second.sensitivity, 0.0031), "sensitivity persists to disk")
	_check(second.invert_y, "invert-Y persists to disk")
	_check(is_equal_approx(second.master_volume, 0.5), "master volume persists to disk")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(first.settings_path))
	first.free()
	second.free()
	print("  settings persistence=ok")


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)


func _finish() -> void:
	print("movement: %d checks, %d failure(s)" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
