extends SceneTree
## Arena budget + integrity report for both maps.
##
##   tools/godot --headless --path . --script tests/headless/arena_stats.gd
##
## The quarry is the shipping map and gets the full check: 9 terrain chunks,
## 8 spawns, cave floor/ceiling clearance, boundary rays and the hard rendering
## budget. The nature arena stays in the report because the old experiment
## harness and the camera regressions still use it.

const MAX_DRAW_CALLS := 150
const MAX_TRIANGLES := 250_000
const NATURE_LOG_POS := Vector3(-12.0, 0.25, -3.0)

var _draw_calls := 0
var _triangles := 0
var _instances := 0
var _colliders := 0


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	var nature_ok := await _check_nature()
	var quarry_ok := await _check_quarry()
	quit(0 if nature_ok and quarry_ok else 1)


func _check_nature() -> bool:
	var arena := await _spawn("res://scenes/maps/arena_nature.tscn")
	if arena == null:
		return false
	_count_node(arena)
	var blocked := _blocked_spawns(arena)
	var spawns := _spawn_points(arena)
	var min_gap := _min_spawn_gap(spawns)
	var log_solid := _shape_hits(arena, NATURE_LOG_POS, 0.2)
	print("arena_stats nature: draw_calls=%d triangles=%d prop_instances=%d colliders=%d spawns=%d min_gap=%.1f blocked_spawns=%d log_solid=%s" % [
		_draw_calls, _triangles, _instances, _colliders, spawns.size(), min_gap, blocked,
		str(log_solid),
	])
	var ok := _budget_ok("nature")
	if blocked > 0:
		push_error("nature: %d spawn point(s) are blocked" % blocked)
		ok = false
	if not log_solid:
		push_error("nature: the fallen log has no collision")
		ok = false
	arena.free()
	return ok


func _check_quarry() -> bool:
	var arena := await _spawn("res://scenes/maps/arena_quarry.tscn")
	if arena == null:
		return false
	_count_node(arena)
	var blocked := _blocked_spawns(arena)
	var spawns := _spawn_points(arena)
	var min_gap := _min_spawn_gap(spawns)
	var chunks := int(arena.call("terrain_chunk_count"))
	var floor_y := float(arena.call("cave_floor_y"))
	var ceiling_y := float(arena.call("cave_ceiling_y"))
	var clearance := _cave_clearance(arena)
	var boundary := _boundary_distance(arena)
	print("arena_stats quarry: draw_calls=%d triangles=%d prop_instances=%d colliders=%d spawns=%d min_gap=%.1f blocked_spawns=%d chunks=%d cave_floor=%.2f cave_ceiling=%.2f cave_clearance=%.2f boundary=%.1f" % [
		_draw_calls, _triangles, _instances, _colliders, spawns.size(), min_gap, blocked,
		chunks, floor_y, ceiling_y, clearance, boundary,
	])
	var ok := _budget_ok("quarry")
	if chunks != 9:
		push_error("quarry: expected 9 terrain chunks, got %d" % chunks)
		ok = false
	if spawns.size() < 8:
		push_error("quarry: only %d spawn points" % spawns.size())
		ok = false
	if min_gap < 15.0:
		push_error("quarry: spawn points are %.1f m apart (need 15 m)" % min_gap)
		ok = false
	if blocked > 0:
		push_error("quarry: %d spawn point(s) are blocked" % blocked)
		ok = false
	if ceiling_y - floor_y < 3.8 or clearance < 3.8:
		push_error("quarry: cave clearance %.2f m (need 3.8 m)" % clearance)
		ok = false
	if boundary > 70.2:
		push_error("quarry: boundary ray escaped to %.1f m" % boundary)
		ok = false
	if _instances < 300:
		push_error("quarry: dressing scattered only %d instances" % _instances)
		ok = false
	arena.free()
	return ok


func _spawn(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error(path + " failed to load")
		return null
	var arena := packed.instantiate() as Node3D
	root.add_child(arena)
	await process_frame
	await physics_frame
	await physics_frame
	_draw_calls = 0
	_triangles = 0
	_instances = 0
	_colliders = 0
	return arena


func _budget_ok(label: String) -> bool:
	var ok := true
	if _draw_calls > MAX_DRAW_CALLS:
		push_error("%s draw calls %d exceed %d" % [label, _draw_calls, MAX_DRAW_CALLS])
		ok = false
	if _triangles > MAX_TRIANGLES:
		push_error("%s triangles %d exceed %d" % [label, _triangles, MAX_TRIANGLES])
		ok = false
	return ok


func _spawn_points(arena: Node3D) -> Array:
	var points: Array = []
	for child in arena.get_children():
		if child is Marker3D and child.name.begins_with("Spawn"):
			points.append((child as Marker3D).global_position)
	return points


func _min_spawn_gap(points: Array) -> float:
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
		if not (child is Marker3D) or not child.name.begins_with("Spawn"):
			continue
		var marker := child as Marker3D
		query.transform = Transform3D(Basis(), marker.global_position + Vector3.UP * 0.7)
		if not space.intersect_shape(query, 1).is_empty():
			blocked += 1
			push_warning("Spawn blocked: " + marker.name)
	return blocked


func _shape_hits(arena: Node3D, pos: Vector3, radius: float) -> bool:
	var space := arena.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.transform = Transform3D(Basis(), pos)
	return not space.intersect_shape(query, 1).is_empty()


func _cave_clearance(arena: Node3D) -> float:
	var space := arena.get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 3.0, -54.0), Vector3(0.0, -8.0, -54.0), 1)
	var up := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 1.0, -54.0), Vector3(0.0, 20.0, -54.0), 1)
	var floor_hit := space.intersect_ray(down)
	var ceiling_hit := space.intersect_ray(up)
	if floor_hit.is_empty() or ceiling_hit.is_empty():
		push_error("quarry: cave floor/ceiling ray missed")
		return 0.0
	return float(ceiling_hit["position"].y) - float(floor_hit["position"].y)


## Longest distance a centre ray travels before the mountain ring or an
## invisible boundary wall stops it. The four cardinal rays use y=12 so they
## clear the terraces; the north ray is offset in x to avoid the cave ridge.
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
			push_error("quarry: boundary ray escaped the map")
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
