class_name BulletVisual
extends Node3D
## Pooled cosmetic projectile. Flies at the real weapon speed, stops on the
## first world/actor surface and never applies damage. The server projectile
## remains authoritative; this exists only so the player can track the round.

var speed: float = 81.0
var direction: Vector3 = Vector3.FORWARD
var life: float = 1.2
var exclude_rids: Array[RID] = []

var _trail: MeshInstance3D
var _rim: MeshInstance3D
var _body: MeshInstance3D


func build(
	body_mesh: Mesh,
	trail_mesh: Mesh,
	rim_mesh: Mesh,
	body_material: Material,
	trail_material: Material,
	rim_material: Material
) -> void:
	# The dark rim sits under the bright streak so it stays readable against
	# bright grass, sand and sky (additive alone washes out on light terrain).
	_rim = MeshInstance3D.new()
	_rim.mesh = rim_mesh
	_rim.material_override = rim_material
	_rim.position = Vector3(0.0, 0.0, 1.35)
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rim)

	_trail = MeshInstance3D.new()
	_trail.mesh = trail_mesh
	_trail.material_override = trail_material
	_trail.position = Vector3(0.0, 0.0, 1.25)
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)

	_body = MeshInstance3D.new()
	_body.mesh = body_mesh
	_body.material_override = body_material
	_body.position = Vector3(0.0, 0.0, -0.18)
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)


func launch(
	origin: Vector3,
	shot_direction: Vector3,
	shot_speed: float,
	shot_life: float,
	exclude: Array[RID],
	body_material: Material,
	trail_material: Material,
	rim_material: Material
) -> void:
	direction = shot_direction.normalized()
	speed = maxf(shot_speed, 1.0)
	life = shot_life
	exclude_rids = exclude
	global_position = origin
	# A shot straight up would make look_at() degenerate. Keep -Z forward.
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	look_at(origin + direction, up)
	if _body:
		_body.material_override = body_material
	if _trail:
		_trail.material_override = trail_material
	if _rim:
		_rim.material_override = rim_material
	visible = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	var from := global_position
	var to := from + direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = exclude_rids
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		var field := get_parent()
		if field is BulletField:
			(field as BulletField).spawn_impact(hit.position, hit.get("normal", Vector3.UP))
		_stop()
		return

	global_position = to
	life -= delta
	if life <= 0.0:
		_stop()


func _stop() -> void:
	visible = false
	set_physics_process(false)
