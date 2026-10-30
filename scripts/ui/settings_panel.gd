extends CanvasLayer
## Reusable CP5 settings overlay. One panel instance is owned by main.gd and
## opened from the main menu or the quick menu in any phase. It only edits the
## Settings autoload, so gameplay, maps, protocol and server authority are
## untouched. Works without pointer lock: the mouse stays visible while open
## and Esc closes it even when the tree is paused.

signal closed

const SETTINGS_SCRIPT := preload("res://scripts/autoload/settings.gd")

const ACCENT := Color(0.215686, 0.878431, 0.784314)
const TEXT := Color(0.909804, 0.92549, 0.972549)
const MUTED := Color(0.490196, 0.533333, 0.65098)
const PANEL := Color(0.043137, 0.062745, 0.109804, 0.98)
const BORDER := Color(0.145098, 0.2, 0.313725)
const FIELD := Color(0.09, 0.13, 0.23)

## The slider speaks in integer ticks of 0.0001 sensitivity so the range reads
## naturally (5 = 0.0005, 100 = 0.01) while Settings stores the raw value.
const SENS_STEP := 0.0001
const SENS_SLIDER_MIN := 5.0
const SENS_SLIDER_MAX := 100.0

var sensitivity_slider: HSlider
var sensitivity_value_label: Label
var invert_check: CheckBox
var scope_slider: HSlider
var scope_value_label: Label
var volume_slider: HSlider
var volume_value_label: Label
var quality_option: OptionButton
var apply_button: Button
var close_button: Button
var reset_button: Button
var status_label: Label

## Optional override for tests; defaults to the /root/Settings autoload.
var settings_node: Node

var _syncing: bool = false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	# Runs while the tree is paused (PROCESS_MODE_ALWAYS) as a standalone
	# fallback; main.gd also consumes Esc before the quick menu sees it.
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func open() -> void:
	refresh()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if close_button:
		close_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func bind(settings: Node) -> void:
	settings_node = settings
	refresh()


func refresh() -> void:
	if sensitivity_slider == null:
		return
	var settings := _get_settings()
	if settings == null:
		return
	_syncing = true
	sensitivity_slider.value = round(float(settings.sensitivity) / SENS_STEP)
	invert_check.button_pressed = bool(settings.invert_y)
	scope_slider.value = float(settings.scope_sensitivity_scale)
	volume_slider.value = round(float(settings.master_volume) * 100.0)
	quality_option.select(clampi(int(settings.quality), 0, quality_option.item_count - 1))
	_syncing = false
	_update_value_labels()


func _get_settings() -> Node:
	if settings_node == null or not is_instance_valid(settings_node):
		settings_node = get_node_or_null("/root/Settings")
	return settings_node


func _update_value_labels() -> void:
	if sensitivity_value_label:
		sensitivity_value_label.text = "%.4f" % (sensitivity_slider.value * SENS_STEP)
	if scope_value_label:
		scope_value_label.text = "%d%%" % int(round(scope_slider.value * 100.0))
	if volume_value_label:
		volume_value_label.text = "%d%%" % int(round(volume_slider.value))


func _on_sensitivity_changed(value: float) -> void:
	_update_value_labels()
	if _syncing:
		return
	var settings := _get_settings()
	if settings:
		settings.set_sensitivity(value * SENS_STEP)


func _on_scope_changed(value: float) -> void:
	_update_value_labels()
	if _syncing:
		return
	var settings := _get_settings()
	if settings:
		settings.set_scope_sensitivity_scale(value)


func _on_volume_changed(value: float) -> void:
	_update_value_labels()
	if _syncing:
		return
	var settings := _get_settings()
	if settings:
		settings.set_master_volume(value / 100.0)


func _on_invert_toggled(pressed: bool) -> void:
	if _syncing:
		return
	var settings := _get_settings()
	if settings:
		settings.set_invert_y(pressed)


func _on_quality_selected(index: int) -> void:
	if _syncing:
		return
	var settings := _get_settings()
	if settings:
		settings.set_quality(index)


func _on_reset_pressed() -> void:
	var settings := _get_settings()
	if settings:
		settings.reset_defaults()
	refresh()
	_set_status("DEFAULTS RESTORED")


func _on_apply_pressed() -> void:
	var settings := _get_settings()
	if settings:
		settings.save_settings()
	_set_status("SETTINGS SAVED")


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
		status_label.add_theme_color_override("font_color", ACCENT)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "SettingsRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015686, 0.023529, 0.047059, 0.86)
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(470.0, 0.0)
	card.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "INPUT · AUDIO · RENDER QUALITY"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", MUTED)
	box.add_child(subtitle)

	box.add_child(HSeparator.new())
	box.add_child(_section_label("MOUSE"))

	var sensitivity := _slider_row(
		box, "SENSITIVITY", SENS_SLIDER_MIN, SENS_SLIDER_MAX, 1.0
	)
	sensitivity_slider = sensitivity["slider"] as HSlider
	sensitivity_value_label = sensitivity["value"] as Label
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)

	invert_check = CheckBox.new()
	invert_check.name = "InvertYCheck"
	invert_check.text = "INVERT Y AXIS"
	invert_check.add_theme_font_size_override("font_size", 11)
	invert_check.add_theme_color_override("font_color", TEXT)
	invert_check.add_theme_color_override("font_hover_color", ACCENT)
	invert_check.add_theme_color_override("font_pressed_color", ACCENT)
	invert_check.add_theme_color_override("font_focus_color", ACCENT)
	invert_check.toggled.connect(_on_invert_toggled)
	box.add_child(invert_check)

	var scope := _slider_row(box, "SCOPE SENSITIVITY", 0.2, 1.0, 0.05)
	scope_slider = scope["slider"] as HSlider
	scope_value_label = scope["value"] as Label
	scope_slider.value_changed.connect(_on_scope_changed)

	box.add_child(HSeparator.new())
	box.add_child(_section_label("AUDIO"))

	var volume := _slider_row(box, "MASTER VOLUME", 0.0, 100.0, 1.0)
	volume_slider = volume["slider"] as HSlider
	volume_value_label = volume["value"] as Label
	volume_slider.value_changed.connect(_on_volume_changed)

	box.add_child(HSeparator.new())
	box.add_child(_section_label("VIDEO"))

	var quality_row := HBoxContainer.new()
	quality_row.name = "QualityRow"
	quality_row.add_theme_constant_override("separation", 10)
	box.add_child(quality_row)

	var quality_label := _small_label("RENDER QUALITY")
	quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_row.add_child(quality_label)

	quality_option = OptionButton.new()
	quality_option.name = "QualityOption"
	quality_option.custom_minimum_size = Vector2(128.0, 30.0)
	quality_option.add_theme_font_size_override("font_size", 11)
	quality_option.add_theme_color_override("font_color", TEXT)
	quality_option.add_theme_color_override("font_hover_color", ACCENT)
	quality_option.add_theme_color_override("font_pressed_color", ACCENT)
	quality_option.add_theme_color_override("font_focus_color", ACCENT)
	quality_option.add_theme_stylebox_override("normal", _button_style(FIELD, BORDER))
	quality_option.add_theme_stylebox_override("hover", _button_style(FIELD.lightened(0.08), ACCENT))
	quality_option.add_theme_stylebox_override("pressed", _button_style(FIELD, ACCENT))
	quality_option.add_theme_stylebox_override("focus", _button_style(FIELD, ACCENT))
	for quality_name in SETTINGS_SCRIPT.QUALITY_NAMES:
		quality_option.add_item(quality_name)
	quality_option.item_selected.connect(_on_quality_selected)
	quality_row.add_child(quality_option)

	var quality_hint := _small_label("LOW saves fill rate on software WebGL · HIGH keeps full resolution")
	quality_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(quality_hint)

	box.add_child(HSeparator.new())

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 8)
	box.add_child(actions)

	reset_button = _button("RESET DEFAULTS", FIELD, TEXT)
	reset_button.name = "ResetButton"
	reset_button.pressed.connect(_on_reset_pressed)
	actions.add_child(reset_button)

	apply_button = _button("APPLY · SAVE", ACCENT, Color(0.02, 0.08, 0.09))
	apply_button.name = "ApplyButton"
	apply_button.pressed.connect(_on_apply_pressed)
	actions.add_child(apply_button)

	close_button = _button("CLOSE", FIELD, TEXT)
	close_button.name = "CloseButton"
	close_button.pressed.connect(close)
	actions.add_child(close_button)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0.0, 18.0)
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", ACCENT)
	box.add_child(status_label)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "ESC CLOSES · CHANGES SAVE TO THIS BROWSER"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", MUTED)
	box.add_child(hint)


func _slider_row(
	box: VBoxContainer, title: String, min_value: float, max_value: float, step: float
) -> Dictionary:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var name_label := _small_label(title)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 10)
	value_label.add_theme_color_override("font_color", ACCENT)
	header.add_child(value_label)
	box.add_child(header)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = min_value
	slider.custom_minimum_size = Vector2(0.0, 20.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	box.add_child(slider)
	return {"slider": slider, "value": value_label}


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", MUTED)
	return label


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", TEXT)
	return label


func _button(text: String, fill: Color, font_color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 34.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_stylebox_override("normal", _button_style(fill, fill.lightened(0.15)))
	button.add_theme_stylebox_override("hover", _button_style(fill.lightened(0.08), ACCENT))
	button.add_theme_stylebox_override("pressed", _button_style(fill.darkened(0.1), ACCENT))
	button.add_theme_stylebox_override("focus", _button_style(fill, ACCENT))
	return button


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 18
	return style
