class_name InputHandler
extends Node
## Samples the InputMap exactly once per simulation tick. Only the locally
## controlled player has this component; the server feeds network frames into
## LocomotionComponent instead.

var sequence: int = 0
var _fire_buffered: bool = false
## Cached `document.hidden`; polled at 4 Hz so a background tab cannot queue
## seconds of movement into the next snapshot. No protocol resync exists.
var _hidden_checked_msec: int = -1000
var _page_hidden: bool = false


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
	if _is_page_hidden():
		_fire_buffered = false
		var idle := PlayerInputFrame.new()
		idle.seq = sequence
		idle.yaw = yaw
		idle.pitch = pitch
		return idle
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


func _is_page_hidden() -> bool:
	var now := Time.get_ticks_msec()
	if now - _hidden_checked_msec < 250:
		return _page_hidden
	_hidden_checked_msec = now
	_page_hidden = false
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		_page_hidden = bool(
			Engine.get_singleton("JavaScriptBridge").eval("document.hidden === true", true)
		)
	return _page_hidden
