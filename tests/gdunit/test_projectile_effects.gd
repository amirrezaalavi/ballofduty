extends BodTestSuite
## Phase 2A projectile effects: gravity drop, pierce, splash, and the
## knockback/slow/bleed hooks. All resolution is server-side.

const DT := 1.0 / 30.0

var _world: Node3D
var _a: PlayerController
var _b: PlayerController
var _c: PlayerController
var _combat: ServerCombat
var _entry: Dictionary
var _entry_b: Dictionary


func after_test() -> void:
	if is_instance_valid(_world):
		_world.free()


func _setup(class_id: int, b_pos: Vector3, c_pos: Vector3, with_floor := true) -> void:
	_world = Node3D.new()
	add_child(_world)
	if with_floor:
		var floor_body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(60, 1, 60)
		col.shape = box
		floor_body.add_child(col)
		floor_body.position = Vector3(0, -0.55, 0)
		_world.add_child(floor_body)

	_a = _player(1, class_id, Vector3(0.0, 0.2, 0.0))
	_b = _player(2, 1, b_pos)
	_c = _player(3, 1, c_pos)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var fallback := load("res://resources/weapons/rifle_stats.tres") as WeaponStats
	_combat = ServerCombat.new(_world, fallback)
	_entry = {"id": 1, "class_id": class_id, "node": _a}
	_entry_b = {"id": 2, "class_id": 1, "node": _b}
	_combat.reset_player(_entry)
	_combat.reset_player(_entry_b)


func _player(id: int, class_id: int, position: Vector3) -> PlayerController:
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_world.add_child(player)
	player.make_server(id, class_id)
	player.global_position = position
	return player


func _health(player: PlayerController) -> HealthComponent:
	return player.get_node("HealthComponent") as HealthComponent


func _aim_frame_at(target: Node3D, fire: bool = true) -> PlayerInputFrame:
	var angles := ServerCombat.aim_angles(_a.global_position, target.global_position)
	var frame := PlayerInputFrame.new()
	frame.yaw = angles.x
	frame.pitch = angles.y
	frame.fire = fire
	return frame


func _fire_at(target: Node3D, wait_frames: int = 10) -> Dictionary:
	var shot := _combat.process(_entry, _a, _aim_frame_at(target), DT)
	for _i in wait_frames:
		await get_tree().physics_frame
	return shot


func _body_shape(player: PlayerController) -> Node3D:
	return player.get_node("BodyHurtbox/CollisionShape3D") as Node3D


func test_knight_projectile_gravity_drop() -> void:
	await _setup(0, Vector3(0, 0.2, -20), Vector3(0, 0.2, -40), false)
	var stats := WeaponRegistry.stats_for(0)
	var projectile := stats.projectile_scene.instantiate() as Projectile
	_world.add_child(projectile)
	projectile.global_position = Vector3(0.0, 8.0, 0.0)
	projectile.setup(Vector3(0, 0, -1), stats, 1, [])
	var start_y := projectile.global_position.y
	for _i in 10:
		await get_tree().physics_frame
	expect(projectile.velocity.y < -0.5, "thrown weapon gains downward velocity (%.2f)" % projectile.velocity.y)
	expect(projectile.global_position.y < start_y - 0.05,
		"thrown weapon visibly drops (y %.2f)" % projectile.global_position.y)
	projectile.free()


func test_mage_projectile_is_flat() -> void:
	await _setup(1, Vector3(0, 0.2, -20), Vector3(0, 0.2, -40), false)
	var stats := WeaponRegistry.stats_for(1)
	var projectile := stats.projectile_scene.instantiate() as Projectile
	_world.add_child(projectile)
	projectile.global_position = Vector3(0.0, 8.0, 0.0)
	projectile.setup(Vector3(0, 0, -1), stats, 1, [])
	for _i in 10:
		await get_tree().physics_frame
	expect(is_zero_approx(projectile.velocity.y), "Mage bolt flies linear (vy %.3f)" % projectile.velocity.y)
	expect(is_equal_approx(projectile.global_position.y, 8.0), "Mage bolt keeps altitude")
	projectile.free()


func test_knight_javelin_pierces_one_target() -> void:
	await _setup(0, Vector3(0, 0.2, -4), Vector3(0, 0.2, -8))
	var shot := await _fire_at(_body_shape(_c), 12)
	expect(not shot.is_empty(), "piercing throw accepted")
	expect(_health(_b).current == 40, "first target takes 60 (hp %d)" % _health(_b).current)
	expect(_health(_c).current == 40, "second target behind takes 60 (hp %d)" % _health(_c).current)
	expect(_combat.pierce_hits >= 1, "pierce contact recorded")
	expect(_combat.projectile_hits == 1, "one projectile accounts for both contacts")


func test_mage_splash_damages_neighbour() -> void:
	await _setup(1, Vector3(0, 0.2, -4), Vector3(1.0, 0.2, -4))
	var shot := await _fire_at(_body_shape(_b), 12)
	expect(not shot.is_empty(), "Mage bolt accepted")
	expect(_health(_b).current == 65, "direct target takes 35 (hp %d)" % _health(_b).current)
	var splash_lost := 100 - _health(_c).current
	expect(splash_lost > 0, "neighbour takes splash damage (lost %d)" % splash_lost)
	expect(splash_lost <= 15, "splash never exceeds its 15 damage cap (lost %d)" % splash_lost)


func test_barbarian_knockback_and_slow_hook() -> void:
	await _setup(4, Vector3(0, 0.2, -4), Vector3(4, 0.2, -4))
	var shot := await _fire_at(_body_shape(_b), 12)
	expect(not shot.is_empty(), "Barbarian axe accepted")
	expect(_health(_b).current == 50, "axe body hit deals 50 (hp %d)" % _health(_b).current)
	expect(Vector2(_b.velocity.x, _b.velocity.z).length() > 0.5,
		"knockback pushes the victim (%.2f m/s)" % Vector2(_b.velocity.x, _b.velocity.z).length())
	expect(_combat.statuses.has(2), "slow status installed on the victim")
	var slow: Dictionary = _combat.statuses.get(2, {})
	expect(float(slow.get("slow_left", 0.0)) > 0.0, "slow has a duration")

	# A slowed victim's movement intent is reduced server-side.
	var move := PlayerInputFrame.new()
	move.move = Vector2(1.0, 0.0)
	_combat.process(_entry_b, _b, move, DT)
	expect(is_equal_approx(move.move.x, 0.65), "slow scales movement input (%.2f)" % move.move.x)

	# The hook expires on the weapon clock.
	for _i in 40:
		_combat.tick(_entry_b, DT)
	expect(not _combat.statuses.has(2), "slow expires after its duration")
	var cleared := PlayerInputFrame.new()
	cleared.move = Vector2(1.0, 0.0)
	_combat.process(_entry_b, _b, cleared, DT)
	expect(is_equal_approx(cleared.move.x, 1.0), "movement is restored after the slow")


func test_crossbow_bleed_hook_ticks_damage() -> void:
	await _setup(3, Vector3(0, 0.2, -4), Vector3(4, 0.2, -4))
	await _fire_at(_body_shape(_b), 8)
	expect(_health(_b).current == 78, "bolt body hit deals 22 (hp %d)" % _health(_b).current)
	expect(_combat.statuses.has(2), "bleed status installed on the victim")
	var hp_after_hit := _health(_b).current
	var damage_before := _combat.damage_hits
	_combat.tick(_entry_b, 0.5)
	expect(_health(_b).current == hp_after_hit - 2,
		"first bleed slice deals 2 (hp %d)" % _health(_b).current)
	expect(_combat.damage_hits == damage_before + 1, "bleed damage is telemetered")
	# Two seconds of bleed: four 2-damage slices in total.
	for _i in 3:
		_combat.tick(_entry_b, 0.5)
	expect(_health(_b).current == hp_after_hit - 8,
		"bleed totals 8 over its duration (hp %d)" % _health(_b).current)
	expect(not _combat.statuses.has(2), "bleed expires")
