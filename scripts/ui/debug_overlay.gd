extends CanvasLayer
## Toggleable diagnostics (F3). Reads the local player only; never mutates state.

@export var toggle_action: StringName = &"debug_overlay"

var _label: Label
var _player: CharacterBody3D
var _accumulator: float = 0.0


func _ready() -> void:
	layer = 9
	_label = Label.new()
	_label.position = Vector2(16, 76)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

	_player = get_parent().get_node_or_null("Player") as CharacterBody3D
	_update_text()


func _process(delta: float) -> void:
	if Input.is_action_just_pressed(toggle_action):
		_label.visible = not _label.visible
		_accumulator = 0.0

	if not _label.visible:
		return
	_accumulator += delta
	if _accumulator < 0.1:
		return
	_accumulator = 0.0
	_update_text()


func _update_text() -> void:
	if _label == null:
		return
	if _player == null:
		_label.text = "BALL OF DUTY · debug\nplayer unavailable"
		return

	var loco := _player.get_node_or_null("LocomotionComponent") as LocomotionComponent
	var rig := _player.get_node_or_null("CameraPivot") as CameraRig
	var health := _player.get_node_or_null("HealthComponent") as HealthComponent

	var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	var seq := 0
	if loco and loco.last_input != null:
		seq = loco.last_input.seq
	var camera_distance := rig.get_camera_distance() if rig else 0.0
	var fov := rig.camera.fov if rig else 0.0
	var hp := "%d/%d" % [health.current, health.max_health] if health else "n/a"

	var pred: Dictionary = _player.prediction_stats() if _player.has_method("prediction_stats") else {}

	var lines := PackedStringArray([
		"BALL OF DUTY · debug  [F3]",
		"fps %d   physics %d Hz   tick %d" % [
			Engine.get_frames_per_second(),
			Engine.physics_ticks_per_second,
			Engine.get_physics_frames(),
		],
		"pos %.2f %.2f %.2f   speed %.2f m/s" % [
			_player.global_position.x,
			_player.global_position.y,
			_player.global_position.z,
			speed,
		],
		"grounded %s   hp %s   seq %d" % [
			"yes" if _player.is_on_floor() else "no",
			hp,
			seq,
		],
		"camera %.2f m   fov %.1f   scoped %s" % [
			camera_distance,
			fov,
			"yes" if rig and rig.is_scoped() else "no",
		],
	])
	if bool(pred.get("enabled", false)):
		lines.append("pred ack %d   pending %d   replay %d" % [
			int(pred.get("ack", 0)),
			int(pred.get("pending", 0)),
			int(pred.get("replay_depth", 0)),
		])
		lines.append("ack err %.3f m   corr %d (%.1f/s)   vis %.3f m" % [
			float(pred.get("recent_ack_error_m", 0.0)),
			int(pred.get("corrections", 0)),
			float(pred.get("corrections_per_sec", 0.0)),
			float(pred.get("visual_error_m", 0.0)),
		])
	_label.text = "\n".join(lines)
