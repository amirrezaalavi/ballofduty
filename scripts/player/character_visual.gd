class_name CharacterVisual
extends Node3D
## Drives the Quaternius mannequin from replicated movement state.
## Purely presentational: no gameplay reads anything from here.
##
## The Standard library has forward locomotion only, so backwards still plays
## the walk cycle reversed (and never sprints). Air uses the real jump clips:
## Jump_Start on takeoff, Jump_Loop while airborne, Jump_Land on touchdown.

@export var walk_threshold: float = 0.25
@export var sprint_threshold: float = 6.4

@onready var body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var animation_player: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var character: Node3D = get_node_or_null("Character") as Node3D
@onready var gun_mount: Node3D = get_node_or_null("GunMount") as Node3D

const GUN_STILL := Vector3(0.06, 0.56, -0.22)
const GUN_MOVE := Vector3(0.16, 0.52, -0.14)

var _state: StringName = &""
var _camera_rig: CameraRig
var _was_airborne: bool = false
var _landed_at_msec: int = 0


func _ready() -> void:
	_camera_rig = get_parent().get_node_or_null("CameraPivot") as CameraRig
	if gun_mount:
		gun_mount.rotation.y = 0.12
	if animation_player == null:
		push_warning("CharacterVisual: no AnimationPlayer found")
		return
	for loop_name: StringName in [&"Walk", &"Sprint", &"Jump", &"Pistol_Idle"]:
		var animation := animation_player.get_animation(loop_name)
		if animation:
			animation.loop_mode = Animation.LOOP_LINEAR
	_play(&"Pistol_Idle")


func _process(_delta: float) -> void:
	if animation_player == null or body == null:
		return

	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := flat.length()
	# Local direction: forward is -Z, so +Z means moving backwards.
	var local: Vector3 = body.transform.basis.inverse() * flat
	var backwards := local.z > 0.3
	var airborne := not body.is_on_floor()

	var next: StringName = &"Idle"
	if airborne:
		next = &"Jump"
	elif _landing_pose_active():
		next = &"Jump_Land"
	elif speed < walk_threshold:
		if _camera_rig != null and _camera_rig.is_scoped():
			next = &"Pistol_Aim"
		else:
			next = &"Pistol_Idle"
	elif backwards:
		next = &"WalkBack"
	elif speed > sprint_threshold:
		next = &"Sprint"
	else:
		next = &"Walk"

	if airborne and not _was_airborne:
		# Takeoff: snap into the jump start, then the loop takes over.
		animation_player.play(&"Jump_Start", 0.08)
		_state = &"Jump"
	elif next != _state:
		match next:
			&"WalkBack":
				animation_player.play(&"Walk", 0.15)
			&"Jump_Land":
				animation_player.play(&"Jump_Land", 0.05)
			&"Jump":
				# Short hops may still be inside Jump_Start; only restart it if needed.
				if animation_player.current_animation != &"Jump_Start":
					animation_player.play(&"Jump", 0.1)
			&"Pistol_Idle":
				animation_player.play(&"Pistol_Idle", 0.15)
			&"Pistol_Aim":
				animation_player.play(&"Pistol_Aim_Neutral", 0.12)
			_:
				animation_player.play(next, 0.15)
		_state = next
	elif _state == &"Jump" and animation_player.current_animation == &"Jump_Start":
		# Jump_Start finished while still airborne: hold the loop, not the last start frame.
		var start_len := animation_player.get_animation(&"Jump_Start").length
		if animation_player.current_animation_position >= start_len - 0.1:
			animation_player.play(&"Jump", 0.1)

	_update_speed_scale(next, speed)

	if _was_airborne and not airborne:
		_landed_at_msec = Time.get_ticks_msec()
	_was_airborne = airborne

	_update_air_lean(airborne)
	_update_gun_pitch()
	_update_gun_position(next, _delta)


func _update_speed_scale(state: StringName, speed: float) -> void:
	match state:
		&"Walk":
			animation_player.speed_scale = clampf(speed / 5.6, 0.6, 1.6)
		&"WalkBack":
			# Reverse the cycle so backwards steps read as backwards. No fast mode.
			animation_player.speed_scale = -clampf(speed / 5.6, 0.6, 1.0)
		&"Sprint":
			animation_player.speed_scale = clampf(speed / 7.56, 0.8, 1.3)
		&"Jump":
			animation_player.speed_scale = 1.0
		&"Pistol_Idle", &"Pistol_Aim", &"Jump_Land", &"Idle":
			animation_player.speed_scale = 1.0
		_:
			animation_player.speed_scale = 1.0


func _landing_pose_active() -> bool:
	return Time.get_ticks_msec() - _landed_at_msec < 250


func _update_air_lean(airborne: bool) -> void:
	if character == null:
		return
	var target := 0.0
	if airborne:
		# Subtle lean on top of the real jump clip.
		target = clampf(-body.velocity.y * 0.02, -0.2, 0.25)
	character.rotation.x = lerpf(character.rotation.x, target, 0.18)


func _update_gun_position(state: StringName, delta: float) -> void:
	if gun_mount == null:
		return
	# Hands hold the gun up front when still; dock it at the shoulder on the move.
	var target := GUN_STILL if state in [&"Pistol_Idle", &"Pistol_Aim"] else GUN_MOVE
	var weight := clampf(delta * 10.0, 0.0, 1.0)
	gun_mount.position = gun_mount.position.lerp(target, weight)
	gun_mount.rotation.y = lerpf(gun_mount.rotation.y, 0.0 if target == GUN_STILL else 0.12, weight)


func _update_gun_pitch() -> void:
	if gun_mount == null or _camera_rig == null:
		return
	# The mount inherits yaw from Visual; copy the camera pitch (plus recoil)
	# so vertical aim moves the gun instead of leaving it fixed.
	gun_mount.rotation.x = _camera_rig.rotation.x


func _play(state: StringName) -> void:
	_state = state
	animation_player.play(state, 0.0)
