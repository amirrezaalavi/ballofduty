extends SceneTree
## CP3 combat checks: weapon data, swept projectile hits at 5/15/30 m,
## headshot multiplier, and hitbox reporting. Run with --script.

const DISTANCES := [5.0, 15.0, 30.0]
const BODY_Y := 0.55
const HEAD_Y := 1.35

var _failures := 0
var _checks := 0
var _stats: WeaponStats


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_stats = load("res://resources/weapons/rifle_stats.tres") as WeaponStats
	_check(_stats != null, "rifle stats load")
	if _stats == null:
		_finish()
		return

	_check(_stats.damage == 25, "body damage is 25")
	_check(is_equal_approx(_stats.headshot_multiplier, 2.0), "headshot multiplier is 2x")
	_check(is_equal_approx(_stats.fire_rate, 10.0), "fire rate is 10 rps")
	_check(_stats.magazine_size == 30, "magazine is 30")
	_check(is_equal_approx(_stats.reload_time, 1.6), "reload is 1.6 s")
	_check(_stats.projectile_scene != null, "projectile scene is assigned")

	for distance: float in DISTANCES:
		await _check_hit(distance, BODY_Y, false, 75)
		# 20 headshots per distance; the acceptance target is 20/20 with no tunneling.
		for i in 20:
			await _check_hit(distance, HEAD_Y, true, 50)

	await _test_weapon_controller()
	await create_timer(2.7).timeout
	_purge_projectiles(root)
	for child in root.get_children():
		child.free()
	await process_frame
	_finish()


func _check_hit(distance: float, target_y: float, expect_headshot: bool, expected_hp: int) -> void:
	var dummy := (load("res://scenes/characters/training_dummy.tscn") as PackedScene).instantiate()
	root.add_child(dummy)
	await physics_frame
	await physics_frame

	var origin := Vector3(0.0, target_y, distance)
	var target := Vector3(0.0, target_y, 0.0)
	var projectile := _stats.projectile_scene.instantiate() as Projectile
	root.add_child(projectile)
	projectile.global_position = origin

	var report := {"hit": false, "headshot": false}
	projectile.hit_confirmed.connect(
		func(headshot: bool, _killed: bool) -> void:
			report["hit"] = true
			report["headshot"] = headshot
	)
	projectile.setup((target - origin).normalized(), _stats, 0, [] as Array[RID])

	var frames := 0
	while is_instance_valid(projectile) and frames < 120:
		await physics_frame
		frames += 1

	var health := dummy.get_node("HealthComponent") as HealthComponent
	_check(bool(report["hit"]), "hit registered at %.0f m (y=%.2f)" % [distance, target_y])
	_check(
		bool(report["headshot"]) == expect_headshot,
		"hitbox reported %s at %.0f m" % ["head" if expect_headshot else "body", distance]
	)
	_check(
		health.current == expected_hp,
		"damage at %.0f m is %d (got %d)" % [distance, expected_hp, health.current]
	)
	dummy.queue_free()
	await process_frame


func _test_weapon_controller() -> void:
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	var weapon := player.get_node("WeaponController") as WeaponController
	_check(weapon != null, "player has a WeaponController")
	if weapon == null:
		player.free()
		return

	weapon.spawn_projectiles = false
	_check(weapon.ammo == 30, "weapon starts with a full magazine")
	var frame := PlayerInputFrame.new()
	frame.fire = true
	weapon.tick(1.0 / 30.0, frame)
	_check(weapon.ammo == 29, "firing consumes one round")
	weapon.tick(1.0 / 30.0, frame)
	_check(weapon.ammo == 29, "fire rate blocks an immediate second shot")
	weapon.tick(1.0 / 30.0, frame)
	weapon.tick(1.0 / 30.0, frame)
	weapon.tick(1.0 / 30.0, frame)
	_check(weapon.ammo == 28, "fire rate allows the next shot after cooldown")

	frame.fire = false
	frame.reload = true
	weapon.tick(1.0 / 30.0, frame)
	_check(weapon.is_reloading(), "reload starts")
	frame.reload = false
	for _i in 60:
		weapon.tick(1.0 / 30.0, frame)
	_check(not weapon.is_reloading(), "reload finishes")
	_check(weapon.ammo == 30, "reload refills the magazine")

	player.queue_free()
	await process_frame
	print("  weapon ammo/fire-rate/reload=ok")


func _purge_projectiles(node: Node) -> void:
	for child in node.get_children():
		if child is Projectile:
			child.free()
		else:
			_purge_projectiles(child)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: " + label)


func _finish() -> void:
	print("combat: %d checks, %d failure(s)" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
