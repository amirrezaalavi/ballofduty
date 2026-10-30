extends Node3D
## Jungle Ruins — 120 x 120 m Phase 2B map candidate.
##
## The height field below is the single source of truth for both the low-poly
## visual chunks and the HeightMapShape3D collision, so the headless server and
## every browser client produce the same ground. Everything is deterministic:
## scatter uses a fixed seed, hand-placed cover is static data, and the vine
## tunnel is built from the same constants on every peer.
##
## Layout (x east, z south):
##   centre      stepped temple on a 2 m plateau, 4 ramp accesses N/E/S/W
##   east        winding shallow river with a vine bridge at z = 6
##   south-east  root-arch vine tunnel through a rock ridge (20 m bore)
##   lanes       fallen colossi (logs + stone rows) as cover
##   edge        a rising jungle ridge plus invisible boundary/camera walls

const SEED := 20261103
const MAP_HALF := 60.0
const PLAY_HALF := 55.0
const CHUNK_SIZE := 40.0
const CHUNK_GRID := 3
const CHUNK_SAMPLES := 41
const VISUAL_STEP := 2
const VISUAL_SAMPLES := 21
const BOUNDARY_HEIGHT := 40.0

# Tunnel constants are public for tests and for the arena budget report.
const TUNNEL_X := 38.0
const TUNNEL_Z := -20.0
const TUNNEL_HALF_LEN := 10.0
const TUNNEL_HALF_WIDTH := 2.8
const TUNNEL_HEIGHT := 4.2
const TUNNEL_LINING := 0.6
const TUNNEL_FLOOR := 0.5

const BRIDGE_Z := 6.0
const BRIDGE_X0 := 8.0
const BRIDGE_X1 := 26.0

const MODEL_DIR := "res://assets/kenney_nature/models/"
const PALETTE := {
	"grass": Color(0.250980, 0.549020, 0.219608),
	"leafsGreen": Color(0.160784, 0.450980, 0.180784),
	"leafsDark": Color(0.100784, 0.320784, 0.140784),
	"woodBark": Color(0.300784, 0.200784, 0.120784),
	"woodBarkDark": Color(0.220784, 0.140784, 0.090784),
	"woodInner": Color(0.520784, 0.380784, 0.220784),
	"dirt": Color(0.330784, 0.260784, 0.170784),
	"stone": Color(0.450784, 0.470784, 0.380784),
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
	Vector3(-38.0, 0.5, -36.0),  # south-west jungle
	Vector3(-40.0, 0.5, 8.0),    # west lane
	Vector3(-20.0, 0.5, 38.0),   # north-west grove
	Vector3(8.0, 0.5, 44.0),     # north shore
	Vector3(36.0, 0.5, 36.0),    # north-east ruins
	Vector3(40.0, 0.5, -2.0),    # east bank by the bridge
	Vector3(8.0, 0.5, -40.0),    # south field
	Vector3(-14.0, 0.5, -6.0),   # west temple approach
]

# Mid-map lane cover: (x, z, yaw). Kept clear of spawns, ramps, the river
# channel, the bridge lane and the tunnel approaches.
const JUNGLE_COVER := [
	Vector3(-18.0, -18.0, 0.4), Vector3(4.0, -18.0, 2.0),
	Vector3(10.0, 26.0, 1.2), Vector3(-24.0, 6.0, 0.8),
	Vector3(28.0, -34.0, 2.6), Vector3(-32.0, -28.0, 1.6),
	Vector3(0.0, -34.0, 2.4), Vector3(-10.0, 16.0, 0.2),
]

# Hand-placed cover. Only (x, z) drive the layout; y comes from the height field.
const HERO_TREES := [
	Vector3(-30.0, -30.0, 3.4), Vector3(-45.0, -10.0, 3.8),
	Vector3(-48.0, 25.0, 3.6), Vector3(-30.0, 30.0, 3.2),
	Vector3(-5.0, 35.0, 3.0), Vector3(26.0, 42.0, 3.2),
	Vector3(45.0, 25.0, 3.6), Vector3(20.0, -38.0, 3.4),
	Vector3(-15.0, -42.0, 3.0), Vector3(-35.0, -18.0, 3.2),
	Vector3(2.0, -28.0, 3.0), Vector3(-15.0, 10.0, 3.4),
	Vector3(-2.0, -14.0, 3.0), Vector3(34.0, 2.0, 3.2),
]
const HERO_ROCKS := [
	Vector3(-22.0, -32.0, 2.8), Vector3(-44.0, -24.0, 3.0),
	Vector3(-38.0, 32.0, 2.6), Vector3(-8.0, 28.0, 2.8),
	Vector3(6.0, 32.0, 2.6), Vector3(34.0, 30.0, 3.0),
	Vector3(46.0, 10.0, 2.8), Vector3(44.0, -38.0, 3.0),
	Vector3(-8.0, -38.0, 2.6), Vector3(-28.0, -2.0, 3.0),
	Vector3(8.0, 16.0, 2.6), Vector3(-20.0, -22.0, 2.8),
]

# Fallen colossi: (x, z, yaw). Each is a mossy log plus a flanking stone row.
const COLOSSI := [
	Vector3(-25.0, -12.0, 0.8), Vector3(-28.0, 18.0, 2.1),
	Vector3(-12.0, 25.0, 1.4), Vector3(30.0, 16.0, 0.3),
	Vector3(-6.0, -30.0, 2.8), Vector3(24.0, -32.0, 1.9),
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
var _tunnel_root: Node3D
var _boundary_root: Node3D
var _mat_terrain: StandardMaterial3D
var _mat_stone: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_tunnel: StandardMaterial3D
var _environment: Environment
var _base_ambient := 0.5
var _ambient_target := 0.5
var _tunnel_active := false


func _ready() -> void:
	_props_root = _node_or_new("Props")
	_terrain_root = _node_or_new("Terrain")
	_tunnel_root = _node_or_new("Tunnel")
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
	_build_tunnel()
	_dress_tunnel_ridge()
	_place_hero_props()
	_scatter_dressing()
	_build_multimeshes()
	_build_colliders()
	_connect_tunnel_atmosphere()
	set_process(false)


# --- height field ---------------------------------------------------------

## River centre line: a winding north-south channel east of the temple.
static func river_x(z: float) -> float:
	return 16.0 + 6.0 * sin(z * 0.08)


## Height in metres at world (x, z). The visual chunk vertices and the
## HeightMapShape3D collision are both sampled from this function.
static func height_at(x: float, z: float) -> float:
	# Gentle jungle hills. Everything else is layered on top with max(), so
	# the walkable routes never dip below the surrounding ground.
	var h := (0.55 * sin(x * 0.09 + 0.7) * cos(z * 0.08 - 0.4)
		+ 0.30 * sin((x - z) * 0.13 + 1.1)
		+ 0.12 * sin(x * 0.31) * cos(z * 0.27))

	# Central temple plateau: flat 2 m top with a soft square footprint.
	var plateau := 2.0 * (1.0 - smoothstep(8.0, 11.0, maxf(absf(x), absf(z))))
	h = maxf(h, plateau)

	# Four walkable ramp accesses N/E/S/W. Each corridor descends 2 m over
	# 13 m (about 9 degrees), well inside the controller climb limits.
	h = _apply_ramp(h, x, z)

	# Winding shallow river cut, 1.2 m deep with soft banks. The ford is a
	# deliberate slowdown, not a trap: banks stay walkable everywhere.
	var cut := 1.0 - smoothstep(0.0, 3.5, absf(x - river_x(z)))
	if cut > 0.0:
		h -= 1.2 * cut

	# Flatten the two tunnel mouths into aprons. Without this the west mouth
	# sits on a hill shoulder and the east mouth has a half-metre lip; both
	# become real entry steps.
	var apron := _tunnel_apron(x, z)
	if apron > 0.0:
		h = lerpf(h, TUNNEL_FLOOR, apron)
	if (absf(z - TUNNEL_Z) < TUNNEL_HALF_WIDTH + 0.6
			and absf(x - TUNNEL_X) < TUNNEL_HALF_LEN + 1.0):
		h = TUNNEL_FLOOR

	# Jungle ridge ring. Flat shelves at 5 / 11 m are separated by steep faces,
	# so the edge reads as a forested ridge rather than a smooth dune. The
	# invisible boundary sits on the first shelf.
	var edge := maxf(absf(x), absf(z))
	var ring := _ring_height(edge)
	if ring > 0.001:
		ring += ring * 0.012 * (sin(x * 0.17) + cos(z * 0.21))
		if edge > 58.0:
			# Break the outer crest silhouette; this is outside the playable
			# boundary, so it does not affect movement routes.
			ring += 1.2 * sin(x * 0.11 + z * 0.07) + 0.8 * cos(x * 0.17 - z * 0.09)
		h = maxf(h, ring)
	return h


## One ramp corridor per axis; the lane mask feathers the edges so the ramp
## melts into the surrounding hills without a lip.
static func _apply_ramp(h: float, x: float, z: float) -> float:
	var corridors := [
		Vector2(x, z), Vector2(-x, z), Vector2(z, x), Vector2(-z, x),
	]
	for corridor: Vector2 in corridors:
		var along := corridor.x
		var lateral := corridor.y
		if along < 6.0 or along > 21.0:
			continue
		if absf(lateral) > 4.0:
			continue
		var ramp_h := minf(2.0, 2.0 * clampf((20.0 - along) / 13.0, 0.0, 1.0))
		var lane := 1.0 - smoothstep(2.5, 4.0, absf(lateral))
		h = lerpf(h, maxf(h, ramp_h), lane)
	return h


static func _ring_height(edge: float) -> float:
	if edge <= 53.0:
		return 0.0
	if edge < 55.5:
		return 5.0 * (edge - 53.0) / 2.5
	if edge < 57.0:
		return 5.0
	if edge < 59.0:
		return 5.0 + 6.0 * (edge - 57.0) / 2.0
	return 11.0


static func terrain_normal(x: float, z: float) -> Vector3:
	const E := 0.8
	var dx := height_at(x + E, z) - height_at(x - E, z)
	var dz := height_at(x, z + E) - height_at(x, z - E)
	return Vector3(-dx, 2.0 * E, -dz).normalized()


static func _tunnel_apron(x: float, z: float) -> float:
	var zt := 1.0 - smoothstep(5.0, 9.0, absf(z - TUNNEL_Z))
	if zt <= 0.0:
		return 0.0
	var xt := 1.0 - smoothstep(
		TUNNEL_HALF_LEN + 1.0, TUNNEL_HALF_LEN + 15.0, absf(x - TUNNEL_X))
	return zt * xt


static func slope_at(x: float, z: float) -> float:
	const E := 0.5
	var dx := (height_at(x + E, z) - height_at(x - E, z)) / (2.0 * E)
	var dz := (height_at(x, z + E) - height_at(x, z - E)) / (2.0 * E)
	return Vector2(dx, dz).length()


static func terrain_color(x: float, z: float, y: float, slope: float) -> Color:
	var n := 0.5 + 0.5 * sin(x * 0.27 + z * 0.19) * cos(x * 0.11 - z * 0.23)
	var moisture := 1.0 - smoothstep(1.5, 7.0, absf(x - river_x(z)))
	var deep := Color(0.16, 0.35, 0.13)
	var leaf := Color(0.25, 0.50, 0.20)
	var moss := Color(0.35, 0.45, 0.22)
	var dirt := Color(0.35, 0.28, 0.18)
	var stone := Color(0.50, 0.50, 0.46)
	var ruin := Color(0.55, 0.54, 0.48)
	var ridge := Color(0.30, 0.36, 0.22)
	var color: Color
	if y > 9.0:
		color = ridge.lerp(stone, n * 0.5)
	elif slope > 1.1:
		color = stone.lerp(moss, n * 0.4)
	elif maxf(absf(x), absf(z)) < 12.5:
		# Trampled mossy stone around the temple esplanade.
		color = ruin.lerp(moss, n * 0.55)
	elif moisture > 0.05:
		color = deep.lerp(leaf, n * 0.6).lerp(dirt, (1.0 - moisture) * 0.35)
	elif y > 4.5:
		color = moss.lerp(leaf, n * 0.5)
	else:
		color = leaf.lerp(dirt, n * 0.4)
	# Broad patches only; fine per-metre noise shimmers at distance.
	var fleck := 0.035 * sin(x * 0.57 + z * 0.41) * sin(z * 0.73 - x * 0.29)
	# Vertex colours are linear in the renderer; authored values are sRGB.
	var authored := Color(
		clampf(color.r + fleck, 0.0, 1.0),
		clampf(color.g + fleck, 0.0, 1.0),
		clampf(color.b + fleck * 0.8, 0.0, 1.0)
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
	_mat_terrain.resource_name = "jungle_terrain"
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

	_mat_stone = _flat_material("jungle_stone", Color(0.62, 0.63, 0.52))
	_mat_wood = _flat_material("jungle_wood", Color(0.48, 0.34, 0.20))
	_mat_tunnel = _flat_material("jungle_tunnel", Color(0.50, 0.52, 0.40))

	_synthetic_meshes["stone_box"] = _unit_box(_mat_stone)
	_synthetic_meshes["wood_box"] = _unit_box(_mat_wood)
	_synthetic_meshes["tunnel_lining"] = _unit_box(_mat_tunnel)


func _flat_material(material_name: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = material_name
	material.albedo_color = color.srgb_to_linear()
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## Seamless leaf-litter detail map. Three periodic value-noise octaves (8, 16
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
			# shadow frustum produces self-shadow acne across the hills.
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
	# deliberate low-poly jungle floor instead of smooth 1 m shading bands.
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


# --- vine tunnel ------------------------------------------------------------

func _build_tunnel() -> void:
	var bore_top := TUNNEL_FLOOR + TUNNEL_HEIGHT
	# Visual lining: a continuous inner tube, so the player never sees the
	# hollow space between the inner and outer shell.
	var segments := 7
	var length := (TUNNEL_HALF_LEN * 2.0 + 1.4) / float(segments)
	for i in segments:
		var tunnel_cx := -TUNNEL_HALF_LEN - 0.7 + length * (float(i) + 0.5) + TUNNEL_X
		_add_instance("tunnel_lining", Transform3D(
			Basis().scaled(Vector3(length + 0.18, 0.7, TUNNEL_HALF_WIDTH * 2.0 + 0.8)),
			Vector3(tunnel_cx, bore_top + 0.35, TUNNEL_Z)))
		for side in [-1.0, 1.0]:
			_add_instance("tunnel_lining", Transform3D(
				Basis().scaled(Vector3(length + 0.18, TUNNEL_HEIGHT, TUNNEL_LINING)),
				Vector3(tunnel_cx, TUNNEL_FLOOR + TUNNEL_HEIGHT * 0.5,
					TUNNEL_Z + side * (TUNNEL_HALF_WIDTH + TUNNEL_LINING * 0.5))))
		# Root ribs break up the long wall and give the tunnel a grown feel.
		if i % 2 == 0:
			for side in [-1.0, 1.0]:
				_add_instance("tunnel_lining", Transform3D(
					Basis().scaled(Vector3(0.8, TUNNEL_HEIGHT, 0.35)),
					Vector3(tunnel_cx, TUNNEL_FLOOR + TUNNEL_HEIGHT * 0.5,
						TUNNEL_Z + side * (TUNNEL_HALF_WIDTH - 0.05))))

	# Portal collars: thick root-arch rings at both mouths, flanked by great trees.
	for side in [-1.0, 1.0]:
		var px: float = TUNNEL_X + side * (TUNNEL_HALF_LEN + 1.3)
		for zsign in [-1.0, 1.0]:
			_add_stone_box(
				Vector3(px, bore_top - 2.0, TUNNEL_Z + zsign * (TUNNEL_HALF_WIDTH + 0.8)),
				Vector3(1.6, 5.2, 1.4), 0.0)
			var root_base := Vector3(
				px + side * 2.2, height_at(px + side * 2.2,
					TUNNEL_Z + zsign * (TUNNEL_HALF_WIDTH + 2.2)),
				TUNNEL_Z + zsign * (TUNNEL_HALF_WIDTH + 2.2))
			_add_tree("tree_fat", root_base, 3.4 + _rng.randf_range(0.0, 0.8))
		_add_stone_box(Vector3(px, bore_top + 0.65, TUNNEL_Z),
			Vector3(1.6, 1.3, TUNNEL_HALF_WIDTH * 2.0 + 3.4), 0.0)
		_add_stone_box(Vector3(px, bore_top + 1.4, TUNNEL_Z),
			Vector3(2.4, 0.6, TUNNEL_HALF_WIDTH * 2.0 + 5.0), 0.0)

	# Outer rock shell. Blocks are deliberately oversized and overlap: the
	# overlapping "rock skirt" hides every seam and stops any sky leak.
	for x in range(26, 52, 4):
		for y: float in [0.0, 3.8, 7.6]:
			for zsign: float in [-1.0, 1.0]:
				var px := float(x) + _rng.randf_range(-0.5, 0.5)
				var py := y + _rng.randf_range(-0.25, 0.25)
				var sx := 4.5 + _rng.randf_range(-0.7, 0.9)
				var sy := 4.4 + _rng.randf_range(-0.7, 0.8)
				var sz := 4.6 + _rng.randf_range(-0.7, 0.9)
				var pz := TUNNEL_Z + zsign * (TUNNEL_HALF_WIDTH + 7.4) + _rng.randf_range(-0.6, 0.6)
				_add_instance("ridge_rock", Transform3D(
					Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)).scaled(
						Vector3(sx, sy, sz)),
					Vector3(px, py, pz)))
		for z in range(-30, -9, 4):
			var px := float(x) + _rng.randf_range(-0.5, 0.5)
			var pz := float(z) + _rng.randf_range(-0.5, 0.5)
			_add_instance("ridge_rock", Transform3D(
				Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12)).scaled(
					Vector3(4.6, 3.2, 4.6)),
				Vector3(px, bore_top + 6.1 + _rng.randf_range(-0.3, 0.3), pz)))

	# End facades: blocks around the mouth, never across the opening.
	for xsign in [-1.0, 1.0]:
		for z in range(-30, -9, 4):
			for y in [0.0, 3.8, 7.6]:
				if absf(float(z) - TUNNEL_Z) < 6.2 and y < 4.7:
					continue
				if y > 4.7 and absf(float(z) - TUNNEL_Z) < 2.0:
					continue
				_add_instance("ridge_rock", Transform3D(
					Basis(Vector3.UP, _rng.randf_range(-0.1, 0.1)).scaled(
						Vector3(4.5, 4.3, 4.6)),
					Vector3(TUNNEL_X + xsign * 12.2 + _rng.randf_range(-0.3, 0.3),
						y + _rng.randf_range(-0.25, 0.25),
						float(z) + _rng.randf_range(-0.35, 0.35))))

	# Rock skirts at the mouths, on the ground, to hide the shell/terrain seam.
	for xsign in [-1.0, 1.0]:
		for zoff in [-8.0, -5.5, 5.5, 8.0]:
			var mx: float = TUNNEL_X + xsign * (TUNNEL_HALF_LEN + 4.0)
			var base := Vector3(mx, height_at(mx, TUNNEL_Z + zoff), TUNNEL_Z + zoff)
			_add_rock("rock_tall" if absf(zoff) < 7.0 else "rock_wide", base,
				3.0 + _rng.randf_range(0.0, 1.2), _rng.randf_range(0.0, TAU), true)
		for zsign in [-1.0, 1.0]:
			var mx: float = TUNNEL_X + xsign * (TUNNEL_HALF_LEN + 2.5)
			var base := Vector3(mx, height_at(mx, TUNNEL_Z + zsign * 4.2),
				TUNNEL_Z + zsign * 4.2)
			_add_rock("rock_large", base, 2.6, _rng.randf_range(0.0, TAU), true)

	# Collision: solid ridge with one clean 5.6 x 4.2 m bore.
	var mid_y := TUNNEL_FLOOR + TUNNEL_HEIGHT * 0.5
	_add_collider_box(Vector3(TUNNEL_X, mid_y, TUNNEL_Z - (TUNNEL_HALF_WIDTH + 6.0)),
		Vector3(TUNNEL_HALF_LEN * 2.0 + 4.0, 11.0, 12.0), 0.0)
	_add_collider_box(Vector3(TUNNEL_X, mid_y, TUNNEL_Z + (TUNNEL_HALF_WIDTH + 6.0)),
		Vector3(TUNNEL_HALF_LEN * 2.0 + 4.0, 11.0, 12.0), 0.0)
	_add_collider_box(Vector3(TUNNEL_X, bore_top + 4.0, TUNNEL_Z),
		Vector3(TUNNEL_HALF_LEN * 2.0 + 4.0, 8.0, 30.0), 0.0)
	for xsign in [-1.0, 1.0]:
		_add_collider_box(Vector3(TUNNEL_X + xsign * (TUNNEL_HALF_LEN + 1.3), bore_top + 3.2, TUNNEL_Z),
			Vector3(1.8, 6.4, 26.0), 0.0)
	# Floor and ceiling are separate from the solid mass above.
	_add_collider_box(Vector3(TUNNEL_X, TUNNEL_FLOOR - 0.25, TUNNEL_Z),
		Vector3(TUNNEL_HALF_LEN * 2.0 + 3.0, 0.5, TUNNEL_HALF_WIDTH * 2.0), 0.0)
	_add_collider_box(Vector3(TUNNEL_X, bore_top + 0.35, TUNNEL_Z),
		Vector3(TUNNEL_HALF_LEN * 2.0 + 3.0, 0.7, TUNNEL_HALF_WIDTH * 2.0), 0.0)
	for zsign in [-1.0, 1.0]:
		_add_collider_box(
			Vector3(TUNNEL_X, mid_y, TUNNEL_Z + zsign * (TUNNEL_HALF_WIDTH + TUNNEL_LINING * 0.5)),
			Vector3(TUNNEL_HALF_LEN * 2.0 + 3.0, TUNNEL_HEIGHT, TUNNEL_LINING), 0.0)

	# Soft green-gold lamps. They are cheap (3 omnis, no shadows) and give the
	# tunnel a readable light/shade rhythm without a second light rig.
	var light_root := Node3D.new()
	light_root.name = "Lights"
	_tunnel_root.add_child(light_root)
	var lamp_positions := [
		Vector3(TUNNEL_X - 7.0, bore_top - 1.0, TUNNEL_Z),
		Vector3(TUNNEL_X, bore_top - 1.0, TUNNEL_Z),
		Vector3(TUNNEL_X + 7.0, bore_top - 1.0, TUNNEL_Z),
	]
	for i in lamp_positions.size():
		var light := OmniLight3D.new()
		light.name = "TunnelLamp_%d" % i
		light.position = lamp_positions[i]
		light.light_color = Color(0.65, 1.0, 0.55) if i != 1 else Color(1.0, 0.85, 0.55)
		light.light_energy = 1.6
		light.omni_range = 14.0
		light.shadow_enabled = false
		light_root.add_child(light)


func _connect_tunnel_atmosphere() -> void:
	var area := get_node_or_null("Tunnel/TunnelInterior") as Area3D
	if area:
		area.body_entered.connect(_on_tunnel_body_entered)
		area.body_exited.connect(_on_tunnel_body_exited)
	var world_env := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		_environment = world_env.environment
		_base_ambient = _environment.ambient_light_energy
		_ambient_target = _base_ambient


func _on_tunnel_body_entered(body: Node) -> void:
	if not _is_local_player(body):
		return
	_tunnel_active = true
	_ambient_target = _base_ambient * 0.6
	set_process(true)


func _on_tunnel_body_exited(body: Node) -> void:
	if not _is_local_player(body):
		return
	_tunnel_active = false
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
	_temple()
	_jungle_cover()
	_vine_bridge()
	_fallen_colossi()
	for spot: Vector3 in HERO_ROCKS:
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var key := "rock_tall" if spot.z >= 3.0 else "rock_large"
		_add_rock(key, base, spot.z, _rng.randf_range(0.0, TAU), true)
	for spot: Vector3 in HERO_TREES:
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var key: String = ["tree_default", "tree_detailed", "tree_fat", "tree_small"][
			int(abs(spot.x + spot.y)) % 4]
		_add_tree(key, base, spot.z)


## Stepped temple: two stacked stone platforms on the plateau with a south
## access ramp each and a pillared canopy on the upper terrace.
func _temple() -> void:
	var ground := height_at(0.0, 0.0)
	# Lower terrace: 12 x 12, top at plateau + 0.8.
	_add_stone_box(Vector3(0.0, ground + 0.4, 0.0), Vector3(12.0, 0.8, 12.0), 0.0)
	# Upper terrace: 6 x 6, top at plateau + 1.6.
	_add_stone_box(Vector3(0.0, ground + 1.2, 0.0), Vector3(6.0, 0.8, 6.0), 0.0)
	# South access ramps. Single sloped colliders, because this controller
	# cannot climb vertical step boxes.
	var lower_angle := atan2(1.665, 5.55)
	# Top surface meets the terrace 0.1 below its top with the end buried in
	# the platform: down-step one way, quarry-proven lip the other.
	_add_stone_box_basis(Vector3(0.0, ground - 0.12, 8.725),
		Vector3(2.4, 0.25, 5.8), Basis(Vector3.RIGHT, lower_angle))
	var upper_angle := atan2(0.933, 2.45)
	# Foot buried under the lower terrace top, top end buried in the upper
	# terrace 0.1 below its top: same down-step/lip pattern as below.
	_add_stone_box_basis(Vector3(0.0, ground + 1.07, 4.125),
		Vector3(2.4, 0.25, 2.5), Basis(Vector3.RIGHT, upper_angle))
	# Pillared canopy on the upper terrace; lintels sit above head height.
	var top := ground + 1.6
	for corner in [Vector2(-2.2, -2.2), Vector2(2.2, -2.2), Vector2(-2.2, 2.2), Vector2(2.2, 2.2)]:
		_add_stone_box(
			Vector3(corner.x, top + 1.1, corner.y), Vector3(0.9, 2.2, 0.9), 0.0)
	for zsign in [-1.0, 1.0]:
		_add_stone_box(Vector3(0.0, top + 2.45, zsign * 2.2),
			Vector3(5.6, 0.5, 1.2), 0.0)
	# Toppled blocks at the esplanade corners give asymmetric silhouette.
	_add_stone_box(Vector3(7.5, ground + 0.4, 5.5), Vector3(2.2, 0.8, 1.2), 0.5)
	_add_stone_box(Vector3(-7.0, ground + 0.35, -6.0), Vector3(1.2, 0.7, 1.4), 0.2)


func _jungle_cover() -> void:
	# Eight hand-placed clusters through the mid-map. Each is a tall boulder
	# plus a mossy wall segment and a low fallen block: enough to break
	# sightlines without creating dead ends. Positions avoid spawns, ramps,
	# the river channel, the bridge lane and the tunnel approaches.
	for i in JUNGLE_COVER.size():
		var spot: Vector3 = JUNGLE_COVER[i]
		var yaw := spot.z
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		_add_rock("rock_tall" if i % 2 == 0 else "rock_large", base,
			3.0 + 0.4 * float(i % 3), yaw, true)
		_add_cliff_wall(base + dir * 2.0,
			Vector3(1.8, 2.2 + 0.4 * float(i % 2), 3.0), yaw + 0.4)
		_add_stone_box(base + dir * 1.1 + Vector3(0.0, 0.35, 0.0),
			Vector3(1.4, 0.7, 1.2), yaw + 0.8)
		_add_stone_box(base + dir * 2.0 + Vector3(0.0, 2.35, 0.0),
			Vector3(1.0, 0.5, 1.2), yaw + 0.7)


func _vine_bridge() -> void:
	# The vine bridge spans the river at z = 6. Both banks sit at similar
	# height, so the deck only ramps gently between them.
	var west_top := height_at(BRIDGE_X0, BRIDGE_Z) + 0.3
	var east_top := height_at(BRIDGE_X1, BRIDGE_Z) + 0.3
	var span := BRIDGE_X1 - BRIDGE_X0
	var slope := atan2(east_top - west_top, span)
	var deck_basis := Basis(Vector3(0.0, 0.0, 1.0), slope)
	var mid_x := (BRIDGE_X0 + BRIDGE_X1) * 0.5
	_add_collider_box_basis(Vector3(mid_x, (west_top + east_top) * 0.5 - 0.1, BRIDGE_Z),
		Vector3(span + 0.2, 0.2, 3.6), deck_basis)
	var planks := 23
	for i in planks:
		var x := BRIDGE_X0 + float(i) * span / float(planks - 1)
		var t := (x - BRIDGE_X0) / span
		var top := lerpf(west_top, east_top, t)
		_add_instance("wood_box", Transform3D(
			Basis().scaled(Vector3(0.72, 0.16, 3.4)), Vector3(x, top - 0.08, BRIDGE_Z)))
	_hero_anchors.append(Vector3(mid_x, (west_top + east_top) * 0.5, BRIDGE_Z))
	# Posts and rails follow the slope. Rails are visual; the posts carry the
	# collision so a player can still step off into the shallows.
	for x in [9.5, 13.5, 17.0, 20.5, 24.5]:
		var t := (float(x) - BRIDGE_X0) / span
		var top := lerpf(west_top, east_top, t)
		for zsign in [-1.0, 1.0]:
			_add_wood_box(Vector3(x, top + 0.62, BRIDGE_Z + zsign * 1.68),
				Vector3(0.16, 1.24, 0.16), 0.0)
			_add_wood_box(Vector3(x, top - 0.8, BRIDGE_Z + zsign * 1.68),
				Vector3(0.18, 1.6, 0.18), 0.0)
	for zsign in [-1.0, 1.0]:
		for i in 4:
			var x0 := 9.5 + float(i) * 3.75
			var x1 := x0 + 3.75
			var t0 := (x0 - BRIDGE_X0) / span
			var t1 := (x1 - BRIDGE_X0) / span
			var y0 := lerpf(west_top, east_top, t0) + 1.18
			var y1 := lerpf(west_top, east_top, t1) + 1.18
			_add_wood_box(Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5,
				BRIDGE_Z + zsign * 1.68), Vector3(3.75, 0.14, 0.16), 0.0)
	# Stone abutments sit under the two deck ends on the banks.
	var west_ground := height_at(BRIDGE_X0, BRIDGE_Z)
	var east_ground := height_at(BRIDGE_X1, BRIDGE_Z)
	_add_stone_box(Vector3(BRIDGE_X0 + 0.2, west_ground - 1.0, BRIDGE_Z),
		Vector3(2.4, 1.4, 4.2), 0.0)
	_add_stone_box(Vector3(BRIDGE_X1 - 0.2, east_ground - 1.0, BRIDGE_Z),
		Vector3(2.4, 1.4, 4.2), 0.0)
	# Hanging vines: bushes draped along both rails, visual only.
	for x in [11.0, 15.0, 19.0, 23.0]:
		var t := (float(x) - BRIDGE_X0) / span
		var top := lerpf(west_top, east_top, t)
		for zsign in [-1.0, 1.0]:
			_add_instance("bush", Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
					Vector3.ONE * _rng.randf_range(1.0, 1.5)),
				Vector3(x, top + 0.9, BRIDGE_Z + zsign * 1.68)))


func _fallen_colossi() -> void:
	# Six fallen giants: a mossy log plus a flanking stone row. The stones sit
	# 3.2 m off the log axis, so every cluster reads as cover but never seals
	# a lane: all gaps stay above 2.5 m.
	for i in COLOSSI.size():
		var spot: Vector3 = COLOSSI[i]
		var yaw := spot.z
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-dir.z, 0.0, dir.x)
		_add_instance("log", Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 3.0),
			base + Vector3(0.0, 0.06, 0.0)))
		_add_collider_box(base + Vector3(0.0, 0.18, 0.0), Vector3(0.7, 0.42, 2.4), yaw)
		_hero_anchors.append(base + Vector3(0.0, 0.18, 0.0))
		for k in [-1.0, 1.0]:
			_add_stone_box(base + side * (k * 3.2) + dir * 0.6 + Vector3(0.0, 0.35, 0.0),
				Vector3(1.6, 0.7, 1.2), yaw + 0.3 * k)


func _add_stone_box(pos: Vector3, size: Vector3, yaw: float) -> void:
	_add_instance("stone_box", Transform3D(Basis(Vector3.UP, yaw).scaled(size), pos))
	_add_collider_box(pos, size, yaw)
	_hero_anchors.append(pos)


func _add_stone_box_basis(pos: Vector3, size: Vector3, basis: Basis) -> void:
	_add_instance("stone_box", Transform3D(basis.scaled(size), pos))
	_add_collider_box_basis(pos, size, basis)
	_hero_anchors.append(pos)


func _add_wood_box(pos: Vector3, size: Vector3, yaw: float) -> void:
	_add_instance("wood_box", Transform3D(Basis(Vector3.UP, yaw).scaled(size), pos))
	_add_collider_box(pos, size, yaw)
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

func _dress_tunnel_ridge() -> void:
	var bore_top := TUNNEL_FLOOR + TUNNEL_HEIGHT
	# Canopy and boulders break the rectangular shell silhouette and hide the
	# seam where the artificial ridge meets the terrain.
	for i in 24:
		var x := TUNNEL_X - 11.0 + float(i) * 0.95 + _rng.randf_range(-0.4, 0.4)
		var z := TUNNEL_Z - 6.0 + _rng.randf_range(0.0, 12.0)
		var key: String = ["tree_detailed", "tree_fat", "tree_default"][_rng.randi_range(0, 2)]
		_add_tree(key, Vector3(x, bore_top + 8.0, z), _rng.randf_range(2.6, 4.2))
	for i in 20:
		var x := TUNNEL_X - 12.0 + float(i) * 1.25 + _rng.randf_range(-0.4, 0.4)
		var z := TUNNEL_Z - 6.0 + _rng.randf_range(0.0, 12.0)
		_add_rock("rock_large" if i % 2 else "rock_wide", Vector3(x, bore_top + 7.9, z),
			_rng.randf_range(2.0, 3.6), _rng.randf_range(0.0, TAU), false)
	# Outcrops across the long south and north faces hide the regular block grid.
	for i in 44:
		var x := TUNNEL_X - 13.0 + _rng.randf_range(0.0, 26.0)
		var z := (TUNNEL_Z - 13.0 if i % 2 == 0 else TUNNEL_Z + 13.4) + _rng.randf_range(-0.5, 0.5)
		var y := _rng.randf_range(0.0, 6.0)
		var key: String = ["rock_tall", "rock_large", "rock_wide"][_rng.randi_range(0, 2)]
		_add_instance(key, Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(
				Vector3.ONE * _rng.randf_range(2.4, 5.0)),
			Vector3(x, y, z)))
	for i in 14:
		var x := TUNNEL_X - 14.0 + float(i) * 2.1 + _rng.randf_range(-0.5, 0.5)
		var z := TUNNEL_Z - 11.5 if i % 2 == 0 else TUNNEL_Z + 11.5
		var base := Vector3(x, height_at(x, z), z + _rng.randf_range(-1.0, 1.0))
		_add_rock("rock_tall" if i % 3 else "rock_wide", base,
			_rng.randf_range(2.4, 4.2), _rng.randf_range(0.0, TAU), true)


func _scatter_dressing() -> void:
	_scatter_canopy(110)
	_scatter_boulders(30)
	_scatter_ridge_rocks(90)
	_scatter_foliage("grass", 500, 1.0, 2.0, 0.4)
	_scatter_foliage("flower_red", 100, 0.9, 1.7, 0.35)
	_scatter_foliage("flower_yellow", 100, 0.9, 1.7, 0.35)
	_scatter_foliage("bush", 90, 1.1, 2.0, 0.45)
	_scatter_foliage("bush_large", 60, 1.2, 2.2, 0.45)
	_scatter_foliage("mushroom", 40, 1.0, 1.8, 0.4)
	_scatter_foliage("rock_small", 150, 1.0, 2.2, 0.6)
	_scatter_logs()


func _scatter_ridge_rocks(count: int) -> void:
	# A rocky rim at the toe of the jungle ridge breaks the smooth dune line.
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
		if pos.y > 7.0 or slope_at(pos.x, pos.z) > 0.9:
			continue
		if _in_traversal_lane(pos):
			continue
		if not _is_dressing_clear(pos, 1.8):
			continue
		var key: String = ["rock_tall", "rock_large", "rock_wide"][_rng.randi_range(0, 2)]
		_add_rock(key, pos, _rng.randf_range(2.2, 4.4), _rng.randf_range(0.0, TAU), true)


func _scatter_boulders(count: int) -> void:
	for _i in count:
		var pos := _random_dressing_point(0.95, true)
		if pos == Vector3.INF:
			continue
		var key: String = ["rock_large", "rock_wide", "rock_tall"][_rng.randi_range(0, 2)]
		var scale_value := _rng.randf_range(1.2, 2.6)
		_add_rock(key, pos, scale_value, _rng.randf_range(0.0, TAU), true)


func _scatter_canopy(count: int) -> void:
	# Dense jungle canopy across the whole floor, kept out of the combat lanes.
	for _i in count:
		var pos := _random_dressing_point(0.55, true)
		if pos == Vector3.INF:
			continue
		var scale_value := _rng.randf_range(2.2, 4.0)
		var key: String = ["tree_default", "tree_detailed", "tree_fat", "tree_small",
			"tree_pine_round"][_rng.randi_range(0, 4)]
		_add_tree(key, pos, scale_value)


func _scatter_logs() -> void:
	for _i in 8:
		var pos := _random_dressing_point(0.5, false)
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


func _scatter_foliage(key: String, count: int, min_scale: float, max_scale: float,
		max_slope: float) -> void:
	for _i in count:
		var pos := _random_dressing_point(max_slope, false)
		if pos == Vector3.INF:
			continue
		var scale_value := _rng.randf_range(min_scale, max_scale)
		_add_instance(key, Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value),
			pos + Vector3(0.0, 0.02, 0.0)))


func _random_dressing_point(max_slope: float, avoid_channel: bool) -> Vector3:
	for _attempt in 28:
		var x := _rng.randf_range(-52.0, 52.0)
		var z := _rng.randf_range(-52.0, 52.0)
		if maxf(absf(x), absf(z)) > 52.0:
			continue
		# Keep the temple esplanade clear of scatter.
		if maxf(absf(x), absf(z)) < 13.5:
			continue
		# Keep the ridge, tunnel mouths and bridge landing clear.
		if absf(x - TUNNEL_X) < 16.0 and absf(z - TUNNEL_Z) < 13.0:
			continue
		if x > BRIDGE_X0 - 2.0 and x < BRIDGE_X1 + 4.0 and z > BRIDGE_Z - 5.0 and z < BRIDGE_Z + 5.0:
			continue
		# Trunks and boulders stay off the river banks; ground foliage may not.
		if avoid_channel and absf(x - river_x(z)) < 4.5:
			continue
		if _in_traversal_lane(Vector3(x, 0.0, z)):
			continue
		if _near_jungle_cover(Vector3(x, 0.0, z), 3.5):
			continue
		if slope_at(x, z) > max_slope:
			continue
		var y := height_at(x, z)
		if y > 8.0:
			continue
		var pos := Vector3(x, y, z)
		if not _is_dressing_clear(pos, 1.1):
			continue
		return pos
	return Vector3.INF


func _near_jungle_cover(pos: Vector3, radius: float) -> bool:
	for spot: Vector3 in JUNGLE_COVER:
		if Vector2(pos.x - spot.x, pos.z - spot.y).length() < radius:
			return true
	for spot: Vector3 in COLOSSI:
		if Vector2(pos.x - spot.x, pos.z - spot.y).length() < radius + 2.0:
			return true
	return false


func _in_traversal_lane(pos: Vector3) -> bool:
	# Keep the main ramp/bridge/spawn approaches free of scatter. The cardinal
	# strips run to the map edge so edge walk-ins never land inside a trunk.
	# Hero props are hand-placed and are checked separately.
	if absf(pos.z) < 4.5 and absf(pos.x) < 52.0:
		return true
	if absf(pos.x) < 4.5 and absf(pos.z) < 52.0:
		return true
	if pos.x > BRIDGE_X0 - 4.0 and pos.x < BRIDGE_X1 + 10.0 and pos.z > BRIDGE_Z - 6.0 and pos.z < BRIDGE_Z + 6.0:
		return true
	if pos.x > TUNNEL_X - 16.0 and pos.x < TUNNEL_X + 20.0 and pos.z > TUNNEL_Z - 7.0 and pos.z < TUNNEL_Z + 7.0:
		return true
	if pos.x > -50.0 and pos.x < -30.0 and pos.z > -42.0 and pos.z < -30.0:
		return true
	if pos.x > -46.0 and pos.x < -34.0 and pos.z > 2.0 and pos.z < 14.0:
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
			# Ruin walls are mossy stone, not green cliff tops.
			if material_key == "grass":
				color = Color(0.350784, 0.420784, 0.250784)
			else:
				color = Color(0.500784, 0.510784, 0.420784)
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


func tunnel_entrances() -> Array:
	return [
		Vector3(TUNNEL_X - TUNNEL_HALF_LEN - 1.3, TUNNEL_FLOOR, TUNNEL_Z),
		Vector3(TUNNEL_X + TUNNEL_HALF_LEN + 1.3, TUNNEL_FLOOR, TUNNEL_Z),
	]


func tunnel_floor_y() -> float:
	return TUNNEL_FLOOR


func tunnel_ceiling_y() -> float:
	return TUNNEL_FLOOR + TUNNEL_HEIGHT


func tunnel_length() -> float:
	return TUNNEL_HALF_LEN * 2.0 + 2.6
