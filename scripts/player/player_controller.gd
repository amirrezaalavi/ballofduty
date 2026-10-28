class_name PlayerController
extends CharacterBody3D
## CP0/CP1 movement stub: 30 Hz physics simulation, render-rate mouse look.
##
## Deliberate design notes:
## - Movement is simulated in _physics_process (project physics tick = 30 Hz).
##   Do NOT add a second accumulator in _process; that would double-step.
## - Mouse look is applied from _unhandled_input at render rate, so aiming never
##   feels stepped at 30 Hz.
## - Camera/aim is presentation until CP4b, when the tick's input frame becomes
##   the authoritative input sent to the server.

@export_group("Movement")
@export var move_speed: float = 5.6
@export var sprint_multiplier: float = 1.35
@export var ground_acceleration: float = 60.0
@export var air_acceleration: float = 12.0
@export var jump_velocity: float = 7.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0022
@export var normal_fov: float = 75.0
@export var scope_fov: float = 55.0
@export var scope_speed: float = 400.0
@export var pitch_min: float = -1.35
@export var pitch_max: float = 0.95

@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D

var _pitch: float = 0.0
var _gravity: float = 22.0


func _ready() -> void:
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 22.0))
	camera.fov = normal_fov
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, pitch_min, pitch_max)
		camera_pivot.rotation.x = _pitch
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("pause") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)

	var target_fov := scope_fov if Input.is_action_pressed("aim") else normal_fov
	camera.fov = move_toward(camera.fov, target_fov, scope_speed * delta)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)
	direction.y = 0.0
	if direction.length_squared() > 1.0:
		direction = direction.normalized()

	var speed := move_speed
	if Input.is_action_pressed("sprint"):
		speed *= sprint_multiplier

	var target := direction * speed
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)

	move_and_slide()
