class_name CharacterVisual
extends Node3D
## Drives the Quaternius mannequin from replicated movement state.
## Purely presentational: no gameplay reads anything from here.
##
## The Standard library has forward locomotion only, so backwards still plays
## the walk cycle reversed (and never sprints). Air uses the real jump clips:
## Jump_Start on takeoff, Jump_Loop while airborne, Jump_Land on touchdown.

@export var walk_threshold: float = 0.1
@export var sprint_threshold: float = 1.9

@onready var body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var animation_player: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var character: Node3D = get_node_or_null("Character") as Node3D
@onready var gun_mount: Node3D = get_node_or_null("GunMount") as Node3D

const GUN_STILL := Vector3(0.06, 0.56, -0.22)
const GUN_MOVE := Vector3(0.16, 0.52, -0.14)
const HAND_BONE := "DEF-hand.R"
const UPPER_BODY_BONES := [
	"DEF-spine", "DEF-neck", "DEF-head", "DEF-shoulder",
	"DEF-upper_arm", "DEF-forearm", "DEF-hand",
]

var _state: StringName = &""
var _camera_rig: CameraRig
var _was_airborne: bool = false
var _landed_at_msec: int = 0
var _gun_attached := false
var _shot_player: AnimationPlayer
var _hold_player: AnimationPlayer
var _hand_skeleton: Skeleton3D
var _hand_bone: int = -1
var _gun_socket: Node3D
## Remote ghosts set this from the snapshot state byte; >= 0 skips local
## derivation and plays the mapped clip (0 still, 1 walk, 2 sprint, 3 air).
var force_anim: int = -1


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
	_setup_overlays.call_deferred()
	_setup_hand_attachment.call_deferred()
	var weapon := body.get_node_or_null("WeaponController")
	if weapon and weapon.has_signal("shot_fired"):
		weapon.shot_fired.connect(_on_weapon_shot)


## Upper-body overlays: a looping Pistol_Aim_Neutral keeps the character in a
## weapon-ready pose while the legs walk, and Pistol_Shoot kicks on fire. Both
## are filtered copies with lower-body tracks removed, so the main AnimationPlayer
## still owns locomotion.
func _setup_overlays() -> void:
	if animation_player == null:
		return
	var hold_clip := _filtered_clip(&"Pistol_Aim_Neutral")
	if hold_clip:
		hold_clip.loop_mode = Animation.LOOP_LINEAR
		_hold_player = _add_overlay("UpperBodyHold", &"Pistol_Aim_Neutral", hold_clip)
		_hold_player.play(&"Pistol_Aim_Neutral", 0.2)

	var shot_clip := _filtered_clip(&"Pistol_Shoot")
	if shot_clip:
		shot_clip.loop_mode = Animation.LOOP_NONE
		_shot_player = _add_overlay("ShotOverlay", &"Pistol_Shoot", shot_clip)
		_shot_player.animation_finished.connect(_on_shot_finished)


func _filtered_clip(clip_name: StringName) -> Animation:
	var clip := animation_player.get_animation(clip_name)
	if clip == null:
		return null
	var filtered := clip.duplicate() as Animation
	for i in range(filtered.get_track_count() - 1, -1, -1):
		var path := String(filtered.track_get_path(i))
		var keep := false
		for bone: String in UPPER_BODY_BONES:
			if path.contains(bone):
				keep = true
				break
		if not keep:
			filtered.remove_track(i)
	return filtered


func _add_overlay(node_name: String, clip_name: StringName, clip: Animation) -> AnimationPlayer:
	var library := AnimationLibrary.new()
	library.add_animation(clip_name, clip)
	var overlay := AnimationPlayer.new()
	overlay.name = node_name
	body.add_child(overlay)
	overlay.add_animation_library("", library)
	var root := animation_player.get_node(animation_player.root_node)
	overlay.root_node = overlay.get_path_to(root)
	return overlay


func _on_weapon_shot(_origin: Vector3, _direction: Vector3) -> void:
	if _shot_player == null or force_anim >= 0:
		return
	_shot_player.play(&"Pistol_Shoot", 0.02)


func _on_shot_finished(_name: StringName) -> void:
	if _shot_player:
		_shot_player.stop()


## Follow the right hand with an external-skeleton attachment, so the gun does
## not float while the arm swings. The attachment lives outside the scaled GLB
## hierarchy and keeps the gun at true world scale.
func _setup_hand_attachment() -> void:
	if gun_mount == null or character == null or _gun_attached:
		return
	var skeleton := character.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var hand := skeleton.find_bone(HAND_BONE)
	if hand < 0:
		push_warning("CharacterVisual: %s bone not found" % HAND_BONE)
		return

	var attachment := BoneAttachment3D.new()
	attachment.name = "GunHand"
	attachment.use_external_skeleton = true
	attachment.override_pose = false
	body.add_child(attachment)
	# Resolve the skeleton only after the attachment is in the tree; absolute
	# paths cannot be looked up before that. The bone name must be assigned after
	# the external skeleton, otherwise bone_idx stays -1 and the gun never follows.
	attachment.external_skeleton = attachment.get_path_to(skeleton)
	attachment.bone_name = HAND_BONE
	attachment.bone_idx = hand

	var socket := Node3D.new()
	socket.name = "GripSocket"
	attachment.add_child(socket)

	# The bone pose is available after one process frame; place the grip at the
	# wrist and keep the barrel along the character's forward axis.
	await get_tree().process_frame
	if not is_instance_valid(gun_mount) or not is_instance_valid(skeleton):
		return
	var hand_xf := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
	socket.global_transform = Transform3D(
		Basis(Vector3.UP, body.rotation.y + 0.12),
		hand_xf.origin + Vector3(0.0, 0.02, 0.0)
	)
	gun_mount.reparent(socket, true)
	gun_mount.transform = Transform3D()
	_gun_socket = socket
	_hand_skeleton = skeleton
	_hand_bone = hand
	_gun_attached = true


func _process(_delta: float) -> void:
	if animation_player == null or body == null:
		return
	_update_gun_attachment()

	if force_anim >= 0:
		_play_forced(force_anim)
		_update_gun_pitch()
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
			animation_player.speed_scale = clampf(speed / 1.0, 0.6, 1.6)
		&"WalkBack":
			# Reverse the cycle so backwards steps read as backwards. No fast mode.
			animation_player.speed_scale = -clampf(speed / 1.0, 0.6, 1.0)
		&"Sprint":
			animation_player.speed_scale = clampf(speed / 2.5, 0.8, 1.3)
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


## Keep the gun at the hand, but do not inherit the wrist's roll/swing: a
## carried weapon should point where the player is looking, not spin with every
## arm animation. Position follows the hand exactly; orientation is derived from
## view yaw (local) or body facing (remotes).
func _update_gun_attachment() -> void:
	if not _gun_attached or _gun_socket == null or _hand_skeleton == null or _hand_bone < 0:
		return
	var hand_xf := _hand_skeleton.global_transform * _hand_skeleton.get_bone_global_pose(_hand_bone)
	var yaw := body.rotation.y
	var pitch := 0.0
	if body is PlayerController:
		var pc := body as PlayerController
		if pc.net_role == PlayerController.NetRole.LOCAL:
			yaw = pc.view_yaw
			if _camera_rig:
				pitch = _camera_rig.rotation.x
	var basis := Basis(Vector3.UP, yaw + 0.12) * Basis(Vector3.RIGHT, pitch)
	_gun_socket.global_transform = Transform3D(basis, hand_xf.origin + Vector3(0.0, 0.02, 0.0))


func _update_gun_position(state: StringName, delta: float) -> void:
	if gun_mount == null or _gun_attached:
		return
	# Hands hold the gun up front when still; dock it at the shoulder on the move.
	var target := GUN_STILL if state in [&"Pistol_Idle", &"Pistol_Aim"] else GUN_MOVE
	var weight := clampf(delta * 10.0, 0.0, 1.0)
	gun_mount.position = gun_mount.position.lerp(target, weight)
	gun_mount.rotation.y = lerpf(gun_mount.rotation.y, 0.0 if target == GUN_STILL else 0.12, weight)


func _update_gun_pitch() -> void:
	if gun_mount == null or _camera_rig == null or _gun_attached:
		return
	# The mount inherits yaw from Visual; copy the camera pitch (plus recoil)
	# so vertical aim moves the gun instead of leaving it fixed.
	gun_mount.rotation.x = _camera_rig.rotation.x


func _play_forced(net_state: int) -> void:
	var clip := &"Pistol_Idle"
	match net_state:
		NetProtocol.AnimState.WALK:
			clip = &"Walk"
		NetProtocol.AnimState.SPRINT:
			clip = &"Sprint"
		NetProtocol.AnimState.AIR:
			clip = &"Jump"
	# Compare against the player, not _state: the local state machine may have
	# left _state == clip while the player itself is stopped.
	if animation_player.current_animation != clip:
		animation_player.play(clip, 0.15)
	_state = clip
	animation_player.speed_scale = 1.0


func _play(state: StringName) -> void:
	_state = state
	animation_player.play(state, 0.0)
