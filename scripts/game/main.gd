extends Node3D
## Entry point. SOLO (menu → Solo): arena + local player, exactly as before.
## SERVER (--server): headless authority, no local player/HUD, snapshots at 30 Hz.
## CLIENT (menu → Join, --connect, or ?join=1 URL): local player + remotes.
##
## A page served by tools/serve.py advertises `window.__BOD_PROXY_WS__ = "/ws"`.
## In that one-origin mode Join uses the page host/port and that request path, so
## only the web port needs forwarding. An explicit `?host=`/`?port=` link keeps
## the legacy direct ws://host:port mode.

const DEFAULT_PORT := 9080
const MAIN_MENU_SCENE: PackedScene = preload("res://scenes/ui/main_menu.tscn")
const LOADING_SCENE: PackedScene = preload("res://scenes/ui/loading_screen.tscn")

var _menu
var _loading
var _panel: PanelContainer
var _status_label: Label
var _leave_button: Button
var _net_banner: Label
var _panel_pinned: bool = false

var _hud_layer: CanvasLayer
var _debug_layer: CanvasLayer
var _page: Dictionary = {}
var _proxy_ws: String = ""
var _join_endpoint: Dictionary = {}
var _in_game: bool = false
var _solo: bool = false
var _was_client: bool = false
var _match_entered: bool = false


func _ready() -> void:
	# Background tabs deliver second-long frame gaps; uncapped catch-up runs many
	# physics steps and bursts inputs at the server. Cap at 4: a 30 Hz client can
	# still feed the server down to ~7.5 FPS, while a hidden tab cannot burst.
	Engine.max_physics_steps_per_frame = 4
	Engine.physics_jitter_fix = 0.0
	var user_args := OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or user_args.has("--server"):
		_start_server(user_args)
		return
	_hud_layer = get_node_or_null("HUD") as CanvasLayer
	_debug_layer = get_node_or_null("DebugOverlay") as CanvasLayer
	_page = _read_page_info()
	_proxy_ws = String(_page.get("proxy", ""))

	_menu = MAIN_MENU_SCENE.instantiate()
	add_child(_menu)
	_loading = LOADING_SCENE.instantiate()
	add_child(_loading)
	_menu.join_requested.connect(_on_menu_join)
	_menu.solo_requested.connect(_on_menu_solo)
	_loading.cancel_requested.connect(_on_cancel_loading)

	_build_net_panel()
	_build_banner()
	_open_menu()
	_try_autoconnect(user_args)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F6:
			_panel_pinned = not _panel_pinned
			if _panel:
				_panel.visible = _panel_pinned


func _process(_delta: float) -> void:
	_update_net_panel_stats()
	_update_banner()
	_update_ui_state()


# --- menu / loading -------------------------------------------------------

func _open_menu(status: String = "", tone: String = "info") -> void:
	_in_game = false
	_solo = false
	_match_entered = false
	if _loading:
		_loading.hide_loading()
	_set_hud_visible(false)
	if _menu:
		_menu.configure(_menu_defaults(_last_or_page_endpoint()))
		_menu.show_menu()
		if status != "":
			_menu.set_status(status, tone)
		else:
			_menu.set_status("Enter a callsign and join, or play offline.", "info")


func _enter_menu(status: String, tone: String) -> void:
	_open_menu(status, tone)
	if _menu:
		_menu.grab_name_focus()


func _enter_match() -> void:
	_match_entered = true
	_in_game = true
	_solo = false
	if _menu:
		_menu.hide_menu()
	if _loading:
		_loading.hide_loading()
	_set_hud_visible(true)


func _enter_solo() -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm and gm.is_net_client():
		gm.stop_all()
		gm.clear_client_error()
	_was_client = false
	_join_endpoint = {}
	_in_game = true
	_solo = true
	_match_entered = true
	if _menu:
		_menu.hide_menu()
	if _loading:
		_loading.hide_loading()
	_set_hud_visible(true)


func _set_hud_visible(value: bool) -> void:
	if _hud_layer:
		_hud_layer.visible = value
	if _debug_layer:
		_debug_layer.visible = value


func _update_ui_state() -> void:
	var gm := get_node_or_null("/root/GameManager")
	var net := get_node_or_null("/root/NetworkManager")
	if gm == null or net == null:
		return

	if gm.is_net_client():
		_was_client = true
		var error_text: String = gm.client_error_text()
		if error_text != "":
			# GameManager normally drops to OFFLINE on failure; if an error lands
			# while still CLIENT, make it impossible to miss instead of leaving a
			# cosmetic-only match state.
			_leave_to_menu("Connection failed — %s\nJoin again to retry." % error_text, "error")
			return
		if gm.local_id > 0:
			if not _match_entered:
				_enter_match()
			return
		# Connected but not accepted yet, or retrying inside the grace window.
		if _match_entered:
			_match_entered = false
		_set_hud_visible(false)
		if _menu and _menu.is_open():
			_menu.hide_menu()
		_show_loading_state(net)
		return

	if _was_client:
		_was_client = false
		var reason: String = gm.client_error_text()
		if reason == "":
			reason = String(net.last_error)
		_was_client = false
		_enter_menu(
			"Connection failed — %s\nJoin again to retry." % reason if reason != "" else "Disconnected.",
			"error"
		)
	elif not _in_game and _menu and not _menu.is_open():
		_open_menu()


func _show_loading_state(net: Node) -> void:
	if _loading == null:
		return
	if bool(net.is_reconnecting()):
		_loading.show_reconnect(int(net.retry_attempt()), int(net.reconnect_remaining_msec()))
		return
	var host := String(_join_endpoint.get("host", "127.0.0.1"))
	var port := int(_join_endpoint.get("port", DEFAULT_PORT))
	if int(net.connection_status()) == MultiplayerPeer.CONNECTION_CONNECTED:
		_loading.show_loading("Joining match…")
	else:
		_loading.show_loading("Connecting to %s:%d…" % [host, port])


func _last_or_page_endpoint() -> Dictionary:
	if not _join_endpoint.is_empty():
		return _join_endpoint
	return resolve_endpoint({}, _page)


func _menu_defaults(endpoint: Dictionary) -> Dictionary:
	return {
		"host": String(endpoint.get("host", "127.0.0.1")),
		"port": int(endpoint.get("port", DEFAULT_PORT)),
		"name": String(endpoint.get("name", "Player")),
		"page_host": String(_page.get("host", "127.0.0.1")),
		"page_port": int(_page.get("port", DEFAULT_PORT)),
		"page_secure": bool(_page.get("secure", false)),
		"proxy_ws": _proxy_ws,
	}


func _on_menu_join(config: Dictionary) -> void:
	var params: Dictionary = {"name": String(config.get("name", "Player"))}
	if bool(config.get("proxied", false)):
		params["proxy"] = "1"
		params["ws"] = String(config.get("path", ""))
	else:
		params["host"] = String(config.get("host", "127.0.0.1"))
		params["port"] = int(config.get("port", DEFAULT_PORT))
	_begin_join(resolve_endpoint(params, _page))


func _on_menu_solo() -> void:
	_enter_solo()


func _begin_join(endpoint: Dictionary) -> void:
	var gm := get_node_or_null("/root/GameManager")
	var net := get_node_or_null("/root/NetworkManager")
	if gm == null or net == null:
		_enter_menu("Networking is unavailable.", "error")
		return
	if gm.is_net_client():
		gm.stop_all()
		gm.clear_client_error()
	_join_endpoint = endpoint
	net.client_path = String(endpoint.get("path", ""))
	net.client_tls = bool(endpoint.get("secure", false))
	_was_client = true
	_in_game = true
	_match_entered = false
	if _menu:
		_menu.hide_menu()
	_set_hud_visible(false)
	if _loading:
		_loading.show_loading("Connecting to %s:%d…" % [
			String(endpoint.get("host", "127.0.0.1")), int(endpoint.get("port", DEFAULT_PORT)),
		])
	var err: int = gm.client_start(
		self,
		String(endpoint.get("host", "127.0.0.1")),
		int(endpoint.get("port", DEFAULT_PORT)),
		String(endpoint.get("name", "Player"))
	)
	if err != OK:
		_was_client = false
		_in_game = false
		if _loading:
			_loading.hide_loading()
		if _menu:
			_menu.configure(_menu_defaults(endpoint))
			_menu.show_menu()
			_menu.set_status("Could not start connection: %s" % error_string(err), "error")


func _on_cancel_loading() -> void:
	_leave_to_menu("Join cancelled.", "info")


func _on_leave_pressed() -> void:
	_leave_to_menu("Left match.", "info")


func _leave_to_menu(status: String, tone: String) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		if gm.is_net_client():
			gm.stop_all()
		gm.clear_client_error()
	_was_client = false
	_join_endpoint = {}
	_panel_pinned = false
	if _panel:
		_panel.visible = false
	_enter_menu(status, tone)


func _try_autoconnect(args: PackedStringArray) -> void:
	var params := _url_params()
	if args.has("--connect"):
		var ci := args.find("--connect")
		if ci + 1 < args.size():
			params["host"] = args[ci + 1]
	var pi := args.find("--port")
	if pi >= 0 and pi + 1 < args.size():
		params["port"] = args[pi + 1]
	var ni := args.find("--name")
	if ni >= 0 and ni + 1 < args.size():
		params["name"] = args[ni + 1]

	var endpoint := resolve_endpoint(params, _page)
	if _menu:
		_menu.configure(_menu_defaults(endpoint))
		_menu.show_menu()
		_menu.set_status("Enter a callsign and join, or play offline.", "info")

	var auto_join: bool = args.has("--connect") or String(params.get("join", "")) == "1" or params.has("host")
	if auto_join:
		_begin_join(endpoint)


## Pure endpoint selection, covered by tests. Rules:
##   explicit ?host=            -> that host (legacy direct mode)
##   ?proxy=1 with a proxy      -> page origin + /ws
##   explicit ?port=            -> page host + that port (legacy direct mode)
##   page served with a proxy   -> page origin + /ws (one-port mode)
##   otherwise                  -> page host + DEFAULT_PORT (direct)
static func resolve_endpoint(params: Dictionary, page: Dictionary) -> Dictionary:
	var page_host := String(page.get("host", "127.0.0.1")).strip_edges()
	if page_host == "":
		page_host = "127.0.0.1"
	var page_port := int(page.get("port", DEFAULT_PORT))
	var page_secure := bool(page.get("secure", false))
	var proxy_ws := String(page.get("proxy", "")).strip_edges()
	var explicit_host := String(params.get("host", "")).strip_edges()
	var has_port := params.has("port") and str(params["port"]).strip_edges() != ""
	var explicit_port := int(params.get("port", 0)) if has_port else 0
	var force_proxy := String(params.get("proxy", "")) == "1"
	var ws_param := String(params.get("ws", "")).strip_edges()

	var host := page_host
	var port := DEFAULT_PORT
	var path := ""
	var proxied := false
	if explicit_host != "":
		host = explicit_host
		port = explicit_port if explicit_port > 0 else DEFAULT_PORT
		path = ws_param
	elif force_proxy and proxy_ws != "":
		port = page_port
		path = ws_param if ws_param != "" else proxy_ws
		proxied = true
	elif explicit_port > 0:
		port = explicit_port
		path = ""
	elif proxy_ws != "":
		port = page_port
		path = ws_param if ws_param != "" else proxy_ws
		proxied = true

	var display_name := NetProtocol.sanitize_name(String(params.get("name", "Player")))
	if display_name == "":
		display_name = "Player"
	return {
		"host": host,
		"port": port,
		"path": path,
		"secure": page_secure,
		"proxied": proxied,
		"name": display_name,
		"url": build_ws_url(host, port, path, page_secure),
	}


static func build_ws_url(host: String, port: int, path: String, secure: bool) -> String:
	var request_path := path.strip_edges()
	if request_path != "" and not request_path.begins_with("/"):
		request_path = "/" + request_path
	return "%s://%s:%d%s" % ["wss" if secure else "ws", host, port, request_path]


func _read_page_info() -> Dictionary:
	var info := {
		"host": "127.0.0.1",
		"port": DEFAULT_PORT,
		"secure": false,
		"proxy": "",
	}
	if not OS.has_feature("web"):
		return info
	var bridge := Engine.get_singleton("JavaScriptBridge") if Engine.has_singleton("JavaScriptBridge") else null
	if bridge == null:
		return info
	var raw := str(bridge.eval(
		"JSON.stringify({host:location.hostname,port:parseInt(location.port||(location.protocol==='https:'?'443':'80'),10),secure:location.protocol==='https:',proxy:(window.__BOD_PROXY_WS__||'')})",
		true
	))
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		info["host"] = String(parsed.get("host", info["host"]))
		info["port"] = int(parsed.get("port", info["port"]))
		info["secure"] = bool(parsed.get("secure", false))
		info["proxy"] = String(parsed.get("proxy", ""))
	return info


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


# --- network panel / banner ----------------------------------------------

func _build_net_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "NetworkPanel"
	var layer := CanvasLayer.new()
	layer.name = "NetUILayer"
	layer.layer = 21
	add_child(layer)
	layer.add_child(_panel)
	_panel.anchor_left = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -300.0
	_panel.offset_top = -116.0
	_panel.offset_right = -12.0
	_panel.offset_bottom = -12.0
	_panel.custom_minimum_size = Vector2(288, 0)
	_panel.visible = false

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var header := Label.new()
	header.text = "NETWORK · F6"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.215686, 0.878431, 0.784314))
	box.add_child(header)
	_status_label = Label.new()
	_status_label.name = "NetStatus"
	_status_label.text = "offline"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.9))
	box.add_child(_status_label)
	_leave_button = Button.new()
	_leave_button.name = "LeaveButton"
	_leave_button.text = "LEAVE MATCH"
	_leave_button.flat = true
	_leave_button.add_theme_font_size_override("font_size", 10)
	_leave_button.pressed.connect(_on_leave_pressed)
	box.add_child(_leave_button)


func _build_banner() -> void:
	var layer := CanvasLayer.new()
	layer.name = "NetBannerLayer"
	layer.layer = 21
	add_child(layer)
	_net_banner = Label.new()
	_net_banner.name = "NetBanner"
	_net_banner.anchor_left = 0.0
	_net_banner.anchor_right = 1.0
	_net_banner.anchor_top = 0.0
	_net_banner.offset_top = 56.0
	_net_banner.offset_bottom = 104.0
	_net_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_net_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_net_banner.add_theme_font_size_override("font_size", 15)
	_net_banner.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35))
	_net_banner.visible = false
	layer.add_child(_net_banner)


func _update_net_panel_stats() -> void:
	if _status_label == null or not is_instance_valid(_status_label):
		return
	var gm := get_node_or_null("/root/GameManager")
	var net := get_node_or_null("/root/NetworkManager")
	if gm == null or net == null:
		return
	if gm.is_net_client():
		var retry := ""
		if bool(net.is_reconnecting()):
			retry = " · reconnecting %d (%.1fs)" % [
				int(net.retry_attempt()), float(net.reconnect_remaining_msec()) / 1000.0,
			]
		_status_label.text = "id=%d remotes=%d rtt=%dms snap=%dB in=%d drop=%d%s" % [
			gm.local_id, gm.remote_count(), net.rtt_ms,
			net.last_snapshot_bytes, net.snapshots_processed, net.snapshots_dropped, retry,
		]
	elif gm.is_net_server():
		_status_label.text = "server · players=%d" % gm.server_player_count()
	else:
		_status_label.text = "offline (solo) · socket %s" % _connection_label(net)


func _connection_label(net: Node) -> String:
	match int(net.connection_status()):
		MultiplayerPeer.CONNECTION_CONNECTING:
			return "connecting"
		MultiplayerPeer.CONNECTION_CONNECTED:
			return "connected"
		_:
			return "disconnected"


func _update_banner() -> void:
	if _net_banner == null:
		return
	var gm := get_node_or_null("/root/GameManager")
	var net := get_node_or_null("/root/NetworkManager")
	if gm == null or net == null or not gm.is_net_client():
		_net_banner.visible = false
		return
	if bool(net.is_reconnecting()):
		_net_banner.text = "RECONNECTING… attempt %d · %.1fs left" % [
			int(net.retry_attempt()), float(net.reconnect_remaining_msec()) / 1000.0,
		]
		_net_banner.add_theme_color_override("font_color", Color(1.0, 0.768627, 0.419608))
		_net_banner.visible = true
	elif gm.local_id <= 0:
		# The loading screen is the status surface until JOIN_OK.
		_net_banner.visible = false
	elif gm.client_error_text() != "":
		_net_banner.text = "CONNECTION LOST — %s\nF6 opens the network panel" % gm.client_error_text()
		_net_banner.add_theme_color_override("font_color", Color(1.0, 0.482353, 0.533333))
		_net_banner.visible = true
	else:
		_net_banner.visible = false


# --- server ---------------------------------------------------------------

func _start_server(args: PackedStringArray) -> void:
	# Do not let a headless server spin a core. 60 FPS keeps the main loop
	# responsive while the 30 Hz physics tick does the simulation.
	Engine.max_fps = 60

	var port := DEFAULT_PORT
	var port_index := args.find("--port")
	if port_index >= 0 and port_index + 1 < args.size():
		port = int(args[port_index + 1])
	var bots := 0
	var bots_index := args.find("--bots")
	if bots_index >= 0 and bots_index + 1 < args.size():
		bots = maxi(0, int(args[bots_index + 1]))

	var local_player := get_node_or_null("Player")
	if local_player:
		local_player.queue_free()
	for layer_name in ["HUD", "DebugOverlay"]:
		var layer := get_node_or_null(layer_name) as CanvasLayer
		if layer:
			layer.visible = false

	var gm := get_node_or_null("/root/GameManager")
	var err: int = gm.server_start(self, port, bots) if gm else ERR_UNAVAILABLE
	if err != OK:
		push_error("BALL_OF_DUTY server failed to start: %s" % err)
		return
	print("BALL_OF_DUTY server listening on port %d" % port)
	get_tree().create_timer(0.75).timeout.connect(
		func() -> void:
			print("BALL_OF_DUTY server tick=%d" % Engine.get_physics_frames())
	)
