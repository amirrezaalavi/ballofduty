extends Node3D
## Sunken Quarry & Cavern Pass — 150 x 150 m Phase 2B arena.
##
## The height field below is the single source of truth for both the low-poly
## visual chunks and the HeightMapShape3D collision, so the headless server and
## every browser client produce the same ground. Everything is deterministic:
## scatter uses a fixed seed, hand-placed cover is static data, and the cave is
## built from the same constants on every peer.
##
## Layout (x east, z south):
##   centre      low quarry bowl with a ruined crane plinth
##   west        three walkable quarry benches (0 / 3 / 6 m) with ramps
##   east        two benches (0 / 2.5 / 5 m), a dry cut and a wooden bridge
##   south       a low terrace with ruined walls and an arch
##   north       a 61 m double-walled cave bypass through a rock ridge
##   edge        a rising mountain ring plus invisible boundary/camera walls

const SEED := 20261101
const MAP_HALF := 75.0
const PLAY_HALF := 69.5
const CHUNK_SIZE := 50.0
const CHUNK_GRID := 3
const CHUNK_SAMPLES := 51
const VISUAL_STEP := 2
const VISUAL_SAMPLES := 26
const BOUNDARY_HEIGHT := 40.0

# Cave constants are public for tests and for the arena budget report.
const CAVE_Z := -54.0
const CAVE_HALF_LEN := 30.0
const CAVE_HALF_WIDTH := 2.8
const CAVE_HEIGHT := 4.6
const CAVE_LINING := 0.6

const MODEL_DIR := "res://assets/kenney_nature/models/"
const PALETTE := {
	"grass": Color(0.301961, 0.619608, 0.25098),
	"leafsGreen": Color(0.239216, 0.552941, 0.239216),
	"leafsDark": Color(0.160784, 0.4, 0.2),
	"woodBark": Color(0.360784, 0.243137, 0.152941),
	"woodBarkDark": Color(0.270588, 0.176471, 0.117647),
	"woodInner": Color(0.607843, 0.454902, 0.278431),
	"dirt": Color(0.360000, 0.280000, 0.190000),
	"stone": Color(0.400000, 0.400000, 0.380000),
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
	"cliff_wall": "cliff_block_stone",
	"ridge_rock": "cliff_block_rock",
	"bush": "plant_bush",
	"bush_large": "plant_bushLarge",
	"grass": "grass_large",
	"flower_red": "flower_redA",
	"flower_yellow": "flower_yellowA",
	"mushroom": "mushroom_red",
	"log": "log",
	"stump": "stump_round",
}

# Spawns are placed around the play space and then snapped to the height field.
# Scene values are close approximations; _ready() writes the exact ground height.
const SPAWN_LAYOUT := [
	Vector3(-40.0, 3.0, 0.0),    # west middle bench
	Vector3(-62.0, 6.0, 34.0),   # west high bench
	Vector3(-18.0, 0.0, 0.0),    # west quarry floor
	Vector3(0.0, 0.0, -30.0),    # south of the cave ridge
	Vector3(24.0, 0.0, -34.0),   # north-east floor
	Vector3(44.0, 2.5, 10.0),    # east bench, by the bridge
	Vector3(60.0, 5.0, 40.0),    # east high bench
	Vector3(0.0, 2.0, 54.0),     # south terrace
]

# Sixteen deterministic rock outcrops on the upper ring. They are height-field
# bumps (not props), so they are part of the terrain collision and cannot float.
const RING_BUMPS := [
	Vector4(70.5, -45.0, 4.2, 5.5), Vector4(71.5, -15.0, 3.4, 4.5),
	Vector4(70.8, 15.0, 4.8, 5.0), Vector4(71.8, 45.0, 3.8, 5.2),
	Vector4(-70.5, -40.0, 4.0, 5.0), Vector4(-71.5, -10.0, 4.6, 5.4),
	Vector4(-70.8, 20.0, 3.5, 4.6), Vector4(-71.8, 50.0, 4.4, 5.2),
	Vector4(-45.0, 70.5, 4.6, 5.4), Vector4(-15.0, 71.5, 3.6, 4.6),
	Vector4(15.0, 70.8, 4.2, 5.0), Vector4(45.0, 71.8, 4.8, 5.4),
	Vector4(-40.0, -70.5, 4.4, 5.2), Vector4(-10.0, -71.5, 3.8, 4.8),
	Vector4(20.0, -70.8, 4.7, 5.2), Vector4(50.0, -71.8, 3.9, 4.8),
]

# Central hero cover clusters: (x, z, yaw). Kept clear of spawns, ramps, cave
# approaches and the bridge lane.
const CENTRAL_COVER := [
	Vector3(10.0, 6.0, 0.4), Vector3(-10.0, -10.0, 1.2),
	Vector3(18.0, 18.0, 2.0), Vector3(-16.0, 22.0, 0.8),
	Vector3(28.0, -6.0, 2.6), Vector3(-26.0, -22.0, 1.6),
	Vector3(-2.0, 30.0, 2.4), Vector3(34.0, 6.0, 0.2),
]

# Hand-placed cover. Only (x, z) drive the layout; y comes from the height field.
const HERO_TREES := [
	Vector3(-36.0, -30.0, 3.2), Vector3(-40.0, 18.0, 3.6),
	Vector3(-58.0, -20.0, 4.2), Vector3(-62.0, 12.0, 4.0),
	Vector3(36.0, 24.0, 3.4), Vector3(46.0, -30.0, 3.2),
	Vector3(58.0, 26.0, 4.2), Vector3(60.0, -6.0, 3.8),
	Vector3(-12.0, 42.0, 2.8), Vector3(14.0, 46.0, 3.0),
	Vector3(20.0, -40.0, 3.0), Vector3(-22.0, -34.0, 2.8),
	Vector3(34.0, 50.0, 3.0), Vector3(-30.0, 44.0, 2.8),
]
const HERO_ROCKS := [
	Vector3(-30.0, -16.0, 3.2), Vector3(-12.0, 22.0, 2.8),
	Vector3(14.0, -24.0, 3.0), Vector3(24.0, 26.0, 2.6),
	Vector3(44.0, -24.0, 3.4), Vector3(-50.0, 10.0, 3.0),
	Vector3(-60.0, -8.0, 3.6), Vector3(58.0, 8.0, 3.2),
	Vector3(-34.0, 36.0, 2.8), Vector3(20.0, 52.0, 3.0),
	Vector3(-18.0, -36.0, 3.4), Vector3(34.0, 34.0, 2.6),
	Vector3(56.0, 45.0, 2.6), Vector3(-4.0, 57.0, 2.6),
]

var _rng := RandomNumberGenerator.new()
var _scene_cache: Dictionary = {}
var _synthetic_meshes: Dictionary = {}
var _placements: Dictionary = {}
var _colliders: Array[Dictionary] = []
var _hero_anchors: Array[Vector3] = []
var _spawns: Array[Vector3] = []
var _tree_positions: Array[Vector3] = []
var _props_root: Node3D
var _terrain_root: Node3D
var _cave_root: Node3D
var _boundary_root: Node3D
var _mat_terrain: StandardMaterial3D
var _mat_stone: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_cave: StandardMaterial3D
var _environment: Environment
var _base_ambient := 0.5
var _ambient_target := 0.5
var _cave_active := false


func _ready() -> void:
	_props_root = _node_or_new("Props")
	_terrain_root = _node_or_new("Terrain")
	_cave_root = _node_or_new("Cave")
	_boundary_root = _node_or_new("Boundary")

	_snap_spawn_markers()
	for child in get_children():
		if child is Marker3D and child.name.begins_with("Spawn"):
			_spawns.append((child as Marker3D).position)
	if _spawns.is_empty():
		for spot: Vector3 in SPAWN_LAYOUT:
			_spawns.append(spot)

	_rng.seed = SEED
	_build_materials()
	_build_terrain()
	_build_boundary()
	_build_cave()
	_dress_cave_ridge()
	_place_hero_props()
	_scatter_dressing()
	_build_multimeshes()
	_build_colliders()
	_connect_cave_atmosphere()
	set_process(false)


# --- height field ---------------------------------------------------------

## Height in metres at world (x, z). The visual chunk vertices and the
## HeightMapShape3D collision are both sampled from this function.
static func height_at(x: float, z: float) -> float:
	var radius := sqrt(x * x + z * z)
	# A shallow central bowl keeps the quarry floor read as "sunken" without
	# creating a hole players must climb out of.
	var h := -0.55 * (1.0 - smoothstep(16.0, 30.0, radius))
	h += 0.04 * sin(x * 0.23) * cos(z * 0.19) + 0.02 * sin((x + z) * 0.41)

	# West quarry benches: 0 -> 3 -> 6 m. The first ramp starts slightly below
	# the bowl floor and blends through max(), so there is no lip at the toe.
	if x < -24.0:
		var hw := -0.6 + 3.6 * clampf((-x - 24.0) / 10.0, 0.0, 1.0)
		if x < -34.0:
			hw = 3.0 + 3.0 * clampf((-x - 46.0) / 14.0, 0.0, 1.0)
		h = maxf(h, hw)

	# East benches: 0 -> 2.5 -> 5 m.
	if x > 26.0:
		var he := -0.5 + 3.0 * clampf((x - 26.0) / 14.0, 0.0, 1.0)
		if x > 40.0:
			he = 2.5 + 2.5 * clampf((x - 50.0) / 10.0, 0.0, 1.0)
		h = maxf(h, he)

	# South terrace: 2 m shelf, then a 4 m shoulder before the mountain ring.
	if z > 40.0:
		var hs := -0.5 + 2.5 * clampf((z - 40.0) / 12.0, 0.0, 1.0)
		if z > 52.0:
			hs = 2.0 + 2.0 * clampf((z - 58.0) / 8.0, 0.0, 1.0)
		h = maxf(h, hs)

	# Dry quarry cut under the east bridge. Smooth-sided, so the bridge is the
	# clean route and the cut is a deliberate fall hazard.
	if x > 40.0 and z > -12.0 and z < 28.0:
		var along := smoothstep(-12.0, -6.0, z) * (1.0 - smoothstep(22.0, 28.0, z))
		var cut := 1.0 - smoothstep(0.0, 4.0, absf(x - 50.0))
		h -= 4.5 * cut * along

	# Flatten the two cave approaches into the terrace. Without this the west
	# mouth sits two metres above the tunnel floor and the east mouth has a
	# half-metre lip; both become real entry steps.
	var apron := _cave_apron(x, z)
	if apron > 0.0:
		h = lerpf(h, 0.0, apron)
	if absf(z - CAVE_Z) < CAVE_HALF_WIDTH + 0.6 and absf(x) < CAVE_HALF_LEN + 1.0:
		h = 0.0

	# Mountain ring as three open-pit benches. Flat shelves at 8 / 18 m are
	# separated by steep faces, so the edge reads as a quarried mountain rather
	# than a smooth dune. The invisible boundary sits on the first shelf.
	var edge := maxf(absf(x), absf(z))
	var ring := _ring_height(edge)
	if ring > 0.001:
		ring += ring * 0.012 * (sin(x * 0.17) + cos(z * 0.21))
		if edge > 70.0:
			# Break the outer crest silhouette; this is outside the playable
			# boundary, so it does not affect movement routes.
			ring += 1.4 * sin(x * 0.11 + z * 0.07) + 0.9 * cos(x * 0.17 - z * 0.09)
		if edge > 69.0:
			ring += _ring_bumps(x, z)
		h = maxf(h, ring)
	return h


static func _ring_bumps(x: float, z: float) -> float:
	var total := 0.0
	for bump: Vector4 in RING_BUMPS:
		var distance := Vector2(x - bump.x, z - bump.y).length()
		if distance < bump.w:
			total = maxf(total, bump.z * (1.0 - smoothstep(0.0, bump.w, distance)))
	return total


static func _ring_height(edge: float) -> float:
	if edge <= 66.0:
		return 0.0
	if edge < 68.2:
		return 8.0 * (edge - 66.0) / 2.2
	if edge < 70.0:
		return 8.0
	if edge < 72.0:
		return 8.0 + 10.0 * (edge - 70.0) / 2.0
	if edge < 73.6:
		return 18.0
	return 18.0 + 8.0 * clampf((edge - 73.6) / 1.4, 0.0, 1.0)


static func terrain_normal(x: float, z: float) -> Vector3:
	const E := 0.8
	var dx := height_at(x + E, z) - height_at(x - E, z)
	var dz := height_at(x, z + E) - height_at(x, z - E)
	return Vector3(-dx, 2.0 * E, -dz).normalized()


static func _cave_apron(x: float, z: float) -> float:
	var zt := 1.0 - smoothstep(5.0, 9.0, absf(z - CAVE_Z))
	if zt <= 0.0:
		return 0.0
	var xt := 1.0 - smoothstep(30.0, 44.0, absf(x))
	return zt * xt


static func slope_at(x: float, z: float) -> float:
	const E := 0.5
	var dx := (height_at(x + E, z) - height_at(x - E, z)) / (2.0 * E)
	var dz := (height_at(x, z + E) - height_at(x, z - E)) / (2.0 * E)
	return Vector2(dx, dz).length()


static func terrain_color(x: float, z: float, y: float, slope: float) -> Color:
	var n := 0.5 + 0.5 * sin(x * 0.27 + z * 0.19) * cos(x * 0.11 - z * 0.23)
	var dirt := Color(0.52, 0.46, 0.37)
	var stone := Color(0.55, 0.54, 0.50)
	var grass := Color(0.38, 0.52, 0.29)
	var dry := Color(0.55, 0.51, 0.36)
	var mountain := Color(0.38, 0.39, 0.37)
	var forest := Color(0.24, 0.32, 0.19)
	var pale := Color(0.60, 0.58, 0.51)
	var color: Color
	if y > 18.0:
		color = mountain.lerp(pale, clampf((y - 18.0) / 14.0, 0.0, 1.0) * 0.45)
	elif y > 11.0:
		color = mountain.lerp(stone, n * 0.55)
	elif slope > 1.1:
		color = stone.lerp(mountain, n * 0.6)
	elif y > 3.2:
		color = forest.lerp(grass, n * 0.5).lerp(dry, n * 0.25)
	elif y > 1.0:
		color = dry.lerp(stone, n * 0.45)
	else:
		color = dirt.lerp(stone, n * 0.5)
	if y < 1.2:
		var patch := 0.5 + 0.5 * sin(x * 0.11 + 1.3) * cos(z * 0.09 - 0.7)
		color = color.lerp(stone, clampf((patch - 0.55) * 1.3, 0.0, 0.45))
	# Broad patches only; fine per-metre noise shimmers at distance.
	var fleck := 0.035 * sin(x * 0.57 + z * 0.41) * sin(z * 0.73 - x * 0.29)
	var strata := 0.035 * sin(y * 1.35 + x * 0.05) if y > 8.0 else 0.0
	# Vertex colours are linear in the renderer; authored values are sRGB.
	var authored := Color(
		clampf(color.r + fleck + strata, 0.0, 1.0),
		clampf(color.g + fleck + strata, 0.0, 1.0),
		clampf(color.b + fleck * 0.8 + strata, 0.0, 1.0)
	)
	return authored.srgb_to_linear()


# --- build ----------------------------------------------------------------

func _node_or_new(path: String) -> Node3D:
	var node := get_node_or_null(path) as Node3D
	if node == null:
		node = Node3D.new()
		node.name = path
		add_child(node)
	return node


func _snap_spawn_markers() -> void:
	for child in get_children():
		if not (child is Marker3D) or not child.name.begins_with("Spawn"):
			continue
		var marker := child as Marker3D
		marker.position.y = height_at(marker.position.x, marker.position.z) + 0.15


func _build_materials() -> void:
	_mat_terrain = StandardMaterial3D.new()
	_mat_terrain.resource_name = "quarry_terrain"
	_mat_terrain.albedo_color = Color.WHITE
	_mat_terrain.vertex_color_use_as_albedo = true
	_mat_terrain.roughness = 1.0
	_mat_terrain.metallic = 0.0
	_mat_terrain.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mat_terrain.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_terrain.albedo_texture = _detail_texture()
	_mat_terrain.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_terrain.uv1_triplanar = true
	_mat_terrain.uv1_world_triplanar = true
	_mat_terrain.uv1_scale = Vector3(0.34, 0.34, 0.34)
	_mat_terrain.uv1_triplanar_sharpness = 2.0

	_mat_stone = _flat_material("quarry_stone", Color(0.64, 0.62, 0.57))
	_mat_wood = _flat_material("quarry_wood", Color(0.70, 0.53, 0.34))
	_mat_cave = _flat_material("quarry_cave", Color(0.55, 0.53, 0.49))

	_synthetic_meshes["stone_box"] = _unit_box(_mat_stone)
	_synthetic_meshes["wood_box"] = _unit_box(_mat_wood)
	_synthetic_meshes["cave_lining"] = _unit_box(_mat_cave)


func _flat_material(name: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.albedo_color = color.srgb_to_linear()
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## Seamless gravel/moss detail map. Three periodic value-noise octaves (8, 16
## and 32 lattice cells) are wrapped at the texture edge, so the 256 px texture
## tiles without seams and reads as random grain rather than a woven pattern.
func _detail_texture() -> ImageTexture:
	var size := 256
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 17
	var octave_sizes := [8, 16, 32]
	var octave_weights := [0.50, 0.30, 0.20]
	var grids: Array[PackedFloat32Array] = []
	for octave in octave_sizes:
		var n: int = octave
		var values := PackedFloat32Array()
		values.resize(n * n)
		for i in n * n:
			values[i] = rng.randf()
		grids.append(values)
	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var sum := 0.0
			for o in octave_sizes.size():
				var n: int = octave_sizes[o]
				var gx := float(x) * float(n) / float(size)
				var gy := float(y) * float(n) / float(size)
				var x0 := int(floor(gx)) % n
				var y0 := int(floor(gy)) % n
				var x1 := (x0 + 1) % n
				var y1 := (y0 + 1) % n
				var tx: float = gx - floor(gx)
				var ty: float = gy - floor(gy)
				tx = tx * tx * (3.0 - 2.0 * tx)
				ty = ty * ty * (3.0 - 2.0 * ty)
				var values := grids[o]
				var v00 := values[y0 * n + x0]
				var v10 := values[y0 * n + x1]
				var v01 := values[y1 * n + x0]
				var v11 := values[y1 * n + x1]
				var top := lerpf(v00, v10, tx)
				var bottom := lerpf(v01, v11, tx)
				sum += lerpf(top, bottom, ty) * float(octave_weights[o])
			var value := 0.80 + 0.20 * clampf(sum, 0.0, 1.0)
			image.set_pixel(x, y, Color(value, value * 0.98, value * 0.92))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _unit_box(material: Material) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = material
	return mesh


func _build_terrain() -> void:
	for cz in CHUNK_GRID:
		for cx in CHUNK_GRID:
			var index := cz * CHUNK_GRID + cx
			var origin := Vector3(
				-MAP_HALF + float(cx) * CHUNK_SIZE, 0.0, -MAP_HALF + float(cz) * CHUNK_SIZE
			)
			var body := StaticBody3D.new()
			body.name = "TerrainChunk_%d" % index
			body.collision_layer = 1
			body.collision_mask = 0
			body.position = origin

			var mesh := MeshInstance3D.new()
			mesh.name = "Mesh"
			mesh.mesh = _build_chunk_mesh(origin)
			# Terrain does not cast: at 1 m resolution a 90 m directional
			# shadow frustum produces self-shadow acne across the benches.
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(mesh)

			var shape_node := CollisionShape3D.new()
			shape_node.name = "CollisionShape3D"
			var shape := HeightMapShape3D.new()
			shape.map_width = CHUNK_SAMPLES
			shape.map_depth = CHUNK_SAMPLES
			var data := PackedFloat32Array()
			data.resize(CHUNK_SAMPLES * CHUNK_SAMPLES)
			for iz in CHUNK_SAMPLES:
				for ix in CHUNK_SAMPLES:
					data[iz * CHUNK_SAMPLES + ix] = height_at(
						origin.x + float(ix), origin.z + float(iz)
					)
			shape.map_data = data
			shape_node.shape = shape
			# HeightMapShape3D is centred on its node, while the visual mesh
			# starts at its local corner.
			shape_node.position = Vector3(CHUNK_SIZE * 0.5, 0.0, CHUNK_SIZE * 0.5)
			body.add_child(shape_node)
			_terrain_root.add_child(body)


func _build_chunk_mesh(origin: Vector3) -> ArrayMesh:
	# Non-indexed triangles give every face a flat normal. The result is a
	# deliberate low-poly quarry surface instead of smooth 1 m shading bands.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var grid_pos := PackedVector3Array()
	var grid_color := PackedColorArray()
	grid_pos.resize(VISUAL_SAMPLES * VISUAL_SAMPLES)
	grid_color.resize(VISUAL_SAMPLES * VISUAL_SAMPLES)
	for iz in VISUAL_SAMPLES:
		for ix in VISUAL_SAMPLES:
			var ox := float(ix * VISUAL_STEP)
			var oz := float(iz * VISUAL_STEP)
			var wx := origin.x + ox
			var wz := origin.z + oz
			var wy := height_at(wx, wz)
			var at := iz * VISUAL_SAMPLES + ix
			grid_pos[at] = Vector3(ox, wy, oz)
			grid_color[at] = terrain_color(wx, wz, wy, slope_at(wx, wz))

	for iz in VISUAL_SAMPLES - 1:
		for ix in VISUAL_SAMPLES - 1:
			var i00 := iz * VISUAL_SAMPLES + ix
			var i10 := i00 + 1
			var i01 := i00 + VISUAL_SAMPLES
			var i11 := i01 + 1
			for tri in [[i00, i01, i11], [i00, i11, i10]]:
				var a: Vector3 = grid_pos[tri[0]]
				var b: Vector3 = grid_pos[tri[1]]
				var c: Vector3 = grid_pos[tri[2]]
				var wa := Vector2(origin.x + a.x, origin.z + a.z) / 12.0
				var wb := Vector2(origin.x + b.x, origin.z + b.z) / 12.0
				var wc := Vector2(origin.x + c.x, origin.z + c.z) / 12.0
				var normal := (b - a).cross(c - a).normalized()
				vertices.append(a)
				vertices.append(b)
				vertices.append(c)
				normals.append(normal)
				normals.append(normal)
				normals.append(normal)
				colors.append(grid_color[tri[0]])
				colors.append(grid_color[tri[1]])
				colors.append(grid_color[tri[2]])
				uvs.append(wa)
				uvs.append(wb)
				uvs.append(wc)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _mat_terrain)
	return mesh

func _build_boundary() -> void:
	for side in 4:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape_node := CollisionShape3D.new()
		var box := BoxShape3D.new()
		match side:
			0:
				body.name = "BoundaryNorth"
				body.position = Vector3(0.0, BOUNDARY_HEIGHT * 0.5, -PLAY_HALF)
				box.size = Vector3(PLAY_HALF * 2.0, BOUNDARY_HEIGHT, 1.0)
			1:
				body.name = "BoundarySouth"
				body.position = Vector3(0.0, BOUNDARY_HEIGHT * 0.5, PLAY_HALF)
				box.size = Vector3(PLAY_HALF * 2.0, BOUNDARY_HEIGHT, 1.0)
			2:
				body.name = "BoundaryWest"
				body.position = Vector3(-PLAY_HALF, BOUNDARY_HEIGHT * 0.5, 0.0)
				box.size = Vector3(1.0, BOUNDARY_HEIGHT, PLAY_HALF * 2.0)
			3:
				body.name = "BoundaryEast"
				body.position = Vector3(PLAY_HALF, BOUNDARY_HEIGHT * 0.5, 0.0)
				box.size = Vector3(1.0, BOUNDARY_HEIGHT, PLAY_HALF * 2.0)
		shape_node.shape = box
		body.add_child(shape_node)
		_boundary_root.add_child(body)


# --- cave -----------------------------------------------------------------

func _build_cave() -> void:
	# Visual lining: a continuous inner tube, so the player never sees the
	# hollow space between the inner and outer shell.
	var segments := 9
	var length := (CAVE_HALF_LEN * 2.0 + 1.4) / float(segments)
	for i in segments:
		var cx := -CAVE_HALF_LEN - 0.7 + length * (float(i) + 0.5)
		_add_instance("cave_lining", Transform3D(
			Basis().scaled(Vector3(length + 0.18, 0.7, CAVE_HALF_WIDTH * 2.0 + 0.8)),
			Vector3(cx, CAVE_HEIGHT + 0.35, CAVE_Z)))
		for side in [-1.0, 1.0]:
			_add_instance("cave_lining", Transform3D(
				Basis().scaled(Vector3(length + 0.18, CAVE_HEIGHT, CAVE_LINING)),
				Vector3(cx, CAVE_HEIGHT * 0.5, CAVE_Z + side * (CAVE_HALF_WIDTH + CAVE_LINING * 0.5))))
		# Pilasters break up the long wall and give the tunnel a built quarry feel.
		if i % 2 == 0:
			for side in [-1.0, 1.0]:
				_add_instance("cave_lining", Transform3D(
					Basis().scaled(Vector3(0.8, CAVE_HEIGHT, 0.35)),
					Vector3(cx, CAVE_HEIGHT * 0.5, CAVE_Z + side * (CAVE_HALF_WIDTH - 0.05))))

	# Portal collars: thick stone arch rings at both mouths.
	for side in [-1.0, 1.0]:
		var px: float = side * (CAVE_HALF_LEN + 1.3)
		for zsign in [-1.0, 1.0]:
			_add_stone_box(
				Vector3(px, 2.6, CAVE_Z + zsign * (CAVE_HALF_WIDTH + 0.8)),
				Vector3(1.6, 5.2, 1.4), 0.0)
		_add_stone_box(Vector3(px, CAVE_HEIGHT + 0.65, CAVE_Z),
			Vector3(1.6, 1.3, CAVE_HALF_WIDTH * 2.0 + 3.4), 0.0)
		_add_stone_box(Vector3(px, CAVE_HEIGHT + 1.4, CAVE_Z),
			Vector3(2.4, 0.6, CAVE_HALF_WIDTH * 2.0 + 5.0), 0.0)

	# Outer rock shell. Blocks are deliberately oversized and overlap: the
	# overlapping "rock skirt" hides every seam and stops any sky leak.
	for x in range(-31, 32, 4):
		for y: float in [0.0, 3.8, 7.6]:
			for zsign: float in [-1.0, 1.0]:
				var px := float(x) + _rng.randf_range(-0.5, 0.5)
				var py := y + _rng.randf_range(-0.25, 0.25)
				var sx := 4.5 + _rng.randf_range(-0.7, 0.9)
				var sy := 4.4 + _rng.randf_range(-0.7, 0.8)
				var sz := 4.6 + _rng.randf_range(-0.7, 0.9)
				var pz := CAVE_Z + zsign * (CAVE_HALF_WIDTH + 7.4) + _rng.randf_range(-0.6, 0.6)
				_add_instance("ridge_rock", Transform3D(
					Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)).scaled(
						Vector3(sx, sy, sz)),
					Vector3(px, py, pz)))
		for z in range(-64, -43, 4):
			var px := float(x) + _rng.randf_range(-0.5, 0.5)
			var pz := float(z) + _rng.randf_range(-0.5, 0.5)
			_add_instance("ridge_rock", Transform3D(
				Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12)).scaled(
					Vector3(4.6, 3.2, 4.6)),
				Vector3(px, CAVE_HEIGHT + 6.6 + _rng.randf_range(-0.3, 0.3), pz)))

	# End facades: blocks around the mouth, never across the opening.
	for xsign in [-1.0, 1.0]:
		for z in range(-64, -43, 4):
			for y in [0.0, 3.8, 7.6]:
				if absf(float(z) - CAVE_Z) < 6.2 and y < 4.7:
					continue
				if y > 4.7 and absf(float(z) - CAVE_Z) < 2.0:
					continue
				_add_instance("ridge_rock", Transform3D(
					Basis(Vector3.UP, _rng.randf_range(-0.1, 0.1)).scaled(
						Vector3(4.5, 4.3, 4.6)),
					Vector3(xsign * 32.2 + _rng.randf_range(-0.3, 0.3),
						y + _rng.randf_range(-0.25, 0.25),
						float(z) + _rng.randf_range(-0.35, 0.35))))

	# Rock skirts at the mouths, on the ground, to hide the shell/terrain seam.
	for xsign in [-1.0, 1.0]:
		for zoff in [-8.0, -5.5, 5.5, 8.0]:
			var base := Vector3(xsign * (CAVE_HALF_LEN + 4.0), height_at(
				xsign * (CAVE_HALF_LEN + 4.0), CAVE_Z + zoff), CAVE_Z + zoff)
			_add_rock("rock_tall" if absf(zoff) < 7.0 else "rock_wide", base,
				3.0 + _rng.randf_range(0.0, 1.2), _rng.randf_range(0.0, TAU), true)
		for zsign in [-1.0, 1.0]:
			var base := Vector3(xsign * (CAVE_HALF_LEN + 2.5),
				height_at(xsign * (CAVE_HALF_LEN + 2.5), CAVE_Z + zsign * 4.2),
				CAVE_Z + zsign * 4.2)
			_add_rock("rock_large", base, 2.6, _rng.randf_range(0.0, TAU), true)

	# Collision: solid ridge with one clean 5.6 x 4.6 m bore.
	_add_collider_box(Vector3(0.0, CAVE_HEIGHT * 0.5, CAVE_Z - (CAVE_HALF_WIDTH + 6.0)),
		Vector3(CAVE_HALF_LEN * 2.0 + 4.0, 11.0, 12.0), 0.0)
	_add_collider_box(Vector3(0.0, CAVE_HEIGHT * 0.5, CAVE_Z + (CAVE_HALF_WIDTH + 6.0)),
		Vector3(CAVE_HALF_LEN * 2.0 + 4.0, 11.0, 12.0), 0.0)
	_add_collider_box(Vector3(0.0, CAVE_HEIGHT + 4.0, CAVE_Z),
		Vector3(CAVE_HALF_LEN * 2.0 + 4.0, 8.0, 30.0), 0.0)
	for xsign in [-1.0, 1.0]:
		_add_collider_box(Vector3(xsign * (CAVE_HALF_LEN + 1.3), CAVE_HEIGHT + 3.2, CAVE_Z),
			Vector3(1.8, 6.4, 26.0), 0.0)
	# Ceiling and inner walls are separate from the solid mass above.
	_add_collider_box(Vector3(0.0, -0.25, CAVE_Z),
		Vector3(CAVE_HALF_LEN * 2.0 + 3.0, 0.5, CAVE_HALF_WIDTH * 2.0), 0.0)
	_add_collider_box(Vector3(0.0, CAVE_HEIGHT + 0.35, CAVE_Z),
		Vector3(CAVE_HALF_LEN * 2.0 + 3.0, 0.7, CAVE_HALF_WIDTH * 2.0), 0.0)
	for zsign in [-1.0, 1.0]:
		_add_collider_box(
			Vector3(0.0, CAVE_HEIGHT * 0.5, CAVE_Z + zsign * (CAVE_HALF_WIDTH + CAVE_LINING * 0.5)),
			Vector3(CAVE_HALF_LEN * 2.0 + 3.0, CAVE_HEIGHT, CAVE_LINING), 0.0)

	# Warm, shadowless lamps. They are cheap (3 omnis, no shadows) and give the
	# tunnel a readable warm/cool rhythm without a second light rig.
	var light_root := Node3D.new()
	light_root.name = "Lights"
	_cave_root.add_child(light_root)
	var lamp_positions := [
		Vector3(-26.0, 3.5, CAVE_Z), Vector3(-13.0, 3.5, CAVE_Z),
		Vector3(0.0, 3.5, CAVE_Z), Vector3(13.0, 3.5, CAVE_Z),
		Vector3(26.0, 3.5, CAVE_Z),
	]
	for i in lamp_positions.size():
		var light := OmniLight3D.new()
		light.name = "CaveLamp_%d" % i
		light.position = lamp_positions[i]
		light.light_color = Color(1.0, 0.72, 0.42) if i != 2 else Color(0.62, 0.78, 1.0)
		light.light_energy = 1.8
		light.omni_range = 16.0
		light.shadow_enabled = false
		light_root.add_child(light)


func _connect_cave_atmosphere() -> void:
	var area := get_node_or_null("Cave/CaveInterior") as Area3D
	if area:
		area.body_entered.connect(_on_cave_body_entered)
		area.body_exited.connect(_on_cave_body_exited)
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		_environment = world_env.environment
		_base_ambient = _environment.ambient_light_energy
		_ambient_target = _base_ambient


func _on_cave_body_entered(body: Node) -> void:
	if not _is_local_player(body):
		return
	_cave_active = true
	_ambient_target = _base_ambient * 0.6
	set_process(true)


func _on_cave_body_exited(body: Node) -> void:
	if not _is_local_player(body):
		return
	_cave_active = false
	_ambient_target = _base_ambient
	set_process(true)


func _is_local_player(body: Node) -> bool:
	if not (body is PlayerController):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	return int((body as PlayerController).net_role) == PlayerController.NetRole.LOCAL


func _process(delta: float) -> void:
	if _environment == null:
		set_process(false)
		return
	_environment.ambient_light_energy = move_toward(
		_environment.ambient_light_energy, _ambient_target, delta * 0.8)
	if is_equal_approx(_environment.ambient_light_energy, _ambient_target):
		set_process(false)


# --- hero cover -----------------------------------------------------------

func _place_hero_props() -> void:
	_central_ruin()
	_central_cover()
	_ruined_arch(Vector3(16.0, 0.0, 34.0), 0.25)
	_ruined_arch(Vector3(-30.0, 0.0, 30.0), -0.4)
	_ruined_walls()
	_bridge()
	_lookout()
	_fallen_log()
	for spot: Vector3 in HERO_ROCKS:
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var key := "rock_tall" if spot.z >= 3.2 else "rock_large"
		_add_rock(key, base, spot.z, _rng.randf_range(0.0, TAU), true)
	for spot: Vector3 in HERO_TREES:
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var key: String = ["tree_default", "tree_detailed", "tree_pine", "tree_fat"][
			int(abs(spot.x + spot.y)) % 4]
		_add_tree(key, base, spot.z)


func _central_cover() -> void:
	# Eight hand-placed clusters through the central band. Each is a tall boulder
	# plus a broken wall segment and a low fallen block: enough to break sightlines
	# without creating dead ends. Positions avoid spawns, ramps, cave and bridge.
	for i in CENTRAL_COVER.size():
		var spot: Vector3 = CENTRAL_COVER[i]
		var yaw := spot.z
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		_add_rock("rock_tall" if i % 2 == 0 else "rock_large", base,
			3.2 + 0.4 * float(i % 3), yaw, true)
		_add_cliff_wall(base + dir * 2.0,
			Vector3(1.8, 2.4 + 0.4 * float(i % 2), 3.2), yaw + 0.4)
		_add_stone_box(base + dir * 1.1 + Vector3(0.0, 0.35, 0.0),
			Vector3(1.4, 0.7, 1.2), yaw + 0.8)
		_add_stone_box(base + dir * 2.0 + Vector3(0.0, 2.55, 0.0),
			Vector3(1.0, 0.5, 1.2), yaw + 0.7)


func _central_ruin() -> void:
	var base := height_at(0.0, 0.0)
	_add_stone_box(Vector3(0.0, base + 0.25, 0.0), Vector3(7.0, 0.5, 7.0), 0.0)
	_add_stone_box(Vector3(0.0, base + 2.25, 0.0), Vector3(1.2, 4.0, 1.2), 0.0)
	_add_stone_box(Vector3(0.0, base + 4.45, 0.0), Vector3(1.6, 0.5, 1.6), 0.35)
	# Toppled capital and broken drum give the plinth asymmetric silhouette.
	_add_stone_box(Vector3(3.0, base + 0.5, 2.0), Vector3(2.4, 0.8, 1.2), 0.55)
	_add_stone_box(Vector3(-2.8, base + 0.55, -1.5), Vector3(1.2, 0.8, 1.2), 0.15)
	for corner in [Vector2(-3.0, -3.0), Vector2(3.0, -3.0), Vector2(-3.0, 3.0), Vector2(3.0, 3.0)]:
		_add_stone_box(
			Vector3(corner.x, base + 0.95, corner.y), Vector3(0.9, 1.4, 0.9), 0.0)


func _ruined_arch(center: Vector3, yaw: float) -> void:
	var base := height_at(center.x, center.z)
	var basis := Basis(Vector3.UP, yaw)
	for side in [-1.0, 1.0]:
		var local := Vector3(side * 2.3, 2.1, 0.0)
		_add_stone_box(center + basis * local + Vector3(0.0, base, 0.0),
			Vector3(1.0, 4.2, 1.2), yaw)
	_add_stone_box(center + Vector3(0.0, base + 4.55, 0.0),
		Vector3(5.8, 0.8, 1.3), yaw)
	_add_stone_box(center + basis * Vector3(1.4, 0.0, 1.4) + Vector3(0.0, base + 0.35, 0.0),
		Vector3(1.4, 0.7, 1.0), yaw + 0.3)


func _ruined_walls() -> void:
	# West terrace retaining wall, broken in the middle so the west ramp route
	# stays open and readable.
	for z in [-22.0, -16.0, -10.0, 10.0, 16.0, 22.0]:
		var base := height_at(-47.5, z)
		_add_cliff_wall(Vector3(-47.5, base, z), Vector3(1.4, 2.4, 4.2), 0.0)
	# East lower wall, also broken.
	for z in [-30.0, -24.0, -12.0, -6.0]:
		var base := height_at(42.5, z)
		_add_cliff_wall(Vector3(42.5, base, z), Vector3(1.4, 2.2, 4.0), 0.0)
	# A small U-shaped ruin on the south terrace.
	var base := height_at(24.0, 48.0)
	_add_stone_box(Vector3(24.0, base + 1.1, 50.0), Vector3(6.0, 2.2, 0.8), 0.0)
	_add_stone_box(Vector3(21.2, base + 1.1, 47.2), Vector3(0.8, 2.2, 4.2), 0.0)
	_add_stone_box(Vector3(26.8, base + 0.7, 47.2), Vector3(0.8, 1.4, 4.2), 0.0)
	_add_stone_box(Vector3(24.0, base + 2.3, 50.6), Vector3(2.0, 0.5, 1.2), 0.35)
	# Round ruined tower on the high west bench.
	var tower_center := Vector3(-56.0, height_at(-56.0, 18.0), 18.0)
	for i in 8:
		if i == 2 or i == 3:
			continue
		var angle := TAU * float(i) / 8.0
		var block := tower_center + Vector3(cos(angle) * 3.2, 0.0, sin(angle) * 3.2)
		_add_cliff_wall(block, Vector3(1.8, 3.2 if i % 3 else 2.2, 2.6), -angle)


func _bridge() -> void:
	# The east bank is one terrace higher than the west bank, so the deck ramps
	# gently between them instead of ending buried under the east grass.
	var west_top := 2.45
	var east_top := height_at(57.0, 6.0)
	var slope := atan2(east_top - west_top, 14.0)
	var deck_basis := Basis(Vector3(0.0, 0.0, 1.0), slope)
	_add_collider_box_basis(Vector3(50.0, (west_top + east_top) * 0.5 - 0.1, 6.0),
		Vector3(14.2, 0.2, 3.8), deck_basis)
	for i in 19:
		var x := 43.0 + float(i) * 0.75
		var t := (x - 43.0) / 14.0
		var top := lerpf(west_top, east_top, t)
		_add_instance("wood_box", Transform3D(
			Basis().scaled(Vector3(0.72, 0.16, 3.6)), Vector3(x, top - 0.08, 6.0)))
	_hero_anchors.append(Vector3(50.0, (west_top + east_top) * 0.5, 6.0))
	# Posts and rails follow the slope. Rails are visual; the posts carry the
	# collision so a player can still step off into the cut.
	for x in [43.8, 47.8, 52.2, 56.2]:
		var t := (float(x) - 43.0) / 14.0
		var top := lerpf(west_top, east_top, t)
		for zsign in [-1.0, 1.0]:
			_add_wood_box(Vector3(x, top + 0.62, 6.0 + zsign * 1.78),
				Vector3(0.16, 1.24, 0.16), 0.0)
			_add_wood_box(Vector3(x, top - 0.8, 6.0 + zsign * 1.78),
				Vector3(0.18, 1.6, 0.18), 0.0)
	for zsign in [-1.0, 1.0]:
		for i in 4:
			var x0 := 43.8 + float(i) * 3.2
			var x1 := x0 + 3.2
			var t0 := (x0 - 43.0) / 14.0
			var t1 := (x1 - 43.0) / 14.0
			var y0 := lerpf(west_top, east_top, t0) + 1.18
			var y1 := lerpf(west_top, east_top, t1) + 1.18
			_add_wood_box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5,
				6.0 + zsign * 1.78), Vector3(3.2, 0.14, 0.16), 0.0)
	# Stone abutments sit under the two deck ends, not on the ravine floor.
	var west_ground := height_at(43.0, 6.0)
	var east_ground := height_at(57.0, 6.0)
	_add_stone_box(Vector3(43.2, west_ground - 1.0, 6.0), Vector3(2.4, 1.4, 4.4), 0.0)
	_add_stone_box(Vector3(56.8, east_ground - 1.0, 6.0), Vector3(2.4, 1.4, 4.4), 0.0)

func _lookout() -> void:
	var base := height_at(-62.0, 48.0)
	var deck_top := base + 1.56
	# Raised timber lookout with a south ramp. The deck is a real elevated
	# platform; the ramp is a single sloped collider, because this controller
	# cannot climb vertical step boxes.
	_add_wood_box(Vector3(-62.0, deck_top - 0.15, 48.0), Vector3(6.0, 0.3, 5.8), 0.0)
	_hero_anchors.append(Vector3(-62.0, deck_top, 48.0))
	var ramp_angle := atan2(1.9, 6.7)
	_add_wood_box_basis(Vector3(-62.0, base + 0.55, 54.15),
		Vector3(2.2, 0.2, 6.7), Basis(Vector3.RIGHT, ramp_angle))
	for corner in [Vector2(-2.7, -2.2), Vector2(2.7, -2.2), Vector2(-2.7, 2.2), Vector2(2.7, 2.2)]:
		_add_wood_box(Vector3(-62.0 + corner.x, base + 0.5, 48.0 + corner.y),
			Vector3(0.22, 3.6, 0.22), 0.0)
	# Rails on the north/east/west sides; the south side is the ramp opening.
	_add_wood_box(Vector3(-62.0, deck_top + 1.05, 45.55),
		Vector3(6.0, 0.15, 0.15), 0.0)
	_add_collider_box(Vector3(-62.0, deck_top + 0.9, 45.55),
		Vector3(6.0, 0.7, 0.2), 0.0)
	_hero_anchors.append(Vector3(-62.0, deck_top + 0.9, 45.55))
	for side in [-1.0, 1.0]:
		_add_wood_box(Vector3(-62.0 + side * 2.95, deck_top + 1.05, 48.0),
			Vector3(0.15, 0.15, 5.6), 0.0)
		_add_collider_box(Vector3(-62.0 + side * 2.95, deck_top + 0.9, 48.0),
			Vector3(0.2, 0.7, 5.6), 0.0)
		_hero_anchors.append(Vector3(-62.0 + side * 2.95, deck_top + 0.9, 48.0))

func _fallen_log() -> void:
	var base := height_at(-8.0, -14.0)
	_add_instance("log", Transform3D(
		Basis(Vector3.UP, 0.8).scaled(Vector3.ONE * 3.0),
		Vector3(-8.0, base + 0.06, -14.0)))
	_add_collider_box(Vector3(-8.0, base + 0.18, -14.0), Vector3(0.7, 0.42, 2.1), 0.8)
	_hero_anchors.append(Vector3(-8.0, base + 0.18, -14.0))


func _add_stone_box(pos: Vector3, size: Vector3, yaw: float) -> void:
	_add_instance("stone_box", Transform3D(Basis(Vector3.UP, yaw).scaled(size), pos))
	_add_collider_box(pos, size, yaw)
	_hero_anchors.append(pos)


func _add_wood_box(pos: Vector3, size: Vector3, yaw: float) -> void:
	_add_instance("wood_box", Transform3D(Basis(Vector3.UP, yaw).scaled(size), pos))
	_add_collider_box(pos, size, yaw)
	_hero_anchors.append(pos)


func _add_wood_box_basis(pos: Vector3, size: Vector3, basis: Basis) -> void:
	_add_instance("wood_box", Transform3D(basis.scaled(size), pos))
	_add_collider_box_basis(pos, size, basis)
	_hero_anchors.append(pos)


func _add_cliff_wall(base_pos: Vector3, size: Vector3, yaw: float) -> void:
	# cliff_block models have their origin at the bottom centre.
	_add_instance("cliff_wall", Transform3D(Basis(Vector3.UP, yaw).scaled(size), base_pos))
	_add_collider_box(base_pos + Vector3(0.0, size.y * 0.5, 0.0), size, yaw)
	_hero_anchors.append(base_pos + Vector3(0.0, size.y * 0.5, 0.0))


func _add_rock(key: String, base_pos: Vector3, scale_value: float, yaw: float, collide: bool) -> void:
	_add_instance(key, Transform3D(
		Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value),
		base_pos + Vector3(0.0, 0.03, 0.0)))
	if collide:
		var height := 0.95 * scale_value if key == "rock_tall" else 0.32 * scale_value
		_add_collider_cylinder(base_pos, 0.46 * scale_value, height)
		_hero_anchors.append(base_pos + Vector3(0.0, height * 0.5, 0.0))


func _add_tree(key: String, base_pos: Vector3, scale_value: float) -> void:
	var yaw := _rng.randf_range(0.0, TAU)
	_add_instance(key, Transform3D(
		Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value),
		base_pos + Vector3(0.0, 0.03, 0.0)))
	var height := 1.3 * scale_value
	_add_collider_cylinder(base_pos, 0.12 * scale_value, height)
	_hero_anchors.append(base_pos + Vector3(0.0, height * 0.5, 0.0))
	_tree_positions.append(base_pos)


# --- scatter --------------------------------------------------------------

func _dress_cave_ridge() -> void:
	# Vegetation and boulders break the rectangular shell silhouette and hide
	# the seam where the artificial ridge meets the terrain.
	for i in 30:
		var x := -27.0 + float(i) * 1.9 + _rng.randf_range(-0.9, 0.9)
		var z := -60.0 + _rng.randf_range(0.0, 13.0)
		var key: String = ["tree_pine", "tree_pine_round", "tree_default"][_rng.randi_range(0, 2)]
		_add_tree(key, Vector3(x, 12.95, z), _rng.randf_range(2.6, 5.0))
	for i in 26:
		var x := -28.0 + float(i) * 2.2 + _rng.randf_range(-0.8, 0.8)
		var z := -60.0 + _rng.randf_range(0.0, 13.0)
		_add_rock("rock_large" if i % 2 else "rock_wide", Vector3(x, 12.9, z),
			_rng.randf_range(2.0, 4.0), _rng.randf_range(0.0, TAU), false)
	# Outcrops across the long south and north faces hide the regular block grid.
	for i in 66:
		var x := -29.0 + _rng.randf_range(0.0, 58.0)
		var z := (-41.0 if i % 2 == 0 else -66.6) + _rng.randf_range(-0.5, 0.5)
		var y := _rng.randf_range(0.0, 7.0)
		var key: String = ["rock_tall", "rock_large", "rock_wide"][_rng.randi_range(0, 2)]
		_add_instance(key, Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
				Vector3.ONE * _rng.randf_range(2.6, 6.0)),
			Vector3(x, y, z)))
	for i in 18:
		var x := -28.0 + float(i) * 3.3 + _rng.randf_range(-0.8, 0.8)
		var z := -43.5 if i % 2 == 0 else -64.0
		var base := Vector3(x, height_at(x, z), z + _rng.randf_range(-1.0, 1.0))
		_add_rock("rock_tall" if i % 3 else "rock_wide", base,
			_rng.randf_range(2.6, 4.8), _rng.randf_range(0.0, TAU), true)


func _scatter_dressing() -> void:
	_scatter_ridge_pines(240)
	_scatter_boulders(34)
	_scatter_mountain_rocks(160)
	_scatter_trees(42)
	_scatter_foliage("grass", 470, 1.0, 2.0, 0.4)
	_scatter_foliage("flower_red", 120, 0.9, 1.7, 0.35)
	_scatter_foliage("flower_yellow", 120, 0.9, 1.7, 0.35)
	_scatter_foliage("bush", 80, 1.1, 2.0, 0.45)
	_scatter_foliage("bush_large", 50, 1.2, 2.2, 0.45)
	_scatter_foliage("mushroom", 44, 1.0, 1.8, 0.4)
	_scatter_foliage("rock_small", 220, 1.0, 2.2, 0.6)
	_scatter_logs()


func _scatter_mountain_rocks(count: int) -> void:
	# A rocky rim at the toe of the mountain ring breaks the smooth dune line.
	for _i in count:
		var side := _rng.randi_range(0, 3)
		var along := _rng.randf_range(-65.0, 65.0)
		var depth := _rng.randf_range(58.0, 73.0)
		var pos := Vector3.ZERO
		match side:
			0:
				pos = Vector3(depth, 0.0, along)
			1:
				pos = Vector3(-depth, 0.0, along)
			2:
				pos = Vector3(along, 0.0, depth)
			3:
				pos = Vector3(along, 0.0, -depth)
		pos.y = height_at(pos.x, pos.z)
		if pos.y > 7.0 or slope_at(pos.x, pos.z) > 0.9:
			continue
		if _in_traversal_lane(pos):
			continue
		if absf(pos.x) < 36.0 and absf(pos.z - CAVE_Z) < 17.0:
			continue
		if not _is_dressing_clear(pos, 1.8):
			continue
		if pos.y < 2.5 and _rng.randf() < 0.55:
			# Grey cliff blocks only at the toe; higher up they can float
			# against the steep face and read as broken geometry.
			var span := 2.6 if pos.y < 4.0 else 1.8
			_add_cliff_wall(pos, Vector3(
				_rng.randf_range(span, span + 2.4), _rng.randf_range(1.6, 4.0),
				_rng.randf_range(span, span + 2.4)), _rng.randf_range(0.0, TAU))
		else:
			var key: String = ["rock_tall", "rock_large", "rock_wide"][_rng.randi_range(0, 2)]
			_add_rock(key, pos, _rng.randf_range(2.4, 5.2), _rng.randf_range(0.0, TAU), true)


func _scatter_boulders(count: int) -> void:
	for _i in count:
		var pos := _random_dressing_point(0.95)
		if pos == Vector3.INF:
			continue
		var key: String = ["rock_large", "rock_wide", "rock_tall"][_rng.randi_range(0, 2)]
		var scale_value := _rng.randf_range(1.2, 2.8)
		_add_rock(key, pos, scale_value, _rng.randf_range(0.0, TAU), true)


## Pines on the terrace/mountain toe soften the ring silhouette and frame the
## play space without eating into the combat floor.
func _scatter_ridge_pines(count: int) -> void:
	for _i in count:
		var side := _rng.randi_range(0, 3)
		var along := _rng.randf_range(-68.0, 68.0)
		var depth := _rng.randf_range(57.0, 73.0)
		var pos := Vector3.ZERO
		match side:
			0:
				pos = Vector3(depth, 0.0, along)
			1:
				pos = Vector3(-depth, 0.0, along)
			2:
				pos = Vector3(along, 0.0, depth)
			3:
				pos = Vector3(along, 0.0, -depth)
		pos.y = height_at(pos.x, pos.z)
		if pos.y > 5.0 or slope_at(pos.x, pos.z) > 0.7:
			continue
		if _in_traversal_lane(pos):
			continue
		if absf(pos.x) < 36.0 and absf(pos.z - CAVE_Z) < 17.0:
			continue
		if not _is_dressing_clear(pos, 1.6):
			continue
		var key: String = ["tree_pine", "tree_pine_round", "tree_default"][_rng.randi_range(0, 2)]
		_add_tree(key, pos, _rng.randf_range(3.0, 5.2))


func _scatter_logs() -> void:
	for _i in 7:
		var pos := _random_dressing_point(0.5)
		if pos == Vector3.INF:
			continue
		if _rng.randf() < 0.5:
			_add_instance("log", Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
					Vector3.ONE * _rng.randf_range(2.0, 3.2)),
				pos + Vector3(0.0, 0.06, 0.0)))
		else:
			_add_instance("stump", Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
					Vector3.ONE * _rng.randf_range(1.8, 2.8)),
				pos + Vector3(0.0, 0.03, 0.0)))


func _scatter_trees(count: int) -> void:
	for _i in count:
		var pos := _random_dressing_point(0.55)
		if pos == Vector3.INF:
			continue
		var scale_value := _rng.randf_range(2.0, 3.8)
		var key: String = ["tree_default", "tree_detailed", "tree_pine", "tree_pine_round",
			"tree_fat"][_rng.randi_range(0, 4)]
		_add_tree(key, pos, scale_value)


func _scatter_foliage(key: String, count: int, min_scale: float, max_scale: float,
		max_slope: float) -> void:
	for _i in count:
		var pos := _random_dressing_point(max_slope)
		if pos == Vector3.INF:
			continue
		var scale_value := _rng.randf_range(min_scale, max_scale)
		_add_instance(key, Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value),
			pos + Vector3(0.0, 0.02, 0.0)))


func _random_dressing_point(max_slope: float) -> Vector3:
	for _attempt in 28:
		var x := _rng.randf_range(-64.0, 64.0)
		var z := _rng.randf_range(-64.0, 64.0)
		if maxf(absf(x), absf(z)) > 64.0:
			continue
		# Keep the ridge, cave mouths and bridge landing clear.
		if absf(x) < 36.0 and absf(z - CAVE_Z) < 15.0:
			continue
		if x > 41.0 and x < 59.0 and z > 1.0 and z < 11.0:
			continue
		if _in_traversal_lane(Vector3(x, 0.0, z)):
			continue
		if _near_central_cover(Vector3(x, 0.0, z), 3.5):
			continue
		if slope_at(x, z) > max_slope:
			continue
		var y := height_at(x, z)
		if y > 9.5:
			continue
		var pos := Vector3(x, y, z)
		if not _is_dressing_clear(pos, 1.1):
			continue
		return pos
	return Vector3.INF


func _near_central_cover(pos: Vector3, radius: float) -> bool:
	for spot: Vector3 in CENTRAL_COVER:
		if Vector2(pos.x - spot.x, pos.z - spot.y).length() < radius:
			return true
	return false


func _in_traversal_lane(pos: Vector3) -> bool:
	# Keep the main ramp/bridge/spawn approaches free of scatter. Hero props are
	# hand-placed and are checked separately.
	if absf(pos.z) < 4.5 and pos.x < -18.0 and pos.x > -70.0:
		return true
	if absf(pos.z + 20.0) < 4.5 and pos.x > 18.0 and pos.x < 70.0:
		return true
	if absf(pos.x - 8.0) < 4.5 and pos.z > 34.0 and pos.z < 68.0:
		return true
	if pos.x > 39.0 and pos.x < 61.0 and pos.z > 1.0 and pos.z < 11.0:
		return true
	if pos.x > -69.0 and pos.x < -55.0 and pos.z > 40.0 and pos.z < 57.0:
		return true
	if pos.x > -62.0 and pos.x < -50.0 and pos.z > 10.0 and pos.z < 26.0:
		return true
	if absf(pos.z + 54.0) < 10.0 and absf(pos.x) > 22.0 and absf(pos.x) < 58.0:
		return true
	return false


func _is_dressing_clear(pos: Vector3, clearance: float) -> bool:
	if Vector2(pos.x, pos.z).length() < 8.0:
		return false
	for spawn: Vector3 in _spawns:
		if Vector2(pos.x - spawn.x, pos.z - spawn.z).length() < 5.0:
			return false
	for anchor: Vector3 in _hero_anchors:
		if Vector2(pos.x - anchor.x, pos.z - anchor.z).length() < clearance + 1.2:
			return false
	for key: String in _placements:
		var list: Array = _placements[key]
		for xform: Transform3D in list:
			if Vector2(xform.origin.x - pos.x, xform.origin.z - pos.z).length() < clearance:
				return false
	return true


# --- rendering / collision ------------------------------------------------

func _add_instance(key: String, xform: Transform3D) -> void:
	if not _placements.has(key):
		var list: Array[Transform3D] = []
		_placements[key] = list
	_placements[key].append(xform)


func _build_multimeshes() -> void:
	for key: String in _placements:
		var xforms: Array = _placements[key]
		var mesh: Mesh = null
		var base_transform := Transform3D.IDENTITY
		var probe: Node = null
		if _synthetic_meshes.has(key):
			mesh = _synthetic_meshes[key] as Mesh
		else:
			var packed := _load_model(key)
			if packed == null:
				continue
			probe = packed.instantiate()
			var mesh_instance := _first_mesh(probe)
			if mesh_instance == null or mesh_instance.mesh == null:
				if probe:
					probe.free()
				push_warning("No mesh in " + key)
				continue
			mesh = mesh_instance.mesh
			base_transform = mesh_instance.transform
			_restyle_mesh(mesh, key)

		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = xforms.size()
		for index in xforms.size():
			multimesh.set_instance_transform(index, xforms[index] * base_transform)

		var instance := MultiMeshInstance3D.new()
		instance.name = "MM_" + key
		instance.multimesh = multimesh
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if key.begins_with("tree") or key.begins_with("rock") or key == "log"
				or key == "stone_box" or key == "cliff_wall" or key == "ridge_rock"
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		_props_root.add_child(instance)
		if probe:
			probe.free()


func _build_colliders() -> void:
	var index := 0
	for collider: Dictionary in _colliders:
		var body := StaticBody3D.new()
		body.name = "PropCollider_%d" % index
		index += 1
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = collider["pos"]
		if collider.has("basis"):
			body.transform.basis = collider["basis"]
		else:
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


func _add_collider_box(pos: Vector3, size: Vector3, yaw: float) -> void:
	if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
		push_error("Non-positive collider box %s at %s" % [str(size), str(pos)])
		return
	_colliders.append({"shape": "box", "pos": pos, "size": size, "yaw": yaw})


func _add_collider_box_basis(pos: Vector3, size: Vector3, basis: Basis) -> void:
	if size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
		push_error("Non-positive collider box %s at %s" % [str(size), str(pos)])
		return
	_colliders.append({"shape": "box", "pos": pos, "size": size, "basis": basis})


func _add_collider_cylinder(base_pos: Vector3, radius: float, height: float) -> void:
	_colliders.append({
		"shape": "cylinder", "pos": base_pos, "radius": radius, "height": height,
	})


func _restyle_mesh(mesh: Mesh, model_key: String = "") -> void:
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material == null:
			continue
		var material_key := String(material.resource_name)
		if not PALETTE.has(material_key):
			continue
		var color: Color = PALETTE[material_key]
		if model_key == "cliff_wall":
			# Quarried retaining walls are stone, not mossy cliff tops. Use a
			# brighter authored value: converting a 0.40 sRGB stone to linear
			# gave 0.13, which collapsed to near-black in shadow.
			if material_key == "grass":
				color = Color(0.52, 0.51, 0.47)
			else:
				color = Color(0.62, 0.60, 0.56)
			color = color.srgb_to_linear()
		var restyled := StandardMaterial3D.new()
		restyled.resource_name = material_key
		restyled.albedo_color = color
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


# --- test / report hooks --------------------------------------------------

## Every tree base generated by this arena (hand placed and scattered).
func tree_positions() -> Array:
	return _tree_positions.duplicate()


## Anchor points for every hand-placed/hero prop, used by the collider test.
func hero_anchor_positions() -> Array:
	return _hero_anchors.duplicate()


func spawn_positions() -> Array:
	return _spawns.duplicate()


func terrain_chunk_count() -> int:
	return _terrain_root.get_child_count() if _terrain_root else 0


func cave_entrances() -> Array:
	return [
		Vector3(-CAVE_HALF_LEN - 1.3, 0.0, CAVE_Z),
		Vector3(CAVE_HALF_LEN + 1.3, 0.0, CAVE_Z),
	]


func cave_floor_y() -> float:
	return 0.0


func cave_ceiling_y() -> float:
	return CAVE_HEIGHT


func cave_length() -> float:
	return CAVE_HALF_LEN * 2.0 + 2.6
