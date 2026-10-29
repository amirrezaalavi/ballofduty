extends Node3D
## Entry point. SOLO (default): arena + local player, exactly as before.
## SERVER (--server): headless authority, no local player/HUD, snapshots at 30 Hz.
## CLIENT (--connect or panel or ?join=1 URL): local player + remotes.

const DEFAULT_PORT := 9080

var _panel: PanelContainer
var _host_field: LineEdit
var _port_field: LineEdit
var _name_field: LineEdit
var _status_label: Label
var _connect_button: Button


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or user_args.has("--server"):
		_start_server(user_args)
		return
	_build_connect_panel()
	_show_boot_version()
	_try_autoconnect(user_args)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F6 and _panel:
			_panel.visible = not _panel.visible


func _process(_delta: float) -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	var gm := get_node_or_null("/root/GameManager")
	var net := get_node_or_null("/root/NetworkManager")
	if gm == null or net == null:
		return
	if gm.is_net_client():
		_status_label.text = "id=%d remotes=%d rtt=%dms snap=%dB in=%d drop=%d" % [
			gm.local_id, gm.remote_count(), net.rtt_ms,
			net.last_snapshot_bytes, net.snapshots_processed, net.snapshots_dropped,
		]
	elif not gm.is_net_client() and not gm.is_net_server():
		_status_label.text = "offline (solo)"
	_connect_button.text = "Disconnect" if gm.is_net_client() else "Connect"


# --- server ---------------------------------------------------------------

func _start_server(args: PackedStringArray) -> void:
	# Do not let a headless server spin a core. 60 FPS keeps the main loop
	# responsive while the 30 Hz physics tick does the simulation.
	Engine.max_fps = 60

	var port := DEFAULT_PORT
	var port_index := args.find("--port")
	if port_index >= 0 and port_index + 1 < args.size():
		port = int(args[port_index + 1])

	var local_player := get_node_or_null("Player")
	if local_player:
		local_player.queue_free()
	for layer_name in ["HUD", "DebugOverlay"]:
		var layer := get_node_or_null(layer_name) as CanvasLayer
		if layer:
			layer.visible = false
	if _panel:
		_panel.queue_free()

	var gm := get_node_or_null("/root/GameManager")
	var err: int = gm.server_start(self, port) if gm else ERR_UNAVAILABLE
	if err != OK:
		push_error("BALL_OF_DUTY server failed to start: %s" % err)
		return
	print("BALL_OF_DUTY server listening on port %d" % port)
	get_tree().create_timer(0.75).timeout.connect(
		func() -> void:
			print("BALL_OF_DUTY server tick=%d" % Engine.get_physics_frames())
	)


# --- client ---------------------------------------------------------------

func _try_autoconnect(args: PackedStringArray) -> void:
	var params := _url_params()
	var host := ""
	var port := DEFAULT_PORT
	var display_name := "Player"
	if args.has("--connect"):
		var ci := args.find("--connect")
		if ci + 1 < args.size():
			host = args[ci + 1]
	var pi := args.find("--port")
	if pi >= 0 and pi + 1 < args.size():
		port = int(args[pi + 1])
	var ni := args.find("--name")
	if ni >= 0 and ni + 1 < args.size():
		display_name = args[ni + 1]
	if params.has("host"):
		host = params["host"]
	# ?join=1 without an explicit host should reach the machine that served the
	# page, not the tester's own localhost.
	if host == "" and params.get("join", "") == "1" and OS.has_feature("web"):
		host = _page_hostname()
	if params.has("port"):
		port = int(params["port"])
	if params.has("name"):
		display_name = params["name"]
	if _host_field:
		_host_field.text = host if host != "" else "127.0.0.1"
		_port_field.text = str(port)
		_name_field.text = display_name
	if host != "" or params.get("join", "") == "1":
		_connect_to(host if host != "" else "127.0.0.1", port, display_name)


func _connect_to(host: String, port: int, display_name: String) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		return
	if gm.is_net_client():
		gm.stop_all()
		_status_label.text = "disconnected"
		return
	var err: int = gm.client_start(self, host, port, display_name)
	if err != OK:
		_status_label.text = "connect failed: %s" % err
	else:
		_status_label.text = "connecting to %s:%d…" % [host, port]


func _page_hostname() -> String:
	var bridge := Engine.get_singleton("JavaScriptBridge") if Engine.has_singleton("JavaScriptBridge") else null
	if bridge == null:
		return "127.0.0.1"
	var page_host := str(bridge.eval("window.location.hostname", true))
	return page_host if page_host != "" else "127.0.0.1"


func _url_params() -> Dictionary:
	var out: Dictionary = {}
	if not OS.has_feature("web"):
		return out
	var bridge := Engine.get_singleton("JavaScriptBridge") if Engine.has_singleton("JavaScriptBridge") else null
	if bridge == null:
		return out
	var query := str(bridge.eval("window.location.search", true)).trim_prefix("?")
	for part in query.split("&"):
		var bits := part.split("=", true, 1)
		if bits.size() == 2 and bits[0] != "":
			out[bits[0]] = bits[1].uri_decode()
	return out


func _build_connect_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ConnectPanel"
	var layer := CanvasLayer.new()
	layer.name = "NetUILayer"
	layer.layer = 9
	add_child(layer)
	layer.add_child(_panel)
	_panel.anchor_left = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -260.0
	_panel.offset_top = -190.0
	_panel.offset_right = 0.0
	_panel.offset_bottom = 0.0
	_panel.custom_minimum_size = Vector2(244, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	_host_field = LineEdit.new()
	_host_field.placeholder_text = "host (127.0.0.1)"
	box.add_child(_host_field)
	_port_field = LineEdit.new()
	_port_field.placeholder_text = "port (9080)"
	box.add_child(_port_field)
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "name"
	_name_field.max_length = 16
	box.add_child(_name_field)
	_connect_button = Button.new()
	_connect_button.text = "Connect"
	_connect_button.pressed.connect(_on_connect_pressed)
	box.add_child(_connect_button)
	_status_label = Label.new()
	_status_label.text = "offline (solo)"
	_status_label.add_theme_font_size_override("font_size", 11)
	box.add_child(_status_label)


func _on_connect_pressed() -> void:
	var host := _host_field.text.strip_edges()
	if host == "":
		host = "127.0.0.1"
	var port := _port_field.text.strip_edges().to_int()
	if port <= 0:
		port = DEFAULT_PORT
	var display_name := _name_field.text.strip_edges()
	if display_name == "":
		display_name = "Player"
	_connect_to(host, port, display_name)


## Temporary CP0 boot stamp. Replaced by the real HUD in CP1/CP3.
func _show_boot_version() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
	var layer := CanvasLayer.new()
	layer.name = "BootOverlay"
	add_child(layer)

	var label := Label.new()
	label.text = "BALL OF DUTY  v%s" % version
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.215686, 0.878431, 0.784314))
	layer.add_child(label)

	var hint := Label.new()
	hint.text = "CLICK CANVAS TO CAPTURE MOUSE  ·  ESC RELEASES"
	hint.position = Vector2(24, 42)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.49, 0.54, 0.66))
	layer.add_child(hint)

	var tween := create_tween()
	tween.tween_interval(3.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.parallel().tween_property(hint, "modulate:a", 0.0, 0.6)
	tween.tween_callback(layer.queue_free)
