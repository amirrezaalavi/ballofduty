class_name ServerCombat
extends RefCounted
## CP4c authoritative weapon simulation. Fire intents come from client input
## frames; origin and direction are derived from the server's own player state
## (canonical muzzle, never a skeleton bone). Damage flows through the existing
## Projectile -> CombatResolver -> EventBus path, and GameManager broadcasts the
## resulting hit/death events.
##
## Phase 2A: weapons are selected per roster entry from class_id through
## WeaponRegistry. All weapon state (ammo, cooldown, reload, heat, charge, burst)
## lives on the entry, so five classes can fire concurrently. The constructor's
## WeaponStats is only the fallback used by legacy tests/offline actors without
## a class_id.
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
## Damage-over-time is applied in fixed slices so the telemetry/HIT events stay
## bounded and deterministic across frame rates.
const BLEED_TICK_SEC := 0.5

var stats: WeaponStats
var world: Node

# Accepted fire / projectile accounting.
var shots_fired: int = 0
var projectiles_fired: int = 0
var projectile_hits: int = 0
var projectile_world_impacts: int = 0
var projectile_expired: int = 0
## Extra hurtbox contacts made by a piercing round (not extra projectiles).
var pierce_hits: int = 0
## Damage events (a hurtbox contact while spawn protection is off).
var damage_hits: int = 0

# Rejection reasons. The legacy counters stay for GameManager's existing
# --net-stats line; the dictionary is the readable per-weapon breakdown.
var blocked_cooldown: int = 0
var blocked_reload: int = 0
var blocked_ammo: int = 0
var blocked_heat: int = 0
var rejections_total: int = 0
## weapon_id (String) -> {reason: count}
var rejections_by_weapon: Dictionary = {}
## weapon_id (String) -> accepted shots
var shots_by_weapon: Dictionary = {}

## entity_id -> {slow_left, slow_scale, bleed_left, bleed_dps, bleed_tick, source_id}
var statuses: Dictionary = {}


func _init(target_world: Node, weapon_stats: WeaponStats) -> void:
	world = target_world
	stats = weapon_stats


## Reset a roster entry's weapon state. Reads entry["class_id"] and installs the
## resolved class profile on the entry, so GameManager needs no weapon knowledge.
func reset_player(entry: Dictionary) -> void:
	var resolved := _resolve_stats(entry)
	entry["stats"] = resolved
	entry["weapon_id"] = String(resolved.weapon_id) if resolved else "unknown"
	entry["ammo"] = resolved.magazine_size if resolved else 0
	entry["cooldown"] = 0.0
	entry["reload_left"] = 0.0
	entry["heat"] = 0.0
	entry["overheated"] = false
	entry["charge"] = 0.0
	entry["fire_prev"] = false
	entry["burst_left"] = 0
	entry["burst_timer"] = 0.0
	var entity_id := int(entry.get("id", -1))
	if entity_id >= 0:
		statuses.erase(entity_id)


## Wall-clock weapon timers. Called on every server tick, even when the input
## queue is starving: cooldown, reload, heat and burst cadence must advance with
## the server clock, not only with simulated inputs.
func tick(entry: Dictionary, delta: float) -> void:
	var weapon := _entry_stats(entry)
	if weapon == null:
		return
	entry["cooldown"] = maxf(0.0, float(entry.get("cooldown", 0.0)) - delta)
	var reload_left := float(entry.get("reload_left", 0.0))
	if reload_left > 0.0:
		reload_left = maxf(0.0, reload_left - delta)
		entry["reload_left"] = reload_left
		if reload_left <= 0.0:
			entry["ammo"] = weapon.magazine_size
	if float(entry.get("heat", 0.0)) > 0.0:
		var heat := maxf(0.0, float(entry["heat"]) - weapon.heat_cool_rate * delta)
		entry["heat"] = heat
		if bool(entry.get("overheated", false)) and heat <= weapon.heat_max * weapon.heat_recover_ratio:
			entry["overheated"] = false
	if int(entry.get("burst_left", 0)) > 0:
		entry["burst_timer"] = maxf(0.0, float(entry.get("burst_timer", 0.0)) - delta)
	_tick_status(entry, delta)


## Attempt a fire/reload intent. Returns a shot description when a round
## actually left the barrel, otherwise {}.
func process(entry: Dictionary, actor: PlayerController, frame: PlayerInputFrame, delta: float) -> Dictionary:
	var weapon := _entry_stats(entry)
	if weapon == null or actor == null:
		return {}
	_apply_slow(entry, frame)

	var fire_held := frame.fire
	if float(entry.get("reload_left", 0.0)) > 0.0:
		if fire_held:
			_reject(entry, "reload")
		_cancel_trigger(entry, fire_held)
		return {}
	if frame.reload and int(entry.get("ammo", 0)) < weapon.magazine_size:
		entry["reload_left"] = weapon.reload_time
		_cancel_trigger(entry, fire_held)
		return {}
	# Mirror the client's automatic reload when the magazine is empty.
	if int(entry.get("ammo", 0)) <= 0:
		entry["reload_left"] = weapon.reload_time
		if fire_held:
			_reject(entry, "ammo")
		_cancel_trigger(entry, fire_held)
		return {}

	match String(weapon.fire_mode):
		"charge":
			return _process_charge(entry, actor, frame, weapon, delta)
		"burst":
			return _process_burst(entry, actor, frame, weapon)
		_:
			return _process_direct(entry, actor, frame, weapon)


func _process_direct(
	entry: Dictionary, actor: PlayerController, frame: PlayerInputFrame, weapon: WeaponStats
) -> Dictionary:
	var fire_held := frame.fire
	var trigger_edge := fire_held and not bool(entry.get("fire_prev", false))
	entry["fire_prev"] = fire_held
	if weapon.heat_max > 0.0 and bool(entry.get("overheated", false)):
		if fire_held:
			_reject(entry, "heat")
		return {}
	# Auto weapons keep firing while held; everything else needs a new press.
	var wants_fire := fire_held if (weapon.automatic or weapon.fire_mode == &"auto") else trigger_edge
	if not wants_fire:
		return {}
	if float(entry.get("cooldown", 0.0)) > 0.0:
		if fire_held:
			_reject(entry, "cooldown")
		return {}
	if weapon.heat_max > 0.0 and float(entry.get("heat", 0.0)) >= weapon.heat_max:
		entry["overheated"] = true
		_reject(entry, "heat")
		return {}
	entry["cooldown"] = 1.0 / maxf(weapon.fire_rate, 0.1)
	return _fire_one(entry, actor, frame, weapon, weapon.damage, weapon.projectile_speed)


## Charge weapons accumulate while fire is held and launch on release. Bots
## cannot physically release a held virtual trigger, so at full draw they
## auto-release; that keeps them live without changing the input protocol.
func _process_charge(
	entry: Dictionary, actor: PlayerController, frame: PlayerInputFrame,
	weapon: WeaponStats, delta: float
) -> Dictionary:
	var fire_held := frame.fire
	if fire_held:
		var charge := minf(weapon.charge_time, float(entry.get("charge", 0.0)) + delta)
		entry["charge"] = charge
		entry["fire_prev"] = true
		if (
			weapon.charge_time > 0.0
			and charge >= weapon.charge_time - 0.001
			and bool(entry.get("is_bot", false))
		):
			if float(entry.get("cooldown", 0.0)) <= 0.0:
				return _fire_charged(entry, actor, frame, weapon, 1.0)
			_reject(entry, "cooldown")
		return {}

	var was_holding := bool(entry.get("fire_prev", false))
	entry["fire_prev"] = false
	var charge := float(entry.get("charge", 0.0))
	entry["charge"] = 0.0
	if not was_holding:
		return {}
	var ratio := 1.0
	if weapon.charge_time > 0.0:
		ratio = clampf(charge / weapon.charge_time, 0.0, 1.0)
	if ratio < weapon.charge_min_ratio:
		return {}
	if float(entry.get("cooldown", 0.0)) > 0.0:
		_reject(entry, "cooldown")
		return {}
	return _fire_charged(entry, actor, frame, weapon, ratio)


func _fire_charged(
	entry: Dictionary, actor: PlayerController, frame: PlayerInputFrame,
	weapon: WeaponStats, ratio: float
) -> Dictionary:
	var speed := lerpf(weapon.charge_min_speed, weapon.projectile_speed, ratio)
	var damage := int(round(lerpf(float(weapon.charge_min_damage), float(weapon.damage), ratio)))
	entry["cooldown"] = 1.0 / maxf(weapon.fire_rate, 0.1)
	return _fire_one(entry, actor, frame, weapon, damage, speed)


## Three-round (stats-driven) burst on press. The per-bolt interval advances on
## the weapon clock; the full cycle cooldown starts after the last bolt so a new
## press cannot skip the burst rhythm.
func _process_burst(
	entry: Dictionary, actor: PlayerController, frame: PlayerInputFrame, weapon: WeaponStats
) -> Dictionary:
	var fire_held := frame.fire
	var trigger_edge := fire_held and not bool(entry.get("fire_prev", false))
	entry["fire_prev"] = fire_held
	var burst_left := int(entry.get("burst_left", 0))
	if trigger_edge and burst_left <= 0:
		if float(entry.get("cooldown", 0.0)) > 0.0:
			_reject(entry, "cooldown")
			return {}
		burst_left = maxi(1, weapon.burst_count)
		entry["burst_timer"] = 0.0
	if burst_left <= 0 or float(entry.get("burst_timer", 0.0)) > 0.0:
		return {}

	burst_left -= 1
	entry["burst_left"] = burst_left
	if burst_left > 0:
		entry["burst_timer"] = weapon.burst_interval
	else:
		entry["burst_timer"] = 0.0
		entry["cooldown"] = 1.0 / maxf(weapon.fire_rate, 0.1)
	return _fire_one(entry, actor, frame, weapon, weapon.damage, weapon.projectile_speed)


func _fire_one(
	entry: Dictionary, actor: PlayerController, frame: PlayerInputFrame,
	weapon: WeaponStats, damage: int, speed: float
) -> Dictionary:
	entry["ammo"] = maxi(0, int(entry.get("ammo", 0)) - 1)
	shots_fired += 1
	var weapon_key := _weapon_key(entry)
	shots_by_weapon[weapon_key] = int(shots_by_weapon.get(weapon_key, 0)) + 1
	if weapon.heat_max > 0.0:
		var heat := float(entry.get("heat", 0.0)) + weapon.heat_per_shot
		entry["heat"] = minf(heat, weapon.heat_max)
		if heat >= weapon.heat_max - 0.001:
			entry["overheated"] = true
	var yaw := frame.yaw
	var pitch := frame.pitch
	var origin := canonical_muzzle(actor.global_position, yaw, pitch)
	var direction := _aim_direction(actor, yaw, pitch, origin, entry, weapon)
	_spawn_projectile(actor, origin, direction, weapon, speed, damage)
	return {
		"shooter_id": actor.net_id,
		"origin": origin,
		"direction": direction,
		"speed": speed,
		"damage": damage,
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


## Called by Projectile when a round passes through an extra hurtbox.
func note_projectile_pierce() -> void:
	pierce_hits += 1


## Called by Projectile on every damaging hurtbox contact. Applies the class
## status hooks (slow/bleed) server-side; knockback is applied by the projectile
## directly to the victim body.
func note_projectile_effect(
	entity_id: int, source_id: int, weapon: WeaponStats, _direction: Vector3
) -> void:
	if weapon == null or entity_id <= 0:
		return
	var status: Dictionary = statuses.get(entity_id, {})
	if weapon.slow_amount > 0.0 and weapon.slow_duration > 0.0:
		status["slow_left"] = maxf(
			float(status.get("slow_left", 0.0)), weapon.slow_duration
		)
		status["slow_scale"] = clampf(1.0 - weapon.slow_amount, 0.0, 1.0)
	if weapon.bleed_dps > 0.0 and weapon.bleed_duration > 0.0:
		status["bleed_left"] = maxf(
			float(status.get("bleed_left", 0.0)), weapon.bleed_duration
		)
		status["bleed_dps"] = maxf(float(status.get("bleed_dps", 0.0)), weapon.bleed_dps)
		status["bleed_tick"] = float(status.get("bleed_tick", BLEED_TICK_SEC))
		status["source_id"] = source_id
	if not status.is_empty():
		statuses[entity_id] = status


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
		"shots=%d proj=%d hit=%d world=%d exp=%d active=%d dmg=%d pierce=%d hit%%=%.1f reject %s"
		% [
			shots_fired, projectiles_fired, projectile_hits, projectile_world_impacts,
			projectile_expired, projectiles_active(), damage_hits, pierce_hits, ratio,
			reject_text,
		]
	)


func rejection_line() -> String:
	return _rejection_text()


func _rejection_text() -> String:
	var total := "cd/rl/ammo=%d/%d/%d" % [blocked_cooldown, blocked_reload, blocked_ammo]
	if blocked_heat > 0:
		total += "/heat=%d" % blocked_heat
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


func _reject(entry: Dictionary, reason: String) -> void:
	rejections_total += 1
	match reason:
		"cooldown":
			blocked_cooldown += 1
		"reload":
			blocked_reload += 1
		"ammo":
			blocked_ammo += 1
		"heat":
			blocked_heat += 1
	var weapon_key := _weapon_key(entry)
	var bucket: Dictionary = rejections_by_weapon.get(weapon_key, {})
	bucket[reason] = int(bucket.get(reason, 0)) + 1
	rejections_by_weapon[weapon_key] = bucket


func _weapon_key(entry: Dictionary) -> String:
	var key := String(entry.get("weapon_id", ""))
	if key != "":
		return key
	var weapon := _entry_stats(entry)
	return String(weapon.weapon_id) if weapon else "unknown"


func _resolve_stats(entry: Dictionary) -> WeaponStats:
	var resolved := WeaponRegistry.stats_for(int(entry.get("class_id", -1)))
	return resolved if resolved != null else stats


func _entry_stats(entry: Dictionary) -> WeaponStats:
	var resolved := entry.get("stats", null) as WeaponStats
	return resolved if resolved != null else stats


func _cancel_trigger(entry: Dictionary, fire_held: bool) -> void:
	entry["fire_prev"] = fire_held
	entry["charge"] = 0.0
	entry["burst_left"] = 0
	entry["burst_timer"] = 0.0


func _apply_slow(entry: Dictionary, frame: PlayerInputFrame) -> void:
	var entity_id := int(entry.get("id", -1))
	if entity_id < 0:
		return
	var status: Dictionary = statuses.get(entity_id, {})
	if status.is_empty() or float(status.get("slow_left", 0.0)) <= 0.0:
		return
	frame.move *= clampf(float(status.get("slow_scale", 1.0)), 0.0, 1.0)


func _tick_status(entry: Dictionary, delta: float) -> void:
	var entity_id := int(entry.get("id", -1))
	if entity_id < 0 or not statuses.has(entity_id):
		return
	var status: Dictionary = statuses[entity_id]
	if float(status.get("slow_left", 0.0)) > 0.0:
		status["slow_left"] = maxf(0.0, float(status["slow_left"]) - delta)
	if float(status.get("bleed_left", 0.0)) > 0.0:
		status["bleed_left"] = maxf(0.0, float(status["bleed_left"]) - delta)
		status["bleed_tick"] = float(status.get("bleed_tick", BLEED_TICK_SEC)) - delta
		if float(status["bleed_tick"]) <= 0.0:
			status["bleed_tick"] = BLEED_TICK_SEC
			var slice := int(round(float(status.get("bleed_dps", 0.0)) * BLEED_TICK_SEC))
			if slice > 0:
				_apply_bleed(entry, int(status.get("source_id", 0)), slice)
	if float(status.get("slow_left", 0.0)) <= 0.0 and float(status.get("bleed_left", 0.0)) <= 0.0:
		statuses.erase(entity_id)
	else:
		statuses[entity_id] = status


func _apply_bleed(entry: Dictionary, source_id: int, amount: int) -> void:
	var node_ref: Variant = entry.get("node", null)
	if not is_instance_valid(node_ref):
		return
	var actor := node_ref as Node
	if actor == null:
		return
	var hurtbox := actor.get_node_or_null("BodyHurtbox") as HurtboxComponent
	if hurtbox == null:
		return
	var health := hurtbox.get_health()
	var hp_before := health.current if health else 0
	CombatResolver.apply_hit(hurtbox, amount, 1.0, source_id, actor.global_position)
	if health != null and health.current < hp_before:
		note_damage_hit()


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


func _aim_direction(
	actor: PlayerController, yaw: float, pitch: float, muzzle: Vector3,
	entry: Dictionary, weapon: WeaponStats
) -> Vector3:
	var cam := camera_origin(actor.global_position, yaw, pitch)
	var view := canonical_direction(yaw, pitch)
	var query := PhysicsRayQueryParameters3D.create(cam, cam + view * 250.0, 1 | 8)
	query.collide_with_areas = true
	query.exclude = _exclusion_rids(actor)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point: Vector3 = hit.position if not hit.is_empty() else cam + view * 250.0
	# Bots aim flat like a human crosshair, but a thrown weapon drops on the way
	# to the target. Lead the arc for bots only; players learn the drop.
	if weapon.projectile_gravity > 0.0 and bool(entry.get("is_bot", false)):
		var distance := aim_point.distance_to(muzzle)
		var travel := distance / maxf(weapon.projectile_speed, 1.0)
		aim_point += Vector3.UP * (0.5 * weapon.projectile_gravity * travel * travel)
	return (aim_point - muzzle).normalized()


func _spawn_projectile(
	actor: PlayerController, origin: Vector3, direction: Vector3, weapon: WeaponStats,
	speed_override: float = -1.0, damage_override: int = -1
) -> void:
	if weapon.projectile_scene == null or world == null:
		return
	var projectile := weapon.projectile_scene.instantiate() as Projectile
	if projectile == null:
		return
	world.add_child(projectile)
	projectile.global_position = origin
	projectile.telemetry = self
	projectile.setup(
		direction, weapon, actor.net_id, _exclusion_rids(actor),
		speed_override, damage_override
	)
	projectiles_fired += 1


func _exclusion_rids(actor: PlayerController) -> Array[RID]:
	var rids: Array[RID] = [actor.get_rid()]
	for path: String in ["BodyHurtbox", "HeadHurtbox"]:
		var area := actor.get_node_or_null(path) as Area3D
		if area:
			rids.append(area.get_rid())
	return rids
