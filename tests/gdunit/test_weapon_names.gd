extends BodTestSuite
## QA bug 3: WeaponStats.display_name (resolved through WeaponRegistry) is the
## single source of truth for the menu card, the class hint/summary and the
## WeaponController fallback table.

const MENU_SCENE := preload("res://scenes/ui/main_menu.tscn")

var _menus: Array[Node] = []


func after_test() -> void:
	for menu in _menus:
		if is_instance_valid(menu):
			menu.queue_free()
	_menus.clear()


func test_menu_cards_and_hint_use_registry_display_names() -> void:
	var menu := _make_menu()
	for class_id in NetProtocol.CLASS_COUNT:
		var stats := WeaponRegistry.stats_for(class_id)
		expect(stats != null, "class %d has registry stats" % class_id)
		if stats == null:
			continue
		var expected := String(stats.display_name).strip_edges()
		expect(expected != "", "class %d has a display name" % class_id)

		var lines: PackedStringArray = menu.class_cards[class_id].text.split("\n")
		expect(lines.size() == 3, "card %d stacks name/weapon/role" % class_id)
		if lines.size() == 3:
			expect(lines[1] == expected.to_upper(),
				"card %d weapon is %s (got %s)" % [class_id, expected.to_upper(), lines[1]])

		var summary: Dictionary = menu.class_summary(class_id)
		expect(String(summary.get("weapon", "")) == expected,
			"summary %d weapon is %s (got %s)" % [
				class_id, expected, String(summary.get("weapon", "")),
			])

		menu.select_class(class_id)
		expect(menu.class_hint.text.contains(expected.to_upper()),
			"hint %d names %s (got %s)" % [class_id, expected.to_upper(), menu.class_hint.text])


func test_controller_fallback_matches_registry() -> void:
	expect(WeaponController.CLASS_WEAPON_NAMES.size() == NetProtocol.CLASS_COUNT,
		"fallback table covers every class")
	for class_id in NetProtocol.CLASS_COUNT:
		var stats := WeaponRegistry.stats_for(class_id)
		expect(stats != null, "class %d has registry stats" % class_id)
		if stats == null:
			continue
		var expected := String(stats.display_name).strip_edges()
		expect(String(WeaponController.CLASS_WEAPON_NAMES[class_id]) == expected,
			"fallback %d is %s (got %s)" % [
				class_id, expected, String(WeaponController.CLASS_WEAPON_NAMES[class_id]),
			])
		expect(WeaponController.class_weapon_name(class_id) == expected,
			"class_weapon_name(%d) is %s" % [class_id, expected])


func _make_menu() -> Node:
	var menu = MENU_SCENE.instantiate()
	add_child(menu)
	_menus.append(menu)
	return menu
