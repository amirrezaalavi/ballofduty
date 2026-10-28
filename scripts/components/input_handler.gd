class_name InputHandler
extends Node
## Samples the InputMap exactly once per simulation tick. Only the locally
## controlled player has this component; the server feeds network frames into
## LocomotionComponent instead.

var sequence: int = 0
var _fire_buffered: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index == MOUSE_BUTTON_LEFT
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	):
		_fire_buffered = true


func sample(yaw: float, pitch: float) -> PlayerInputFrame:
	sequence += 1
	var frame := PlayerInputFrame.new()
	frame.seq = sequence
	frame.move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	frame.jump = Input.is_action_just_pressed("jump")
	frame.sprint = Input.is_action_pressed("sprint")
	frame.aim = Input.is_action_pressed("aim")
	frame.fire = Input.is_action_pressed("fire") or _fire_buffered
	_fire_buffered = false
	frame.reload = Input.is_action_just_pressed("reload")
	frame.yaw = yaw
	frame.pitch = pitch
	return frame
