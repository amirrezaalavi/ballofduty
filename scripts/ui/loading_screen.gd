extends CanvasLayer
## Join/match loading overlay. The HTML shell owns the boot animation; this
## screen covers the handshake between "Join" and the first authoritative
## JOIN_OK so a slow or unreachable server never looks like a dead menu.

signal cancel_requested

const ACCENT := Color(0.215686, 0.878431, 0.784314)
const WARN := Color(1.0, 0.768627, 0.419608)

var status_label: Label
var detail_label: Label
var progress: ProgressBar
var cancel_button: Button

var _elapsed: float = 0.0
var _spinner: Control
var _target_message: String = ""
var _message: String = ""
var _reconnecting: bool = false


func _ready() -> void:
	layer = 19
	visible = false
	_build_ui()


func show_loading(message: String) -> void:
	visible = true
	_reconnecting = false
	_set_message(message)
	if cancel_button:
		cancel_button.text = "CANCEL"
	if progress:
		progress.add_theme_color_override("font_color", ACCENT)
		progress.modulate = Color.WHITE


func show_reconnect(attempt: int, remaining_msec: int) -> void:
	visible = true
	_reconnecting = true
	var seconds := maxf(0.0, float(remaining_msec) / 1000.0)
	_set_message("Reconnecting… attempt %d · %.1fs left" % [maxi(attempt, 1), seconds])
	if detail_label:
		detail_label.text = "The match is paused from your side until the socket is back."
	if cancel_button:
		cancel_button.text = "RETURN TO MENU"
	if progress:
		progress.modulate = WARN


func set_message(message: String) -> void:
	_set_message(message)


func hide_loading() -> void:
	visible = false
	_reconnecting = false


func is_loading() -> bool:
	return visible


func _build_ui() -> void:
	var root := Control.new()
	root.name = "LoadingRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.023529, 0.035294, 0.070588, 0.96)
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box := VBoxContainer.new()
	box.name = "LoadingContent"
	box.custom_minimum_size = Vector2(420.0, 0.0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	_spinner = Control.new()
	_spinner.name = "Spinner"
	_spinner.custom_minimum_size = Vector2(72.0, 72.0)
	_spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_spinner.draw.connect(func() -> void: _draw_spinner(_spinner))
	box.add_child(_spinner)

	var title := Label.new()
	title.name = "LoadingTitle"
	title.text = "DEPLOYING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", ACCENT)
	box.add_child(title)

	status_label = Label.new()
	status_label.name = "LoadingStatus"
	status_label.text = "Connecting…"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.909804, 0.92549, 0.972549))
	box.add_child(status_label)

	detail_label = Label.new()
	detail_label.name = "LoadingDetail"
	detail_label.text = "Waiting for the arena authority to accept the join."
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 10)
	detail_label.add_theme_color_override("font_color", Color(0.490196, 0.533333, 0.65098))
	box.add_child(detail_label)

	progress = ProgressBar.new()
	progress.name = "LoadingProgress"
	progress.custom_minimum_size = Vector2(0.0, 8.0)
	progress.show_percentage = false
	progress.max_value = 100.0
	progress.value = 0.0
	box.add_child(progress)

	cancel_button = Button.new()
	cancel_button.name = "LoadingCancel"
	cancel_button.text = "CANCEL"
	cancel_button.flat = true
	cancel_button.add_theme_font_size_override("font_size", 11)
	cancel_button.add_theme_color_override("font_color", Color(0.490196, 0.533333, 0.65098))
	cancel_button.pressed.connect(func() -> void: cancel_requested.emit())
	box.add_child(cancel_button)


func _set_message(message: String) -> void:
	_target_message = message
	# Message changes are brief; a tiny type-in would be noise. Use it directly.
	_message = message
	if status_label:
		status_label.text = message


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _spinner and is_instance_valid(_spinner):
		_spinner.queue_redraw()
	if progress:
		if _reconnecting:
			# Slow pulse: the grace window is indeterminate.
			progress.value = 50.0 + sin(_elapsed * 2.0) * 30.0
		else:
			progress.value = fmod(_elapsed * 42.0, 100.0)
	if detail_label and not _reconnecting and _elapsed > 1.2:
		detail_label.text = "Still trying. A direct ws:// socket may be blocked by the page origin."


func _draw_spinner(canvas: Control) -> void:
	var center: Vector2 = canvas.size * 0.5
	var radius := minf(canvas.size.x, canvas.size.y) * 0.34
	var color := ACCENT if not _reconnecting else WARN
	# Faint track plus twelve orbiting ticks: readable without a texture.
	canvas.draw_arc(center, radius, 0.0, TAU, 48, Color(color, 0.18), 2.0, true)
	for i in 12:
		var angle := _elapsed * 3.4 + float(i) * TAU / 12.0
		var inner := center + Vector2(cos(angle), sin(angle)) * (radius - 5.0)
		var outer := center + Vector2(cos(angle), sin(angle)) * (radius + 3.0)
		var alpha := 0.25 + 0.75 * float(i) / 12.0
		canvas.draw_line(inner, outer, Color(color, alpha), 2.0)
