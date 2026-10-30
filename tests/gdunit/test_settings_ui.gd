extends BodTestSuite
## CP5 / L6 settings UI: one reusable panel reachable from the main menu and
## the quick menu in every phase. The panel only edits the Settings autoload,
## so these tests redirect that autoload to a scratch config file and restore
## the player's real values afterwards.

const PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const QUICK_SCENE := preload("res://scenes/ui/quick_menu.tscn")
const SETTINGS_SCRIPT := preload("res://scripts/autoload/settings.gd")

const TEST_PATH := "user://l6_settings_ui_test.cfg"

var _settings: Node
var _nodes: Array[Node] = []
var _original: Dictionary = {}


func before_test() -> void:
	_settings = get_node("/root/Settings")
	_original = {
		"path": _settings.settings_path,
		"sensitivity": _settings.sensitivity,
		"invert_y": _settings.invert_y,
		"scope": _settings.scope_sensitivity_scale,
		"volume": _settings.master_volume,
		"quality": _settings.quality,
	}
	_settings.settings_path = TEST_PATH
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	_settings.reset_defaults()


func after_test() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	if _settings == null or not is_instance_valid(_settings):
		return
	_settings.settings_path = String(_original["path"])
	_settings.sensitivity = float(_original["sensitivity"])
	_settings.invert_y = bool(_original["invert_y"])
	_settings.scope_sensitivity_scale = float(_original["scope"])
	_settings.master_volume = float(_original["volume"])
	_settings.quality = int(_original["quality"])
	_settings.save_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func test_panel_opens_and_closes_from_both_entry_points() -> void:
	var panel := _make_panel()
	var menu := _make_menu()
	var quick := _make_quick()

	# main.gd wires both menu signals to the single shared panel.
	menu.settings_requested.connect(panel.open)
	quick.settings_requested.connect(panel.open)

	expect(not panel.is_open(), "settings panel starts closed")
	menu.settings_button.pressed.emit()
	expect(panel.is_open(), "main menu SETTINGS opens the panel")
	panel.close()
	expect(not panel.is_open(), "panel closes back to the menu")

	for phase: StringName in [&"menu", &"connecting", &"match", &"respawning", &"solo", &"match_over"]:
		quick.set_phase(phase, "phase detail")
		expect(quick.settings_button.visible, "quick menu SETTINGS is visible in %s" % phase)

	quick.open()
	quick.set_phase(&"match", "SUNKEN QUARRY · KNIGHT")
	quick.settings_button.pressed.emit()
	expect(panel.is_open(), "quick menu SETTINGS opens the panel in a live match")

	var escape := InputEventAction.new()
	escape.action = &"pause"
	escape.pressed = true
	panel._unhandled_input(escape)
	expect(not panel.is_open(), "Esc closes the settings panel")


func test_widgets_reflect_settings_and_write_back() -> void:
	_settings.set_sensitivity(0.0031)
	_settings.set_invert_y(true)
	_settings.set_scope_sensitivity_scale(0.55)
	_settings.set_master_volume(0.4)
	_settings.set_quality(SETTINGS_SCRIPT.QUALITY_MEDIUM)

	var panel := _make_panel()
	expect(is_equal_approx(panel.sensitivity_slider.value, 31.0),
		"sensitivity slider reflects 0.0031")
	expect(panel.invert_check.button_pressed, "invert-Y checkbox reflects the setting")
	expect(is_equal_approx(panel.scope_slider.value, 0.55), "scope slider reflects 0.55")
	expect(is_equal_approx(panel.volume_slider.value, 40.0), "volume slider reflects 40%")
	expect(panel.quality_option.selected == SETTINGS_SCRIPT.QUALITY_MEDIUM,
		"quality selector reflects MEDIUM")

	panel.sensitivity_slider.value = 75.0
	expect(is_equal_approx(_settings.sensitivity, 0.0075), "sensitivity slider writes back")
	panel.invert_check.button_pressed = false
	expect(not _settings.invert_y, "invert-Y checkbox writes back")
	panel.scope_slider.value = 0.9
	expect(is_equal_approx(_settings.scope_sensitivity_scale, 0.9), "scope slider writes back")
	panel.volume_slider.value = 65.0
	expect(is_equal_approx(_settings.master_volume, 0.65), "volume slider writes back")
	panel.quality_option.select(SETTINGS_SCRIPT.QUALITY_LOW)
	panel.quality_option.item_selected.emit(SETTINGS_SCRIPT.QUALITY_LOW)
	expect(_settings.quality == SETTINGS_SCRIPT.QUALITY_LOW, "quality selector writes back")


func test_reset_restores_defaults() -> void:
	_settings.set_sensitivity(0.009)
	_settings.set_invert_y(true)
	_settings.set_scope_sensitivity_scale(0.25)
	_settings.set_master_volume(0.2)
	_settings.set_quality(SETTINGS_SCRIPT.QUALITY_LOW)

	var panel := _make_panel()
	panel.reset_button.pressed.emit()
	expect(is_equal_approx(_settings.sensitivity, SETTINGS_SCRIPT.DEFAULT_SENSITIVITY),
		"reset restores default sensitivity")
	expect(not _settings.invert_y, "reset clears invert-Y")
	expect(
		is_equal_approx(_settings.scope_sensitivity_scale, SETTINGS_SCRIPT.DEFAULT_SCOPE_SENSITIVITY_SCALE),
		"reset restores the default scope scale"
	)
	expect(is_equal_approx(_settings.master_volume, SETTINGS_SCRIPT.DEFAULT_MASTER_VOLUME),
		"reset restores full volume")
	expect(_settings.quality == SETTINGS_SCRIPT.DEFAULT_QUALITY, "reset restores HIGH quality")
	expect(is_equal_approx(panel.volume_slider.value, 100.0), "widgets refresh after reset")
	expect(panel.status_label.text.contains("DEFAULT"), "reset confirms in the panel")


func test_values_are_clamped() -> void:
	_settings.set_sensitivity(99.0)
	expect(is_equal_approx(_settings.sensitivity, SETTINGS_SCRIPT.SENSITIVITY_MAX),
		"sensitivity clamps to the maximum")
	_settings.set_sensitivity(-1.0)
	expect(is_equal_approx(_settings.sensitivity, SETTINGS_SCRIPT.SENSITIVITY_MIN),
		"sensitivity clamps to the minimum")

	_settings.set_master_volume(2.0)
	expect(is_equal_approx(_settings.master_volume, 1.0), "volume clamps to 100%")
	_settings.set_master_volume(-0.5)
	expect(is_equal_approx(_settings.master_volume, 0.0), "volume clamps to 0%")

	_settings.set_scope_sensitivity_scale(5.0)
	expect(is_equal_approx(_settings.scope_sensitivity_scale, SETTINGS_SCRIPT.SCOPE_SCALE_MAX),
		"scope scale clamps high")
	_settings.set_scope_sensitivity_scale(-2.0)
	expect(is_equal_approx(_settings.scope_sensitivity_scale, SETTINGS_SCRIPT.SCOPE_SCALE_MIN),
		"scope scale clamps low")

	_settings.set_quality(42)
	expect(_settings.quality == SETTINGS_SCRIPT.QUALITY_HIGH, "quality clamps to HIGH")
	_settings.set_quality(-3)
	expect(_settings.quality == SETTINGS_SCRIPT.QUALITY_LOW, "quality clamps to LOW")

	var panel := _make_panel()
	panel.volume_slider.value = 500.0
	expect(is_equal_approx(_settings.master_volume, 1.0), "slider input is clamped by the widget too")


func test_quality_applies_real_render_settings() -> void:
	_settings.set_quality(SETTINGS_SCRIPT.QUALITY_LOW)
	expect(
		is_equal_approx(get_tree().root.scaling_3d_scale, SETTINGS_SCRIPT.QUALITY_SCALES[0]),
		"LOW lowers the 3D resolution scale"
	)
	_settings.set_quality(SETTINGS_SCRIPT.QUALITY_HIGH)
	expect(
		is_equal_approx(get_tree().root.scaling_3d_scale, SETTINGS_SCRIPT.QUALITY_SCALES[2]),
		"HIGH restores full resolution"
	)


func test_settings_persist_through_save_and_reload() -> void:
	_settings.set_sensitivity(0.0042)
	_settings.set_invert_y(true)
	_settings.set_scope_sensitivity_scale(0.35)
	_settings.set_master_volume(0.55)
	_settings.set_quality(SETTINGS_SCRIPT.QUALITY_MEDIUM)

	var loaded := SETTINGS_SCRIPT.new() as Node
	loaded.settings_path = TEST_PATH
	loaded.load_settings()
	expect(is_equal_approx(loaded.sensitivity, 0.0042), "sensitivity survives a reload")
	expect(loaded.invert_y, "invert-Y survives a reload")
	expect(is_equal_approx(loaded.scope_sensitivity_scale, 0.35), "scope scale survives a reload")
	expect(is_equal_approx(loaded.master_volume, 0.55), "volume survives a reload")
	expect(loaded.quality == SETTINGS_SCRIPT.QUALITY_MEDIUM, "quality survives a reload")
	loaded.free()


func test_apply_button_saves_and_confirms() -> void:
	var panel := _make_panel()
	panel.volume_slider.value = 30.0
	panel.apply_button.pressed.emit()
	expect(panel.status_label.text.contains("SAVED"), "apply confirms in the panel")

	var loaded := SETTINGS_SCRIPT.new() as Node
	loaded.settings_path = TEST_PATH
	loaded.load_settings()
	expect(is_equal_approx(loaded.master_volume, 0.3), "apply persists the live volume")
	loaded.free()


func _make_panel() -> Node:
	var panel := PANEL_SCENE.instantiate()
	add_child(panel)
	_nodes.append(panel)
	return panel


func _make_menu() -> Node:
	var menu := MENU_SCENE.instantiate()
	add_child(menu)
	_nodes.append(menu)
	return menu


func _make_quick() -> Node:
	var quick := QUICK_SCENE.instantiate()
	add_child(quick)
	_nodes.append(quick)
	return quick
