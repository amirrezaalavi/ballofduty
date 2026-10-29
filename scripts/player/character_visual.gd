class_name CharacterVisual
extends Node3D
## Drives the blocky character's animation from replicated movement state.
## Purely presentational: no gameplay reads anything from here.
##
## The Blocky pack has no jump/backwards clips, so those are synthesized:
## backwards plays the walk cycle in reverse and never sprints; airborne uses
## its own state with a procedural lean so it never reuses the ground pose 1:1.

@export var walk_threshold: float = 0.25
@export var sprint_threshold: float = 6.4
@export var skin_texture: Texture2D = preload("res://assets/kenney_blocky/Textures/texture-a.png")

@onready var body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var animation_player: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var character: Node3D = get_node_or_null("Character") as Node3D
@onready var gun_mount: Node3D = get_node_or_null("GunMount") as Node3D

var _state: StringName = &""
var _camera_rig: CameraRig


func _ready() -> void:
	_apply_skin()
	_camera_rig = get_parent().get_node_or_null("CameraPivot") as CameraRig
	if gun_mount:
		gun_mount.rotation.y = 0.12
	if animation_player == null:
		push_warning("CharacterVisual: no AnimationPlayer found")
		return
	for loop_name: StringName in [&"idle", &"walk", &"sprint"]:
		var animation := animation_player.get_animation(loop_name)
		if animation:
			animation.loop_mode = Animation.LOOP_LINEAR
	_play(&"idle", 0.0)


func _process(_delta: float) -> void:
	if animation_player == null or body == null:
		return

	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	var speed := flat.length()
	# Local direction: forward is -Z, so +Z means moving backwards.
	var local: Vector3 = body.transform.basis.inverse() * flat
	var backwards := local.z > 0.3
	var airborne := not body.is_on_floor()

	var next: StringName = &"idle"
	if airborne:
		next = &"air_move" if speed > walk_threshold else &"air_idle"
	elif speed < walk_threshold:
		next = &"idle"
	elif backwards:
		next = &"walk_back"
	elif speed > sprint_threshold:
		next = &"sprint"
	else:
		next = &"walk"

	if next != _state:
		match next:
			&"walk_back", &"air_move":
				animation_player.play(&"walk", 0.15)
			&"air_idle":
				animation_player.play(&"idle", 0.15)
			_:
				animation_player.play(next, 0.15)
		_state = next

	match next:
		&"walk":
			animation_player.speed_scale = clampf(speed / 5.6, 0.6, 1.6)
		&"walk_back":
			# Reverse the cycle so backwards steps read as backwards. No fast mode.
			animation_player.speed_scale = -clampf(speed / 5.6, 0.6, 1.0)
		&"sprint":
			animation_player.speed_scale = clampf(speed / 7.56, 0.8, 1.3)
		&"air_move":
			animation_player.speed_scale = 1.1
		_:
			animation_player.speed_scale = 1.0

	_update_air_lean(airborne)
	_update_gun_pitch()


func _update_air_lean(airborne: bool) -> void:
	if character == null:
		return
	var target := 0.0
	if airborne:
		# Lean back while rising, tip forward while falling. Distinct from any
		# grounded pose and proportional to vertical velocity.
		target = clampf(-body.velocity.y * 0.03, -0.3, 0.35)
	character.rotation.x = lerpf(character.rotation.x, target, 0.18)


func _update_gun_pitch() -> void:
	if gun_mount == null or _camera_rig == null:
		return
	# The mount inherits yaw from Visual; copy the camera pitch (plus recoil)
	# so vertical aim moves the gun instead of leaving it fixed.
	gun_mount.rotation.x = _camera_rig.rotation.x


func _apply_skin() -> void:
	if skin_texture == null:
		return
	var skin := StandardMaterial3D.new()
	skin.albedo_texture = skin_texture
	skin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for node in find_children("*", "MeshInstance3D", true, false):
		if gun_mount != null and (node == gun_mount or gun_mount.is_ancestor_of(node)):
			continue
		(node as MeshInstance3D).material_override = skin


func _play(state: StringName, blend: float) -> void:
	_state = state
	animation_player.play(state, blend)
