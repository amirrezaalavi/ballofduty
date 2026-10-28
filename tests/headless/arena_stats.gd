extends SceneTree
## Loads the nature arena, runs its deterministic scatter, and reports the
## rendering/collision budget. Fails if CP2 limits are exceeded.

const MAX_DRAW_CALLS := 150
const MAX_TRIANGLES := 250_000

var _draw_calls := 0
var _triangles := 0
var _instances := 0
var _colliders := 0


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var packed := load("res://scenes/maps/arena_nature.tscn") as PackedScene
	if packed == null:
		push_error("arena_nature.tscn failed to load")
		quit(1)
		return

	var arena := packed.instantiate() as Node3D
	root.add_child(arena)
	await process_frame
	await physics_frame
	_count_node(arena)
	var blocked_spawns := _blocked_spawns(arena)
	print("arena_stats: draw_calls=%d triangles=%d prop_instances=%d colliders=%d blocked_spawns=%d" % [
		_draw_calls, _triangles, _instances, _colliders, blocked_spawns,
	])

	var ok := true
	if _draw_calls > MAX_DRAW_CALLS:
		push_error("draw calls %d exceed %d" % [_draw_calls, MAX_DRAW_CALLS])
		ok = false
	if _triangles > MAX_TRIANGLES:
		push_error("triangles %d exceed %d" % [_triangles, MAX_TRIANGLES])
		ok = false
	if _instances < 80:
		push_error("scatter produced too few props: %d" % _instances)
		ok = false
	if blocked_spawns > 0:
		push_error("%d spawn point(s) are blocked by geometry" % blocked_spawns)
		ok = false

	arena.free()
	quit(0 if ok else 1)


func _blocked_spawns(arena: Node3D) -> int:
	var space := arena.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var blocked := 0
	for child in arena.get_children():
		if not (child is Marker3D) or not child.name.begins_with("Spawn"):
			continue
		var marker := child as Marker3D
		query.transform = Transform3D(Basis(), marker.position + Vector3.UP * 0.7)
		if not space.intersect_shape(query, 1).is_empty():
			blocked += 1
			push_warning("Spawn blocked: " + marker.name)
	return blocked


func _count_node(node: Node) -> void:
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		var mesh := mmi.multimesh.mesh
		var count := mmi.multimesh.instance_count
		_instances += count
		if mesh:
			_draw_calls += mesh.get_surface_count()
			_triangles += (mesh.get_faces().size() / 3) * count
	elif node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			_draw_calls += mesh_instance.mesh.get_surface_count()
			_triangles += mesh_instance.mesh.get_faces().size() / 3
	if node is StaticBody3D:
		_colliders += 1
	for child in node.get_children():
		_count_node(child)
