extends SceneTree
## Diagnostic: sample the collision floor of every map on a 1 m grid and report
## height discontinuities a 0.8 m capsule cannot walk up. Godot's move_and_slide
## has no step climbing, so anything above floor_snap_length (0.3 m) is a wall.
##
## Not a gate: cliffs are intended. Use it after a map change to confirm there
## are no holes and that the step count has not exploded.
##
##   ./tools/godot --headless --path . --script tests/headless/map_surface_probe.gd

const MAPS := ["quarry", "dunes", "crater", "jungle"]
const STEP := 1.0
const MAX_WALK := 0.30  # floor_snap_length; above this a step is a wall

var _space: PhysicsDirectSpaceState3D


func _init() -> void:
	await process_frame
	for map_id in MAPS:
		await _probe(map_id)
	quit()


func _probe(map_id: String) -> void:
	var path := "res://scenes/maps/arena_%s.tscn" % map_id
	var packed := load(path) as PackedScene
	if packed == null:
		print("MAP_PROBE %s MISSING %s" % [map_id, path])
		return
	var arena := packed.instantiate() as Node3D
	root.add_child(arena)
	for _i in 6:
		await physics_frame
	var shape := arena.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	var extent := 50.0
	if shape and shape.shape is HeightMapShape3D:
		var hm := shape.shape as HeightMapShape3D
		extent = minf(float(hm.map_width), float(hm.map_depth)) * float(hm.map_scale.x) * 0.5
	_space = arena.get_world_3d().direct_space_state

	var half := extent - 2.0
	var samples := int((half * 2.0) / STEP) + 1
	var grid := {}
	var misses := 0
	var total := 0
	for ix in samples:
		for iz in samples:
			var x := -half + float(ix) * STEP
			var z := -half + float(iz) * STEP
			total += 1
			var hit := _floor(x, z)
			if hit.is_empty():
				misses += 1
				continue
			grid[Vector2i(ix, iz)] = (hit["position"] as Vector3).y

	var walls := 0
	var edges := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var slopes := 0
	for cell: Vector2i in grid:
		var y: float = grid[cell]
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var other: Vector2i = cell + d
			if not grid.has(other):
				continue
			edges += 1
			var dy: float = absf(float(grid[other]) - y)
			if dy > worst:
				worst = dy
				worst_at = Vector2(float(cell.x), float(cell.y))
			if dy > MAX_WALK:
				walls += 1
			if dy > STEP * 0.9:
				slopes += 1
	print("MAP_PROBE %-7s extent=%.0fm samples=%d holes=%d edges=%d steps>%.2fm=%d (%.2f%%) worst=%.2fm at %s" % [
		map_id, extent, total, misses, edges, MAX_WALK, walls,
		100.0 * float(walls) / maxf(1.0, float(edges)), worst, str(worst_at),
	])
	arena.queue_free()
	await process_frame


func _floor(x: float, z: float) -> Dictionary:
	var from := Vector3(x, 80.0, z)
	var to := Vector3(x, -80.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return _space.intersect_ray(query)
