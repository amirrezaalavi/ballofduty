class_name BulletVisual
extends Node3D
## Pooled cosmetic projectile. Flies at the real weapon speed, stops on the
## first world/actor surface and never applies damage. The server projectile
## remains authoritative; this exists only so the player can track the round.
##
## Phase 1 C: the streak grows out of the muzzle. At spawn the trail/rim length
## is zero; it reaches its full 2.2 m / 2.4 m only after travelling that far, so
## it can never paint a beam backwards through the camera. Cosmetic movement and
## the swept ray run at render rate (_process), which keeps 60 fps growth smooth.

var speed: float = 81.0
var direction: Vector3 = Vector3.FORWARD
var life: float = 1.2
var exclude_rids: Array[RID] = []
## Metres travelled since launch. Drives the growing streak.
var distance: float = 0.0

var _trail: MeshInstance3D
var _rim: MeshInstance3D
var _body: MeshInstance3D
var _trail_length: float = 2.2
var _rim_length: float = 2.4


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
	_rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rim)
	_rim_length = _mesh_length(rim_mesh)

	_trail = MeshInstance3D.new()
	_trail.mesh = trail_mesh
	_trail.material_override = trail_material
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_trail_length = _mesh_length(trail_mesh)

	_body = MeshInstance3D.new()
	_body.mesh = body_mesh
	_body.material_override = body_material
	_body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_body)

	visible = false
	set_process(false)
	set_physics_process(false)
	_update_streak()


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
	distance = 0.0
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
	set_process(true)
	set_physics_process(false)
	_update_streak()


func _process(delta: float) -> void:
	if not visible:
		return
	var from := global_position
	var to := from + direction * speed * delta
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 8)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = exclude_rids
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit.position
		distance += from.distance_to(hit.position)
		_update_streak()
		var field := get_parent()
		if field is BulletField:
			(field as BulletField).spawn_impact(hit.position, hit.get("normal", Vector3.UP))
		_stop()
		return

	global_position = to
	distance += from.distance_to(to)
	life -= delta
	_update_streak()
	if life <= 0.0:
		_stop()


## Local +Z is backwards after look_at(). The visible streak spans from the
## bullet back towards the muzzle: length min(distance, max_length), never more.
func _update_streak() -> void:
	_update_bar(_trail, _trail_length)
	_update_bar(_rim, _rim_length)


func _update_bar(bar: MeshInstance3D, max_length: float) -> void:
	if bar == null or max_length <= 0.001:
		return
	var visible_length := clampf(distance, 0.0, max_length)
	bar.visible = visible_length > 0.01
	if not bar.visible:
		return
	bar.scale = Vector3(1.0, 1.0, visible_length / max_length)
	bar.position = Vector3(0.0, 0.0, visible_length * 0.5)


func _mesh_length(mesh: Mesh) -> float:
	var box := mesh as BoxMesh
	return absf(box.size.z) if box else 1.0


func _stop() -> void:
	visible = false
	set_process(false)
	set_physics_process(false)
