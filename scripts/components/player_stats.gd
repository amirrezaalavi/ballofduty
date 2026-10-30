class_name PlayerStats
extends Resource
## Data-driven movement tuning. Shared by the client and the headless server so
## prediction and authority use exactly the same numbers.

@export_group("Movement")
## Tuned for the 0.82 m avatar: 1.05 m/s walking, 2.75 m/s sprinting.
@export_range(0.5, 12.0, 0.05) var move_speed: float = 1.05
@export_range(1.0, 4.0, 0.01) var sprint_multiplier: float = 2.62
@export_range(10.0, 200.0, 1.0) var ground_acceleration: float = 60.0
@export_range(1.0, 60.0, 0.5) var air_acceleration: float = 18.0

@export_group("Jump")
## L1 jump curve. Apex = v^2 / (2g): 9.03^2 / (2 * 34) = 1.20 m analytic,
## ~1.35 m with the 30 Hz explicit step. Rise = v / g = 0.267 s. The fall uses
## gravity * fall_gravity_multiplier (45.9 m/s^2), so a full jump lasts ~0.51 s
## instead of the old 0.67 s while keeping the same +10 % apex.
@export_range(1.0, 15.0, 0.1) var jump_velocity: float = 9.03
@export_range(5.0, 80.0, 0.5) var gravity: float = 34.0
## > 1 makes the descent snappier than the rise (platformer feel).
@export_range(1.0, 2.5, 0.05) var fall_gravity_multiplier: float = 1.35
@export_range(10.0, 80.0, 1.0) var max_fall_speed: float = 30.0
@export_range(0.0, 0.3, 0.01) var coyote_time: float = 0.12
@export_range(0.0, 0.3, 0.01) var jump_buffer_time: float = 0.15

@export_group("Presentation")
@export_range(1.0, 30.0, 0.5) var visual_turn_speed: float = 14.0
## How fast the body rotates toward the movement direction (rad/s). Yaw is
## independent of the camera, so this is what makes turns read as turns.
@export_range(2.0, 40.0, 0.5) var turn_speed: float = 14.0
