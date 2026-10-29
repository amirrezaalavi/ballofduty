extends BodTestSuite
## CP3 combat checks: weapon data and swept projectile hits at 5/15/30 m.

const DISTANCES := [5.0, 15.0, 30.0]
const BODY_Y := 0.55

var _stats: WeaponStats


func before_test() -> void:
	_stats = load("res://resources/weapons/rifle_stats.tres") as WeaponStats
	expect(_stats != null, "rifle stats load")


func test_weapon_data() -> void:
	expect(_stats.damage == 25, "body damage is 25")
	expect(is_equal_approx(_stats.fire_rate, 10.0), "fire rate is 10 rps")
	expect(_stats.magazine_size == 30, "magazine is 30")
	expect(is_equal_approx(_stats.reload_time, 1.6), "reload is 1.6 s")
	expect(_stats.projectile_scene != null, "projectile scene is assigned")


func test_hits_at_5m() -> void:
	await _hit_suite(5.0)


func test_hits_at_15m() -> void:
	await _hit_suite(15.0)


func test_hits_at_30m() -> void:
	await _hit_suite(30.0)


func _hit_suite(distance: float) -> void:
	# 20 body shots per distance; the acceptance target is 20/20 with no tunneling.
	for _i in 20:
		await _check_hit(distance, BODY_Y, 75)


func _check_hit(distance: float, target_y: float, expected_hp: int) -> void:
	var dummy := (load("res://scenes/characters/training_dummy.tscn") as PackedScene).instantiate()
	add_child(dummy)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var origin := Vector3(0.0, target_y, distance)
	var target := Vector3(0.0, target_y, 0.0)
	var projectile := _stats.projectile_scene.instantiate() as Projectile
	add_child(projectile)
	projectile.global_position = origin

	var report := {"hit": false}
	projectile.hit_confirmed.connect(
		func(_killed: bool) -> void:
			report["hit"] = true
	)
	projectile.setup((target - origin).normalized(), _stats, 0, [] as Array[RID])

	var frames := 0
	while is_instance_valid(projectile) and frames < 120:
		await get_tree().physics_frame
		frames += 1

	var health := dummy.get_node("HealthComponent") as HealthComponent
	expect(bool(report["hit"]), "hit registered at %.0f m (y=%.2f)" % [distance, target_y])
	expect(
		health.current == expected_hp,
		"damage at %.0f m is %d (got %d)" % [distance, expected_hp, health.current]
	)
	dummy.queue_free()
	await get_tree().process_frame


func test_weapon_controller() -> void:
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await get_tree().process_frame
	var weapon := player.get_node("WeaponController") as WeaponController
	expect(weapon != null, "player has a WeaponController")
	if weapon == null:
		player.queue_free()
		return

	weapon.spawn_projectiles = false
	# This suite covers the legacy rifle controller; keep it on rifle stats even
	# though the default player class (Knight) loads a class profile at _ready.
	weapon.stats = load("res://resources/weapons/rifle_stats.tres") as WeaponStats
	weapon.class_id = player.class_id
	weapon.reset_ammo()
	expect(weapon.ammo == 30, "weapon starts with a full magazine")
	var frame := PlayerInputFrame.new()
	frame.fire = true
	weapon.tick(1.0 / 30.0, frame)
	expect(weapon.ammo == 29, "firing consumes one round")
	weapon.tick(1.0 / 30.0, frame)
	expect(weapon.ammo == 29, "fire rate blocks an immediate second shot")
	weapon.tick(1.0 / 30.0, frame)
	weapon.tick(1.0 / 30.0, frame)
	weapon.tick(1.0 / 30.0, frame)
	expect(weapon.ammo == 28, "fire rate allows the next shot after cooldown")

	frame.fire = false
	frame.reload = true
	weapon.tick(1.0 / 30.0, frame)
	expect(weapon.is_reloading(), "reload starts")
	frame.reload = false
	for _i in 60:
		weapon.tick(1.0 / 30.0, frame)
	expect(not weapon.is_reloading(), "reload finishes")
	expect(weapon.ammo == 30, "reload refills the magazine")

	player.queue_free()
	await get_tree().process_frame
	print("  weapon ammo/fire-rate/reload=ok")
