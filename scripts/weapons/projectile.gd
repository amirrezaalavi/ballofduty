class_name Projectile
extends Node3D
## Swept projectile. A ray from the previous position to the new position each
## physics tick prevents tunneling at 90 m/s / 30 Hz.

signal hit_confirmed(headshot: bool, killed: bool)

var velocity: Vector3 = Vector3.ZERO
var damage: int = 25
var headshot_multiplier: float = 2.0
var source_id: int = 0
var lifetime: float = 2.5
var exclusion_rids: Array[RID] = []

var _spawn_position: Vector3 = Vector3.ZERO


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
		_resolve(hit)
		queue_free()
		return

	global_position = to
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()


func _resolve(hit: Dictionary) -> void:
	var hurtbox := hit.collider as HurtboxComponent
	if hurtbox:
		var headshot := hurtbox.hitbox_name == &"head"
		var killed := CombatResolver.apply_hit(
			hurtbox, damage, headshot_multiplier, source_id, hit.position
		)
		hit_confirmed.emit(headshot, killed)

	_spawn_impact(hit.position, hit.normal)


func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.75, 0.3)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.6, 0.2)
	material.emission_energy_multiplier = 2.5
	flash.mesh = sphere
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var scene := get_tree().current_scene
	if scene == null:
		scene = get_parent()
	if scene == null:
		return
	scene.add_child(flash)
	flash.global_position = position + normal * 0.02

	var tween := flash.create_tween()
	tween.tween_property(flash, "scale", Vector3.ZERO, 0.12)
	tween.tween_callback(flash.queue_free)
