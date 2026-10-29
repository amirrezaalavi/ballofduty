extends BodTestSuite
## Phase 1 C projectile visuals: the 64-node pool is fixed. Firing 500 rounds
## (and 500 pooled impacts) must not grow the scene tree or rebuild materials.

var _world: Node3D
var _field: BulletField


func after_test() -> void:
	if is_instance_valid(_world):
		_world.free()


func _setup() -> void:
	_world = Node3D.new()
	add_child(_world)
	_field = BulletField.new()
	_field.name = "TestBulletField"
	_world.add_child(_field)
	await get_tree().process_frame


func test_pool_is_built_once_at_fixed_size() -> void:
	await _setup()
	expect(_field.get_child_count() == BulletField.POOL_SIZE + BulletField.IMPACT_POOL,
		"pool has %d bullet + %d impact nodes (got %d)" % [
			BulletField.POOL_SIZE, BulletField.IMPACT_POOL, _field.get_child_count()])
	expect(_field.pool_builds == 1, "meshes/materials build once (builds=%d)" % _field.pool_builds)
	expect(_field._body_materials.size() == 2, "two body materials (local/remote)")
	expect(_field._trail_materials.size() == 2, "two trail materials")
	expect(_field._rim_materials.size() == 2, "two rim materials")
	expect(_field._impacts.size() == BulletField.IMPACT_POOL, "impact pool is fixed")
	expect(_field._body_mesh.size.is_equal_approx(BulletField.CORE_SIZE),
		"core is 0.018 x 0.36 m")
	expect(_field._trail_mesh.size.is_equal_approx(BulletField.TRAIL_SIZE),
		"trail is 0.006 x 2.2 m")
	expect(_field._rim_mesh.size.is_equal_approx(BulletField.RIM_SIZE),
		"rim is 0.026 x 2.4 m")


func test_500_rounds_do_not_grow_the_tree() -> void:
	await _setup()
	var bullets_before := _field.get_child_count()
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var none: Array[RID] = []
	for i in 500:
		var direction := Vector3(sin(float(i)), 0.1, -cos(float(i))).normalized()
		_field._launch(Vector3(0.0, 1.0, 0.0), direction, 81.0, i % 2 == 0, none)
		if i % 10 == 9:
			await get_tree().physics_frame
	await get_tree().physics_frame

	expect(_field.launches == 500, "500 launches recorded (got %d)" % _field.launches)
	expect(_field.get_child_count() == bullets_before,
		"child count stays fixed after 500 rounds (%d vs %d)" % [
			_field.get_child_count(), bullets_before])
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	expect(abs(nodes_after - nodes_before) <= 8,
		"global node count stays flat (before %d after %d)" % [nodes_before, nodes_after])
	expect(_field.pool_builds == 1, "500 rounds rebuild no material (builds=%d)" % _field.pool_builds)
	expect(_field.peak_active <= BulletField.POOL_SIZE, "active peak is bounded by the pool")

	# Every live bullet points at one of the shared, pre-built materials.
	var body_materials: Dictionary = {}
	var trail_materials: Dictionary = {}
	for bullet: BulletVisual in _field._bullets:
		var body_material: Material = bullet._body.material_override
		var trail_material: Material = bullet._trail.material_override
		expect(body_material != null and trail_material != null, "pooled bullet keeps its material")
		if body_material:
			body_materials[body_material.get_instance_id()] = true
		if trail_material:
			trail_materials[trail_material.get_instance_id()] = true
	expect(body_materials.size() <= 2, "bullets share at most 2 body materials (got %d)" % body_materials.size())
	expect(trail_materials.size() <= 2, "bullets share at most 2 trail materials (got %d)" % trail_materials.size())


func test_impact_pool_is_bounded() -> void:
	await _setup()
	var before := _field.get_child_count()
	for i in 500:
		_field.spawn_impact(Vector3(float(i % 10), 0.5, 0.0), Vector3.UP)
	expect(_field.impacts_shown == 500, "500 impacts counted")
	expect(_field.get_child_count() == before, "impact pool never grows the tree")
	var visible := 0
	for impact: MeshInstance3D in _field._impacts:
		if impact.visible:
			visible += 1
	expect(visible <= BulletField.IMPACT_POOL, "visible impacts stay inside the pool")


func test_streak_grows_from_the_muzzle() -> void:
	await _setup()
	var none: Array[RID] = []
	_field._launch(Vector3(0.0, 1.0, 0.0), Vector3.FORWARD, 81.0, true, none)
	var bullet: BulletVisual = null
	for candidate: BulletVisual in _field._bullets:
		if candidate.visible:
			bullet = candidate
			break
	expect(bullet != null, "one pooled bullet is live")
	if bullet == null:
		return
	expect(not bullet._trail.visible and not bullet._rim.visible,
		"no streak behind the muzzle at spawn (distance 0)")
	expect(is_equal_approx(bullet.distance, 0.0), "spawn distance starts at zero")

	# One metre travelled: the streak is exactly one metre long, not 2.2 m.
	bullet.distance = 1.0
	bullet._update_streak()
	var trail_1m := _streak_length(bullet._trail)
	expect(absf(trail_1m - 1.0) < 0.02,
		"trail length tracks distance (%.2f m at 1 m)" % trail_1m)
	expect(_streak_length(bullet._rim) <= 1.02, "rim never exceeds travelled distance")

	# Past the full length the streak caps instead of growing.
	bullet.distance = 10.0
	bullet._update_streak()
	var trail_full := _streak_length(bullet._trail)
	var rim_full := _streak_length(bullet._rim)
	expect(absf(trail_full - 2.2) < 0.02, "trail caps at 2.2 m (%.2f m)" % trail_full)
	expect(absf(rim_full - 2.4) < 0.02, "rim caps at 2.4 m (%.2f m)" % rim_full)
	expect(trail_full <= bullet.distance + 0.001, "streak never exceeds travelled distance")
	bullet._stop()


func _streak_length(bar: MeshInstance3D) -> float:
	if bar == null or not bar.visible:
		return 0.0
	var box := bar.mesh as BoxMesh
	return absf(box.size.z) * bar.scale.z
