extends SceneTree
## Multi-map smoke probe: every MapRegistry candidate must load headless with
## 8 unblocked spawns (>=15 m apart), 9 terrain chunks, contained boundary
## rays and inside the rendering budget.
##
##   tools/godot --headless --path . --script tests/headless/map_smoke.gd

const MAX_DRAW_CALLS := 150
const MAX_TRIANGLES := 250_000

var _draw_calls := 0
var _triangles := 0
var _instances := 0
var _colliders := 0
var _failures := 0
var _checked := 0


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var registry := load("res://scripts/game/map_registry.gd")
	for entry: Dictionary in registry.MAPS:
		await _check_map(String(entry["id"]), String(entry["scene"]))
	print("MAP_SMOKE maps=%d failures=%d result=%s" % [
		_checked, _failures, "PASS" if _failures == 0 else "FAIL",
	])
	quit(0 if _failures == 0 else 1)


func _check_map(map_id: String, scene_path: String) -> void:
	_checked += 1
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures += 1
		print("MAP_SMOKE %-8s FAIL scene missing: %s" % [map_id, scene_path])
		return
	var arena := packed.instantiate() as Node3D
	root.add_child(arena)
	await process_frame
	await physics_frame
	await physics_frame
	_draw_calls = 0
	_triangles = 0
	_instances = 0
	_colliders = 0
	_count_node(arena)

	var problems: Array[String] = []
	var spawns: Array = []
	for child in arena.get_children():
		if child is Marker3D and child.name.begins_with("Spawn"):
			spawns.append((child as Marker3D).global_position)
	if spawns.size() < 8:
		problems.append("only %d spawns" % spawns.size())
	var gap := _min_gap(spawns)
	if gap < 15.0:
		problems.append("spawn gap %.1f m" % gap)
	var blocked := _blocked_spawns(arena)
	if blocked > 0:
		problems.append("%d blocked spawns" % blocked)
	if arena.has_method("terrain_chunk_count"):
		var chunks := int(arena.call("terrain_chunk_count"))
		if chunks != 9:
			problems.append("chunks=%d" % chunks)
	else:
		problems.append("no terrain_chunk_count()")
	var boundary := _boundary_distance(arena)
	if boundary > 70.5 or boundary < 40.0:
		problems.append("boundary ray %.1f m" % boundary)
	if _draw_calls > MAX_DRAW_CALLS:
		problems.append("draw calls %d" % _draw_calls)
	if _triangles > MAX_TRIANGLES:
		problems.append("triangles %d" % _triangles)

	if problems.is_empty():
		print("MAP_SMOKE %-8s PASS spawns=%d gap=%.1f draws=%d tris=%d inst=%d colliders=%d boundary=%.1f" % [
			map_id, spawns.size(), gap, _draw_calls, _triangles,
			_instances, _colliders, boundary,
		])
	else:
		_failures += 1
		print("MAP_SMOKE %-8s FAIL %s" % [map_id, " + ".join(problems)])
	arena.free()


func _min_gap(points: Array) -> float:
	var gap := INF
	for a in points.size():
		for b in range(a + 1, points.size()):
			var pa: Vector3 = points[a]
			var pb: Vector3 = points[b]
			gap = minf(gap, Vector2(pa.x - pb.x, pa.z - pb.z).length())
	return gap


func _blocked_spawns(arena: Node3D) -> int:
	var space := arena.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var blocked := 0
	for child in arena.get_children():
		if child is Marker3D and child.name.begins_with("Spawn"):
			var marker := child as Marker3D
			query.transform = Transform3D(Basis(), marker.global_position + Vector3.UP * 0.7)
			if not space.intersect_shape(query, 1).is_empty():
				blocked += 1
	return blocked


func _boundary_distance(arena: Node3D) -> float:
	var space := arena.get_world_3d().direct_space_state
	var rays := [
		[Vector3(0.0, 12.0, 0.0), Vector3(1.0, 0.0, 0.0)],
		[Vector3(0.0, 12.0, 0.0), Vector3(-1.0, 0.0, 0.0)],
		[Vector3(40.0, 12.0, 0.0), Vector3(0.0, 0.0, 1.0)],
		[Vector3(40.0, 12.0, 0.0), Vector3(0.0, 0.0, -1.0)],
	]
	var farthest := 0.0
	for ray: Array in rays:
		var from: Vector3 = ray[0]
		var dir: Vector3 = ray[1]
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return 999.0
		farthest = maxf(farthest, from.distance_to(hit["position"]))
	return farthest


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
