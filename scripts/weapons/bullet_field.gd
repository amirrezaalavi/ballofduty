class_name BulletField
extends Node3D
## Cosmetic bullet/impact pool. One field per world, created on first shot.
## All meshes and materials are built once, so firing never allocates or
## compiles a shader mid-match (the old per-shot tracer did both).
##
## Phase 1 C: fixed 64-node pool, integer counters, and an impact path that is
## also pooled. Launching past 64 simultaneous visible rounds reuses the oldest
## slot instead of growing the tree; the counter makes that visible.

const POOL_SIZE := 64
const IMPACT_POOL := 24
const IMPACT_LIFE := 0.10
## Bullet spec (Phase 1 C): long streak, thin radial profile. The visual grows
## out of the muzzle in BulletVisual, so length is safe even at spawn.
const CORE_SIZE := Vector3(0.018, 0.018, 0.36)
const TRAIL_SIZE := Vector3(0.006, 0.006, 2.2)
const RIM_SIZE := Vector3(0.026, 0.026, 2.4)

const LOCAL_COLOR := Color(1.0, 0.9, 0.45)
const REMOTE_COLOR := Color(1.0, 0.6, 0.32)

static var _instance: BulletField

var _bullets: Array[BulletVisual] = []
var _impacts: Array[MeshInstance3D] = []
var _impact_left: Array[float] = []
var _body_materials: Array[StandardMaterial3D] = []
var _trail_materials: Array[StandardMaterial3D] = []
var _rim_materials: Array[StandardMaterial3D] = []
var _body_mesh: BoxMesh
var _trail_mesh: BoxMesh
var _rim_mesh: BoxMesh
var _impact_mesh: SphereMesh
var _impact_material: StandardMaterial3D
var _steal_index: int = 0

# Cheap telemetry (integers only, no per-frame work).
var pool_builds: int = 0
var launches: int = 0
var pool_exhausted: int = 0
var impacts_shown: int = 0
var peak_active: int = 0


static func spawn(
	parent: Node,
	origin: Vector3,
	direction: Vector3,
	speed: float,
	local_shot: bool,
	exclude: Array[RID] = []
) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless" or direction.length_squared() < 0.0001:
		return
	var field := _ensure(parent)
	field._launch(origin, direction, speed, local_shot, exclude)


## Pooled impact flash. Used by offline Projectile hits so a match never builds
## a mesh + material per impact.
static func impact_at(parent: Node, position: Vector3, normal: Vector3) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if DisplayServer.get_name() == "headless":
		return
	var field := _ensure(parent)
	field.spawn_impact(position, normal)


## Read-only counters for the debug HUD. Returns {} before the first shot.
static func pool_stats() -> Dictionary:
	if not is_instance_valid(_instance):
		return {}
	return {
		"launches": _instance.launches,
		"active": _instance.active_count(),
		"size": POOL_SIZE,
		"exhausted": _instance.pool_exhausted,
		"impacts": _instance.impacts_shown,
		"peak": _instance.peak_active,
		"builds": _instance.pool_builds,
	}


static func _ensure(parent: Node) -> BulletField:
	if is_instance_valid(_instance) and _instance.is_inside_tree():
		if _instance.get_parent() == parent:
			return _instance
		_instance.queue_free()
	var field := BulletField.new()
	field.name = "BulletField"
	parent.add_child(field)
	_instance = field
	return field


func _ready() -> void:
	_ensure_pool()


func _ensure_pool() -> void:
	if not _bullets.is_empty():
		return
	pool_builds += 1
	_body_mesh = BoxMesh.new()
	_body_mesh.size = CORE_SIZE
	# The streak is long but thin; BulletVisual grows its visible length from the
	# muzzle so it never extends behind the gun at spawn.
	_trail_mesh = BoxMesh.new()
	_trail_mesh.size = TRAIL_SIZE
	_rim_mesh = BoxMesh.new()
	_rim_mesh.size = RIM_SIZE
	_impact_mesh = SphereMesh.new()
	_impact_mesh.radius = 0.015
	_impact_mesh.height = 0.03

	for color: Color in [LOCAL_COLOR, REMOTE_COLOR]:
		var body := StandardMaterial3D.new()
		body.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		body.albedo_color = color
		body.emission_enabled = true
		body.emission = color
		body.emission_energy_multiplier = 3.0
		_body_materials.append(body)

		var trail := StandardMaterial3D.new()
		trail.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		trail.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		trail.albedo_color = Color(color.r, color.g, color.b, 0.9)
		trail.emission_enabled = true
		trail.emission = color
		trail.emission_energy_multiplier = 2.4
		trail.cull_mode = BaseMaterial3D.CULL_DISABLED
		_trail_materials.append(trail)

		var rim := StandardMaterial3D.new()
		rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rim.albedo_color = Color(0.04, 0.035, 0.03)
		rim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rim.albedo_color.a = 0.75
		rim.cull_mode = BaseMaterial3D.CULL_DISABLED
		_rim_materials.append(rim)

	_impact_material = StandardMaterial3D.new()
	_impact_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impact_material.albedo_color = Color(1.0, 0.78, 0.35)
	_impact_material.emission_enabled = true
	_impact_material.emission = Color(1.0, 0.62, 0.22)
	_impact_material.emission_energy_multiplier = 2.5

	for i in POOL_SIZE:
		var bullet := BulletVisual.new()
		bullet.name = "Bullet%d" % i
		add_child(bullet)
		bullet.build(
			_body_mesh, _trail_mesh, _rim_mesh,
			_body_materials[0], _trail_materials[0], _rim_materials[0]
		)
		bullet.visible = false
		bullet.set_process(false)
		bullet.set_physics_process(false)
		_bullets.append(bullet)

	for i in IMPACT_POOL:
		var impact := MeshInstance3D.new()
		impact.name = "Impact%d" % i
		impact.mesh = _impact_mesh
		impact.material_override = _impact_material
		impact.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		impact.visible = false
		add_child(impact)
		_impacts.append(impact)
		_impact_left.append(0.0)


func _launch(
	origin: Vector3,
	direction: Vector3,
	speed: float,
	local_shot: bool,
	exclude: Array[RID]
) -> void:
	_ensure_pool()
	var index := 0 if local_shot else 1
	launches += 1
	for bullet in _bullets:
		if not bullet.visible:
			bullet.launch(
				origin, direction, speed, 1.2, exclude,
				_body_materials[index], _trail_materials[index], _rim_materials[index]
			)
			peak_active = maxi(peak_active, active_count())
			return
	# A sustained 12-shooter burst can exceed 64 visible rounds. Reuse a slot
	# round-robin rather than allocating: the pool stays exactly 64 nodes.
	pool_exhausted += 1
	var reuse := _bullets[_steal_index % _bullets.size()]
	_steal_index += 1
	reuse.launch(
		origin, direction, speed, 1.2, exclude,
		_body_materials[index], _trail_materials[index], _rim_materials[index]
	)


func active_count() -> int:
	var count := 0
	for bullet in _bullets:
		if bullet.visible:
			count += 1
	return count


func spawn_impact(position: Vector3, normal: Vector3) -> void:
	impacts_shown += 1
	for i in _impacts.size():
		if not _impacts[i].visible:
			_impacts[i].global_position = position + normal * 0.02
			_impacts[i].scale = Vector3.ONE
			_impacts[i].visible = true
			_impact_left[i] = IMPACT_LIFE
			return
	# Impact pool exhausted: reuse slot 0 rather than allocating a node.
	_impacts[0].global_position = position + normal * 0.02
	_impacts[0].scale = Vector3.ONE
	_impacts[0].visible = true
	_impact_left[0] = IMPACT_LIFE


func _process(delta: float) -> void:
	for i in _impacts.size():
		if not _impacts[i].visible:
			continue
		_impact_left[i] -= delta
		if _impact_left[i] <= 0.0:
			_impacts[i].visible = false
			continue
		var t := clampf(_impact_left[i] / IMPACT_LIFE, 0.0, 1.0)
		_impacts[i].scale = Vector3.ONE * (0.35 + 0.65 * t)
