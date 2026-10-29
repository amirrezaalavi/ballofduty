class_name Projectile
extends Node3D
## Swept projectile. A ray from the previous position to the new position each
## physics tick prevents tunneling at 81 m/s / 30 Hz.
##
## Phase 1 C: resolution is reported to an optional telemetry sink (ServerCombat)
## so the soak can prove that every spawned round ends as a hit, a world impact
## or an expiry. Impacts use the shared BulletField pool: a shot no longer
## allocates a mesh/material per hit.

signal hit_confirmed(headshot: bool, killed: bool)

var velocity: Vector3 = Vector3.ZERO
var damage: int = 25
var headshot_multiplier: float = 2.0
var source_id: int = 0
var lifetime: float = 2.5
var exclusion_rids: Array[RID] = []
## ServerCombat (RefCounted) or any object with note_projectile_resolved().
var telemetry: Object = null

var _spawn_position: Vector3 = Vector3.ZERO
var _resolved: bool = false


func setup(
	direction: Vector3,
	stats: WeaponStats,
	shooter_id: int,
	exclude: Array[RID]
) -> void:
	velocity = direction.normalized() * stats.projectile_speed
	damage = stats.damage
	headshot_multiplier = stats.headshot_multiplier
	lifetime = stats.projectile_lifetime
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
		var kind := _resolve(hit)
		_done(kind)
		queue_free()
		return

	global_position = to
	lifetime -= delta
	if lifetime <= 0.0:
		_done(&"expired")
		queue_free()


## Returns the telemetry bucket: "hit" for a roster player, "world" for all
## other surfaces (including entity_id 0 training dummies).
func _resolve(hit: Dictionary) -> StringName:
	var kind: StringName = &"world"
	var hurtbox := hit.collider as HurtboxComponent
	if hurtbox:
		# Server actors have ids 1..N. id 0 is a training dummy, not a roster
		# player, so it belongs in the world bucket for hit/miss accounting.
		var roster_target := hurtbox.entity_id > 0
		if roster_target:
			kind = &"hit"
		var health := hurtbox.get_health()
		var hp_before := health.current if health else 0
		var headshot := hurtbox.hitbox_name == &"head"
		var killed := CombatResolver.apply_hit(
			hurtbox, damage, headshot_multiplier, source_id, hit.position
		)
		if roster_target and health != null and health.current < hp_before and telemetry != null:
			telemetry.call("note_damage_hit")
		hit_confirmed.emit(headshot, killed)

	_spawn_impact(hit.position, hit.get("normal", Vector3.UP))
	return kind


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
