extends BodTestSuite
## Phase-aware quick menu: every phase exposes the right actions, signals are
## wired, and Esc closes it even while the solo tree is paused.

const QUICK_SCENE := preload("res://scenes/ui/quick_menu.tscn")

var _menus: Array[Node] = []


func after_test() -> void:
	for menu in _menus:
		if is_instance_valid(menu):
			menu.queue_free()
	_menus.clear()


func _make() -> CanvasLayer:
	var menu := QUICK_SCENE.instantiate() as CanvasLayer
	add_child(menu)
	_menus.append(menu)
	await get_tree().process_frame
	return menu


func test_every_phase_has_the_right_actions() -> void:
	var menu := await _make()

	menu.set_phase(&"menu", "Choose a class.")
	expect(menu.phase_label.text == "MAIN MENU", "menu phase label")
	expect(menu.resume_button.text == "CLOSE", "menu phase can close the overlay")
	expect(not menu.cancel_button.visible, "menu phase has no cancel")
	expect(not menu.leave_button.visible, "menu phase has no leave")
	expect(not menu.restart_button.visible, "menu phase has no restart")
	expect(menu.settings_button.visible, "settings is available everywhere")

	menu.set_phase(&"connecting", "Connecting to 127.0.0.1:8099…")
	expect(menu.phase_label.text == "CONNECTING", "connecting phase label")
	expect(menu.cancel_button.visible, "connecting can cancel")
	expect(menu.resume_button.text == "HIDE", "connecting can hide the overlay")
	expect(not menu.leave_button.visible, "connecting has no leave")

	menu.set_phase(&"match", "SUNKEN QUARRY · KNIGHT")
	expect(menu.phase_label.text == "IN MATCH", "match phase label")
	expect(menu.resume_button.text == "RESUME", "match can resume")
	expect(menu.leave_button.visible and menu.leave_button.text == "LEAVE MATCH",
		"match can leave")
	expect(not menu.restart_button.visible, "online match cannot restart")

	menu.set_phase(&"respawning", "SUNKEN QUARRY · respawning")
	expect(menu.phase_label.text == "RESPAWNING", "respawn phase label")
	expect(menu.leave_button.visible, "respawn can still leave")

	menu.set_phase(&"solo", "SUNKEN QUARRY · OFFLINE")
	expect(menu.phase_label.text == "SOLO PRACTICE", "solo phase label")
	expect(menu.restart_button.visible, "solo can restart")
	expect(menu.leave_button.text == "LEAVE TO MENU", "solo leaves to the menu")

	menu.set_phase(&"match_over", "SUNKEN QUARRY · match complete")
	expect(menu.phase_label.text == "MATCH OVER", "match-over phase label")
	expect(not menu.resume_button.visible, "match over has no resume")
	expect(menu.leave_button.text == "BACK TO MENU", "match over returns to menu")


func test_signals_and_settings_entry() -> void:
	var menu := await _make()
	var counts := {"resume": 0, "cancel": 0, "leave": 0, "restart": 0, "quit": 0}
	menu.resume_requested.connect(func() -> void: counts["resume"] += 1)
	menu.cancel_requested.connect(func() -> void: counts["cancel"] += 1)
	menu.leave_requested.connect(func() -> void: counts["leave"] += 1)
	menu.restart_requested.connect(func() -> void: counts["restart"] += 1)
	menu.quit_requested.connect(func() -> void: counts["quit"] += 1)

	menu.resume_button.pressed.emit()
	menu.cancel_button.pressed.emit()
	menu.leave_button.pressed.emit()
	menu.restart_button.pressed.emit()
	menu.quit_button.pressed.emit()
	expect(counts["resume"] == 1 and counts["cancel"] == 1 and counts["leave"] == 1,
		"resume/cancel/leave emit once")
	expect(counts["restart"] == 1 and counts["quit"] == 1, "restart/quit emit once")

	var settings_pressed := [0]
	menu.settings_requested.connect(func() -> void: settings_pressed[0] += 1)
	menu.settings_button.pressed.emit()
	expect(settings_pressed[0] == 1, "settings opens the real panel from the quick menu")


func test_open_close_toggle_and_escape() -> void:
	var menu := await _make()
	expect(not menu.is_open(), "quick menu starts hidden")
	menu.open()
	expect(menu.is_open(), "open shows the overlay")
	menu.close()
	expect(not menu.is_open(), "close hides the overlay")
	menu.toggle()
	expect(menu.is_open(), "toggle opens")
	menu.toggle()
	expect(not menu.is_open(), "toggle closes")

	var closed := [0]
	menu.resume_requested.connect(func() -> void: closed[0] += 1)
	menu.open()
	var escape := InputEventAction.new()
	escape.action = &"pause"
	escape.pressed = true
	menu._unhandled_input(escape)
	expect(closed[0] == 1, "Esc requests a close while the overlay is open")
	expect(menu.is_open(), "the overlay waits for main to close it")
