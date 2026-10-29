extends BodTestSuite
## Phase 2A class picker: five cards, persistent selection, Join payload, and
## `?class=0..4` URL handling (with `?join=1` still working).

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")

var _menus: Array[Node] = []


func after_test() -> void:
	for menu in _menus:
		if is_instance_valid(menu):
			menu.queue_free()
	_menus.clear()


func test_menu_shows_five_class_cards_and_defaults_to_knight() -> void:
	var menu := _make_menu()
	expect(menu.class_cards.size() == 5, "menu has five class cards")
	expect(menu.selected_class() == 0, "Knight is selected by default")
	expect(menu.class_hint.text.contains("KNIGHT"), "selected card is called out explicitly")
	expect(menu.class_hint.text.contains("HEAVY JAVELIN"), "selected card shows the weapon")
	var expected := ["KNIGHT", "MAGE", "ROGUE", "ROGUE HOODED", "BARBARIAN"]
	for index in expected.size():
		var card: Button = menu.class_cards[index]
		expect(card.text.begins_with(expected[index]), "card %d is %s" % [index, expected[index]])
		expect(card.text.contains("\n"), "card %d stacks name/weapon/role" % index)


func test_card_click_changes_selection_and_join_payload() -> void:
	var menu := _make_menu()
	menu.configure({"host": "127.0.0.1", "port": 9080, "name": "Pip",
		"page_host": "127.0.0.1", "page_port": 9080, "proxy_ws": ""})
	menu.class_cards[3].pressed.emit()
	expect(menu.selected_class() == 3, "clicking the Hooded card selects class 3")
	expect(menu.class_hint.text.contains("ROGUE HOODED"), "hint follows the click")
	var config: Dictionary = menu.join_config()
	expect(int(config.get("class_id", -1)) == 3, "Join passes class_id=3")
	menu.class_cards[1].pressed.emit()
	expect(menu.selected_class() == 1, "selection replaces, not toggles")
	expect(int(menu.join_config().get("class_id", -1)) == 1, "Join follows the new selection")


func test_join_signal_carries_class_and_selection_survives_show() -> void:
	var menu := _make_menu()
	menu.configure({"host": "127.0.0.1", "port": 9080, "name": "Pip",
		"page_host": "127.0.0.1", "page_port": 9080, "proxy_ws": ""})
	menu.class_cards[4].pressed.emit()
	var joins: Array = []
	menu.join_requested.connect(func(config: Dictionary) -> void: joins.append(config))
	menu.join_button.pressed.emit()
	expect(joins.size() == 1, "Join emits once")
	if not joins.is_empty():
		expect(int(joins[0]["class_id"]) == 4, "join_requested carries the Barbarian class")
	menu.hide_menu()
	menu.show_menu()
	expect(menu.selected_class() == 4, "selection persists while the menu is open/reopened")


func test_class_from_url_and_join_still_works() -> void:
	var main_script := load("res://scripts/game/main.gd")
	var page := {"host": "play.example.test", "port": 8099, "secure": false, "proxy": "/ws"}
	var auto_join: Dictionary = main_script.resolve_endpoint(
		{"join": "1", "name": "Ann", "class": "3"}, page
	)
	expect(String(auto_join["url"]) == "ws://play.example.test:8099/ws",
		"?join=1&class=3 keeps one-origin mode")
	expect(int(auto_join["class_id"]) == 3, "?class=3 selects the Hooded class")

	var default_class: Dictionary = main_script.resolve_endpoint({"join": "1"}, page)
	expect(int(default_class["class_id"]) == 0, "missing ?class defaults to Knight")

	var clamped: Dictionary = main_script.resolve_endpoint({"class": "99"}, page)
	expect(int(clamped["class_id"]) == 4, "out-of-range ?class clamps to the last class")

	var negative: Dictionary = main_script.resolve_endpoint({"class": "-2"}, page)
	expect(int(negative["class_id"]) == 0, "negative ?class clamps to Knight")

	var menu := _make_menu()
	menu.configure({
		"host": "127.0.0.1", "port": 9080, "name": "Pip",
		"page_host": "127.0.0.1", "page_port": 9080, "proxy_ws": "",
		"class_id": int(auto_join["class_id"]),
	})
	expect(menu.selected_class() == 3, "menu adopts the URL class")


func _make_menu() -> Node:
	var menu = MENU_SCENE.instantiate()
	add_child(menu)
	_menus.append(menu)
	return menu
