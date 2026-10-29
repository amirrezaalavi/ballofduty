class_name ServerCombat
extends RefCounted
## CP4c authoritative weapon simulation. Fire intents come from client input
## frames; origin and direction are derived from the server's own player state
## (canonical muzzle, never a skeleton bone). Damage flows through the existing
## Projectile -> CombatResolver -> EventBus path, and GameManager broadcasts the
## resulting hit/death events.
##
## Phase 1 C telemetry stays integer-only: no per-shot strings or arrays are
## built. Rejections are bucketed by weapon id so a future loadout can be read
## without a new log format.

const EYE_HEIGHT := 0.62
const SHOULDER := Vector3(0.14, 0.0, -0.30)
## Mirror CameraRig: pivot 0.95 m up, camera 0.35 m right and 2.3 m behind.
## The client aims from the camera, so tracing from the eye alone made shots
## drift at range and near cover.
const CAMERA_PIVOT_HEIGHT := 0.95
const CAMERA_SHOULDER_X := 0.35
const CAMERA_BACK := 2.3

var stats: WeaponStats
var world: Node

# Accepted fire / projectile accounting.
var shots_fired: int = 0
var projectiles_fired: int = 0
var projectile_hits: int = 0
var projectile_world_impacts: int = 0
var projectile_expired: int = 0
## Damage events (a hurtbox contact while spawn protection is off).
var damage_hits: int = 0

# Rejection reasons. The legacy counters stay for GameManager's existing
# --net-stats line; the dictionary is the readable per-weapon breakdown.
var blocked_cooldown: int = 0
var blocked_reload: int = 0
var blocked_ammo: int = 0
var rejections_total: int = 0
## weapon_id (String) -> {reason: count}
var rejections_by_weapon: Dictionary = {}
## weapon_id (String) -> accepted shots
var shots_by_weapon: Dictionary = {}


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
		if frame.fire:
			_reject("reload")
		return {}
	if frame.reload and int(entry.get("ammo", 0)) < stats.magazine_size:
		entry["reload_left"] = stats.reload_time
		return {}
	# Mirror the client's automatic reload when the magazine is empty.
	if int(entry.get("ammo", 0)) <= 0:
		entry["reload_left"] = stats.reload_time
		if frame.fire:
			_reject("ammo")
		return {}
	if not frame.fire:
		return {}
	if float(entry.get("cooldown", 0.0)) > 0.0:
		_reject("cooldown")
		return {}

	entry["ammo"] = int(entry["ammo"]) - 1
	shots_fired += 1
	var weapon_key := _weapon_key()
	shots_by_weapon[weapon_key] = int(shots_by_weapon.get(weapon_key, 0)) + 1
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


## Called by Projectile when a round resolves. Kept allocation-free: a single
## StringName match, integer increment.
func note_projectile_resolved(kind: StringName) -> void:
	match kind:
		&"hit":
			projectile_hits += 1
		&"world":
			projectile_world_impacts += 1
		&"expired":
			projectile_expired += 1


## Called by GameManager's damage event (one per damaging hurtbox contact).
func note_damage_hit() -> void:
	damage_hits += 1


## Rounds still in flight. Suppressed shots (lifetime/no collision) are the
## remainder; a clean shutdown should leave only a handful.
func projectiles_active() -> int:
	return projectiles_fired - (projectile_hits + projectile_world_impacts + projectile_expired)


## Compact one-line telemetry for the debug HUD/log parser.
## Example: shots=1200 proj=1180 hit=214 world=712 exp=251 active=3 dmg=208
##          hit%=18.1 reject cd/rl/ammo=41/3/0
func telemetry_line() -> String:
	var resolved := projectile_hits + projectile_world_impacts + projectile_expired
	var ratio := 0.0
	if resolved > 0:
		ratio = 100.0 * float(projectile_hits) / float(resolved)
	var reject_text := _rejection_text()
	return (
		"shots=%d proj=%d hit=%d world=%d exp=%d active=%d dmg=%d hit%%=%.1f reject %s"
		% [
			shots_fired, projectiles_fired, projectile_hits, projectile_world_impacts,
			projectile_expired, projectiles_active(), damage_hits, ratio, reject_text,
		]
	)


func rejection_line() -> String:
	return _rejection_text()


func _rejection_text() -> String:
	var total := "cd/rl/ammo=%d/%d/%d" % [blocked_cooldown, blocked_reload, blocked_ammo]
	if rejections_by_weapon.is_empty():
		return total
	var parts: PackedStringArray = []
	for weapon_key in rejections_by_weapon:
		var bucket: Dictionary = rejections_by_weapon[weapon_key]
		parts.append("%s:%d/%d/%d" % [
			String(weapon_key), int(bucket.get("cooldown", 0)),
			int(bucket.get("reload", 0)), int(bucket.get("ammo", 0)),
		])
	return total + " by_weapon[" + ",".join(parts) + "]"


func _reject(reason: String) -> void:
	rejections_total += 1
	match reason:
		"cooldown":
			blocked_cooldown += 1
		"reload":
			blocked_reload += 1
		"ammo":
			blocked_ammo += 1
	var weapon_key := _weapon_key()
	var bucket: Dictionary = rejections_by_weapon.get(weapon_key, {})
	bucket[reason] = int(bucket.get(reason, 0)) + 1
	rejections_by_weapon[weapon_key] = bucket


func _weapon_key() -> String:
	return String(stats.weapon_id) if stats else "unknown"


static func canonical_muzzle(actor_position: Vector3, yaw: float, pitch: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return actor_position + Vector3(0.0, EYE_HEIGHT, 0.0) + basis * SHOULDER


static func canonical_direction(yaw: float, pitch: float) -> Vector3:
	return (Basis.from_euler(Vector3(pitch, yaw, 0.0)) * Vector3(0.0, 0.0, -1.0)).normalized()


## The camera aims at a point, while the muzzle sits off to the shoulder. Firing
## parallel to the view makes close headshots miss, so trace the view first and
## aim from the muzzle at the resulting point (the same correction the client
## applies in WeaponController._aim_direction).
## Yaw/pitch that put `target` under the crosshair from the third-person camera.
## Used by bots/tests; converges in three iterations because the camera offset
## itself rotates with yaw and pitch.
static func aim_angles(actor_position: Vector3, target: Vector3) -> Vector2:
	var yaw := atan2(-(target.x - actor_position.x), -(target.z - actor_position.z))
	var pitch := 0.0
	for _i in 3:
		var cam := camera_origin(actor_position, yaw, pitch)
		var d := target - cam
		yaw = atan2(-d.x, -d.z)
		pitch = atan2(d.y, Vector2(d.x, d.z).length())
	return Vector2(yaw, pitch)


static func camera_origin(actor_position: Vector3, yaw: float, pitch: float) -> Vector3:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	return (
		actor_position
		+ Vector3(0.0, CAMERA_PIVOT_HEIGHT, 0.0)
		+ basis * Vector3(CAMERA_SHOULDER_X, 0.0, CAMERA_BACK)
	)


func _aim_direction(actor: PlayerController, yaw: float, pitch: float, muzzle: Vector3) -> Vector3:
	var cam := camera_origin(actor.global_position, yaw, pitch)
	var view := canonical_direction(yaw, pitch)
	var query := PhysicsRayQueryParameters3D.create(cam, cam + view * 250.0, 1 | 8)
	query.collide_with_areas = true
	query.exclude = _exclusion_rids(actor)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point: Vector3 = hit.position if not hit.is_empty() else cam + view * 250.0
	return (aim_point - muzzle).normalized()


func _spawn_projectile(actor: PlayerController, origin: Vector3, direction: Vector3) -> void:
	if stats.projectile_scene == null or world == null:
		return
	var projectile := stats.projectile_scene.instantiate() as Projectile
	if projectile == null:
		return
	world.add_child(projectile)
	projectile.global_position = origin
	projectile.telemetry = self
	projectile.setup(direction, stats, actor.net_id, _exclusion_rids(actor))
	projectiles_fired += 1


func _exclusion_rids(actor: PlayerController) -> Array[RID]:
	var rids: Array[RID] = [actor.get_rid()]
	for path: String in ["BodyHurtbox", "HeadHurtbox"]:
		var area := actor.get_node_or_null(path) as Area3D
		if area:
			rids.append(area.get_rid())
	return rids
