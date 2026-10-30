extends Node3D
## Sun-scorched Dunes & Ruined Fort — 120 x 120 m map candidate.
##
## The height field below is the single source of truth for both the low-poly
## visual chunks and the HeightMapShape3D collision, so the headless server and
## every browser client produce the same ground. Everything is deterministic:
## scatter uses a fixed seed and hand-placed cover is static data.
##
## Layout (x east, z south):
##   centre      narrow canyon slot along z with a timber bridge at z = 2
##   west        two walkable mesa benches (0 / 2.5 / 5 m) with gentle ramps
##   east        rolling dunes with an oasis dip and pond disc at (30, 18)
##   south       a ruined fort square (gaps north/south) + corner tower platform
##   edge        a rising dune/rock ring plus invisible boundary/camera walls

const SEED := 20261102
const MAP_HALF := 60.0
const PLAY_HALF := 55.0
const CHUNK_SIZE := 40.0
const CHUNK_GRID := 3
const CHUNK_SAMPLES := 41
const VISUAL_STEP := 2
const VISUAL_SAMPLES := 21
const BOUNDARY_HEIGHT := 40.0

# Canyon constants are public for tests and the arena budget report.
const CANYON_X := 0.0
const CANYON_Z_MIN := -42.0
const CANYON_Z_MAX := 28.0
const CANYON_HALF_WIDTH := 3.0
const CANYON_DEPTH := 5.0
const BRIDGE_Z := 2.0
const BRIDGE_HALF := 7.0

const FORT_H := 1.0
const OASIS_X := 30.0
const OASIS_Z := 18.0
const OASIS_R := 12.0
const OASIS_DEPTH := 1.2

const MODEL_DIR := "res://assets/kenney_nature/models/"
const PALETTE := {
	"grass": Color(0.750000, 0.660000, 0.420000),
	"leafsGreen": Color(0.450000, 0.500000, 0.280000),
	"leafsDark": Color(0.360000, 0.400000, 0.220000),
	"woodBark": Color(0.550000, 0.420000, 0.280000),
	"woodBarkDark": Color(0.430000, 0.320000, 0.220000),
	"woodInner": Color(0.720000, 0.580000, 0.380000),
	"dirt": Color(0.720000, 0.600000, 0.420000),
	"stone": Color(0.660000, 0.570000, 0.460000),
	"colorRed": Color(0.85, 0.25, 0.25),
	"colorYellow": Color(0.95, 0.78, 0.25),
	"_defaultMat": Color(0.80, 0.68, 0.48),
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
	Vector3(-42.0, 3.0, -30.0),  # west mesa bench
	Vector3(-44.0, 3.0, 20.0),   # west mesa south
	Vector3(-16.0, 0.0, -8.0),   # west central dunes
	Vector3(16.0, 0.0, -28.0),   # east north dunes
	Vector3(36.0, 0.0, 8.0),     # east dunes, north of oasis
	Vector3(30.0, 0.0, 30.0),    # east dunes, south of oasis
	Vector3(0.0, 1.0, 50.0),     # south, beyond the fort
	Vector3(0.0, 0.0, -48.0),    # north dunes
]

# Twelve deterministic rock outcrops on the upper ring. They are height-field
# bumps (not props), so they are part of the terrain collision and cannot float.
const RING_BUMPS := [
	Vector4(56.5, -36.0, 3.4, 4.5), Vector4(57.0, -12.0, 2.8, 4.0),
	Vector4(56.8, 12.0, 3.8, 4.2), Vector4(57.2, 36.0, 3.0, 4.4),
	Vector4(-56.5, -32.0, 3.2, 4.2), Vector4(-57.0, -8.0, 3.8, 4.5),
	Vector4(-56.8, 16.0, 2.9, 4.0), Vector4(-57.2, 40.0, 3.6, 4.4),
	Vector4(-32.0, 56.5, 3.8, 4.4), Vector4(-8.0, 57.0, 3.0, 4.0),
	Vector4(16.0, 56.8, 3.4, 4.2), Vector4(40.0, 57.2, 3.8, 4.5),
]

# Central cover clusters: (x, z, yaw). Kept clear of spawns, the canyon, the
# bridge lane, the fort and the oasis pond.
const CENTRAL_COVER := [
	Vector3(-14.0, 10.0, 0.4), Vector3(14.0, 12.0, 1.2),
	Vector3(-12.0, -24.0, 2.0), Vector3(16.0, -22.0, 0.8),
	Vector3(-28.0, 8.0, 2.6), Vector3(28.0, -2.0, 1.6),
	Vector3(10.0, 24.0, 2.4), Vector3(-10.0, 26.0, 0.2),
]

# Hand-placed cover. Only (x, z) drive the layout; y comes from the height field.
const HERO_TREES := [
	Vector3(25.0, 14.0, 2.6), Vector3(35.0, 14.0, 2.8),
	Vector3(25.0, 22.0, 2.6), Vector3(35.0, 22.0, 2.8),
	Vector3(-30.0, -18.0, 2.8), Vector3(-34.0, 30.0, 3.0),
	Vector3(20.0, -34.0, 2.8), Vector3(-20.0, 40.0, 3.0),
]
const HERO_ROCKS := [
	Vector3(-24.0, -12.0, 2.8), Vector3(-8.0, 16.0, 2.6),
	Vector3(12.0, -16.0, 3.0), Vector3(22.0, 26.0, 2.6),
	Vector3(40.0, -18.0, 3.2), Vector3(-38.0, 4.0, 3.0),
	Vector3(-48.0, -12.0, 3.2), Vector3(46.0, 20.0, 3.0),
	Vector3(-26.0, 34.0, 2.8), Vector3(16.0, 44.0, 2.6),
	Vector3(-14.0, -38.0, 3.0), Vector3(24.0, 40.0, 2.6),
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
var _boundary_root: Node3D
var _mat_terrain: StandardMaterial3D
var _mat_stone: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_water: StandardMaterial3D


func _ready() -> void:
	_props_root = _node_or_new("Props")
	_terrain_root = _node_or_new("Terrain")
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
	_place_hero_props()
	_scatter_dressing()
	_build_multimeshes()
	_build_colliders()
	_build_oasis_pond()
	set_process(false)


# --- height field --------------------------------------------------------

## Height in metres at world (x, z). The visual chunk vertices and the
## HeightMapShape3D collision are both sampled from this function.
static func height_at(x: float, z: float) -> float:
	var h := 0.55 * sin(x * 0.11) * cos(z * 0.09)
	h += 0.30 * sin(x * 0.23 + z * 0.17) + 0.15 * cos(z * 0.31 - x * 0.07)
	h += 0.80 * sin(x * 0.09 + 1.2) * cos(z * 0.05 + 0.4)
	h += 0.60 * cos(z * 0.12 - 0.5) * sin(x * 0.05 + 0.8)

	# West mesa benches: 0 -> 2.5 -> 5 m over gentle ramps (max ~0.25 rise/m).
	if x < -24.0:
		var hw := 2.5 * clampf((-x - 24.0) / 12.0, 0.0, 1.0)
		if x < -36.0:
			hw = 2.5 + 2.5 * clampf((-x - 40.0) / 10.0, 0.0, 1.0)
		h = maxf(h, hw)

	# East oasis dip: a shallow walkable bowl around the pond.
	var oasis_d := Vector2(x - OASIS_X, z - OASIS_Z).length()
	if oasis_d < OASIS_R:
		h -= OASIS_DEPTH * (1.0 - smoothstep(0.0, OASIS_R, oasis_d))

	# South fort plateau: flat floor with smooth aprons on every side.
	var fort_blend := _fort_blend(x, z)
	if fort_blend > 0.0:
		h = lerpf(h, FORT_H, fort_blend)

	# Central canyon slot. Steep smooth sides; the timber bridge is the route.
	if x > -8.0 and x < 8.0 and z > -46.0 and z < 30.0:
		var along := smoothstep(-44.0, -38.0, z) * (1.0 - smoothstep(22.0, 28.0, z))
		if along > 0.0:
			var cut := 1.0 - smoothstep(1.5, 4.5, absf(x - CANYON_X))
			h -= CANYON_DEPTH * cut * along

	# Rising dune/rock ring outside the playable boundary.
	var edge := maxf(absf(x), absf(z))
	var ring := _ring_height(edge)
	if ring > 0.001:
		ring += ring * 0.012 * (sin(x * 0.17) + cos(z * 0.21))
		if edge > 58.0:
			# Break the outer crest silhouette; outside the playable
			# boundary, so it does not affect movement routes.
			ring += 1.2 * sin(x * 0.13 + z * 0.07) + 0.8 * cos(x * 0.17 - z * 0.09)
		if edge > 54.0:
			ring += _ring_bumps(x, z)
		h = maxf(h, ring)
	return h


static func _fort_blend(x: float, z: float) -> float:
	var ix := 1.0 - smoothstep(8.0, 12.0, absf(x))
	if ix <= 0.0:
		return 0.0
	var iz := smoothstep(28.0, 32.0, z) * (1.0 - smoothstep(44.0, 48.0, z))
	return ix * iz


static func _ring_bumps(x: float, z: float) -> float:
	var total := 0.0
	for bump: Vector4 in RING_BUMPS:
		var distance := Vector2(x - bump.x, z - bump.y).length()
		if distance < bump.w:
			total = maxf(total, bump.z * (1.0 - smoothstep(0.0, bump.w, distance)))
	return total


static func _ring_height(edge: float) -> float:
	if edge <= 54.0:
		return 0.0
	if edge < 56.0:
		return 6.0 * (edge - 54.0) / 2.0
	if edge < 58.0:
		return 6.0
	return 6.0 + 8.0 * clampf((edge - 58.0) / 2.0, 0.0, 1.0)


static func terrain_normal(x: float, z: float) -> Vector3:
	const E := 0.8
	var dx := height_at(x + E, z) - height_at(x - E, z)
	var dz := height_at(x, z + E) - height_at(x, z - E)
	return Vector3(-dx, 2.0 * E, -dz).normalized()


static func slope_at(x: float, z: float) -> float:
	const E := 0.5
	var dx := (height_at(x + E, z) - height_at(x - E, z)) / (2.0 * E)
	var dz := (height_at(x, z + E) - height_at(x, z - E)) / (2.0 * E)
	return Vector2(dx, dz).length()


static func terrain_color(x: float, z: float, y: float, slope: float) -> Color:
	var n := 0.5 + 0.5 * sin(x * 0.27 + z * 0.19) * cos(x * 0.11 - z * 0.23)
	var sand := Color(0.76, 0.66, 0.48)
	var dune := Color(0.82, 0.71, 0.52)
	var rock := Color(0.62, 0.53, 0.42)
	var scrub := Color(0.55, 0.52, 0.33)
	var mountain := Color(0.55, 0.47, 0.38)
	var pale := Color(0.88, 0.80, 0.64)
	var oasis_tint := Color(0.45, 0.48, 0.30)
	var color: Color
	if y > 12.0:
		color = mountain.lerp(pale, clampf((y - 12.0) / 8.0, 0.0, 1.0) * 0.45)
	elif y > 6.0:
		color = mountain.lerp(rock, n * 0.55)
	elif slope > 1.0:
		color = rock.lerp(mountain, n * 0.6)
	elif y > 2.5:
		color = dune.lerp(rock, n * 0.45)
	elif y > 0.5:
		color = sand.lerp(dune, n * 0.5)
	else:
		color = sand.lerp(scrub, n * 0.35)
	var oasis_d := Vector2(x - OASIS_X, z - OASIS_Z).length()
	if oasis_d < 9.0:
		color = color.lerp(oasis_tint, (1.0 - smoothstep(0.0, 9.0, oasis_d)) * 0.55)
	# Broad patches only; fine per-metre noise shimmers at distance.
	var fleck := 0.035 * sin(x * 0.57 + z * 0.41) * sin(z * 0.73 - x * 0.29)
	var strata := 0.035 * sin(y * 1.35 + x * 0.05) if y > 6.0 else 0.0
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
	_mat_terrain.resource_name = "dunes_terrain"
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

	_mat_stone = _flat_material("dunes_stone", Color(0.72, 0.63, 0.50))
	_mat_wood = _flat_material("dunes_wood", Color(0.78, 0.62, 0.40))
	_mat_water = StandardMaterial3D.new()
	_mat_water.resource_name = "dunes_water"
	_mat_water.albedo_color = Color(0.20, 0.55, 0.62).srgb_to_linear()
	_mat_water.roughness = 0.25
	_mat_water.metallic = 0.1

	_synthetic_meshes["stone_box"] = _unit_box(_mat_stone)
	_synthetic_meshes["wood_box"] = _unit_box(_mat_wood)


func _flat_material(name: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.albedo_color = color.srgb_to_linear()
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## Seamless sand-grain detail map. Three periodic value-noise octaves (8, 16
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
			var value := 0.82 + 0.18 * clampf(sum, 0.0, 1.0)
			image.set_pixel(x, y, Color(value, value * 0.97, value * 0.90))
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
			# Terrain does not cast: at 1 m resolution a large directional
			# shadow frustum produces self-shadow acne across the dunes.
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
	# deliberate low-poly dune surface instead of smooth 1 m shading bands.
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


# --- hero cover -----------------------------------------------------------

func _place_hero_props() -> void:
	_central_cover()
	_ruined_arch(Vector3(-22.0, 0.0, -14.0), 0.3)
	_ruined_arch(Vector3(24.0, 0.0, -10.0), -0.35)
	_fort()
	_bridge()
	_fallen_log()
	for spot: Vector3 in HERO_ROCKS:
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var key := "rock_tall" if spot.z >= 3.0 else "rock_large"
		_add_rock(key, base, spot.z, _rng.randf_range(0.0, TAU), true)
	for spot: Vector3 in HERO_TREES:
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var key: String = ["tree_default", "tree_detailed", "tree_small", "tree_fat"][
			int(abs(spot.x + spot.y)) % 4]
		_add_tree(key, base, spot.z)


func _central_cover() -> void:
	# Eight hand-placed clusters through the dune field. Each is a tall boulder
	# plus a broken wall segment and a low fallen block: enough to break
	# sightlines without creating dead ends. Positions avoid spawns, the
	# canyon, the bridge lane, the fort and the oasis pond.
	for i in CENTRAL_COVER.size():
		var spot: Vector3 = CENTRAL_COVER[i]
		var yaw := spot.z
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		_add_rock("rock_tall" if i % 2 == 0 else "rock_large", base,
			3.0 + 0.4 * float(i % 3), yaw, true)
		_add_cliff_wall(base + dir * 2.0,
			Vector3(1.8, 2.2 + 0.4 * float(i % 2), 3.0), yaw + 0.4)
		_add_stone_box(base + dir * 1.1 + Vector3(0.0, 0.35, 0.0),
			Vector3(1.4, 0.7, 1.2), yaw + 0.8)


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


func _fort() -> void:
	# Ruined fort square centred on (0, 38): four stone walls with a 5 m gap
	# on the north and south sides aligned with the approach aprons. The
	# interior floor is the flattened fort plateau (FORT_H).
	var floor := FORT_H
	var half := 6.0
	# North wall (z = 32) with a central gap |x| < 2.5.
	_add_stone_box(Vector3(-4.25, floor + 1.1, 32.0), Vector3(3.5, 2.2, 0.8), 0.0)
	_add_stone_box(Vector3(4.25, floor + 1.1, 32.0), Vector3(3.5, 2.2, 0.8), 0.0)
	# South wall (z = 44) with a central gap |x| < 2.5.
	_add_stone_box(Vector3(-4.25, floor + 1.1, 44.0), Vector3(3.5, 2.2, 0.8), 0.0)
	_add_stone_box(Vector3(4.25, floor + 1.1, 44.0), Vector3(3.5, 2.2, 0.8), 0.0)
	# East and west walls run the full 12 m depth.
	_add_stone_box(Vector3(-half, floor + 1.1, 38.0), Vector3(0.8, 2.2, 12.8), 0.0)
	_add_stone_box(Vector3(half, floor + 1.1, 38.0), Vector3(0.8, 2.2, 12.8), 0.0)
	# Corner bastions: low square blocks at the four corners.
	for corner in [Vector2(-half, 32.0), Vector2(half, 32.0),
			Vector2(-half, 44.0), Vector2(half, 44.0)]:
		_add_stone_box(Vector3(corner.x, floor + 0.5, corner.y),
			Vector3(1.6, 1.0, 1.6), 0.0)
	# Corner tower platform in the south-east corner with a timber ramp.
	# Deck top sits 1.5 m above the fort floor; the ramp runs 5 m north of
	# the deck so the climb stays at a walkable ~0.3 rise per metre.
	var deck := Vector3(3.4, floor + 1.5, 41.6)
	_add_wood_box(Vector3(deck.x, deck.y - 0.15, deck.z), Vector3(3.6, 0.3, 3.6), 0.0)
	var ramp_angle := atan2(1.5, 5.0)
	_add_wood_box_basis(Vector3(deck.x, floor + 0.75, deck.z - 4.3),
		Vector3(2.4, 0.2, 5.4), Basis(Vector3.RIGHT, -ramp_angle))
	for corner in [Vector2(-1.5, -1.5), Vector2(1.5, -1.5),
			Vector2(-1.5, 1.5), Vector2(1.5, 1.5)]:
		_add_wood_box(Vector3(deck.x + corner.x, floor + 0.6, deck.z + corner.y),
			Vector3(0.22, 2.4, 0.22), 0.0)
	# Rails on the east/south sides; the north side is the ramp opening.
	_add_wood_box(Vector3(deck.x + 1.75, deck.y + 0.9, deck.z),
		Vector3(0.2, 0.7, 3.6), 0.0)
	_add_collider_box(Vector3(deck.x + 1.75, deck.y + 0.9, deck.z),
		Vector3(0.2, 0.7, 3.6), 0.0)
	_add_wood_box(Vector3(deck.x, deck.y + 0.9, deck.z + 1.75),
		Vector3(3.6, 0.7, 0.2), 0.0)
	_add_collider_box(Vector3(deck.x, deck.y + 0.9, deck.z + 1.75),
		Vector3(3.6, 0.7, 3.6 * 0.06), 0.0)


func _bridge() -> void:
	# The canyon floor sits ~5 m below the dune surface; the deck spans the
	# slot east-west at z = BRIDGE_Z with stone abutments on both banks.
	var west_top := height_at(-BRIDGE_HALF, BRIDGE_Z)
	var east_top := height_at(BRIDGE_HALF, BRIDGE_Z)
	var slope := atan2(east_top - west_top, BRIDGE_HALF * 2.0)
	var deck_basis := Basis(Vector3(0.0, 0.0, 1.0), slope)
	_add_collider_box_basis(Vector3(0.0, (west_top + east_top) * 0.5 - 0.1, BRIDGE_Z),
		Vector3(BRIDGE_HALF * 2.0 + 0.2, 0.2, 3.8), deck_basis)
	for i in 19:
		var x := -BRIDGE_HALF + float(i) * (BRIDGE_HALF * 2.0 / 18.0)
		var t := (x + BRIDGE_HALF) / (BRIDGE_HALF * 2.0)
		var top := lerpf(west_top, east_top, t)
		_add_instance("wood_box", Transform3D(
			Basis().scaled(Vector3(0.72, 0.16, 3.6)), Vector3(x, top - 0.08, BRIDGE_Z)))
	_hero_anchors.append(Vector3(0.0, (west_top + east_top) * 0.5, BRIDGE_Z))
	# Posts and rails follow the slope. Rails are visual; the posts carry the
	# collision so a player can still step off into the canyon.
	for x in [-6.2, -2.2, 2.2, 6.2]:
		var t := (float(x) + BRIDGE_HALF) / (BRIDGE_HALF * 2.0)
		var top := lerpf(west_top, east_top, t)
		for zsign in [-1.0, 1.0]:
			_add_wood_box(Vector3(x, top + 0.62, BRIDGE_Z + zsign * 1.78),
				Vector3(0.16, 1.24, 0.16), 0.0)
			_add_wood_box(Vector3(x, top - 0.8, BRIDGE_Z + zsign * 1.78),
				Vector3(0.18, 1.6, 0.18), 0.0)
	for zsign in [-1.0, 1.0]:
		for i in 4:
			var x0 := -6.2 + float(i) * 3.1
			var x1 := x0 + 3.1
			var t0 := (x0 + BRIDGE_HALF) / (BRIDGE_HALF * 2.0)
			var t1 := (x1 + BRIDGE_HALF) / (BRIDGE_HALF * 2.0)
			var y0 := lerpf(west_top, east_top, t0) + 1.18
			var y1 := lerpf(west_top, east_top, t1) + 1.18
			_add_wood_box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5,
				BRIDGE_Z + zsign * 1.78), Vector3(3.1, 0.14, 0.16), 0.0)
	# Stone abutments sit under the two deck ends on the canyon banks.
	var west_ground := height_at(-BRIDGE_HALF, BRIDGE_Z)
	var east_ground := height_at(BRIDGE_HALF, BRIDGE_Z)
	_add_stone_box(Vector3(-BRIDGE_HALF - 0.2, west_ground - 1.0, BRIDGE_Z),
		Vector3(2.4, 1.4, 4.4), 0.0)
	_add_stone_box(Vector3(BRIDGE_HALF + 0.2, east_ground - 1.0, BRIDGE_Z),
		Vector3(2.4, 1.4, 4.4), 0.0)

func _fallen_log() -> void:
	var base := height_at(-8.0, -14.0)
	_add_instance("log", Transform3D(
		Basis(Vector3.UP, 0.8).scaled(Vector3.ONE * 3.0),
		Vector3(-8.0, base + 0.06, -14.0)))
	_add_collider_box(Vector3(-8.0, base + 0.18, -14.0), Vector3(0.7, 0.42, 2.1), 0.8)
	_hero_anchors.append(Vector3(-8.0, base + 0.18, -14.0))


func _build_oasis_pond() -> void:
	# Shallow pond disc: visual only (no collider), so the oasis floor stays
	# fully walkable. One extra draw call.
	var floor := height_at(OASIS_X, OASIS_Z)
	var disc := MeshInstance3D.new()
	disc.name = "OasisPond"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 3.5
	cylinder.bottom_radius = 3.5
	cylinder.height = 0.1
	cylinder.radial_segments = 24
	cylinder.material = _mat_water
	disc.mesh = cylinder
	disc.position = Vector3(OASIS_X, floor + 0.05, OASIS_Z)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_props_root.add_child(disc)


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

func _scatter_dressing() -> void:
	_scatter_boulders(30)
	_scatter_mountain_rocks(120)
	_scatter_trees(16)
	_scatter_foliage("grass", 350, 1.0, 2.0, 0.4)
	_scatter_foliage("bush", 70, 1.1, 2.0, 0.45)
	_scatter_foliage("bush_large", 40, 1.2, 2.2, 0.45)
	_scatter_foliage("flower_red", 60, 0.9, 1.7, 0.35)
	_scatter_foliage("flower_yellow", 60, 0.9, 1.7, 0.35)
	_scatter_foliage("rock_small", 160, 1.0, 2.2, 0.6)
	_scatter_logs()


func _scatter_mountain_rocks(count: int) -> void:
	# A rocky rim at the toe of the dune ring breaks the smooth dune line.
	for _i in count:
		var side := _rng.randi_range(0, 3)
		var along := _rng.randf_range(-52.0, 52.0)
		var depth := _rng.randf_range(46.0, 58.0)
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
		if pos.y > 6.0 or slope_at(pos.x, pos.z) > 0.9:
			continue
		if _in_traversal_lane(pos):
			continue
		if not _is_dressing_clear(pos, 1.8):
			continue
		var key: String = ["rock_tall", "rock_large", "rock_wide"][_rng.randi_range(0, 2)]
		_add_rock(key, pos, _rng.randf_range(2.2, 4.6), _rng.randf_range(0.0, TAU), true)


func _scatter_boulders(count: int) -> void:
	for _i in count:
		var pos := _random_dressing_point(0.9)
		if pos == Vector3.INF:
			continue
		var key: String = ["rock_large", "rock_wide", "rock_tall"][_rng.randi_range(0, 2)]
		var scale_value := _rng.randf_range(1.2, 2.6)
		_add_rock(key, pos, scale_value, _rng.randf_range(0.0, TAU), true)


func _scatter_logs() -> void:
	for _i in 5:
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
	# Sparse dry palms: a few around the dunes, most clustered near the oasis
	# via the hand-placed HERO_TREES.
	for _i in count:
		var pos := _random_dressing_point(0.55)
		if pos == Vector3.INF:
			continue
		var scale_value := _rng.randf_range(2.0, 3.4)
		var key: String = ["tree_default", "tree_detailed", "tree_small",
			"tree_fat"][_rng.randi_range(0, 3)]
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
		var x := _rng.randf_range(-52.0, 52.0)
		var z := _rng.randf_range(-52.0, 52.0)
		if maxf(absf(x), absf(z)) > 52.0:
			continue
		# Keep the canyon, bridge landing, fort and pond clear.
		if absf(x - CANYON_X) < 6.0 and z > -44.0 and z < 30.0:
			continue
		if absf(z - BRIDGE_Z) < 4.0 and absf(x) < 13.0:
			continue
		if absf(x) < 12.0 and z > 28.0 and z < 48.0:
			continue
		if Vector2(x - OASIS_X, z - OASIS_Z).length() < 5.0:
			continue
		if _in_traversal_lane(Vector3(x, 0.0, z)):
			continue
		if _near_central_cover(Vector3(x, 0.0, z), 3.5):
			continue
		if slope_at(x, z) > max_slope:
			continue
		var y := height_at(x, z)
		if y > 7.0:
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
	# Keep the main mesa/bridge/fort/spawn approaches free of scatter. Hero
	# props are hand-placed and are checked separately.
	if absf(pos.z - BRIDGE_Z) < 4.0 and pos.x > -13.0 and pos.x < 13.0:
		return true
	if absf(pos.z) < 4.5 and pos.x < -15.0 and pos.x > -55.0:
		return true
	if absf(pos.z) < 4.5 and pos.x > 44.0 and pos.x < 56.0:
		return true
	if absf(pos.x) < 4.5 and pos.z > 44.0 and pos.z < 56.0:
		return true
	if absf(pos.x) < 4.5 and pos.z < -44.0 and pos.z > -56.0:
		return true
	if absf(pos.z - 38.0) < 10.0 and absf(pos.x) < 12.0:
		return true
	if Vector2(pos.x - OASIS_X, pos.z - OASIS_Z).length() < 5.0:
		return true
	if absf(pos.z + 48.0) < 6.0 and absf(pos.x) < 8.0:
		return true
	if absf(pos.z - 50.0) < 6.0 and absf(pos.x) < 8.0:
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
			# Sun-bleached sandstone retaining walls. Use a brighter authored
			# value: converting a 0.40 sRGB stone to linear gave 0.13, which
			# collapsed to near-black in shadow.
			if material_key == "grass":
				color = Color(0.72, 0.64, 0.50)
			else:
				color = Color(0.74, 0.66, 0.53)
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


func bridge_center() -> Vector3:
	return Vector3(0.0, (height_at(-BRIDGE_HALF, BRIDGE_Z) + height_at(BRIDGE_HALF, BRIDGE_Z)) * 0.5, BRIDGE_Z)


func fort_center() -> Vector3:
	return Vector3(0.0, FORT_H, 38.0)
