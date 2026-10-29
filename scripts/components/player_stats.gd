class_name PlayerStats
extends Resource
## Data-driven movement tuning. Shared by the client and the headless server so
## prediction and authority use exactly the same numbers.

@export_group("Movement")
## Tuned for the 0.82 m avatar: ~1 body length/s walking, ~2.5 sprinting.
@export_range(0.5, 12.0, 0.05) var move_speed: float = 1.0
@export_range(1.0, 4.0, 0.01) var sprint_multiplier: float = 2.5
@export_range(10.0, 200.0, 1.0) var ground_acceleration: float = 60.0
@export_range(1.0, 60.0, 0.5) var air_acceleration: float = 12.0

@export_group("Jump")
@export_range(1.0, 15.0, 0.1) var jump_velocity: float = 7.0
@export_range(5.0, 60.0, 0.5) var gravity: float = 22.0
@export_range(10.0, 80.0, 1.0) var max_fall_speed: float = 30.0
@export_range(0.0, 0.3, 0.01) var coyote_time: float = 0.1
@export_range(0.0, 0.3, 0.01) var jump_buffer_time: float = 0.12

@export_group("Presentation")
@export_range(1.0, 30.0, 0.5) var visual_turn_speed: float = 14.0
## How fast the body rotates toward the movement direction (rad/s). Yaw is
## independent of the camera, so this is what makes turns read as turns.
@export_range(2.0, 40.0, 0.5) var turn_speed: float = 14.0
