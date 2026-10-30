extends BodTestSuite
## Entry menu state + one-origin endpoint selection. Pure UI/logic only: no
## socket is opened in this suite.

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")
const LOADING_SCENE := preload("res://scenes/ui/loading_screen.tscn")

var _menus: Array[Node] = []


func after_test() -> void:
	for menu in _menus:
		if is_instance_valid(menu):
			menu.queue_free()
	_menus.clear()


func test_menu_has_required_entry_fields() -> void:
	var menu := _make_menu()
	menu.configure({
		"host": "play.example.test",
		"port": 8099,
		"name": "Alice",
		"page_host": "play.example.test",
		"page_port": 8099,
		"page_secure": false,
		"proxy_ws": "/ws",
	})
	expect(menu.title_label.text == "BALL OF DUTY", "menu shows the game title")
	expect(menu.name_field.text == "Alice", "menu keeps the supplied callsign")
	expect(menu.host_field.text == "play.example.test", "menu keeps the supplied host")
	expect(menu.port_field.text == "8099", "menu keeps the supplied port")
	expect(menu.join_button.text == "JOIN MATCH", "menu has Join")
	expect(menu.solo_button.text == "SOLO", "menu has Solo")
	expect(menu.settings_button.text.contains("SETTINGS"), "menu has a settings entry")
	expect(menu.mode_label.text.contains("ONE-ORIGIN"), "proxy page explains one-origin mode")
	var config: Dictionary = menu.join_config()
	expect(bool(config["proxied"]), "page-origin config is marked proxied")
	expect(String(config["path"]) == "/ws", "proxied join uses the /ws path")


func test_menu_direct_mode_when_port_is_edited() -> void:
	var menu := _make_menu()
	menu.configure({
		"host": "127.0.0.1",
		"port": 8099,
		"name": "Bob",
		"page_host": "127.0.0.1",
		"page_port": 8099,
		"page_secure": false,
		"proxy_ws": "/ws",
	})
	menu.port_field.text = "9180"
	var config: Dictionary = menu.join_config()
	expect(not bool(config["proxied"]), "editing the port falls back to direct mode")
	expect(String(config["path"]) == "", "direct mode has no proxy path")
	expect(int(config["port"]) == 9180, "direct mode keeps the edited port")
	expect(menu.mode_label.text.contains("DIRECT"), "mode hint switches to direct when edited")


func test_menu_join_and_solo_signals() -> void:
	var menu := _make_menu()
	menu.configure({
		"host": "127.0.0.1",
		"port": 9080,
		"name": "  Scout!  ",
		"page_host": "127.0.0.1",
		"page_port": 9080,
		"page_secure": false,
		"proxy_ws": "",
	})
	var joined: Array = []
	var soloed: Array = []
	menu.join_requested.connect(func(config: Dictionary) -> void: joined.append(config))
	menu.solo_requested.connect(func() -> void: soloed.append(true))
	menu.join_button.pressed.emit()
	expect(joined.size() == 1, "Join emits one join request")
	if not joined.is_empty():
		expect(String(joined[0]["name"]).strip_edges() == "Scout!", "callsign is trimmed")
	menu.solo_button.pressed.emit()
	expect(soloed.size() == 1, "Solo emits one request")


func test_menu_settings_entry_and_status_tones() -> void:
	var menu := _make_menu()
	var settings_pressed: Array = []
	menu.settings_requested.connect(func() -> void: settings_pressed.append(true))
	menu.set_status("boom", "error")
	expect(menu.status_label.text == "boom", "error text is shown in the menu")
	expect(
		menu.status_label.get_theme_color("font_color") == Color(1.0, 0.482353, 0.533333),
		"error text uses the error colour"
	)
	menu.settings_button.pressed.emit()
	expect(settings_pressed.size() == 1, "settings entry opens the real panel")
	expect(menu.settings_button.text == "SETTINGS", "settings entry is no longer a placeholder")


func test_menu_visibility_states() -> void:
	var menu := _make_menu()
	expect(menu.is_open(), "menu starts open")
	menu.hide_menu()
	expect(not menu.is_open(), "menu can be hidden after joining")
	menu.show_menu()
	expect(menu.is_open(), "menu can be shown again after a failure")


func test_loading_screen_is_animated_and_cancellable() -> void:
	var loading = LOADING_SCENE.instantiate()
	add_child(loading)
	loading.show_loading("Connecting to arena…")
	expect(loading.is_loading(), "loading overlay is visible while joining")
	var cancel: Array = []
	loading.cancel_requested.connect(func() -> void: cancel.append(true))
	loading.cancel_button.pressed.emit()
	expect(cancel.size() == 1, "loading screen can be cancelled back to the menu")
	loading.show_reconnect(2, 5400)
	expect(loading.status_label.text.contains("Reconnecting"), "reconnect status is explicit")
	loading.hide_loading()
	expect(not loading.is_loading(), "loading overlay hides after JOIN_OK")
	loading.queue_free()


func test_endpoint_selection_one_origin_vs_direct() -> void:
	var main_script := load("res://scripts/game/main.gd")
	var page := {
		"host": "play.example.test",
		"port": 8099,
		"secure": false,
		"proxy": "/ws",
	}
	var one_origin: Dictionary = main_script.resolve_endpoint({}, page)
	expect(String(one_origin["url"]) == "ws://play.example.test:8099/ws",
		"proxy page defaults to page origin + /ws (got %s)" % one_origin["url"])
	expect(bool(one_origin["proxied"]), "proxy default is marked proxied")

	var auto_join: Dictionary = main_script.resolve_endpoint({"join": "1", "name": "Ann"}, page)
	expect(String(auto_join["url"]) == "ws://play.example.test:8099/ws",
		"?join=1 on a proxy page keeps one-origin mode")

	var direct: Dictionary = main_script.resolve_endpoint(
		{"host": "10.0.0.5", "port": "9180", "name": "Dee"}, page
	)
	expect(String(direct["url"]) == "ws://10.0.0.5:9180",
		"explicit host/port keeps the legacy two-port path (got %s)" % direct["url"])
	expect(not bool(direct["proxied"]), "explicit host/port is direct mode")

	var port_only: Dictionary = main_script.resolve_endpoint({"port": "9080"}, page)
	expect(String(port_only["url"]) == "ws://play.example.test:9080",
		"?join=1&port=… links keep working against the page host")
	expect(not bool(port_only["proxied"]), "explicit port is direct mode")

	var forced: Dictionary = main_script.resolve_endpoint({"proxy": "1"}, page)
	expect(String(forced["url"]) == "ws://play.example.test:8099/ws",
		"?proxy=1 forces the page origin")

	var no_proxy: Dictionary = main_script.resolve_endpoint(
		{}, {"host": "127.0.0.1", "port": 8099, "secure": false, "proxy": ""}
	)
	expect(String(no_proxy["url"]) == "ws://127.0.0.1:9080",
		"plain static server keeps the direct default port (got %s)" % no_proxy["url"])

	var secure: Dictionary = main_script.resolve_endpoint(
		{}, {"host": "play.example.test", "port": 443, "secure": true, "proxy": "/ws"}
	)
	expect(String(secure["url"]).begins_with("wss://"), "https pages use wss://")
	expect(String(secure["name"]) == "Player", "missing name falls back to Player")
	var sanitized: Dictionary = main_script.resolve_endpoint({"name": "Bob!@#"}, page)
	expect(String(sanitized["name"]) == "Bob", "names are sanitized before connecting")


func test_network_manager_builds_one_origin_url() -> void:
	var net_script := load("res://scripts/networking/network_manager.gd")
	expect(
		net_script.build_ws_url("example.test", 8099, "/ws", false)
		== "ws://example.test:8099/ws",
		"transport URL includes the proxy path"
	)
	expect(
		net_script.build_ws_url("example.test", 9180, "", false)
		== "ws://example.test:9180",
		"legacy transport URL has no trailing path"
	)
	expect(
		net_script.build_ws_url("example.test", 443, "ws", true)
		== "wss://example.test:443/ws",
		"secure transport URL normalizes a missing slash"
	)


func _make_menu() -> Node:
	var menu = MENU_SCENE.instantiate()
	add_child(menu)
	_menus.append(menu)
	return menu
