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
	on_floor_override: int = -1
) -> void:
	if stats == null:
		push_error("LocomotionComponent.stats is not assigned")
		return
	last_input = input

	var on_floor := body.is_on_floor()
	if on_floor_override >= 0:
		on_floor = on_floor_override != 0
	# Input move is local (x = strafe, y = forward/back); convert to world using
	# the body yaw so the server can replay from its own authoritative rotation.
	var wish_dir := body.transform.basis * Vector3(input.move.x, 0.0, input.move.y)
	wish_dir.y = 0.0

	var horizontal := horizontal_velocity(body.velocity, wish_dir, input.sprint, on_floor, delta)
	var vertical := vertical_velocity(body.velocity.y, input.jump, on_floor, delta)
	body.velocity = Vector3(horizontal.x, vertical, horizontal.z)
	body.move_and_slide()


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
	if sprint:
		target_speed *= stats.sprint_multiplier
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
	return maxf(current_y - stats.gravity * delta, -stats.max_fall_speed)
