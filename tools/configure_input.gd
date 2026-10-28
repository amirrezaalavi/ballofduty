extends SceneTree
## Regenerates the [input] section of project.godot from one canonical list.
## Run: tools/godot --headless --path . --script tools/configure_input.gd
##
## Inputs are physical keycodes so WASD stays in the same physical place on
## non-QWERTY layouts. Gameplay scripts must use these action names only.

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"sprint": [KEY_SHIFT],
	"reload": [KEY_R],
	"scoreboard": [KEY_TAB],
	"pause": [KEY_ESCAPE],
	"debug_overlay": [KEY_F3],
}

const MOUSE_ACTIONS := {
	"fire": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
}


func _init() -> void:
	for action: String in ACTIONS:
		var events: Array[InputEvent] = []
		for keycode: int in ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			event.device = -1
			events.append(event)
		_write_action(action, events)
	for action: String in MOUSE_ACTIONS:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_ACTIONS[action]
		event.device = -1
		_write_action(action, [event] as Array[InputEvent])

	var err := ProjectSettings.save()
	if err != OK:
		push_error("Failed to save project settings: %s" % error_string(err))
		quit(1)
		return
	print("Input map written: %d actions" % (ACTIONS.size() + MOUSE_ACTIONS.size()))
	quit(0)


func _write_action(action: String, events: Array[InputEvent]) -> void:
	ProjectSettings.set_setting(
		"input/" + action,
		{
			"deadzone": 0.2,
			"events": events,
		}
	)
