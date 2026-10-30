class_name LocomotionComponent
extends Node
## Deterministic movement step. No global Input, no camera, no rendering:
## the client and the CP4b server replay call exactly this code with the same
## PlayerInputFrame and fixed delta.

@export var stats: PlayerStats

var jump_buffer_left: float = 0.0
var coyote_left: float = 0.0
var last_input: PlayerInputFrame


## on_floor_override: -1 uses the body's cached state. CP4b passes 0/1 for the
## first replayed frame because a teleport has not run move_and_slide yet, so
## is_on_floor() still describes the pre-correction pose.
func simulate(
	body: CharacterBody3D,
	input: PlayerInputFrame,
	delta: float,
	on_floor_override: int = -1,
	view_yaw: float = NAN
) -> void:
	if stats == null:
		push_error("LocomotionComponent.stats is not assigned")
		return
	last_input = input

	var on_floor := body.is_on_floor()
	if on_floor_override >= 0:
		on_floor = on_floor_override != 0

	# Movement is camera-relative when a view yaw is supplied (CP4b). The body
	# faces the movement direction, not the camera; aiming locks facing to the
	# view so scoped players strafe instead of turning.
	var basis := body.transform.basis
	if not is_nan(view_yaw):
		basis = Basis(Vector3.UP, view_yaw)
	var wish_dir := basis * Vector3(input.move.x, 0.0, input.move.y)
	wish_dir.y = 0.0
	var wish_len := minf(wish_dir.length(), 1.0)
	var move_dir := wish_dir.normalized() if wish_len > 0.0001 else Vector3.ZERO

	var alignment := 0.0
	if input.aim and not is_nan(view_yaw):
		# ADS/fire locks facing to the camera even while standing still. The
		# upper-body modifier still aims within its clamp while the body turns.
		_turn_body_toward(body, view_yaw, delta)
		alignment = 1.0 if wish_len > 0.0001 else 0.0
	elif wish_len > 0.0001:
		var target_yaw := atan2(-move_dir.x, -move_dir.z)
		_turn_body_toward(body, target_yaw, delta)
		# Turn in place first: only translate as the facing aligns with the
		# intended direction. This removes the sliding-sideways look.
		alignment = maxf(0.0, (-body.transform.basis.z).dot(move_dir))

	var horizontal := horizontal_velocity(
		body.velocity, move_dir * (wish_len * alignment), input.sprint, on_floor, delta
	)
	var vertical := vertical_velocity(body.velocity.y, input.jump, on_floor, delta)
	body.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	body.move_and_slide()


## Deterministic turn. A 180-degree turn is ambiguous: the client's full-float
## view yaw and the server's quantized yaw can fall on opposite sides of PI and
## rotate the body in opposite directions, which prediction then fights with
## large corrections. Snap the tie to +PI so both sides choose the same path.
func _turn_body_toward(body: CharacterBody3D, target_yaw: float, delta: float) -> void:
	var diff := wrapf(target_yaw - body.rotation.y, -PI, PI)
	if absf(absf(diff) - PI) < 0.02:
		diff = PI
	var step := clampf(diff, -stats.turn_speed * delta, stats.turn_speed * delta)
	body.rotation.y = wrapf(body.rotation.y + step, -PI, PI)


## Pure horizontal step, unit-testable without a physics world.
func horizontal_velocity(
	current: Vector3,
	wish_dir: Vector3,
	sprint: bool,
	on_floor: bool,
	delta: float
) -> Vector3:
	var direction := Vector3(wish_dir.x, 0.0, wish_dir.z)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	var target_speed := stats.move_speed
	if sprint and on_floor:
		target_speed *= stats.sprint_multiplier
	elif not on_floor:
		# Sprint cannot start or accelerate in the air; keep existing momentum
		# so a sprint jump does not brake mid-flight.
		var current_speed := Vector2(current.x, current.z).length()
		target_speed = maxf(
			target_speed, minf(current_speed, stats.move_speed * stats.sprint_multiplier)
		)
	var target := direction * target_speed
	var acceleration := stats.ground_acceleration if on_floor else stats.air_acceleration
	var horizontal := Vector3(current.x, 0.0, current.z)
	return horizontal.move_toward(target, acceleration * delta)


## Pure vertical step with coyote time and jump buffering. Requires the
## on_floor flag from the last physics move; safe before the first move.
func vertical_velocity(current_y: float, jump_pressed: bool, on_floor: bool, delta: float) -> float:
	if on_floor:
		coyote_left = stats.coyote_time
	else:
		coyote_left = maxf(0.0, coyote_left - delta)

	if jump_pressed:
		jump_buffer_left = stats.jump_buffer_time
	else:
		jump_buffer_left = maxf(0.0, jump_buffer_left - delta)

	if jump_buffer_left > 0.0 and coyote_left > 0.0:
		jump_buffer_left = 0.0
		coyote_left = 0.0
		return stats.jump_velocity

	if on_floor and current_y <= 0.0:
		return 0.0
	# Asymmetric fall: the rise uses base gravity, the descent uses the
	# multiplier so jumps feel snappy without changing the apex.
	var gravity := stats.gravity
	if current_y <= 0.0:
		gravity *= maxf(stats.fall_gravity_multiplier, 1.0)
	return maxf(current_y - gravity * delta, -stats.max_fall_speed)


## Analytic helpers used by the tuning tests and the editor notes.
## Apex = v^2 / (2g); full symmetric airtime = 2v / g.
static func jump_apex(velocity: float, gravity: float) -> float:
	if gravity <= 0.0:
		return 0.0
	return velocity * velocity / (2.0 * gravity)


static func jump_rise_time(velocity: float, gravity: float) -> float:
	if gravity <= 0.0:
		return 0.0
	return velocity / gravity


static func fall_time(height: float, gravity: float) -> float:
	if gravity <= 0.0 or height <= 0.0:
		return 0.0
	return sqrt(2.0 * height / gravity)
