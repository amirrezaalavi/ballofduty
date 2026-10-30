extends CanvasLayer
## Phase-aware quick menu (Esc). One overlay for every state the game can be
## in: main menu, connecting, live match, respawn, solo and match over. It owns
## presentation only; main.gd decides which actions are legal and performs them.

signal resume_requested
signal cancel_requested
signal leave_requested
signal restart_requested
signal settings_requested
signal quit_requested

const ACCENT := Color(0.215686, 0.878431, 0.784314)
const TEXT := Color(0.909804, 0.92549, 0.972549)
const MUTED := Color(0.490196, 0.533333, 0.65098)
const PANEL := Color(0.043137, 0.062745, 0.109804, 0.98)
const BORDER := Color(0.145098, 0.2, 0.313725)
const DANGER := Color(1.0, 0.482353, 0.533333)

var phase_label: Label
var detail_label: Label
var status_label: Label
var resume_button: Button
var cancel_button: Button
var leave_button: Button
var restart_button: Button
var settings_button: Button
var quit_button: Button

var _phase: StringName = &"menu"


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	set_phase(&"menu", "Choose a class and join, or play offline.")


func _unhandled_input(event: InputEvent) -> void:
	# Runs while the tree is paused (PROCESS_MODE_ALWAYS), so Esc always closes.
	if visible and event.is_action_pressed("pause"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	status_label.text = ""
	if resume_button and resume_button.visible:
		resume_button.grab_focus()


func close() -> void:
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		open()


func phase() -> StringName:
	return _phase


## phase: menu, connecting, match, respawning, solo, match_over.
func set_phase(phase: StringName, detail: String = "", status: String = "") -> void:
	_phase = phase
	if phase_label == null:
		return
	match phase:
		&"connecting":
			phase_label.text = "CONNECTING"
		&"match":
			phase_label.text = "IN MATCH"
		&"respawning":
			phase_label.text = "RESPAWNING"
		&"solo":
			phase_label.text = "SOLO PRACTICE"
		&"match_over":
			phase_label.text = "MATCH OVER"
		_:
			phase_label.text = "MAIN MENU"

	detail_label.text = detail
	status_label.text = status
	status_label.add_theme_color_override("font_color", ACCENT)

	var in_match := phase == &"match" or phase == &"respawning"
	resume_button.visible = phase != &"match_over"
	cancel_button.visible = phase == &"connecting"
	leave_button.visible = in_match or phase == &"solo" or phase == &"match_over"
	restart_button.visible = phase == &"solo"
	settings_button.visible = true
	quit_button.visible = not OS.has_feature("web")

	if phase == &"menu":
		resume_button.text = "CLOSE"
	elif phase == &"connecting":
		resume_button.text = "HIDE"
	else:
		resume_button.text = "RESUME"

	leave_button.text = "BACK TO MENU" if phase == &"match_over" else (
		"LEAVE TO MENU" if phase == &"solo" else "LEAVE MATCH"
	)


func flash_status(text: String) -> void:
	if status_label == null:
		return
	status_label.text = text
	status_label.add_theme_color_override("font_color", ACCENT)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "QuickRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015686, 0.023529, 0.047059, 0.72)
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(380.0, 0.0)
	card.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "QUICK MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)

	phase_label = Label.new()
	phase_label.name = "PhaseLabel"
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 11)
	phase_label.add_theme_color_override("font_color", MUTED)
	box.add_child(phase_label)

	detail_label = Label.new()
	detail_label.name = "DetailLabel"
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 12)
	detail_label.add_theme_color_override("font_color", TEXT)
	box.add_child(detail_label)

	box.add_child(HSeparator.new())

	resume_button = _button("RESUME", ACCENT, Color(0.02, 0.08, 0.09))
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	box.add_child(resume_button)

	cancel_button = _button("CANCEL CONNECTION", Color(0.09, 0.13, 0.23), TEXT)
	cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	box.add_child(cancel_button)

	leave_button = _button("LEAVE MATCH", Color(0.09, 0.13, 0.23), TEXT)
	leave_button.pressed.connect(func() -> void: leave_requested.emit())
	box.add_child(leave_button)

	restart_button = _button("RESTART SOLO", Color(0.09, 0.13, 0.23), TEXT)
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	box.add_child(restart_button)

	settings_button = _button("SETTINGS", Color(0.09, 0.13, 0.23), TEXT)
	settings_button.pressed.connect(func() -> void:
		flash_status("SETTINGS · COMING SOON (CP5 / L6)")
		settings_requested.emit()
	)
	box.add_child(settings_button)

	quit_button = _button("QUIT", Color(0.18, 0.06, 0.09), DANGER)
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	box.add_child(quit_button)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", ACCENT)
	box.add_child(status_label)

	var hint := Label.new()
	hint.text = "ESC CLOSES  ·  F6 NETWORK PANEL"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", MUTED)
	box.add_child(hint)


func _button(text: String, fill: Color, font_color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 12)
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
