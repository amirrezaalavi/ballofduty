class_name CharacterVisual
extends Node3D
## Drives the blocky character's animation from replicated movement state.
## Purely presentational: no gameplay reads anything from here.

@export var walk_threshold: float = 0.25
@export var sprint_threshold: float = 6.4
@export var skin_texture: Texture2D = preload("res://assets/kenney_blocky/Textures/texture-a.png")

@onready var body: CharacterBody3D = get_parent() as CharacterBody3D
@onready var animation_player: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer

var _state: StringName = &""


func _ready() -> void:
	_apply_skin()
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

	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	var next: StringName = &"idle"
	if not body.is_on_floor():
		next = &"sprint" if speed > sprint_threshold else &"idle"
	elif speed > sprint_threshold:
		next = &"sprint"
	elif speed > walk_threshold:
		next = &"walk"

	if next != _state:
		_play(next, 0.15)

	if next == &"walk":
		animation_player.speed_scale = clampf(speed / 5.6, 0.6, 1.6)
	elif next == &"sprint":
		animation_player.speed_scale = clampf(speed / 7.56, 0.8, 1.3)
	else:
		animation_player.speed_scale = 1.0


func _apply_skin() -> void:
	if skin_texture == null:
		return
	var skin := StandardMaterial3D.new()
	skin.albedo_texture = skin_texture
	skin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = skin


func _play(state: StringName, blend: float) -> void:
	_state = state
	animation_player.play(state, blend)
