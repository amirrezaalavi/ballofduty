extends CanvasLayer
## In-engine entry menu. Owns only presentation: main.gd supplies page/proxy
## defaults, receives `join_requested` and decides whether the transport should
## use a one-origin path or a direct host:port.

signal join_requested(config: Dictionary)
signal solo_requested
signal settings_requested

const ACCENT := Color(0.215686, 0.878431, 0.784314)
const TEXT := Color(0.909804, 0.92549, 0.972549)
const MUTED := Color(0.490196, 0.533333, 0.65098)
const ERROR := Color(1.0, 0.482353, 0.533333)
const WARN := Color(1.0, 0.768627, 0.419608)

var title_label: Label
var name_field: LineEdit
var host_field: LineEdit
var port_field: LineEdit
var join_button: Button
var solo_button: Button
var settings_button: Button
var status_label: Label
var mode_label: Label

var _page_host: String = "127.0.0.1"
var _page_port: int = 9080
var _page_secure: bool = false
var _proxy_ws: String = ""


func _ready() -> void:
	layer = 20
	_build_ui()


func configure(defaults: Dictionary) -> void:
	_page_host = String(defaults.get("page_host", "127.0.0.1"))
	_page_port = int(defaults.get("page_port", 9080))
	_page_secure = bool(defaults.get("page_secure", false))
	_proxy_ws = String(defaults.get("proxy_ws", ""))
	if name_field:
		name_field.text = String(defaults.get("name", "Player"))
	if host_field:
		host_field.text = String(defaults.get("host", _page_host))
	if port_field:
		port_field.text = str(int(defaults.get("port", 9080)))
	_update_mode_hint()


func show_menu() -> void:
	visible = true


func hide_menu() -> void:
	visible = false


func is_open() -> bool:
	return visible


func set_status(text: String, tone: String = "info") -> void:
	if status_label == null:
		return
	status_label.text = text
	match tone:
		"error":
			status_label.add_theme_color_override("font_color", ERROR)
		"warn", "reconnecting":
			status_label.add_theme_color_override("font_color", WARN)
		"ok":
			status_label.add_theme_color_override("font_color", ACCENT)
		_:
			status_label.add_theme_color_override("font_color", MUTED)


func join_config() -> Dictionary:
	var host := host_field.text.strip_edges() if host_field else ""
	if host == "":
		host = "127.0.0.1"
	var port := port_field.text.strip_edges().to_int() if port_field else 0
	if port <= 0:
		port = 9080
	var display_name := name_field.text.strip_edges() if name_field else ""
	if display_name == "":
		display_name = "Player"
	var proxied := _proxy_ws != "" and host == _page_host and port == _page_port
	_update_mode_hint()
	return {
		"host": host,
		"port": port,
		"name": display_name.left(16),
		"path": _proxy_ws if proxied else "",
		"secure": _page_secure,
		"proxied": proxied,
	}


func grab_name_focus() -> void:
	if name_field:
		name_field.grab_focus()
		name_field.select_all()


func _update_mode_hint() -> void:
	if mode_label == null or host_field == null or port_field == null:
		return
	var host := host_field.text.strip_edges()
	var port := port_field.text.strip_edges().to_int()
	var proxied := _proxy_ws != "" and host == _page_host and port == _page_port
	if proxied:
		mode_label.text = "ONE-ORIGIN MODE · WebSocket rides this page at %s" % _proxy_ws
	elif _proxy_ws != "":
		mode_label.text = "DIRECT MODE · %s is available at %s:%d" % [_proxy_ws, _page_host, _page_port]
	else:
		mode_label.text = "DIRECT MODE · enter the game server host and port"


func _build_ui() -> void:
	var root := Control.new()
	root.name = "MenuRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.027451, 0.043137, 0.086275, 0.94)
	root.add_child(backdrop)

	var glow := ColorRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	glow.offset_bottom = 4.0
	glow.color = Color(0.215686, 0.878431, 0.784314, 0.5)
	root.add_child(glow)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(470.0, 0.0)
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	card.add_child(margin)

	var box := VBoxContainer.new()
	box.name = "Content"
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.name = "Title"
	title_label = title
	title.text = "BALL OF DUTY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "SMALL-SQUAD BROWSER ARENA"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", MUTED)
	box.add_child(subtitle)

	var rule := HSeparator.new()
	box.add_child(rule)

	var callsign := _small_label("CALLSIGN")
	box.add_child(callsign)
	name_field = LineEdit.new()
	name_field.name = "NameField"
	name_field.placeholder_text = "Player"
	name_field.max_length = 16
	name_field.text = "Player"
	_style_field(name_field)
	name_field.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	box.add_child(name_field)

	var address := HBoxContainer.new()
	address.name = "AddressRow"
	address.add_theme_constant_override("separation", 10)
	box.add_child(address)

	var host_box := VBoxContainer.new()
	host_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_box.add_theme_constant_override("separation", 3)
	host_box.add_child(_small_label("HOST"))
	host_field = LineEdit.new()
	host_field.name = "HostField"
	host_field.placeholder_text = "127.0.0.1"
	host_field.text = "127.0.0.1"
	_style_field(host_field)
	host_field.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	host_field.text_changed.connect(func(_text: String) -> void: _update_mode_hint())
	host_box.add_child(host_field)
	address.add_child(host_box)

	var port_box := VBoxContainer.new()
	port_box.custom_minimum_size = Vector2(102.0, 0.0)
	port_box.add_theme_constant_override("separation", 3)
	port_box.add_child(_small_label("PORT"))
	port_field = LineEdit.new()
	port_field.name = "PortField"
	port_field.placeholder_text = "9080"
	port_field.text = "9080"
	port_field.max_length = 5
	_style_field(port_field)
	port_field.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	port_field.text_changed.connect(func(_text: String) -> void: _update_mode_hint())
	port_box.add_child(port_field)
	address.add_child(port_box)

	mode_label = Label.new()
	mode_label.name = "ModeHint"
	mode_label.text = "DIRECT MODE · enter the game server host and port"
	mode_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_label.add_theme_font_size_override("font_size", 10)
	mode_label.add_theme_color_override("font_color", MUTED)
	box.add_child(mode_label)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)

	join_button = Button.new()
	join_button.name = "JoinButton"
	join_button.text = "JOIN MATCH"
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.custom_minimum_size = Vector2(0.0, 40.0)
	join_button.add_theme_color_override("font_color", Color(0.02, 0.08, 0.09))
	join_button.add_theme_color_override("font_hover_color", Color(0.02, 0.08, 0.09))
	join_button.add_theme_stylebox_override("normal", _button_style(ACCENT, ACCENT))
	join_button.add_theme_stylebox_override("hover", _button_style(ACCENT.lightened(0.12), ACCENT))
	join_button.add_theme_stylebox_override("pressed", _button_style(ACCENT.darkened(0.12), ACCENT))
	join_button.pressed.connect(_on_join_pressed)
	actions.add_child(join_button)

	solo_button = Button.new()
	solo_button.name = "SoloButton"
	solo_button.text = "SOLO"
	solo_button.custom_minimum_size = Vector2(108.0, 40.0)
	solo_button.add_theme_stylebox_override("normal", _button_style(Color(0.09, 0.13, 0.23), Color(0.21, 0.28, 0.43)))
	solo_button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.18, 0.31), ACCENT))
	solo_button.pressed.connect(func() -> void: solo_requested.emit())
	actions.add_child(solo_button)

	settings_button = Button.new()
	settings_button.name = "SettingsButton"
	settings_button.text = "SETTINGS · COMING SOON"
	settings_button.flat = true
	settings_button.add_theme_font_size_override("font_size", 11)
	settings_button.add_theme_color_override("font_color", MUTED)
	settings_button.pressed.connect(_on_settings_pressed)
	box.add_child(settings_button)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Enter a callsign and join, or play offline."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0.0, 34.0)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", MUTED)
	box.add_child(status_label)

	var hint := Label.new()
	hint.name = "CaptureHint"
	hint.text = "CLICK CANVAS TO CAPTURE MOUSE  ·  ESC RELEASES  ·  F6 NETWORK PANEL"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.34, 0.39, 0.51))
	box.add_child(hint)


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.49, 0.54, 0.66))
	return label


func _style_field(field: LineEdit) -> void:
	field.custom_minimum_size = Vector2(0.0, 34.0)
	field.add_theme_font_size_override("font_size", 13)
	field.add_theme_color_override("font_color", TEXT)
	field.add_theme_color_override("caret_color", ACCENT)
	field.add_theme_stylebox_override("normal", _field_style(Color(0.05, 0.08, 0.15), Color(0.16, 0.22, 0.35)))
	field.add_theme_stylebox_override("focus", _field_style(Color(0.06, 0.10, 0.18), ACCENT))


func _field_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	return style


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _on_join_pressed() -> void:
	join_requested.emit(join_config())


func _on_settings_pressed() -> void:
	set_status("Settings panel is coming soon — sensitivity and audio keep their saved values.", "info")
	settings_requested.emit()
