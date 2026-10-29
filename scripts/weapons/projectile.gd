class_name Projectile
extends Node3D
## Swept projectile. A ray from the previous position to the new position each
## physics tick prevents tunneling at 81 m/s / 30 Hz. Phase 2A adds class
## ballistics: pierce, splash and a slow hook. All of it resolves on the
## authoritative server with normal physics queries; clients still only see
## SHOT/HIT events. Rounds fly flat and optionally inherit shooter velocity.
##
## Phase 1 C: resolution is reported to an optional telemetry sink (ServerCombat)
## so the soak can prove that every spawned round ends as a hit, a world impact
## or an expiry. Impacts use the shared BulletField pool: a shot no longer
## allocates a mesh/material per hit.

signal hit_confirmed(killed: bool)

## EXPERIMENTAL: a round keeps the shooter's velocity, so strafing, sprinting or
## jumping nudges the throw. Flip this off (or set the scale to 0) to return to
## purely muzzle-relative shots. Shared by the server and offline play.
const INHERIT_SHOOTER_VELOCITY := true
const INHERIT_SHOOTER_VELOCITY_SCALE := 1.0


static func inherited_velocity(shooter_velocity: Vector3) -> Vector3:
	if not INHERIT_SHOOTER_VELOCITY:
		return Vector3.ZERO
	return shooter_velocity * INHERIT_SHOOTER_VELOCITY_SCALE

var velocity: Vector3 = Vector3.ZERO
var damage: int = 25
var source_id: int = 0
var lifetime: float = 2.5
var exclusion_rids: Array[RID] = []
## ServerCombat (RefCounted) or any object with note_projectile_resolved().
var telemetry: Object = null

# Class ballistics/effects snapshot.
var weapon: WeaponStats = null
var pierce_left: int = 0
var splash_radius: float = 0.0
var splash_damage: int = 0
var splash_edge_scale: float = 0.5

var _spawn_position: Vector3 = Vector3.ZERO
var _resolved: bool = false
var _hit_entities: Dictionary = {}


func setup(
	direction: Vector3,
	stats: WeaponStats,
	shooter_id: int,
	exclude: Array[RID],
	speed_override: float = -1.0,
	damage_override: int = -1,
	inherit_velocity: Vector3 = Vector3.ZERO
) -> void:
	weapon = stats
	var speed := stats.projectile_speed
	if speed_override >= 0.0:
		speed = speed_override
	velocity = direction.normalized() * speed + inherit_velocity
	damage = stats.damage
	if damage_override >= 0:
		damage = damage_override
	lifetime = stats.projectile_lifetime
	pierce_left = stats.pierce
	splash_radius = stats.splash_radius
	splash_damage = stats.splash_damage
	splash_edge_scale = stats.splash_edge_scale
	source_id = shooter_id
	exclusion_rids = exclude
	_spawn_position = global_position
	if velocity.length_squared() > 0.001:
		look_at(global_position + velocity, Vector3.UP)


func _physics_process(delta: float) -> void:
	if velocity.length_squared() < 0.001:
		return

	var from := global_position
	var to := from + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = exclusion_rids
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		_impact(hit)
		return

	global_position = to
	lifetime -= delta
	if lifetime <= 0.0:
		_done(&"expired")
		queue_free()


func _impact(hit: Dictionary) -> void:
	var hurtbox := hit.collider as HurtboxComponent
	if hurtbox == null:
		_apply_splash(hit.position, null)
		_spawn_impact(hit.position, hit.get("normal", Vector3.UP))
		_done(&"world")
		queue_free()
		return

	var entity_key := _entity_key(hurtbox)
	var already_hit := _hit_entities.has(entity_key)
	var damaged := false
	if not already_hit:
		_hit_entities[entity_key] = true
		damaged = _damage_hurtbox(hurtbox, damage, hit.position)
		if damaged:
			_apply_hit_effects(hurtbox)
	else:
		# A piercing round met the same victim's second hurtbox (body/head).
		# Never double-dip and never stop on the same entity: step past it and
		# keep the remaining pierce budget for the next target.
		exclusion_rids.append(hurtbox.get_rid())
		global_position = hit.position + velocity.normalized() * 0.02
		return

	_spawn_impact(hit.position, hit.get("normal", Vector3.UP))
	if pierce_left > 0 and not already_hit:
		pierce_left -= 1
		exclusion_rids.append(hurtbox.get_rid())
		if telemetry != null:
			telemetry.call("note_projectile_pierce")
		# Step past the contact point so the next sweep does not start inside it.
		var forward := velocity.normalized()
		global_position = hit.position + forward * 0.02
		return

	_apply_splash(hit.position, hurtbox)
	var kind: StringName = &"hit" if hurtbox.entity_id > 0 else &"world"
	_done(kind)
	queue_free()


## Returns true when the contact actually removed HP.
func _damage_hurtbox(
	hurtbox: HurtboxComponent, base_damage: int, position: Vector3
) -> bool:
	var health := hurtbox.get_health()
	var hp_before := health.current if health else 0
	var killed := CombatResolver.apply_hit(
		hurtbox, base_damage, source_id, position
	)
	var damaged := health != null and health.current < hp_before
	if damaged and hurtbox.entity_id > 0 and telemetry != null:
		telemetry.call("note_damage_hit")
	hit_confirmed.emit(killed)
	return damaged


func _apply_hit_effects(hurtbox: HurtboxComponent) -> void:
	if weapon == null:
		return
	if weapon.knockback > 0.0:
		var body := hurtbox.get_parent() as CharacterBody3D
		if body:
			var push := velocity
			push.y = 0.0
			push = push.normalized()
			body.velocity += push * weapon.knockback
			body.velocity.y += weapon.knockback * 0.2
	if telemetry == null:
		return
	if weapon.slow_amount > 0.0:
		telemetry.call(
			"note_projectile_effect", hurtbox.entity_id, source_id, weapon, velocity.normalized()
		)


## Server-side radial damage. Skips the direct victim (already damaged) and the
## shooter (in exclusion_rids), and de-duplicates body/head hurtboxes.
func _apply_splash(point: Vector3, direct: HurtboxComponent) -> void:
	if splash_radius <= 0.0 or splash_damage <= 0:
		return
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = splash_radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), point)
	params.collision_mask = 8
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.exclude = exclusion_rids.duplicate()
	var results := space.intersect_shape(params, 32)
	var direct_key := _entity_key(direct) if direct else 0
	var seen: Dictionary = {}
	for result in results:
		var hurtbox := result.get("collider") as HurtboxComponent
		if hurtbox == null:
			continue
		var key := _entity_key(hurtbox)
		if key == direct_key or seen.has(key):
			continue
		seen[key] = true
		var distance := point.distance_to(hurtbox.global_position)
		var t := clampf(distance / splash_radius, 0.0, 1.0)
		var amount := int(round(splash_damage * lerpf(1.0, splash_edge_scale, t)))
		if amount <= 0:
			continue
		_damage_hurtbox(hurtbox, amount, point)


func _entity_key(hurtbox: HurtboxComponent) -> int:
	if hurtbox.entity_id > 0:
		return hurtbox.entity_id
	# Training dummies use entity_id 0; key their body/head hurtboxes together.
	var owner_node := hurtbox.get_parent()
	return -owner_node.get_instance_id() if owner_node else -hurtbox.get_instance_id()


## Report exactly once, even if a future path resolves a projectile twice.
func _done(kind: StringName) -> void:
	if _resolved:
		return
	_resolved = true
	if telemetry != null:
		telemetry.call("note_projectile_resolved", kind)


func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	# Pooled on the client. The authoritative server is headless, where
	# BulletField.impact_at() returns immediately.
	BulletField.impact_at(get_parent(), position, normal)
