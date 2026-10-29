extends Node3D
## Nature arena dressing and collision.
##
## Deterministic (fixed seed) so the headless server and every web client build
## the same map. Gameplay props are hand-placed; foliage is scattered with
## rejection sampling. Rendering uses MultiMesh per prop type to keep draw calls
## low, while large props get simple analytic collision shapes.

const SEED := 20261028
const PLAY_RADIUS := 30.0
const SPAWN_CLEARANCE := 4.0
const CENTER_CLEARANCE := 5.0

const MODEL_DIR := "res://assets/kenney_nature/models/"
const PALETTE := {
	"grass": Color(0.301961, 0.619608, 0.25098),
	"leafsGreen": Color(0.239216, 0.552941, 0.239216),
	"leafsDark": Color(0.160784, 0.4, 0.2),
	"woodBark": Color(0.360784, 0.243137, 0.152941),
	"woodBarkDark": Color(0.270588, 0.176471, 0.117647),
	"woodInner": Color(0.607843, 0.454902, 0.278431),
	"dirt": Color(0.443137, 0.329412, 0.211765),
	"stone": Color(0.556863, 0.572549, 0.545098),
	"colorRed": Color(0.85, 0.25, 0.25),
	"colorYellow": Color(0.95, 0.78, 0.25),
	"_defaultMat": Color(0.9, 0.9, 0.86),
}
const MODELS := {
	"tree_default": "tree_default",
	"tree_detailed": "tree_detailed",
	"tree_fat": "tree_fat",
	"tree_pine": "tree_pineTallA",
	"tree_pine_round": "tree_pineRoundA",
	"tree_small": "tree_small",
	"rock_large": "rock_largeA",
	"rock_wide": "rock_largeC",
	"rock_tall": "rock_tallA",
	"rock_small": "rock_smallA",
	"cliff": "cliff_block_stone",
	"cliff_rock": "cliff_block_rock",
	"bush": "plant_bush",
	"bush_large": "plant_bushLarge",
	"grass": "grass_large",
	"flower_red": "flower_redA",
	"flower_yellow": "flower_yellowA",
	"mushroom": "mushroom_red",
	"log": "log",
	"stump": "stump_round",
}

# Hand-placed gameplay cover. Positions are (x, z, scale); the script adds the
# ground offset and a trunk/rock collider.
const HERO_TREES := [
	Vector3(-18.0, -12.0, 2.6), Vector3(-15.5, -13.8, 2.2),
	Vector3(14.0, -17.0, 2.8), Vector3(16.8, -14.5, 2.3),
	Vector3(-14.0, 14.0, 2.7), Vector3(-11.5, 16.5, 2.2),
	Vector3(18.0, 11.0, 2.5), Vector3(20.5, 8.0, 2.2),
	Vector3(-22.0, -3.0, 2.4), Vector3(6.0, 19.0, 2.6),
	Vector3(-4.0, -18.0, 2.4), Vector3(8.0, 12.0, 2.2),
	Vector3(-20.0, 8.0, 2.3), Vector3(22.0, -10.0, 2.4),
	Vector3(-8.0, 20.0, 2.0), Vector3(10.0, -20.0, 2.2),
	Vector3(20.0, 18.0, 2.6), Vector3(-20.0, -18.0, 2.5),
	Vector3(0.0, -16.0, 2.6),
]
const HERO_ROCKS := [
	Vector3(-6.0, 6.0, 2.5), Vector3(7.0, 5.0, 2.2),
	Vector3(6.0, -7.0, 2.8), Vector3(-7.0, -6.0, 2.0),
	Vector3(18.0, -2.0, 2.4), Vector3(-18.0, 2.0, 2.6),
	Vector3(0.0, -11.0, 1.8), Vector3(-3.0, 3.0, 1.5),
	Vector3(4.0, 12.0, 1.8), Vector3(-10.0, 10.0, 2.0),
	Vector3(14.0, 4.0, 1.6), Vector3(-4.0, -16.0, 2.2),
	Vector3(16.0, -22.0, 1.8), Vector3(-16.0, -20.0, 2.0),
	Vector3(0.0, 8.0, 2.4), Vector3(9.0, -1.0, 2.6),
	Vector3(-9.0, 1.0, 2.2),
]

var _rng := RandomNumberGenerator.new()
var _scene_cache: Dictionary = {}
var _placements: Dictionary = {}
var _colliders: Array[Dictionary] = []
var _spawns: Array[Vector3] = []
var _props_root: Node3D


func _ready() -> void:
	_props_root = get_node_or_null("Props") as Node3D
	if _props_root == null:
		_props_root = Node3D.new()
		_props_root.name = "Props"
		add_child(_props_root)

	for child in get_children():
		if child is Marker3D and child.name.begins_with("Spawn"):
			_spawns.append(child.position)

	_rng.seed = SEED
	_place_hero_props()
	_place_border()
	_scatter_foliage()
	_build_multimeshes()
	_build_colliders()


func _place_hero_props() -> void:
	for spot: Vector3 in HERO_TREES:
		var scale_value := spot.z
		if not _is_clear(Vector3(spot.x, 0.0, spot.y), 2.0):
			continue
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value)
		_add_instance("tree_default" if _rng.randf() < 0.5 else "tree_detailed",
			Transform3D(basis, Vector3(spot.x, 0.03, spot.y)))
		_colliders.append({
			"shape": "cylinder", "pos": Vector3(spot.x, 0.0, spot.y),
			"radius": 0.12 * scale_value, "height": 1.3 * scale_value,
		})

	for spot: Vector3 in HERO_ROCKS:
		var scale_value := spot.z
		if not _is_clear(Vector3(spot.x, 0.0, spot.y), 1.0):
			continue
		var key := "rock_tall" if scale_value >= 2.6 else "rock_large"
		var basis := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value)
		_add_instance(key, Transform3D(basis, Vector3(spot.x, 0.03, spot.y)))
		if key == "rock_tall":
			_colliders.append({
				"shape": "cylinder", "pos": Vector3(spot.x, 0.0, spot.y),
				"radius": 0.45 * scale_value, "height": 0.95 * scale_value,
			})
		else:
			_colliders.append({
				"shape": "cylinder", "pos": Vector3(spot.x, 0.0, spot.y),
				"radius": 0.46 * scale_value, "height": 0.3 * scale_value,
			})

	# A couple of fallen logs and stumps as low cover landmarks.
	_add_instance("log", Transform3D(
		Basis(Vector3.UP, 0.6).scaled(Vector3.ONE * 2.4), Vector3(-12.0, 0.12, -3.0)))
	_colliders.append({
		"shape": "box", "pos": Vector3(-12.0, 0.22, -3.0),
		"size": Vector3(0.7, 0.4, 1.9), "yaw": 0.6,
	})

	_add_instance("stump", Transform3D(
		Basis(Vector3.UP, 1.2).scaled(Vector3.ONE * 2.5), Vector3(11.0, 0.03, 14.0)))
	_colliders.append({
		"shape": "cylinder", "pos": Vector3(11.0, 0.0, 14.0),
		"radius": 0.4, "height": 0.45,
	})


func _place_border() -> void:
	# Decorative trees outside the playable walls.
	for i in 28:
		var angle := TAU * float(i) / 28.0 + _rng.randf_range(-0.06, 0.06)
		var radius := _rng.randf_range(33.0, 36.5)
		var key: String = ["tree_pine", "tree_default", "tree_fat", "tree_pine_round"][i % 4]
		var scale_value := _rng.randf_range(3.0, 4.6)
		var pos := Vector3(cos(angle) * radius, 0.03, sin(angle) * radius)
		_add_instance(key, Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value), pos))
		# Diagonal border trees fall inside the square cliff boundary; without a
		# collider the player can walk straight through them.
		_colliders.append({
			"shape": "cylinder", "pos": pos,
			"radius": 0.12 * scale_value, "height": 1.3 * scale_value,
		})

	# Inner tree line hides the rock wall and gives the arena depth.
	for i in 20:
		var angle := TAU * float(i) / 20.0 + _rng.randf_range(-0.12, 0.12)
		var radius := _rng.randf_range(26.0, 28.5)
		var pos := Vector3(cos(angle) * radius, 0.03, sin(angle) * radius)
		if not _spawn_clear(pos, 5.0):
			continue
		var key: String = ["tree_pine", "tree_default", "tree_fat", "tree_pine_round"][i % 4]
		var scale_value := _rng.randf_range(2.0, 3.0)
		_add_instance(key, Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value), pos))
		_colliders.append({
			"shape": "cylinder", "pos": pos,
			"radius": 0.12 * scale_value, "height": 1.3 * scale_value,
		})

	# Rock wall just outside the invisible boundary.
	for side in 4:
		for step in 16:
			var along := -30.0 + float(step) * 4.0 + 2.0
			var pos := Vector3.ZERO
			var yaw := 0.0
			match side:
				0:
					pos = Vector3(along, 0.03, -31.2)
				1:
					pos = Vector3(along, 0.03, 31.2)
					yaw = PI
				2:
					pos = Vector3(-31.2, 0.03, along)
					yaw = PI * 0.5
				3:
					pos = Vector3(31.2, 0.03, along)
					yaw = PI * 0.5
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3(4.0, 3.0, 4.0))
			_add_instance("cliff", Transform3D(basis, pos))
			_colliders.append({
				"shape": "box", "pos": Vector3(pos.x, 1.5, pos.z),
				"size": Vector3(4.1, 3.0, 4.1),
			})


func _scatter_foliage() -> void:
	var foliage := ["bush", "bush_large", "grass", "flower_red", "flower_yellow", "mushroom"]
	var counts := {"bush": 18, "bush_large": 12, "grass": 80, "flower_red": 18, "flower_yellow": 18, "mushroom": 14}
	for key: String in foliage:
		for _i in int(counts[key]):
			var pos := _random_ground_point(6.0, 28.0)
			if pos == Vector3.INF:
				continue
			var scale_value := _rng.randf_range(1.4, 2.4)
			_add_instance(key, Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value), pos))


func _random_ground_point(min_radius: float, max_radius: float) -> Vector3:
	for _attempt in 24:
		var angle := _rng.randf_range(0.0, TAU)
		var radius := _rng.randf_range(min_radius, max_radius)
		var pos := Vector3(cos(angle) * radius, 0.02, sin(angle) * radius)
		if not _is_clear(pos, 1.2):
			continue
		if _in_platform_zone(pos):
			continue
		return pos
	return Vector3.INF


func _spawn_clear(pos: Vector3, clearance: float) -> bool:
	for spawn: Vector3 in _spawns:
		if Vector2(pos.x - spawn.x, pos.z - spawn.z).length() < clearance:
			return false
	return true


func _is_clear(pos: Vector3, clearance: float) -> bool:
	if Vector2(pos.x, pos.z).length() < CENTER_CLEARANCE:
		return false
	for spawn: Vector3 in _spawns:
		if Vector2(pos.x - spawn.x, pos.z - spawn.z).length() < SPAWN_CLEARANCE + clearance:
			return false
	for key: String in _placements:
		var list: Array = _placements[key]
		for xform: Transform3D in list:
			if Vector2(xform.origin.x - pos.x, xform.origin.z - pos.z).length() < clearance + 1.0:
				return false
	return true


func _in_platform_zone(pos: Vector3) -> bool:
	return pos.x > 8.0 and pos.x < 16.0 and pos.z > -16.0 and pos.z < -2.0


## Test/debug hook: every tree transform generated by the arena. The MultiMesh
## GPU buffer is not readable under the headless dummy renderer, so geometry
## regressions assert against the source placements instead.
func tree_positions() -> Array:
	var out: Array = []
	for key: String in _placements:
		if key.begins_with("tree"):
			for xform in _placements[key]:
				out.append(xform.origin)
	return out


func _add_instance(key: String, xform: Transform3D) -> void:
	if not _placements.has(key):
		var list: Array[Transform3D] = []
		_placements[key] = list
	_placements[key].append(xform)


func _build_multimeshes() -> void:
	for key: String in _placements:
		var xforms: Array = _placements[key]
		var packed := _load_model(key)
		if packed == null:
			continue
		var probe := packed.instantiate()
		var mesh_instance := _first_mesh(probe)
		if mesh_instance == null or mesh_instance.mesh == null:
			probe.free()
			push_warning("No mesh in " + key)
			continue

		_restyle_mesh(mesh_instance.mesh)

		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh_instance.mesh
		multimesh.instance_count = xforms.size()
		var base_transform := mesh_instance.transform
		for index in xforms.size():
			multimesh.set_instance_transform(index, xforms[index] * base_transform)

		var instance := MultiMeshInstance3D.new()
		instance.name = "MM_" + key
		instance.multimesh = multimesh
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if key.begins_with("tree") or key.begins_with("rock") or key.begins_with("log") or key == "stump"
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		_props_root.add_child(instance)
		probe.free()


func _build_colliders() -> void:
	var index := 0
	for collider: Dictionary in _colliders:
		var body := StaticBody3D.new()
		# Unique names keep debugging and tests honest; duplicate names become
		# internal @StaticBody3D@N identifiers.
		body.name = "PropCollider_%d" % index
		index += 1
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = collider["pos"]
		body.rotation.y = float(collider.get("yaw", 0.0))

		var shape_node := CollisionShape3D.new()
		if collider["shape"] == "box":
			var box := BoxShape3D.new()
			box.size = collider["size"]
			shape_node.shape = box
		else:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = collider["radius"]
			cylinder.height = collider["height"]
			shape_node.shape = cylinder
			shape_node.position.y = float(collider["height"]) * 0.5

		body.add_child(shape_node)
		_props_root.add_child(body)


func _restyle_mesh(mesh: Mesh) -> void:
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material == null:
			continue
		var key := String(material.resource_name)
		if not PALETTE.has(key):
			continue
		var restyled := StandardMaterial3D.new()
		restyled.resource_name = key
		restyled.albedo_color = PALETTE[key]
		restyled.metallic = 0.0
		restyled.roughness = 1.0
		restyled.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mesh.surface_set_material(surface, restyled)


func _load_model(key: String) -> PackedScene:
	if _scene_cache.has(key):
		return _scene_cache[key]
	var path := MODEL_DIR + String(MODELS[key]) + ".glb"
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Missing model: " + path)
		return null
	_scene_cache[key] = packed
	return packed


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh(child)
		if found:
			return found
	return null
