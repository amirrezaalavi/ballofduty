extends BodTestSuite
## Phase 2B arena regressions: heightmap/mesh parity, spawns, cave clearance,
## hero-prop collision, walkable ramps and an inescapable boundary.

const ARENA_PATH := "res://scenes/maps/arena_quarry.tscn"
const SCRIPT := preload("res://scripts/game/quarry_arena.gd")

var _arena: Node3D


func after_test() -> void:
	if is_instance_valid(_arena):
		_arena.free()
		_arena = null


func _make_arena() -> void:
	_arena = (load(ARENA_PATH) as PackedScene).instantiate() as Node3D
	add_child(_arena)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame


func test_map_loads_with_nine_chunks_and_cave() -> void:
	await _make_arena()
	expect(_arena != null, "quarry arena instantiates")
	expect(int(_arena.call("terrain_chunk_count")) == 9, "terrain has a 3x3 chunk grid")
	var terrain := _arena.get_node("Terrain")
	expect(terrain.get_child_count() == 9, "Terrain root has 9 chunk bodies")
	var all_heightmaps := true
	for chunk in terrain.get_children():
		var body := chunk as StaticBody3D
		var mesh := body.get_node_or_null("Mesh") as MeshInstance3D
		var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if body == null or mesh == null or shape == null:
			all_heightmaps = false
			continue
		if not (shape.shape is HeightMapShape3D):
			all_heightmaps = false
			continue
		var hm := shape.shape as HeightMapShape3D
		if hm.map_width != 51 or hm.map_depth != 51:
			all_heightmaps = false
	expect(all_heightmaps, "every chunk has a 51x51 HeightMapShape3D and a mesh")
	expect(_arena.get_node_or_null("Cave/CaveInterior") is Area3D, "cave atmosphere Area3D exists")
	var entrances: Array = _arena.call("cave_entrances")
	expect(entrances.size() == 2, "cave has two entrances")
	if entrances.size() == 2:
		expect((entrances[0] as Vector3).distance_to(entrances[1]) > 60.0,
			"cave bypass is a long north route (%.1f m)" % (entrances[0] as Vector3).distance_to(entrances[1]))


func test_heightmap_collision_matches_visual_mesh() -> void:
	await _make_arena()
	var space := _arena.get_world_3d().direct_space_state
	var excludes: Array[RID] = []
	for body in _arena.find_children("*", "StaticBody3D", true, false):
		if not String(body.name).begins_with("TerrainChunk"):
			excludes.append((body as StaticBody3D).get_rid())
	var samples := [
		Vector2(-12, 12), Vector2(18, -18), Vector2(-42, 8),
		Vector2(-56, -18), Vector2(28, 36), Vector2(58, 30),
	]
	for sample: Vector2 in samples:
		var expected := SCRIPT.height_at(sample.x, sample.y)
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(sample.x, 80.0, sample.y), Vector3(sample.x, -20.0, sample.y), 1)
		query.exclude = excludes
		var hit := space.intersect_ray(query)
		expect(not hit.is_empty(), "terrain ray hits at (%.0f, %.0f)" % [sample.x, sample.y])
		if hit.is_empty():
			continue
		expect(absf(float(hit["position"].y) - expected) < 0.05,
			"heightmap collision matches height field at (%.0f, %.0f)" % [sample.x, sample.y])
	# Every rendered vertex — at the visual mesh resolution — is sampled from
	# the same height field as the collider.
	var checked := 0
	var mismatched := 0
	for body in _arena.get_node("Terrain").get_children():
		var chunk := body as Node3D
		var mesh_instance := chunk.get_node("Mesh") as MeshInstance3D
		var arrays := mesh_instance.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			var gx := chunk.position.x + vertex.x
			var gz := chunk.position.z + vertex.z
			checked += 1
			if absf(vertex.y - SCRIPT.height_at(gx, gz)) > 0.01:
				mismatched += 1
	expect(checked > 10_000, "terrain mesh provides a dense vertex set (%d vertices)" % checked)
	expect(mismatched == 0, "all rendered vertices match the height field (%d mismatched)" % mismatched)


func test_spawns_are_spread_and_unblocked() -> void:
	await _make_arena()
	var spawns: Array = _arena.call("spawn_positions")
	expect(spawns.size() == 8, "arena exposes 8 spawn points")
	var space := _arena.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.55
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	for a in spawns.size():
		var pa: Vector3 = spawns[a]
		expect(absf(pa.y - (SCRIPT.height_at(pa.x, pa.z) + 0.15)) < 0.02,
			"spawn %d is snapped to the ground" % (a + 1))
		expect(SCRIPT.slope_at(pa.x, pa.z) < 0.35, "spawn %d is on walkable ground" % (a + 1))
		query.transform = Transform3D(Basis(), pa + Vector3.UP * 0.7)
		expect(space.intersect_shape(query, 1).is_empty(), "spawn %d is not blocked" % (a + 1))
		for b in range(a + 1, spawns.size()):
			var pb: Vector3 = spawns[b]
			expect(Vector2(pa.x - pb.x, pa.z - pb.z).length() >= 15.0,
				"spawns %d and %d are at least 15 m apart" % [a + 1, b + 1])


func test_cave_has_38m_clearance_and_floor_ceiling_collision() -> void:
	await _make_arena()
	var space := _arena.get_world_3d().direct_space_state
	expect(float(_arena.call("cave_ceiling_y")) - float(_arena.call("cave_floor_y")) >= 3.8,
		"cave constants give >= 3.8 m clearance")
	for x in [-20.0, 0.0, 20.0]:
		var down := PhysicsRayQueryParameters3D.create(
			Vector3(x, 3.0, -54.0), Vector3(x, -8.0, -54.0), 1)
		var up := PhysicsRayQueryParameters3D.create(
			Vector3(x, 1.0, -54.0), Vector3(x, 12.0, -54.0), 1)
		var floor_hit := space.intersect_ray(down)
		var ceiling_hit := space.intersect_ray(up)
		expect(not floor_hit.is_empty(), "cave floor collides at x=%.0f" % x)
		expect(not ceiling_hit.is_empty(), "cave ceiling collides at x=%.0f" % x)
		if not floor_hit.is_empty() and not ceiling_hit.is_empty():
			var clearance := float(ceiling_hit["position"].y) - float(floor_hit["position"].y)
			expect(clearance >= 3.8, "cave interior clearance is %.2f m at x=%.0f" % [clearance, x])
			expect(clearance < 6.0, "cave clearance stays believable (%.2f m)" % clearance)
	# Side walls close the bore on both sides.
	for zsign in [-1.0, 1.0]:
		var side := PhysicsRayQueryParameters3D.create(
			Vector3(0.0, 2.0, -54.0), Vector3(0.0, 2.0, -54.0 + zsign * 10.0), 1)
		var side_hit := space.intersect_ray(side)
		expect(not side_hit.is_empty(), "cave side wall collides (z%s)" % str(zsign))
	# Looking straight up from inside must never expose the sky.
	var sky := PhysicsRayQueryParameters3D.create(
		Vector3(4.0, 1.0, -54.0), Vector3(4.0, 60.0, -54.0), 1)
	expect(not space.intersect_ray(sky).is_empty(), "cave roof blocks the sky")


func test_every_hero_prop_has_a_collider() -> void:
	await _make_arena()
	var space := _arena.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.12
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var anchors: Array = _arena.call("hero_anchor_positions")
	expect(anchors.size() > 100, "arena has a meaningful amount of hand-placed cover (%d anchors)" % anchors.size())
	var missing := 0
	for anchor: Vector3 in anchors:
		query.transform = Transform3D(Basis(), anchor)
		if space.intersect_shape(query, 1).is_empty():
			missing += 1
	expect(missing == 0, "all %d hero anchors have collision (%d missing)" % [anchors.size(), missing])
	var trees: Array = _arena.call("tree_positions")
	expect(trees.size() >= 35, "arena has a meaningful tree cover (%d)" % trees.size())
	var trees_missing := 0
	for base: Vector3 in trees:
		query.transform = Transform3D(Basis(), base + Vector3.UP * 0.4)
		if space.intersect_shape(query, 1).is_empty():
			trees_missing += 1
	expect(trees_missing == 0, "every tree has a trunk collider (%d missing)" % trees_missing)


func test_terrace_routes_are_walkable() -> void:
	await _make_arena()
	var routes := [
		[-64.0, 0.0, 0.0, 0.0],   # west benches along z=0 (through the wall gap)
		[0.0, -20.0, 64.0, -20.0], # east benches, away from the bridge cut
		[8.0, 0.0, 8.0, 64.0],    # south terrace
	]
	for route: Array in routes:
		var from := Vector2(float(route[0]), float(route[1]))
		var to := Vector2(float(route[2]), float(route[3]))
		var distance := from.distance_to(to)
		var steps := int(distance / 0.5)
		var worst := 0.0
		var previous := SCRIPT.height_at(from.x, from.y)
		for i in range(1, steps + 1):
			var t := float(i) / float(steps)
			var p := from.lerp(to, t)
			var h := SCRIPT.height_at(p.x, p.y)
			worst = maxf(worst, absf(h - previous))
			previous = h
		expect(worst <= 0.3, "route (%.0f,%.0f)->(%.0f,%.0f) max step %.3f m <= 0.3 m" % [
			from.x, from.y, to.x, to.y, worst])


func test_boundary_blocks_escape() -> void:
	await _make_arena()
	var space := _arena.get_world_3d().direct_space_state
	var rays := [
		[Vector3(0.0, 12.0, 0.0), Vector3(1.0, 0.0, 0.0)],
		[Vector3(0.0, 12.0, 0.0), Vector3(-1.0, 0.0, 0.0)],
		[Vector3(40.0, 12.0, 0.0), Vector3(0.0, 0.0, 1.0)],
		[Vector3(40.0, 12.0, 0.0), Vector3(0.0, 0.0, -1.0)],
	]
	for ray: Array in rays:
		var from: Vector3 = ray[0]
		var dir: Vector3 = ray[1]
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * 200.0, 1)
		var hit := space.intersect_ray(query)
		expect(not hit.is_empty(), "escape ray %s is blocked" % str(dir))
		if hit.is_empty():
			continue
		var distance := from.distance_to(hit["position"])
		expect(distance <= 70.2, "boundary stops the ray at %.1f m (<= 70.2)" % distance)
		expect(distance > 60.0, "boundary is at the map edge, not the play centre (%.1f m)" % distance)


func test_camera_stays_inside_the_boundary() -> void:
	await _make_arena()
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	_arena.add_child(player)
	var rig := player.get_node("CameraPivot") as CameraRig
	var ground := SCRIPT.height_at(66.5, 0.0)
	player.global_position = Vector3(66.5, ground + 0.5, 0.0)
	player.rotation.y = PI * 0.5
	player.set_view_yaw(PI * 0.5)
	player.set_physics_process(false)
	for _i in 16:
		await get_tree().process_frame
	var cam := rig.camera
	expect(rig.spring_arm.get_hit_length() > 0.0, "spring arm finds the boundary/mountain")
	expect(cam.global_position.x < 69.6, "camera stays inside the 150 m footprint (x %.2f)" % cam.global_position.x)


func test_main_scene_uses_the_quarry() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var arena := main.get_node_or_null("Arena") as Node3D
	expect(arena != null, "main scene instances an Arena")
	if arena:
		expect(String(arena.get_script().resource_path).ends_with("quarry_arena.gd"),
			"main Arena uses the Sunken Quarry arena")
		expect(arena.get_node_or_null("Spawn08") != null, "main Arena has Spawn08")
	main.free()
