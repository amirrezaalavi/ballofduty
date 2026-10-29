class_name ServerCombat
extends RefCounted
## CP4c authoritative weapon simulation. Fire intents come from client input
## frames; origin and direction are derived from the server's own player state
## (canonical muzzle, never a skeleton bone). Damage flows through the existing
## Projectile -> CombatResolver -> EventBus path, and GameManager broadcasts the
## resulting hit/death events.

const EYE_HEIGHT := 0.62
const SHOULDER := Vector3(0.14, 0.0, -0.30)

var stats: WeaponStats
var world: Node
var projectiles_fired: int = 0


func _init(target_world: Node, weapon_stats: WeaponStats) -> void:
	world = target_world
	stats = weapon_stats


func reset_player(entry: Dictionary) -> void:
	entry["ammo"] = stats.magazine_size if stats else 0
	entry["cooldown"] = 0.0
	entry["reload_left"] = 0.0


## Wall-clock weapon timers. Called on every server tick, even when the input
## queue is starving: cooldown and reload must advance with the server clock,
## not only with simulated inputs.
func tick(entry: Dictionary, delta: float) -> void:
	if stats == null:
		return
	entry["cooldown"] = maxf(0.0, float(entry.get("cooldown", 0.0)) - delta)
	var reload_left := float(entry.get("reload_left", 0.0))
	if reload_left > 0.0:
		reload_left = maxf(0.0, reload_left - delta)
		entry["reload_left"] = reload_left
		if reload_left <= 0.0:
			entry["ammo"] = stats.magazine_size


## Attempt a fire/reload intent. Returns a shot description when a round
## actually left the barrel, otherwise {}.
func process(entry: Dictionary, actor: PlayerController, frame: PlayerInputFrame, _delta: float) -> Dictionary:
	if stats == null or actor == null:
		return {}
	if float(entry.get("reload_left", 0.0)) > 0.0:
		return {}
	if frame.reload and int(entry.get("ammo", 0)) < stats.magazine_size:
		entry["reload_left"] = stats.reload_time
		return {}
	# Mirror the client's automatic reload when the magazine is empty.
	if int(entry.get("ammo", 0)) <= 0:
		entry["reload_left"] = stats.reload_time
		return {}
	if not frame.fire or float(entry.get("cooldown", 0.0)) > 0.0:
		return {}

	entry["ammo"] = int(entry["ammo"]) - 1
	entry["cooldown"] = 1.0 / maxf(stats.fire_rate, 0.1)
	var yaw := frame.yaw
	var pitch := frame.pitch
	var origin := canonical_muzzle(actor.global_position, yaw, pitch)
	var direction := _aim_direction(actor, yaw, pitch, origin)
	_spawn_projectile(actor, origin, direction)
	return {
		"shooter_id": actor.net_id,
		"origin": origin,
		"direction": direction,
	}


static func canonical_muzzle(actor_position: Vector3, yaw: float, pitch: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return actor_position + Vector3(0.0, EYE_HEIGHT, 0.0) + basis * SHOULDER


static func canonical_direction(yaw: float, pitch: float) -> Vector3:
	return (Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0.0, 0.0, -1.0)).normalized()


## The camera aims at a point, while the muzzle sits off to the shoulder. Firing
## parallel to the view makes close headshots miss, so trace the view first and
## aim from the muzzle at the resulting point (the same correction the client
## applies in WeaponController._aim_direction).
func _aim_direction(actor: PlayerController, yaw: float, pitch: float, muzzle: Vector3) -> Vector3:
	var eye := actor.global_position + Vector3(0.0, EYE_HEIGHT, 0.0)
	var view := canonical_direction(yaw, pitch)
	var query := PhysicsRayQueryParameters3D.create(eye, eye + view * 250.0, 1 | 8)
	query.collide_with_areas = true
	query.exclude = _exclusion_rids(actor)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point: Vector3 = hit.position if not hit.is_empty() else eye + view * 250.0
	return (aim_point - muzzle).normalized()


func _spawn_projectile(actor: PlayerController, origin: Vector3, direction: Vector3) -> void:
	if stats.projectile_scene == null or world == null:
		return
	var projectile := stats.projectile_scene.instantiate() as Projectile
	if projectile == null:
		return
	world.add_child(projectile)
	projectile.global_position = origin
	projectile.setup(direction, stats, actor.net_id, _exclusion_rids(actor))
	projectiles_fired += 1


func _exclusion_rids(actor: PlayerController) -> Array[RID]:
	var rids: Array[RID] = [actor.get_rid()]
	for path: String in ["BodyHurtbox", "HeadHurtbox"]:
		var area := actor.get_node_or_null(path) as Area3D
		if area:
			rids.append(area.get_rid())
	return rids
