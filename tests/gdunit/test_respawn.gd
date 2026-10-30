extends BodTestSuite
## Step 5 respawn picker: rank spawns by distance to the nearest living enemy,
## then raycast only the top two candidates. The old path cast a ray for every
## spawn x roster pair (8 x 4 = 32 here); the new path is capped at 2 x 4.

const SPAWN_COUNT := 8
const SPAWN_RADIUS := 18.0
const ACTOR_COUNT := 4

var _world: Node3D
var _gm: Node
var _actors: Array = []
var _entries: Array = []
var _spawns: Array = []


func after_test() -> void:
	if is_instance_valid(_gm):
		_gm.stop_all()
	if is_instance_valid(_world):
		_world.free()
	_world = null
	_gm = null
	_actors.clear()
	_entries.clear()
	_spawns.clear()


func _build_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.55, 0.0)
	_world.add_child(floor_body)

	_gm = load("res://scripts/game/game_manager.gd").new()
	add_child(_gm)
	_gm._world = _world

	# Eight spawns on a 36 m circle: the pair is spread over ~40 m of arc.
	for i in SPAWN_COUNT:
		var angle := TAU * float(i) / float(SPAWN_COUNT)
		_spawns.append(Vector3(cos(angle) * SPAWN_RADIUS, 0.0, sin(angle) * SPAWN_RADIUS))
	_gm._spawns = _spawns

	# Four living actors clustered near the centre, so every candidate has an
	# actor inside the 25 m ray range and the ray pass actually runs.
	var scene := load("res://scenes/characters/player.tscn") as PackedScene
	for i in ACTOR_COUNT:
		var actor := scene.instantiate() as PlayerController
		_world.add_child(actor)
		actor.make_server(i + 1)
		actor.global_position = Vector3(float(i) - 1.5, 0.2, float(i % 2))
		_actors.append(actor)
	await get_tree().physics_frame

	for i in ACTOR_COUNT:
		var entry: Dictionary = _gm._new_entry(
			i + 1, "TARGET %d" % (i + 1), _actors[i], -1001 - i
		)
		_entries.append(entry)
		_gm._roster[-1001 - i] = entry
		_gm._by_id[i + 1] = entry


func _is_configured_spawn(pos: Vector3) -> bool:
	for spawn_point: Vector3 in _spawns:
		if pos.is_equal_approx(spawn_point + Vector3(0.0, 0.2, 0.0)):
			return true
	return false


func test_respawn_raycasts_top_two_only() -> void:
	await _build_world()
	var respawning: Dictionary = _entries[0]

	var before := int(_gm.spawn_raycasts)
	var picked: Dictionary = _gm._choose_respawn(respawning)
	var rays := int(_gm.spawn_raycasts) - before
	print("  respawn raycasts: %d (top-2 x %d living others)" % [rays, ACTOR_COUNT - 1])
	expect(_is_configured_spawn(picked["pos"]), "respawn returns a configured spawn point")
	expect(rays > 0, "ray pass runs when actors are within 25 m of the candidates")
	expect(rays <= 2 * ACTOR_COUNT,
		"top-2 x %d actors bounds the rays, not the old %d x %d (%d rays)" % [
			ACTOR_COUNT, SPAWN_COUNT, ACTOR_COUNT, rays,
		])

	# Clustered deaths: park the respawned actor on the chosen spawn each time.
	var worst := 0
	for i in 10:
		var start := int(_gm.spawn_raycasts)
		var result: Dictionary = _gm._choose_respawn(respawning)
		var call_rays := int(_gm.spawn_raycasts) - start
		worst = maxi(worst, call_rays)
		expect(_is_configured_spawn(result["pos"]),
			"clustered respawn %d returns a configured spawn" % i)
		expect(call_rays > 0 and call_rays <= 2 * ACTOR_COUNT,
			"clustered respawn %d stays inside the top-2 bound (%d rays)" % [i, call_rays])
		_actors[0].global_position = result["pos"]
		await get_tree().physics_frame
	print("  clustered respawn worst case: %d rays per call" % worst)
	expect(worst <= 2 * ACTOR_COUNT,
		"worst clustered call stays inside the top-2 bound (%d rays)" % worst)
