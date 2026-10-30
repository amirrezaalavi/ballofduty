extends BodTestSuite
## CP1 locomotion checks: pure component math, no physics world required.

const DT := 1.0 / 30.0

var _stats: PlayerStats


func before_test() -> void:
	_stats = load("res://resources/players/default_player.tres") as PlayerStats
	expect(_stats != null, "PlayerStats loads")


func test_ground_travel_and_speed() -> void:
	var loco := auto_free(LocomotionComponent.new()) as LocomotionComponent
	loco.stats = _stats

	# 3 seconds of held forward input, starting from rest.
	var velocity := Vector3.ZERO
	var distance := 0.0
	for _i in 90:
		velocity = loco.horizontal_velocity(velocity, Vector3(1, 0, 0), false, true, DT)
		distance += velocity.length() * DT
	print("  travel_3s=%.2f m  speed=%.2f m/s" % [distance, velocity.length()])
	expect(is_equal_approx(velocity.length(), _stats.move_speed), "ground speed settles at move_speed")
	expect(distance > 2.95 and distance < 3.2,
		"3 s travel distance is ~3.15 m at 1.05 m/s (got %.2f)" % distance)


func test_diagonal_is_not_faster() -> void:
	var loco := auto_free(LocomotionComponent.new()) as LocomotionComponent
	loco.stats = _stats
	var cardinal := Vector3.ZERO
	var diagonal := Vector3.ZERO
	for _i in 30:
		cardinal = loco.horizontal_velocity(cardinal, Vector3(1, 0, 0), false, true, DT)
		diagonal = loco.horizontal_velocity(diagonal, Vector3(1, 0, 1), false, true, DT)
	print("  cardinal=%.2f m/s  diagonal=%.2f m/s" % [cardinal.length(), diagonal.length()])
	expect(
		absf(cardinal.length() - diagonal.length()) < 0.001,
		"diagonal input is not faster (%.3f vs %.3f)" % [cardinal.length(), diagonal.length()]
	)


func test_release_and_sprint() -> void:
	var loco := auto_free(LocomotionComponent.new()) as LocomotionComponent
	loco.stats = _stats
	var velocity := Vector3.ZERO
	for _i in 30:
		velocity = loco.horizontal_velocity(velocity, Vector3(1, 0, 0), false, true, DT)
	for _i in 10:
		velocity = loco.horizontal_velocity(velocity, Vector3.ZERO, false, true, DT)
	expect(velocity.length() < 0.001, "release stops the player at 60 m/s²")

	var sprint := Vector3.ZERO
	for _i in 30:
		sprint = loco.horizontal_velocity(sprint, Vector3.FORWARD, true, true, DT)
	print("  sprint=%.2f m/s" % sprint.length())
	expect(
		is_equal_approx(sprint.length(), _stats.move_speed * _stats.sprint_multiplier),
		"sprint reaches move_speed * sprint_multiplier"
	)

	# Sprint must not start or accelerate in the air.
	var airborne := Vector3.ZERO
	for _i in 30:
		airborne = loco.horizontal_velocity(airborne, Vector3.FORWARD, true, false, DT)
	print("  airborne sprint=%.2f m/s" % airborne.length())
	expect(
		airborne.length() <= _stats.move_speed + 0.01,
		"sprint does not accelerate in the air (%.2f m/s)" % airborne.length()
	)


func test_jump_apex() -> void:
	var loco := auto_free(LocomotionComponent.new()) as LocomotionComponent
	loco.stats = _stats
	var takeoff := loco.vertical_velocity(0.0, true, true, DT)
	expect(is_equal_approx(takeoff, _stats.jump_velocity), "jump starts at jump_velocity")

	var height := 0.0
	var vy := takeoff
	var peak := 0.0
	for _i in 90:
		height += vy * DT
		peak = maxf(peak, height)
		vy = maxf(vy - _stats.gravity * DT, -_stats.max_fall_speed)
	print("  jump_apex=%.2f m" % peak)
	expect(peak > 1.30 and peak < 1.40, "L1 jump apex stays ~1.35 m (got %.2f)" % peak)


func test_jump_curve_derivation() -> void:
	var analytic := LocomotionComponent.jump_apex(_stats.jump_velocity, _stats.gravity)
	var rise := LocomotionComponent.jump_rise_time(_stats.jump_velocity, _stats.gravity)
	var fall := LocomotionComponent.fall_time(
		1.35, _stats.gravity * _stats.fall_gravity_multiplier
	)
	print("  jump_analytic=%.2f m rise=%.3f s fall=%.3f s" % [analytic, rise, fall])
	expect(analytic > 1.15 and analytic < 1.25, "v^2/2g gives the ~1.20 m analytic apex")
	expect(rise > 0.24 and rise < 0.29, "v/g gives a ~0.27 s rise")
	expect(fall < rise, "asymmetric fall is faster than the rise (%.3f < %.3f)" % [fall, rise])
	expect(fall + rise < 0.60, "full jump is snappier than the old 0.67 s arc")


func test_asymmetric_fall_and_terminal_velocity() -> void:
	# Sample finely so the discrete peak is not lost between 30 Hz ticks.
	const FINE_DT := 1.0 / 240.0
	var loco := auto_free(LocomotionComponent.new()) as LocomotionComponent
	loco.stats = _stats
	var takeoff := loco.vertical_velocity(0.0, true, true, FINE_DT)
	var height := 0.0
	var vy := takeoff
	var elapsed := 0.0
	var peak := 0.0
	var peak_at := 0.0
	var lowest := 0.0
	while elapsed < 2.0:
		height += vy * FINE_DT
		if height > peak:
			peak = height
			peak_at = elapsed
		vy = loco.vertical_velocity(vy, false, false, FINE_DT)
		elapsed += FINE_DT
		lowest = minf(lowest, vy)
		if elapsed > 0.05 and height <= 0.0:
			break
	print("  airtime=%.3f s rise=%.3f s fall=%.3f s" % [
		elapsed, peak_at, elapsed - peak_at,
	])
	expect(elapsed - peak_at < peak_at, "descent is shorter than the rise")
	expect(elapsed < 0.60, "full jump is snappier than the old 0.67 s arc")
	expect(lowest >= -_stats.max_fall_speed - 0.001, "terminal velocity is respected")

	# Falling from height reaches terminal velocity and never exceeds it.
	var terminal_vy := 0.0
	for _i in 240:
		terminal_vy = loco.vertical_velocity(terminal_vy, false, false, FINE_DT)
	expect(is_equal_approx(terminal_vy, -_stats.max_fall_speed),
		"a long fall settles at -max_fall_speed (%.2f)" % terminal_vy)


func test_jump_assists() -> void:
	# Coyote time: jump one tick after walking off a ledge.
	var loco := auto_free(LocomotionComponent.new()) as LocomotionComponent
	loco.stats = _stats
	loco.vertical_velocity(0.0, false, true, DT)
	expect(
		is_equal_approx(loco.vertical_velocity(0.0, true, false, DT), _stats.jump_velocity),
		"coyote time allows a jump just after leaving the floor"
	)

	# Coyote expires.
	var late := auto_free(LocomotionComponent.new()) as LocomotionComponent
	late.stats = _stats
	late.vertical_velocity(0.0, false, true, DT)
	for _i in 5:
		late.vertical_velocity(-1.0, false, false, DT)
	expect(late.vertical_velocity(-1.0, true, false, DT) < _stats.jump_velocity, "coyote time expires")

	# Jump buffer: press in the air, land, jump fires on landing.
	var buffered := auto_free(LocomotionComponent.new()) as LocomotionComponent
	buffered.stats = _stats
	buffered.vertical_velocity(-1.0, true, false, DT)
	expect(
		is_equal_approx(buffered.vertical_velocity(-1.0, false, true, DT), _stats.jump_velocity),
		"jump buffer fires on landing"
	)


func test_settings_persist() -> void:
	var script := load("res://scripts/autoload/settings.gd")
	var first := auto_free(script.new()) as Node
	first.settings_path = "user://cp1_settings_test.cfg"
	first.sensitivity = 0.0031
	first.invert_y = true
	first.master_volume = 0.5
	first.save_settings()

	var second := auto_free(script.new()) as Node
	second.settings_path = first.settings_path
	second.load_settings()
	expect(is_equal_approx(second.sensitivity, 0.0031), "sensitivity persists to disk")
	expect(second.invert_y, "invert-Y persists to disk")
	expect(is_equal_approx(second.master_volume, 0.5), "master volume persists to disk")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(first.settings_path))
	print("  settings persistence=ok")
