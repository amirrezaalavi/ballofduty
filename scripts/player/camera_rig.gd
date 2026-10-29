class_name CameraRig
extends Node3D
## Third-person spring-arm camera. Yaw lives on the player body (so movement and
## aim share a frame); this node owns pitch, shoulder framing and scope FOV.

@export_group("Framing")
@export var spring_length: float = 2.3
@export var normal_fov: float = 75.0
@export var scope_fov: float = 48.0
@export var scope_transition_degrees_per_second: float = 300.0
@export var pitch_min: float = -1.35
@export var pitch_max: float = 0.25

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var pitch: float = 0.0
var recoil_pitch: float = 0.0

var _settings: Node


func _ready() -> void:
	spring_arm.spring_length = spring_length
	camera.fov = normal_fov
	_settings = get_node_or_null("/root/Settings")


## Applies pitch and returns the yaw delta the caller should apply to the body.
## Sensitivity scaling in scope lives here so the feel stays consistent.
func look(relative: Vector2, scoped: bool) -> float:
	var settings := _get_settings()
	var sensitivity := float(settings.sensitivity) if settings else 0.0022
	if scoped:
		sensitivity *= float(settings.scope_sensitivity_scale) if settings else 0.7
	var invert := -1.0 if settings and bool(settings.invert_y) else 1.0

	pitch = clampf(pitch - relative.y * sensitivity * invert, pitch_min, pitch_max)
	rotation.x = pitch + recoil_pitch
	return -relative.x * sensitivity


func update_aim(aiming: bool, delta: float) -> void:
	var target := scope_fov if aiming else normal_fov
	camera.fov = move_toward(camera.fov, target, scope_transition_degrees_per_second * delta)
	recoil_pitch = lerpf(recoil_pitch, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	rotation.x = pitch + recoil_pitch


func is_scoped() -> bool:
	return camera.fov < normal_fov - 0.5


func add_recoil(degrees: float) -> void:
	recoil_pitch += deg_to_rad(degrees)


func get_camera_distance() -> float:
	return spring_arm.get_hit_length()


func _get_settings() -> Node:
	if _settings == null or not is_instance_valid(_settings):
		_settings = get_node_or_null("/root/Settings")
	return _settings
