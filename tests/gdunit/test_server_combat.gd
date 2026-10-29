extends BodTestSuite
## CP4c authoritative combat: canonical muzzle, fire rate/ammo, server hit
## resolution, headshots, spawn protection, and death events.

var _world: Node3D
var _a: PlayerController
var _b: PlayerController
var _combat: ServerCombat
var _entry: Dictionary
var _body_target: Vector3
var _head_target: Vector3


func after_test() -> void:
	if is_instance_valid(_world):
		_world.free()


func _setup() -> void:
	_world = Node3D.new()
	add_child(_world)
	_a = (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_b = (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_world.add_child(_a)
	_world.add_child(_b)
	_a.make_server(1)
	_b.make_server(2)
	_a.global_position = Vector3(0.0, 0.2, 0.0)
	_b.global_position = Vector3(2.0, 0.2, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var stats := load("res://resources/weapons/rifle_stats.tres") as WeaponStats
	_combat = ServerCombat.new(_world, stats)
	_entry = {"id": 1, "ammo": 30, "cooldown": 0.0, "reload_left": 0.0}
	_combat.reset_player(_entry)
	_body_target = (_b.get_node("BodyHurtbox/CollisionShape3D") as Node3D).global_position
	_head_target = (_b.get_node("HeadHurtbox/CollisionShape3D") as Node3D).global_position
	_set_target_damage(true)


func _set_target_damage(enabled: bool) -> void:
	for path: String in ["BodyHurtbox", "HeadHurtbox"]:
		var hurtbox := _b.get_node(path) as HurtboxComponent
		hurtbox.damage_enabled = enabled


func _body() -> HealthComponent:
	return _b.get_node("HealthComponent") as HealthComponent


func _fire(pitch: float, wait_frames: int = 5) -> Dictionary:
	var frame := PlayerInputFrame.new()
	frame.yaw = -PI * 0.5
	frame.pitch = pitch
	frame.fire = true
	var shot := _combat.process(_entry, _a, frame, 1.0 / 30.0)
	for _i in wait_frames:
		await get_tree().physics_frame
	return shot


func _fire_at(target: Vector3, wait_frames: int = 5) -> Dictionary:
	var angles := ServerCombat.aim_angles(_a.global_position, target)
	var frame := PlayerInputFrame.new()
	frame.yaw = angles.x
	frame.pitch = angles.y
	frame.fire = true
	var shot := _combat.process(_entry, _a, frame, 1.0 / 30.0)
	for _i in wait_frames:
		await get_tree().physics_frame
	return shot


func test_body_hit_and_fire_rate() -> void:
	await _setup()
	var shot := await _fire_at(_body_target)
	expect(not shot.is_empty(), "accepted fire produces a shot event")
	expect(int(_entry["ammo"]) == 29, "one round consumed")
	expect(_body().current == 75, "body shot deals 25 (hp %d)" % _body().current)

	# Holding fire inside the cooldown cannot produce a second round.
	var again := await _fire_at(_body_target)
	expect(again.is_empty(), "fire rate blocks an immediate second shot")
	expect(int(_entry["ammo"]) == 29, "blocked shot consumes no ammo")
	expect(_body().current == 75, "blocked shot deals no damage")

	_entry["cooldown"] = 0.0
	await _fire_at(_body_target)
	expect(_body().current == 50, "next allowed shot deals 25 (hp %d)" % _body().current)


func test_headshot_is_double() -> void:
	await _setup()
	await _fire_at(_head_target)
	expect(_body().current == 50, "headshot deals 50 (hp %d)" % _body().current)


func test_ammo_and_reload() -> void:
	await _setup()
	_entry["ammo"] = 1
	await _fire_at(_body_target)
	expect(int(_entry["ammo"]) == 0, "magazine empties")
	# Auto reload starts on the next tick, then completes.
	var reload := PlayerInputFrame.new()
	reload.yaw = -PI * 0.5
	for _i in 60:
		_combat.tick(_entry, 1.0 / 30.0)
		_combat.process(_entry, _a, reload, 1.0 / 30.0)
	expect(int(_entry["ammo"]) == 30, "reload refills the magazine")
	expect(float(_entry["reload_left"]) == 0.0, "reload timer cleared")


func test_spawn_protection_blocks_damage() -> void:
	await _setup()
	_set_target_damage(false)
	await _fire_at(_body_target)
	expect(_body().current == 100, "spawn-protected target takes no damage")
	_set_target_damage(true)
	_entry["cooldown"] = 0.0
	await _fire_at(_body_target)
	expect(_body().current == 75, "damage resumes when protection ends")


func test_kill_emits_death_event() -> void:
	await _setup()
	var died: Array = []
	var bus := get_node_or_null("/root/EventBus")
	bus.player_died.connect(func(victim: int, killer: int, _pos: Vector3) -> void:
		died.append([victim, killer]))
	for _i in 4:
		_entry["cooldown"] = 0.0
		await _fire_at(_body_target)
	expect(_body().current == 0, "four body shots kill (hp %d)" % _body().current)
	expect(died.size() == 1 and int(died[0][0]) == 2, "death event names the victim")
	expect(int(died[0][1]) == 1, "death event names the shooter")
