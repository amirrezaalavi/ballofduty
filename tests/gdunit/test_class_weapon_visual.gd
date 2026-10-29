extends BodTestSuite
## Phase 2A client visual contract: class → variant, five weapon/muzzle
## attachments, per-class animation map, and HUD class/heat/charge labels.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const HUD_SCRIPT := preload("res://scripts/ui/hud.gd")

const EXPECTED_ANIM := [
	["Ranged_2H_Aiming", "Throw"],
	["Ranged_Magic_Spellcasting", "Ranged_Magic_Shoot"],
	["Ranged_Bow_Draw", "Ranged_Bow_Release"],
	["Ranged_1H_Aiming", "Ranged_1H_Shoot"],
	["Ranged_1H_Aiming", "Throw"],
]
const EXPECTED_MUZZLE_Z := [-0.47, -0.51, -0.39, -0.47, -0.54]

var _players: Array[PlayerController] = []
var _huds: Array[Node] = []


func after_test() -> void:
	for hud in _huds:
		if is_instance_valid(hud):
			hud.queue_free()
	_huds.clear()
	for player in _players:
		if is_instance_valid(player):
			player.free()
	_players.clear()


func test_class_selects_variant_not_net_id() -> void:
	for class_id in 5:
		expect(CharacterVisual.variant_index_for(class_id) == class_id,
			"class %d maps to variant %d" % [class_id, class_id])
		expect(CharacterVisual.variant_index_for(5) == 4, "classes clamp to the last variant")
		var player := await _spawn(class_id, 900 + class_id)
		var character := player.get_node_or_null("Visual/Character") as Node3D
		expect(character != null, "class %d has a Character node" % class_id)
		if character == null:
			continue
		expect(String(character.get_meta("kaykit_variant", "")) == CharacterVisual.VARIANT_NAMES[class_id],
			"class %d shows %s (got %s)" % [
				class_id, CharacterVisual.VARIANT_NAMES[class_id],
				String(character.get_meta("kaykit_variant", "")),
			])
		expect((player.visual as CharacterVisual).class_id() == class_id,
			"visual reports the class it built")


func test_five_weapons_keep_hand_mount_and_muzzle_contract() -> void:
	for class_id in 5:
		var player := await _spawn(class_id, 40 + class_id)
		var mount := player.get_node_or_null("GunHand/GripSocket/GunMount") as Node3D
		if mount == null:
			mount = player.get_node_or_null("Visual/GunMount") as Node3D
		var gun := mount.get_node_or_null("Gun") as Node3D if mount else null
		var muzzle := mount.get_node_or_null("Muzzle") as Marker3D if mount else null
		expect(mount != null, "class %d keeps GunMount" % class_id)
		expect(gun != null, "class %d swaps in its weapon under GunMount" % class_id)
		expect(muzzle != null, "class %d keeps the Muzzle marker" % class_id)
		if gun == null or muzzle == null or mount == null:
			continue
		expect(player.weapon != null and player.weapon.muzzle == muzzle,
			"class %d WeaponController still points at Muzzle" % class_id)
		expect(is_equal_approx(muzzle.position.z, EXPECTED_MUZZLE_Z[class_id]),
			"class %d muzzle sits at the weapon tip (%.2f)" % [class_id, muzzle.position.z])
		expect(gun.find_children("*", "MeshInstance3D", true, false).size() > 0,
			"class %d weapon has visible meshes" % class_id)
		for node in gun.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			expect(mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"class %d weapon casts no shadow" % class_id)

		var bounds := _local_bounds(gun)
		print("  class %d weapon length=%.3f m forward=%.3f m" % [
			class_id, bounds.size.z, bounds.position.z,
		])
		expect(bounds.size.z > 0.30 and bounds.size.z < 0.85,
			"class %d weapon is 0.30-0.85 m long (%.3f)" % [class_id, bounds.size.z])
		expect(bounds.position.z < -0.20, "class %d weapon points forward" % class_id)

		var hand := player.get_node_or_null("GunHand") as BoneAttachment3D
		expect(hand != null and hand.bone_name == "handslot.r",
			"class %d weapon is hand-locked to handslot.r" % class_id)
		expect(player.get_node_or_null("Visual/GunMount") == null,
			"class %d mount moved out of the floating visual slot" % class_id)


func test_class_animation_map_and_hold_overlay() -> void:
	for class_id in 5:
		var anim := CharacterVisual.class_anim(class_id)
		expect(StringName(anim["hold"]) == StringName(EXPECTED_ANIM[class_id][0]),
			"class %d hold is %s" % [class_id, EXPECTED_ANIM[class_id][0]])
		expect(StringName(anim["shoot"]) == StringName(EXPECTED_ANIM[class_id][1]),
			"class %d shoot is %s" % [class_id, EXPECTED_ANIM[class_id][1]])

	var player := await _spawn(1, 71)
	var hold := player.get_node_or_null("UpperBodyHold") as AnimationPlayer
	var shot := player.get_node_or_null("ShotOverlay") as AnimationPlayer
	var reload := player.get_node_or_null("ReloadOverlay") as AnimationPlayer
	expect(hold != null, "upper-body hold overlay exists")
	if hold == null:
		return
	player.aiming = true
	player.aim_hold_until_msec = Time.get_ticks_msec() + 800
	for _i in 14:
		await get_tree().process_frame
	expect(hold.current_animation == &"Ranged_Magic_Spellcasting",
		"Mage hold uses Ranged_Magic_Spellcasting (got %s)" % hold.current_animation)
	player.weapon.shot_fired.emit(player.global_position, Vector3.FORWARD)
	await get_tree().process_frame
	expect(shot != null and shot.current_animation == &"Ranged_Magic_Shoot",
		"Mage shot uses Ranged_Magic_Shoot")
	player.weapon.reload_state_changed.emit(true)
	await get_tree().process_frame
	expect(reload != null and reload.current_animation == &"Ranged_2H_Reload",
		"Mage reload keeps the 2H reload overlay")
	player.weapon.reload_state_changed.emit(false)


func test_hud_shows_class_weapon_heat_and_charge() -> void:
	var player := await _spawn(1, 81)
	player.weapon.spawn_projectiles = false
	var hud := _make_hud(player)
	expect(hud.weapon_name_text() == "Arcane Staff",
		"HUD falls back to the Mage weapon label (got %s)" % hud.weapon_name_text())
	expect(hud.fire_mode() == "HEAT", "Mage HUD reads as a heat weapon")
	expect(is_equal_approx(hud.heat_ratio(), 0.0), "heat starts empty")

	var fire := PlayerInputFrame.new()
	fire.fire = true
	player.weapon.tick(1.0 / 30.0, fire)
	await get_tree().process_frame
	expect(hud.heat_ratio() > 0.0, "firing raises the heat indicator")
	hud._on_heat(player.weapon.heat_max(), player.weapon.heat_max())
	expect(hud.state_label() == "OVERHEATED", "HUD shows the heat lockout")
	hud._on_heat(0.0, player.weapon.heat_max())

	# Rogue: charge state and label.
	player.class_id = 2
	player.weapon.set_class(2)
	hud.bind_player(player)
	expect(hud.weapon_name_text() == "Recurve Longbow", "HUD follows the class change")
	expect(hud.fire_mode() == "CHARGE", "Rogue HUD reads as a charge weapon")
	player.weapon.reset_ammo()
	var draw := PlayerInputFrame.new()
	draw.fire = true
	for _i in 15:
		player.weapon.tick(1.0 / 30.0, draw)
	await get_tree().process_frame
	expect(hud.charge_ratio() > 0.4, "holding fire builds the draw meter")
	expect(hud.state_label().begins_with("DRAW"), "HUD shows the draw percentage")
	var before := player.weapon.ammo
	draw.fire = false
	player.weapon.tick(1.0 / 30.0, draw)
	expect(player.weapon.ammo == before - 1, "releasing the draw fires once")
	expect(is_equal_approx(hud.charge_ratio(), 0.0), "release clears the draw meter")

	# Hooded: burst label; reload label keeps priority.
	player.class_id = 3
	player.weapon.set_class(3)
	hud.bind_player(player)
	expect(hud.fire_mode() == "BURST", "Hooded HUD reads as a burst weapon")
	expect(hud.state_label().begins_with("BURST"), "HUD shows the burst count")
	hud._on_reload(true)
	expect(hud.state_label() == "RELOADING", "reload label keeps priority")
	hud._on_reload(false)
	hud._on_ammo(3, -1)
	expect(hud.ammo_text() == "3", "HUD ammo follows the weapon signal")
	expect(hud.reserve_text().contains("reserve"), "HUD reserve line stays present")


func _spawn(class_id: int, net_id: int) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.class_id = class_id
	player.net_id = net_id
	add_child(player)
	_players.append(player)
	for _i in 4:
		await get_tree().physics_frame
	for _i in 8:
		await get_tree().process_frame
	player.set_physics_process(false)
	return player


func _local_bounds(gun: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for node in gun.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var xf := gun.global_transform.affine_inverse() * mesh_instance.global_transform
		var bounds: AABB = xf * mesh_instance.get_aabb()
		if first:
			total = bounds
			first = false
		else:
			total = total.merge(bounds)
	return total


func _make_hud(player: PlayerController) -> Control:
	var hud := HUD_SCRIPT.new() as Control
	add_child(hud)
	_huds.append(hud)
	hud.bind_player(player)
	return hud
