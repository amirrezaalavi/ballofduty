extends BodTestSuite
## Phase 1 C combat telemetry: every accepted shot ends as a hurtbox hit, a
## world impact or an expiry; rejections are bucketed by weapon and reason.

const DT := 1.0 / 30.0

var _world: Node3D
var _a: PlayerController
var _b: PlayerController
var _combat: ServerCombat
var _entry: Dictionary
var _stats: WeaponStats


func after_test() -> void:
	if is_instance_valid(_world):
		_world.free()


func _setup() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.55, 0.0)
	_world.add_child(floor_body)

	_a = (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_b = (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_world.add_child(_a)
	_world.add_child(_b)
	_a.make_server(1)
	_b.make_server(2)
	_a.global_position = Vector3(0.0, 0.2, 0.0)
	_b.global_position = Vector3(0.0, 0.2, 3.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Duplicate so the lifetime tweak in the expiry test never leaks into the
	# shared .tres used by other suites.
	_stats = (load("res://resources/weapons/rifle_stats.tres") as WeaponStats).duplicate() as WeaponStats
	_combat = ServerCombat.new(_world, _stats)
	_entry = {"id": 1, "ammo": 30, "cooldown": 0.0, "reload_left": 0.0}
	_combat.reset_player(_entry)
	_set_target_damage(true)


func _set_target_damage(enabled: bool) -> void:
	for path: String in ["BodyHurtbox"]:
		var hurtbox := _b.get_node(path) as HurtboxComponent
		hurtbox.damage_enabled = enabled


func _fire(yaw: float, pitch: float, frames: int = 6) -> Dictionary:
	var frame := PlayerInputFrame.new()
	frame.yaw = yaw
	frame.pitch = pitch
	frame.fire = true
	var shot := _combat.process(_entry, _a, frame, DT)
	for _i in frames:
		await get_tree().physics_frame
	return shot


func test_hit_and_rejection_telemetry() -> void:
	await _setup()
	var body := (_b.get_node("BodyHurtbox/CollisionShape3D") as Node3D).global_position
	var angles := ServerCombat.aim_angles(_a.global_position, body)
	var shot := await _fire(angles.x, angles.y)
	expect(not shot.is_empty(), "shot accepted")
	expect(_combat.shots_fired == 1, "one accepted shot")
	expect(_combat.projectiles_fired == 1, "one spawned projectile")
	expect(_combat.projectile_hits == 1, "one hurtbox hit (got %d)" % _combat.projectile_hits)
	expect(_combat.damage_hits == 1, "one damaging hit (got %d)" % _combat.damage_hits)
	expect(_combat.projectile_expired == 0, "hit did not expire")
	expect(_combat.projectile_world_impacts == 0, "hit did not count as a world impact")

	# Cooldown rejection is bucketed under the weapon id.
	var again := await _fire(angles.x, angles.y, 1)
	expect(again.is_empty(), "cooldown blocks the second shot")
	expect(_combat.blocked_cooldown == 1, "legacy cooldown counter increments")
	expect(_combat.rejections_total == 1, "rejection total increments")
	var bucket: Dictionary = _combat.rejections_by_weapon.get(String(_stats.weapon_id), {})
	expect(int(bucket.get("cooldown", 0)) == 1, "per-weapon cooldown reason recorded (%s)" % str(bucket))
	expect(_combat.telemetry_line().contains("reject"), "telemetry line exposes rejections")
	expect(_combat.telemetry_line().contains("by_weapon"), "telemetry line groups rejections by weapon")


func test_expiry_is_counted() -> void:
	await _setup()
	_stats.projectile_lifetime = 0.12
	_entry["cooldown"] = 0.0
	# Level shot down the empty lane: no hurtbox, no floor, so the only possible
	# resolution is the lifetime timer.
	await _fire(0.0, 0.0, 10)
	expect(_combat.projectile_expired == 1,
		"lifetime expiry recorded (expired=%d)" % _combat.projectile_expired)
	expect(_combat.projectile_hits == 0, "expiry is not a hit")
	expect(_combat.shots_fired == 1, "one shot fired")
	expect(_combat.projectiles_active() == 0, "nothing left in flight")


func test_world_impact_is_counted() -> void:
	await _setup()
	_entry["cooldown"] = 0.0
	await _fire(0.0, 1.45, 10)
	expect(_combat.projectile_world_impacts == 1,
		"ground impact recorded (world=%d)" % _combat.projectile_world_impacts)
	expect(_combat.projectile_hits == 0, "world impact is not a player hit")
	expect(_combat.projectiles_active() == 0, "nothing left in flight")


func test_projectile_accounting_is_consistent() -> void:
	await _setup()
	_entry["cooldown"] = 0.0
	await _fire(0.0, 1.45, 8)
	_entry["cooldown"] = 0.0
	await _fire(0.0, 0.0, 8)
	var body := (_b.get_node("BodyHurtbox/CollisionShape3D") as Node3D).global_position
	var angles := ServerCombat.aim_angles(_a.global_position, body)
	_entry["cooldown"] = 0.0
	await _fire(angles.x, angles.y, 8)

	var resolved := (
		_combat.projectile_hits + _combat.projectile_world_impacts + _combat.projectile_expired
	)
	expect(_combat.projectiles_fired == 3, "three rounds spawned")
	expect(resolved + _combat.projectiles_active() == _combat.projectiles_fired,
		"every round is accounted for (spawned %d, resolved %d, active %d)" % [
			_combat.projectiles_fired, resolved, _combat.projectiles_active()])
	expect(_combat.projectile_hits == 1 and _combat.projectile_world_impacts == 1,
		"one hit and one world impact")
	expect(_combat.damage_hits == 1, "damage telemetry matches the hit")
	print("  telemetry: " + _combat.telemetry_line())
