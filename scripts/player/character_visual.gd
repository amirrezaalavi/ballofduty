class_name CharacterVisual
extends Node3D
## KayKit Adventurers visual layer.
##
## The old Quaternius UAL mannequin is replaced by five 23-bone Rig_Medium
## characters. Everything here is presentational: gameplay and hit authority
## never read this node.
##
## Layers:
##   * main AnimationPlayer (inside the Character scene) - full-body locomotion
##     and death, from NetProtocol.AnimState (local) or force_anim (remotes);
##   * UpperBodyHold - looping Ranged_2H_Aiming overlay, upper body only;
##   * ShotOverlay / ReloadOverlay / HitOverlay - one-shot upper-body reactions.
##
## The gun stays welded to handslot.r through an external-skeleton
## BoneAttachment3D. Orientation comes from the body yaw (plus the Phase 0
## additive chest aim), never from the camera directly.

const SCALE := 0.32244
const HAND_BONE := "handslot.r"
const SPINE_BONE := "chest"
const GUN_YAW_OFFSET := 0.08
const HAND_OFFSET := Vector3(0.0, 0.02, 0.0)
const SHOT_SPEED := 6.5

const VARIANT_SCENES := [
	preload("res://assets/kaykit/adventurers/knight.scn"),
	preload("res://assets/kaykit/adventurers/mage.scn"),
	preload("res://assets/kaykit/adventurers/rogue.scn"),
	preload("res://assets/kaykit/adventurers/rogue_hooded.scn"),
	preload("res://assets/kaykit/adventurers/barbarian.scn"),
]
const VARIANT_NAMES := ["Knight", "Mage", "Rogue", "Rogue_Hooded", "Barbarian"]
const MAIN_LIBRARY := preload("res://assets/kaykit/animations/kaykit_medium.res")
const UPPER_LIBRARY := preload("res://assets/kaykit/animations/kaykit_upper.res")

const LOOP_CLIPS := [
	"Idle_A", "Idle_B", "Walking_A", "Walking_B", "Walking_C", "Walking_Backwards",
	"Running_A", "Running_B", "Running_HoldingRifle",
	"Running_Strafe_Left", "Running_Strafe_Right", "Jump_Idle",
	"Ranged_2H_Aiming", "Ranged_2H_Shooting",
]

@export var walk_threshold: float = 0.1
@export var sprint_threshold: float = 1.9

@onready var body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var gun_mount: Node3D = get_node_or_null("GunMount") as Node3D

var character: Node3D
var animation_player: AnimationPlayer
var _hold_player: AnimationPlayer
var _shot_player: AnimationPlayer
var _reload_player: AnimationPlayer
var _hit_player: AnimationPlayer

## Remote ghosts set this from the snapshot state byte; >= 0 skips local
## derivation and plays the mapped clip (0 still, 1 walk, 2 sprint, 3 air).
var force_anim: int = -1

var _camera_rig: CameraRig
var _state: StringName = &""
var _variant: int = 0
var _was_airborne: bool = false
var _landed_at_msec: int = 0
var _dead: bool = false
var _death_marker: Node3D
var _last_health: int = 100
var _last_position := Vector3.ZERO
var _motion_local := Vector3.ZERO

var _gun_attached := false
var _hand_skeleton: Skeleton3D
var _hand_bone: int = -1
var _gun_socket: Node3D
var _spine_bone: int = -1
var _grip_offset := Transform3D()
var _grip_calibrated: bool = false
var _aim_weight: float = 0.0
var _aim_was_active: bool = false


## Deterministic across every client: net_id 0 (the local host) is the Knight,
## remotes and bots draw from the same five-character pool.
static func variant_index_for(net_id: int) -> int:
	return absi(net_id) % VARIANT_SCENES.size()


func _ready() -> void:
	# Run after the AnimationPlayers so the additive chest aim is the last word.
	process_priority = 100
	_camera_rig = get_parent().get_node_or_null("CameraPivot") as CameraRig
	character = get_node_or_null("Character") as Node3D
	_build_death_marker()
	_bind_character()
	_setup_overlays.call_deferred()
	_setup_hand_attachment.call_deferred()
	_last_position = body.global_position if body else Vector3.ZERO
	var health: HealthComponent = null
	var weapon: Node = null
	if body:
		health = body.get_node_or_null("HealthComponent") as HealthComponent
		weapon = body.get_node_or_null("WeaponController")
	if health:
		_last_health = health.current
		if not health.health_changed.is_connected(_on_health_changed):
			health.health_changed.connect(_on_health_changed)
	if weapon:
		if weapon.has_signal("shot_fired") and not weapon.shot_fired.is_connected(_on_weapon_shot):
			weapon.shot_fired.connect(_on_weapon_shot)
		if weapon.has_signal("reload_state_changed") and not weapon.reload_state_changed.is_connected(_on_reload_state_changed):
			weapon.reload_state_changed.connect(_on_reload_state_changed)


func _process(delta: float) -> void:
	if body == null:
		return
	_ensure_variant()
	if animation_player == null:
		return
	_update_motion(delta)
	_update_death_state()
	if _dead:
		_update_gun_attachment()
		return
	_update_aim()
	_maybe_calibrate_grip()
	_update_gun_attachment()

	if force_anim >= 0:
		_play_forced(force_anim)
		_update_gun_pitch()
		return

	_update_locomotion()
	_update_gun_pitch()


# --- character variants ---------------------------------------------------

func _ensure_variant() -> void:
	if body == null:
		return
	var wanted := variant_index_for(body.net_id)
	if wanted == _variant and character != null:
		return
	_swap_character(wanted)


func _swap_character(index: int) -> void:
	index = clampi(index, 0, VARIANT_SCENES.size() - 1)
	_detach_gun()
	if character != null:
		character.free()
	character = VARIANT_SCENES[index].instantiate() as Node3D
	character.name = "Character"
	character.scale = Vector3.ONE * SCALE
	character.rotation.y = PI
	add_child(character)
	_variant = index
	_bind_character()
	_setup_hand_attachment.call_deferred()


func _bind_character() -> void:
	if character == null:
		character = get_node_or_null("Character") as Node3D
	if character == null:
		push_warning("CharacterVisual: no Character node")
		return
	animation_player = character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		push_warning("CharacterVisual: no AnimationPlayer found")
		return
	if animation_player.get_animation_library_list().is_empty():
		animation_player.add_animation_library("", MAIN_LIBRARY)
	for clip_name: String in LOOP_CLIPS:
		var clip := animation_player.get_animation(clip_name)
		if clip:
			clip.loop_mode = Animation.LOOP_LINEAR
	_play(&"Idle_A", 0.0)
	_state = &"Idle_A"


# --- overlays -------------------------------------------------------------

func _setup_overlays() -> void:
	if animation_player == null:
		return
	if _hold_player == null:
		_hold_player = _add_overlay("UpperBodyHold")
		_hold_player.speed_scale = 1.0
	if _shot_player == null:
		_shot_player = _add_overlay("ShotOverlay")
		_shot_player.speed_scale = SHOT_SPEED
		if not _shot_player.animation_finished.is_connected(_on_shot_finished):
			_shot_player.animation_finished.connect(_on_shot_finished)
	if _reload_player == null:
		_reload_player = _add_overlay("ReloadOverlay")
		_reload_player.speed_scale = 1.0
		if not _reload_player.animation_finished.is_connected(_on_reload_finished):
			_reload_player.animation_finished.connect(_on_reload_finished)
	if _hit_player == null:
		_hit_player = _add_overlay("HitOverlay")
		_hit_player.speed_scale = 1.0
		if not _hit_player.animation_finished.is_connected(_on_hit_finished):
			_hit_player.animation_finished.connect(_on_hit_finished)


func _add_overlay(node_name: String) -> AnimationPlayer:
	var overlay := AnimationPlayer.new()
	overlay.name = node_name
	overlay.process_priority = 50
	body.add_child(overlay)
	overlay.add_animation_library("", UPPER_LIBRARY)
	var root := animation_player.get_node_or_null(animation_player.root_node)
	if root:
		overlay.root_node = overlay.get_path_to(root)
	return overlay


func _action_playing() -> bool:
	return (
		(_shot_player != null and _shot_player.is_playing())
		or (_reload_player != null and _reload_player.is_playing())
		or (_hit_player != null and _hit_player.is_playing())
	)


func _stop_actions() -> void:
	for overlay in [_shot_player, _reload_player, _hit_player]:
		if overlay and overlay.is_playing():
			overlay.stop()


# --- weapon reactions -----------------------------------------------------

func _on_weapon_shot(_origin: Vector3, _direction: Vector3) -> void:
	if _shot_player == null or force_anim >= 0 or _dead:
		return
	if _reload_player and _reload_player.is_playing():
		return
	if _hit_player and _hit_player.is_playing():
		return
	if _hold_player:
		_hold_player.stop()
	_shot_player.speed_scale = SHOT_SPEED
	_shot_player.play(&"Ranged_2H_Shoot", 0.02)


func _on_shot_finished(_name: StringName) -> void:
	if _shot_player:
		_shot_player.stop()


func _on_reload_state_changed(reloading: bool) -> void:
	if reloading:
		if _reload_player == null or _dead:
			return
		if _hit_player and _hit_player.is_playing():
			return
		_stop_actions()
		if _hold_player:
			_hold_player.stop()
		_reload_player.speed_scale = 1.0
		_reload_player.play(&"Ranged_2H_Reload", 0.05)
	elif _reload_player:
		_reload_player.stop()


func _on_reload_finished(_name: StringName) -> void:
	if _reload_player:
		_reload_player.stop()


func _on_hit_finished(_name: StringName) -> void:
	if _hit_player:
		_hit_player.stop()


func _on_health_changed(current: int, _maximum: int) -> void:
	if current < _last_health:
		if current <= 0:
			_play_death()
		elif not _dead:
			_play_hit()
	elif current > _last_health and _dead:
		_revive()
	_last_health = current


func _play_hit() -> void:
	if _hit_player == null or _dead:
		return
	_stop_actions()
	if _hold_player:
		_hold_player.stop()
	_hit_player.play(&"Hit_A", 0.03)


func _play_death() -> void:
	if _dead or animation_player == null:
		return
	_dead = true
	_stop_actions()
	if _hold_player:
		_hold_player.stop()
	animation_player.speed_scale = 1.0
	animation_player.play(&"Death_A", 0.12)
	_state = &"Death_A"
	if _death_marker:
		_death_marker.visible = true


func _revive() -> void:
	if not _dead:
		return
	_dead = false
	if _death_marker:
		_death_marker.visible = false
	_play(&"Idle_A", 0.15)


## Flat red pool + a faint red shell over the body. Presentational only; it
## marks a corpse for both the local player and remote ghosts.
func _build_death_marker() -> void:
	if _death_marker != null or body == null:
		return
	_death_marker = Node3D.new()
	_death_marker.name = "DeathMarker"
	_death_marker.visible = false
	# The visual can be constructed before the body has entered the tree; defer
	# so the marker always ends up parented (an unparented node would leak).
	body.call_deferred("add_child", _death_marker)

	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.38
	disc_mesh.bottom_radius = 0.38
	disc_mesh.height = 0.012
	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(0.72, 0.03, 0.04, 0.55)
	disc_mat.emission_enabled = true
	disc_mat.emission = Color(0.75, 0.04, 0.05)
	disc_mat.emission_energy_multiplier = 0.7
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = disc_mat
	disc.position = Vector3(0.0, 0.02, 0.0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_death_marker.add_child(disc)

	var shell_mesh := CapsuleMesh.new()
	shell_mesh.radius = 0.24
	shell_mesh.height = 0.80
	var shell_mat := StandardMaterial3D.new()
	shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mat.albedo_color = Color(0.85, 0.06, 0.05, 0.15)
	shell_mat.emission_enabled = true
	shell_mat.emission = Color(0.8, 0.05, 0.04)
	shell_mat.emission_energy_multiplier = 0.5
	shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shell := MeshInstance3D.new()
	shell.mesh = shell_mesh
	shell.material_override = shell_mat
	shell.position = Vector3(0.0, 0.40, 0.0)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_death_marker.add_child(shell)


func _update_death_state() -> void:
	var pc := body as PlayerController
	if pc == null:
		return
	if _dead:
		if not pc.dead and not pc.net_dead:
			_revive()
		return
	if pc.dead or pc.net_dead:
		_play_death()


# --- locomotion -----------------------------------------------------------

func _update_motion(delta: float) -> void:
	if body == null:
		return
	var world_flat: Vector3
	var pc := body as PlayerController
	if pc != null and pc.net_role == PlayerController.NetRole.REMOTE:
		var moved: Vector3 = body.global_position - _last_position
		world_flat = Vector3(moved.x, 0.0, moved.z) / maxf(delta, 0.0001)
	else:
		world_flat = Vector3(body.velocity.x, 0.0, body.velocity.z)
	_last_position = body.global_position
	_motion_local = body.transform.basis.inverse() * world_flat


func _update_locomotion() -> void:
	var speed := _motion_local.length()
	var local := _motion_local
	var backwards := local.z > 0.3
	var lateral := absf(local.x) > maxf(0.25, absf(local.z) * 1.2)
	var airborne := not body.is_on_floor()
	var just_left := airborne and not _was_airborne
	var just_landed := not airborne and _was_airborne
	if just_landed:
		_landed_at_msec = Time.get_ticks_msec()
	_was_airborne = airborne

	if just_left:
		_play(&"Jump_Start", 0.08)
		animation_player.speed_scale = 1.0
		return
	if airborne:
		if _state == &"Jump_Start":
			var start := animation_player.get_animation(&"Jump_Start")
			var start_length: float = start.length if start else 0.6
			if animation_player.current_animation_position >= start_length - 0.08:
				_play(&"Jump_Idle", 0.1)
		elif _state != &"Jump_Idle":
			_play(&"Jump_Idle", 0.1)
		animation_player.speed_scale = 1.0
		return
	if _landing_pose_active():
		if _state != &"Jump_Land":
			_play(&"Jump_Land", 0.05)
		animation_player.speed_scale = 1.0
		return

	var next: StringName
	if speed < walk_threshold:
		next = &"Idle_A"
	elif backwards:
		next = &"Walking_Backwards"
	elif lateral:
		next = &"Running_Strafe_Right" if local.x > 0.0 else &"Running_Strafe_Left"
	elif speed > sprint_threshold:
		next = &"Running_HoldingRifle"
	else:
		next = &"Walking_A"

	if next != _state or animation_player.current_animation != next:
		var fade := 0.15 if next != &"Idle_A" else 0.18
		_play(next, fade)
	_update_speed_scale(speed)


func _update_speed_scale(speed: float) -> void:
	match _state:
		&"Walking_A":
			animation_player.speed_scale = clampf(speed / 1.05, 0.6, 1.6)
		&"Walking_Backwards":
			animation_player.speed_scale = clampf(speed / 1.05, 0.6, 1.2)
		&"Running_Strafe_Left", &"Running_Strafe_Right":
			animation_player.speed_scale = clampf(speed / 1.6, 0.6, 1.2)
		&"Running_HoldingRifle", &"Running_A":
			animation_player.speed_scale = clampf(speed / 2.75, 0.8, 1.3)
		_:
			animation_player.speed_scale = 1.0


func _landing_pose_active() -> bool:
	return Time.get_ticks_msec() - _landed_at_msec < 250


func _play(state: StringName, fade: float) -> void:
	if animation_player == null:
		return
	if animation_player.current_animation != state:
		animation_player.play(state, fade)
	_state = state


func _play_forced(net_state: int) -> void:
	if animation_player == null:
		return
	var clip := &"Idle_A"
	var sprinting := net_state == NetProtocol.AnimState.SPRINT
	match net_state:
		NetProtocol.AnimState.WALK:
			clip = _forced_direction_clip(false)
		NetProtocol.AnimState.SPRINT:
			clip = _forced_direction_clip(true)
		NetProtocol.AnimState.AIR:
			clip = &"Jump_Idle"
		_:
			clip = &"Idle_A"
	if animation_player.current_animation != clip:
		animation_player.play(clip, 0.15)
	_state = clip
	if net_state == NetProtocol.AnimState.STILL or net_state == NetProtocol.AnimState.AIR:
		animation_player.speed_scale = 1.0
	else:
		var speed := _motion_local.length()
		if speed < 0.15:
			speed = 2.75 if sprinting else 1.05
		_update_speed_scale(speed)


func _forced_direction_clip(sprinting: bool) -> StringName:
	var local := _motion_local
	if local.length() > 0.15:
		if local.z > 0.3:
			return &"Walking_Backwards"
		if absf(local.x) > maxf(0.25, absf(local.z) * 1.2):
			return &"Running_Strafe_Right" if local.x > 0.0 else &"Running_Strafe_Left"
	return &"Running_HoldingRifle" if sprinting else &"Walking_A"


# --- aim ------------------------------------------------------------------

## Upper-body additive aim + hold overlay. Local players aim while scoped or
## for a short post-fire window (Phase 0 behaviour); remote ghosts stay in the
## rifle-ready upper-body pose because no aim bit is replicated.
func _update_aim() -> void:
	var pc := body as PlayerController
	var active := false
	var target_yaw := 0.0
	var target_pitch := 0.0
	if pc != null:
		if pc.net_role == PlayerController.NetRole.REMOTE:
			active = true
		elif pc.net_role == PlayerController.NetRole.LOCAL:
			active = pc.aiming or Time.get_ticks_msec() < pc.aim_hold_until_msec
			if active:
				target_yaw = clampf(
					wrapf(pc.view_yaw - body.rotation.y, -PI, PI),
					-deg_to_rad(70.0), deg_to_rad(70.0)
				)
				if _camera_rig:
					target_pitch = clampf(_camera_rig.pitch, deg_to_rad(-55.0), deg_to_rad(30.0))
	if active and _reload_player and _reload_player.is_playing():
		active = false
	if active and _hit_player and _hit_player.is_playing():
		active = false
	_aim_weight = move_toward(_aim_weight, 1.0 if active else 0.0, 0.12)
	if _aim_weight > 0.001 and _spine_bone >= 0 and _hand_skeleton != null:
		var posed := _hand_skeleton.get_bone_pose_rotation(_spine_bone)
		var delta := (
			Quaternion(Vector3.UP, target_yaw * _aim_weight)
			* Quaternion(Vector3.RIGHT, target_pitch * _aim_weight)
		)
		_hand_skeleton.set_bone_pose_rotation(_spine_bone, posed * delta)
		_aim_was_active = true
	elif _aim_was_active and _spine_bone >= 0 and _hand_skeleton != null:
		_hand_skeleton.set_bone_pose_rotation(_spine_bone, Quaternion.IDENTITY)
		_aim_was_active = false

	if _hold_player == null:
		return
	if _aim_weight > 0.5 and not _action_playing():
		if not _hold_player.is_playing():
			_hold_player.play(&"Ranged_2H_Aiming", 0.12)
	elif _hold_player.is_playing():
		_hold_player.stop()


# --- hand attachment ------------------------------------------------------

## Follow handslot.r with an external-skeleton attachment. The gun lives outside
## the scaled GLB hierarchy, so its world scale stays 1.0.
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
	_spine_bone = skeleton.find_bone(SPINE_BONE)

	var attachment := BoneAttachment3D.new()
	attachment.name = "GunHand"
	attachment.use_external_skeleton = true
	attachment.override_pose = false
	body.add_child(attachment)
	# Resolve the skeleton only after the attachment is in the tree; absolute
	# paths cannot be looked up before that. Assign the bone name after the
	# external skeleton, otherwise bone_idx stays -1.
	attachment.external_skeleton = attachment.get_path_to(skeleton)
	attachment.bone_name = HAND_BONE
	attachment.bone_idx = hand

	var socket := Node3D.new()
	socket.name = "GripSocket"
	attachment.add_child(socket)

	var hand_xf := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
	var desired := Transform3D(
		Basis(Vector3.UP, body.rotation.y + GUN_YAW_OFFSET),
		hand_xf.origin + HAND_OFFSET
	)
	_grip_offset = hand_xf.affine_inverse() * desired
	gun_mount.reparent(socket, true)
	gun_mount.transform = Transform3D()
	_gun_socket = socket
	_hand_skeleton = skeleton
	_hand_bone = hand
	_grip_calibrated = false
	_gun_attached = true


func _detach_gun() -> void:
	if not _gun_attached:
		return
	var attachment := body.get_node_or_null("GunHand") as BoneAttachment3D
	if attachment:
		if gun_mount and is_instance_valid(gun_mount):
			gun_mount.reparent(self, true)
		attachment.free()
	_gun_socket = null
	_hand_skeleton = null
	_hand_bone = -1
	_spine_bone = -1
	_grip_calibrated = false
	_gun_attached = false


func _update_gun_attachment() -> void:
	if not _gun_attached or _gun_socket == null or _hand_skeleton == null or _hand_bone < 0:
		return
	var hand_xf := _hand_skeleton.global_transform * _hand_skeleton.get_bone_global_pose(_hand_bone)
	_gun_socket.global_transform = hand_xf * _grip_offset


## Recompute the hand-space offset once, using the settled idle pose.
func _maybe_calibrate_grip() -> void:
	if _grip_calibrated or not _gun_attached or _hand_skeleton == null or _hand_bone < 0 or _dead:
		return
	if not body.is_on_floor():
		return
	if animation_player and animation_player.current_animation in [&"Jump_Start", &"Jump_Idle", &"Jump_Land"]:
		return
	var hand_xf := _hand_skeleton.global_transform * _hand_skeleton.get_bone_global_pose(_hand_bone)
	var desired := Transform3D(
		Basis(Vector3.UP, body.rotation.y + GUN_YAW_OFFSET),
		hand_xf.origin + HAND_OFFSET
	)
	_grip_offset = hand_xf.affine_inverse() * desired
	_grip_calibrated = true


func _update_gun_pitch() -> void:
	if gun_mount == null or _camera_rig == null or _gun_attached:
		return
	gun_mount.rotation.x = _camera_rig.rotation.x
