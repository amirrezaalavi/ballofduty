extends Node3D
## Starfall Crater — 120 x 120 m space/frost arena (map candidate 2).
##
## The height field below is the single source of truth for both the low-poly
## visual chunks and the HeightMapShape3D collision, so the headless server and
## every browser client produce the same ground. Everything is deterministic:
## scatter uses a fixed seed, hand-placed cover is static data.
##
## Layout (x east, z south):
##   centre      impact bowl (floor -3 m) with a crashed relay platform ring
##   rim         raised rim (+1.2 m at r~20 m) with 4 flattened ramp gaps N/E/S/W
##   north       wreck ridge arc (+2 m) with wreck arch pieces
##   east        flat ice field with a shallow fissure + ice bridge
##   south       glow crack (visual only, walkable, no damage)
##   edge        a rising frost mountain ring plus invisible boundary walls

const SEED := 20261030
const MAP_HALF := 60.0
const PLAY_HALF := 55.0
const CHUNK_SIZE := 40.0
const CHUNK_GRID := 3
const CHUNK_SAMPLES := 41
const VISUAL_STEP := 2
const VISUAL_SAMPLES := 21
const BOUNDARY_HEIGHT := 40.0

const CRATER_R := 19.0
const CRATER_FLOOR_R := 6.0
const CRATER_DEPTH := 2.8
const RIM_R := 20.5
const RIM_H := 1.0
const PLATFORM_R := 5.0
const DECK_LIFT := 0.55
const BRIDGE_Z := 5.0
const BRIDGE_X0 := 23.5
const BRIDGE_X1 := 36.5
const FISSURE_X := 30.0

const MODEL_DIR := "res://assets/kenney_nature/models/"
const MODELS := {
	"tree_pine": "tree_pineTallA",
	"tree_pine_round": "tree_pineRoundA",
	"rock_large": "rock_largeA",
	"rock_wide": "rock_largeC",
	"rock_tall": "rock_tallA",
	"rock_small": "rock_smallA",
	"cliff_wall": "cliff_block_stone",
	"ridge_rock": "cliff_block_rock",
	"bush": "plant_bush",
}

# Spawns are placed around the play space and then snapped to the height field.
# Scene values are close approximations; _ready() writes the exact ground height.
const SPAWN_LAYOUT := [
	Vector3(-40.0, 0.0, -36.0),
	Vector3(-2.0, 0.0, -36.0),
	Vector3(38.0, 0.0, -30.0),
	Vector3(-44.0, 0.0, 6.0),
	Vector3(30.0, 0.0, 24.0),
	Vector3(-28.0, 0.0, 38.0),
	Vector3(12.0, 0.0, 42.0),
	Vector3(12.0, 0.0, 6.0),
]

# Central cover clusters: (x, z, yaw). Kept clear of spawns, rim ramps, the
# platform ring, the fissure/bridge lane and crystal spires.
const CENTRAL_COVER := [
	Vector3(12.0, -12.0, 0.4), Vector3(-13.0, -12.0, 1.2),
	Vector3(14.0, 12.0, 2.0), Vector3(-13.0, 13.0, 0.8),
	Vector3(16.0, -4.0, 2.6), Vector3(-16.0, 5.0, 1.6),
]

# Six emissive crystal spires: (x, z). All off-axis so the four rim ramp lanes
# stay clear, and away from spawns, the fissure and the bridge lane.
const CRYSTALS := [
	Vector3(20.0, 0.0, -20.0), Vector3(-22.0, 0.0, -16.0), Vector3(24.0, 0.0, 16.0),
	Vector3(-20.0, 0.0, 24.0), Vector3(10.0, 0.0, -30.0), Vector3(-12.0, 0.0, 34.0),
]

# Hand-placed cover. Only (x, z) drive the layout; y comes from the height field.
const HERO_TREES := [
	Vector3(-34.0, -28.0, 3.0), Vector3(-38.0, 20.0, 3.4),
	Vector3(-48.0, -18.0, 3.8), Vector3(44.0, -22.0, 3.0),
	Vector3(46.0, 30.0, 3.6), Vector3(-10.0, 46.0, 2.8),
	Vector3(24.0, 44.0, 3.0), Vector3(-46.0, -30.0, 3.4),
	Vector3(8.0, -44.0, 3.0), Vector3(-24.0, -44.0, 3.2),
]
const HERO_ROCKS := [
	Vector3(-28.0, -14.0, 3.0), Vector3(-10.0, 24.0, 2.6),
	Vector3(14.0, -22.0, 2.8), Vector3(22.0, 30.0, 2.6),
	Vector3(42.0, -14.0, 3.2), Vector3(-48.0, 28.0, 2.8),
	Vector3(44.0, 6.0, 3.0), Vector3(-32.0, 30.0, 2.6),
	Vector3(-18.0, -32.0, 3.2), Vector3(20.0, -36.0, 2.8),
	Vector3(36.0, 38.0, 2.6), Vector3(-4.0, 48.0, 2.6),
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
var _mat_wreck: StandardMaterial3D
var _mat_ice: StandardMaterial3D
var _mat_crystal: StandardMaterial3D
var _mat_glow: StandardMaterial3D


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
	_build_platform_ring()
	_build_crystals()
	_build_bridge()
	_build_arches()
	_place_hero_props()
	_scatter_dressing()
	_build_multimeshes()
	_build_colliders()
	set_process(false)


# --- height field ---------------------------------------------------------

## Height in metres at world (x, z). The visual chunk vertices and the
## HeightMapShape3D collision are both sampled from this function.
static func height_at(x: float, z: float) -> float:
	var radius := sqrt(x * x + z * z)
	# Gentle outer swells. Kept small so the plain reads calm under the frost.
	var h := 0.25 * sin(x * 0.09) * cos(z * 0.08) + 0.12 * sin((x + z) * 0.21)

	# Impact bowl: flat floor at -DEPTH inside 6 m, smooth rise to the plain
	# at 18 m. Peak gradient is ~0.38, comfortably walkable without ramps.
	var bowl := 1.0 - smoothstep(CRATER_FLOOR_R, CRATER_R, radius)
	h += -CRATER_DEPTH * bowl

	# Raised rim ring at ~20.5 m. Peak gradient is ~0.4, walkable all around;
	# the four axis gaps below flatten it into true ramps.
	var rim := RIM_H * exp(-pow((radius - RIM_R) / 2.6, 2.0))
	var gap := ramp_gap(x, z)
	if gap > 0.0:
		rim *= 1.0 - gap
		# In the gap lanes the ground is the pure bowl profile: no swells,
		# no rim. The lane is flat across (>=3.2 m) with soft feathers.
		var lane := -CRATER_DEPTH * bowl
		h = lerpf(h, lane, gap)
	h += rim

	# North wreck ridge: a broad +2 m arc. Sigma 6.5 keeps the gradient ~0.26.
	var ridge_band := exp(-pow((z + 42.0) / 6.5, 2.0))
	var ridge_span := 1.0 - smoothstep(28.0, 40.0, absf(x))
	h += 2.0 * ridge_band * ridge_span

	# East ice field: flattened frost pan.
	var ice := (smoothstep(20.0, 28.0, x) * (1.0 - smoothstep(46.0, 54.0, x))
		* smoothstep(-22.0, -14.0, z) * (1.0 - smoothstep(26.0, 34.0, z)))
	if ice > 0.0:
		h = lerpf(h, 0.15, ice)

	# Shallow fissure under the ice bridge. Depth 1.2 over a 4 m half-width
	# (gradient ~0.45) so falling in is a detour, never a trap.
	var fissure_along := smoothstep(-14.0, -8.0, z) * (1.0 - smoothstep(18.0, 24.0, z))
	if fissure_along > 0.0:
		var cut := 1.0 - smoothstep(0.0, 4.0, absf(x - FISSURE_X))
		h -= 1.2 * cut * fissure_along

	# South glow crack: shallow visual groove, fully walkable, no damage.
	var crack := exp(-pow((z - 30.0) / 1.6, 2.0)) * (1.0 - smoothstep(16.0, 22.0, absf(x)))
	h -= 0.5 * crack

	# Frost mountain ring. A steady 0.5 grade from 52 to 60 m; the invisible
	# boundary walls at +-55 stop players well before the crest.
	var edge := maxf(absf(x), absf(z))
	var ring := 0.0
	if edge > 52.0:
		ring = 4.0 * clampf((edge - 52.0) / 8.0, 0.0, 1.0)
		ring += ring * 0.02 * (sin(x * 0.17) + cos(z * 0.21))
	if ring > 0.001:
		h = maxf(h, ring)
	return h


## 0..1 mask for the four flattened rim ramp lanes (N/E/S/W). Full-flat 3.2 m
## wide with soft feathers; only active on the rim band (r 10..28).
static func ramp_gap(x: float, z: float) -> float:
	var radius := sqrt(x * x + z * z)
	if radius < 9.0 or radius > 29.0:
		return 0.0
	var lane := maxf(1.0 - smoothstep(2.0, 4.0, absf(x)), 1.0 - smoothstep(2.0, 4.0, absf(z)))
	# Radial feather so the lane blends into the plain without a step.
	var edge := smoothstep(9.0, 11.0, radius) * (1.0 - smoothstep(27.0, 29.0, radius))
	return lane * edge


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
	var radius := sqrt(x * x + z * z)
	var n := 0.5 + 0.5 * sin(x * 0.27 + z * 0.19) * cos(x * 0.11 - z * 0.23)
	var basalt := Color(0.23, 0.25, 0.31)
	var dark := Color(0.16, 0.17, 0.23)
	var frost := Color(0.60, 0.68, 0.78)
	var ice := Color(0.62, 0.73, 0.85)
	var rock := Color(0.30, 0.32, 0.38)
	var color: Color
	if slope > 0.9:
		color = rock.lerp(dark, n * 0.4)
	elif y > 2.5 or (x > 24.0 and z > -16.0 and z < 26.0):
		# High ground and the whole east pan read as frost/ice.
		color = basalt.lerp(frost, 0.45 + n * 0.35)
		if x > 24.0 and z > -16.0 and z < 26.0:
			color = color.lerp(ice, 0.45)
	elif radius < CRATER_FLOOR_R + 1.0:
		color = dark.lerp(basalt, n * 0.4)
	else:
		color = basalt.lerp(frost, (n * 0.35 + clampf(y * 0.08, 0.0, 0.2)))
	# Warm tint hugging the south glow crack.
	var crack := exp(-pow((z - 30.0) / 2.5, 2.0)) * (1.0 - smoothstep(16.0, 22.0, absf(x)))
	if crack > 0.01:
		color = color.lerp(Color(0.48, 0.30, 0.18), crack * 0.55)
	var fleck := 0.03 * sin(x * 0.57 + z * 0.41) * sin(z * 0.73 - x * 0.29)
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
	_mat_terrain.resource_name = "crater_terrain"
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

	_mat_stone = _flat_material("crater_stone", Color(0.42, 0.45, 0.54))
	_mat_wreck = _flat_material("crater_wreck", Color(0.30, 0.27, 0.26))
	_mat_ice = _flat_material("crater_ice", Color(0.68, 0.78, 0.88))

	_mat_crystal = StandardMaterial3D.new()
	_mat_crystal.resource_name = "crater_crystal"
	_mat_crystal.albedo_color = Color(0.10, 0.35, 0.45)
	_mat_crystal.emission_enabled = true
	_mat_crystal.emission = Color(0.25, 0.85, 1.0)
	_mat_crystal.emission_energy_multiplier = 2.0
	_mat_crystal.roughness = 0.4

	_mat_glow = StandardMaterial3D.new()
	_mat_glow.resource_name = "crater_glow"
	_mat_glow.albedo_color = Color(0.45, 0.16, 0.05)
	_mat_glow.emission_enabled = true
	_mat_glow.emission = Color(1.0, 0.42, 0.10)
	_mat_glow.emission_energy_multiplier = 2.5
	_mat_glow.roughness = 0.6
	_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_synthetic_meshes["stone_box"] = _unit_box(_mat_stone)
	_synthetic_meshes["wreck_box"] = _unit_box(_mat_wreck)
	_synthetic_meshes["ice_box"] = _unit_box(_mat_ice)
	_synthetic_meshes["crystal_box"] = _unit_box(_mat_crystal)
	_synthetic_meshes["glow_box"] = _unit_box(_mat_glow)


func _flat_material(name: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = name
	material.albedo_color = color.srgb_to_linear()
	material.metallic = 0.0
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## Seamless frost-grain detail map. Three periodic value-noise octaves wrapped
## at the texture edge, so the 256 px texture tiles without seams.
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
			image.set_pixel(x, y, Color(value, value, value * 1.02))
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
			# shadow frustum produces self-shadow acne on the bowl walls.
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
	# deliberate low-poly crater surface instead of smooth 1 m shading bands.
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


# --- signature features -----------------------------------------------------

func _build_platform_ring() -> void:
	# Crashed relay platform: a ring of basalt deck slabs around the crater
	# floor with two ramp accesses (north/south) and a centre mast. The deck
	# is only DECK_LIFT above the floor and the ramps are long and gentle.
	var floor_y := crater_floor_y()
	var deck_top := floor_y + DECK_LIFT
	for i in 12:
		var angle := TAU * float(i) / 12.0
		var pos := Vector3(sin(angle) * PLATFORM_R, deck_top - 0.175, cos(angle) * PLATFORM_R)
		_add_instance("stone_box", Transform3D(
			Basis(Vector3.UP, angle).scaled(Vector3(3.4, 0.35, 2.6)), pos))
		_add_collider_box(pos, Vector3(3.4, 0.35, 2.6), angle)
	_hero_anchors.append(Vector3(PLATFORM_R, deck_top, 0.0))
	_hero_anchors.append(Vector3(-PLATFORM_R, deck_top, 0.0))

	# Ramps: short slabs from the deck edge down to the bowl floor. End heights
	# are sampled from the terrain so the tread always sits just above ground
	# and can never dive under it and trap the player.
	for zsign in [-1.0, 1.0]:
		var inner := 6.0
		var outer := 8.6
		var terr := height_at(0.0, zsign * outer)
		var top_outer := maxf(terr + 0.05, deck_top - 0.45)
		var mid := Vector3(0.0, (deck_top + top_outer) * 0.5, zsign * (inner + outer) * 0.5)
		var ang := atan2(deck_top - top_outer, outer - inner)
		var basis := Basis(Vector3.RIGHT, zsign * ang)
		var size := Vector3(2.6, 0.25, outer - inner + 0.6)
		_add_instance("stone_box", Transform3D(basis.scaled(size), mid + Vector3(0, -0.12, 0)))
		_add_collider_box_basis(mid + Vector3(0, -0.115, 0), size, basis)
		_hero_anchors.append(Vector3(0.0, deck_top, zsign * PLATFORM_R))

	# Centre mast: broken relay spire with a live tip light-box.
	_add_instance("wreck_box", Transform3D(
		Basis().scaled(Vector3(0.8, 5.5, 0.8)),
		Vector3(0.0, floor_y + 2.75, 0.0)))
	_add_collider_cylinder(Vector3(0.0, floor_y, 0.0), 0.45, 5.5)
	_hero_anchors.append(Vector3(0.0, floor_y + 2.75, 0.0))
	_add_instance("crystal_box", Transform3D(
		Basis().scaled(Vector3(0.5, 0.6, 0.5)),
		Vector3(0.0, floor_y + 5.8, 0.0)))
	# Low glow strip around the mast base: pure visual, no collision.
	_add_instance("glow_box", Transform3D(
		Basis().scaled(Vector3(2.2, 0.08, 2.2)),
		Vector3(0.0, floor_y + 0.10, 0.0)))


func _build_crystals() -> void:
	# Six tall thin emissive spires. Each is a synthetic box with a matching
	# analytic box collider: real cover, cheap to draw.
	for spot: Vector3 in CRYSTALS:
		var base := Vector3(spot.x, height_at(spot.x, spot.z), spot.z)
		var yaw := atan2(spot.x, spot.y) + 0.35
		var pos := base + Vector3(0.0, 2.5, 0.0)
		_add_instance("crystal_box", Transform3D(
			Basis(Vector3.UP, yaw).scaled(Vector3(1.2, 5.0, 1.2)), pos))
		_add_collider_box(pos, Vector3(1.2, 5.0, 1.2), yaw)
		_hero_anchors.append(pos)
		# Fallen shard leaning at the base: visual only, walk-over height.
		_add_instance("crystal_box", Transform3D(
			Basis(Vector3.UP, yaw + 0.9).scaled(Vector3(0.5, 0.35, 1.6)),
			base + Vector3(1.4, 0.18, 0.6)))


func _build_bridge() -> void:
	# Ice bridge across the fissure at z = BRIDGE_Z. The deck ends are exactly
	# coplanar with the bank landings (no step lips either way); the deck
	# slopes gently between them, like the quarry timber bridge.
	var west_top := height_at(BRIDGE_X0, BRIDGE_Z)
	var east_top := height_at(BRIDGE_X1, BRIDGE_Z)
	var slope := atan2(east_top - west_top, BRIDGE_X1 - BRIDGE_X0)
	var deck_basis := Basis(Vector3(0.0, 0.0, 1.0), slope)
	var mid := Vector3((BRIDGE_X0 + BRIDGE_X1) * 0.5,
		(west_top + east_top) * 0.5 - 0.1, BRIDGE_Z)
	_add_collider_box_basis(mid, Vector3(BRIDGE_X1 - BRIDGE_X0, 0.2, 3.8), deck_basis)
	for i in 19:
		var x := 23.6 + float(i) * (12.8 / 18.0)
		var t := (x - 23.6) / 12.8
		var top := lerpf(west_top, east_top, t)
		_add_instance("ice_box", Transform3D(
			Basis().scaled(Vector3(0.68, 0.16, 3.6)), Vector3(x, top - 0.08, BRIDGE_Z)))
	_hero_anchors.append(Vector3((BRIDGE_X0 + BRIDGE_X1) * 0.5,
		(west_top + east_top) * 0.5, BRIDGE_Z))
	# Frost posts: visual only (kept out of the walk lane) so the crossing
	# can never snag a sprinting player.
	for x in [24.6, 28.4, 32.2, 35.4]:
		var t := (float(x) - 23.6) / 12.8
		var top := lerpf(west_top, east_top, t)
		for zsign in [-1.0, 1.0]:
			_add_instance("ice_box", Transform3D(
				Basis().scaled(Vector3(0.16, 1.2, 0.16)),
				Vector3(x, top + 0.6, BRIDGE_Z + zsign * 1.7)))
	# Stone abutments buried under the two deck ends, tops below the tread.
	var west_ground := height_at(BRIDGE_X0 - 0.5, BRIDGE_Z)
	var east_ground := height_at(BRIDGE_X1 + 0.5, BRIDGE_Z)
	_add_stone_box(Vector3(BRIDGE_X0 - 0.5, west_ground - 1.0, BRIDGE_Z),
		Vector3(1.6, 1.2, 4.2), 0.0)
	_add_stone_box(Vector3(BRIDGE_X1 + 0.5, east_ground - 1.0, BRIDGE_Z),
		Vector3(1.6, 1.2, 4.2), 0.0)


func _build_arches() -> void:
	# Two wreck arch pieces: tilted dark-metal frames half-buried in the frost.
	_wreck_arch(Vector3(-30.0, 0.0, -20.0), 0.5)
	_wreck_arch(Vector3(18.0, 0.0, 34.0), -0.3)


func _wreck_arch(center: Vector3, yaw: float) -> void:
	var base := height_at(center.x, center.z)
	var basis := Basis(Vector3.UP, yaw)
	for side in [-1.0, 1.0]:
		var local := Vector3(side * 2.3, 1.9, 0.0)
		_add_wreck_box(center + basis * local + Vector3(0.0, base, 0.0),
			Vector3(0.9, 3.8, 1.1), yaw)
	_add_wreck_box(center + Vector3(0.0, base + 4.0, 0.0),
		Vector3(5.6, 0.7, 1.2), yaw)
	_add_wreck_box(center + basis * Vector3(1.4, 0.0, 1.4) + Vector3(0.0, base + 0.3, 0.0),
		Vector3(1.3, 0.6, 0.9), yaw + 0.3)


# --- hero cover -------------------------------------------------------------

func _place_hero_props() -> void:
	_central_cover()
	_glow_crack_strip()
	for spot: Vector3 in HERO_ROCKS:
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var key := "rock_tall" if spot.z >= 3.0 else "rock_large"
		_add_rock(key, base, spot.z, _rng.randf_range(0.0, TAU), true)
	for spot: Vector3 in HERO_TREES:
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var key: String = ["tree_pine", "tree_pine_round"][_rng.randi_range(0, 1)]
		_add_tree(key, base, spot.z)


func _central_cover() -> void:
	# Six hand-placed clusters through the mid ring. Each is a tall boulder
	# plus a broken basalt slab: enough to break sightlines without creating
	# dead ends. Positions avoid spawns, rim ramps, the platform and bridge.
	for i in CENTRAL_COVER.size():
		var spot: Vector3 = CENTRAL_COVER[i]
		var yaw := spot.z
		var base := Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		_add_rock("rock_tall" if i % 2 == 0 else "rock_large", base,
			3.0 + 0.4 * float(i % 3), yaw, true)
		_add_stone_box(base + dir * 2.0 + Vector3(0.0, 0.35, 0.0),
			Vector3(1.4, 0.7, 1.2), yaw + 0.8)


func _glow_crack_strip() -> void:
	# Emissive flow-glow laid directly on the crack floor. Pure visual, no
	# collision: the crack stays fully walkable.
	for i in 12:
		var x := -17.5 + float(i) * 3.18
		var z := 30.0 + sin(float(i) * 1.3) * 0.4
		var y := height_at(x, z) + 0.07
		_add_instance("glow_box", Transform3D(
			Basis(Vector3.UP, 0.15 * sin(float(i) * 2.1)).scaled(Vector3(3.3, 0.1, 0.9)),
			Vector3(x, y, z)))


func _add_stone_box(pos: Vector3, size: Vector3, yaw: float) -> void:
	_add_instance("stone_box", Transform3D(Basis(Vector3.UP, yaw).scaled(size), pos))
	_add_collider_box(pos, size, yaw)
	_hero_anchors.append(pos)


func _add_wreck_box(pos: Vector3, size: Vector3, yaw: float) -> void:
	_add_instance("wreck_box", Transform3D(Basis(Vector3.UP, yaw).scaled(size), pos))
	_add_collider_box(pos, size, yaw)
	_hero_anchors.append(pos)


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


# --- scatter ----------------------------------------------------------------

func _scatter_dressing() -> void:
	_scatter_ridge_pines(120)
	_scatter_boulders(24)
	_scatter_mountain_rocks(90)
	_scatter_trees(24)
	_scatter_foliage("bush", 40, 1.1, 2.0, 0.45)
	_scatter_foliage("rock_small", 140, 1.0, 2.2, 0.6)


func _scatter_mountain_rocks(count: int) -> void:
	# A rocky rim at the toe of the mountain ring breaks the smooth dune line.
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
		if pos.y > 5.0 or slope_at(pos.x, pos.z) > 0.9:
			continue
		if _in_traversal_lane(pos):
			continue
		if not _is_dressing_clear(pos, 1.8):
			continue
		if pos.y < 2.0 and _rng.randf() < 0.5:
			_add_cliff_wall(pos, Vector3(
				_rng.randf_range(2.0, 3.6), _rng.randf_range(1.6, 3.4),
				_rng.randf_range(2.0, 3.6)), _rng.randf_range(0.0, TAU))
		else:
			var key: String = ["rock_tall", "rock_large", "rock_wide"][_rng.randi_range(0, 2)]
			_add_rock(key, pos, _rng.randf_range(2.0, 4.0), _rng.randf_range(0.0, TAU), true)


func _scatter_boulders(count: int) -> void:
	for _i in count:
		var pos := _random_dressing_point(0.9)
		if pos == Vector3.INF:
			continue
		var key: String = ["rock_large", "rock_wide", "rock_tall"][_rng.randi_range(0, 2)]
		var scale_value := _rng.randf_range(1.2, 2.6)
		_add_rock(key, pos, scale_value, _rng.randf_range(0.0, TAU), true)


## Frost pines on the outer plain soften the ring silhouette and frame the
## play space without eating into the combat floor.
func _scatter_ridge_pines(count: int) -> void:
	for _i in count:
		var side := _rng.randi_range(0, 3)
		var along := _rng.randf_range(-54.0, 54.0)
		var depth := _rng.randf_range(45.0, 58.0)
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
		if pos.y > 4.0 or slope_at(pos.x, pos.z) > 0.7:
			continue
		if _in_traversal_lane(pos):
			continue
		if not _is_dressing_clear(pos, 1.6):
			continue
		var key: String = ["tree_pine", "tree_pine_round"][_rng.randi_range(0, 1)]
		_add_tree(key, pos, _rng.randf_range(2.6, 4.4))


func _scatter_trees(count: int) -> void:
	for _i in count:
		var pos := _random_dressing_point(0.55)
		if pos == Vector3.INF:
			continue
		var scale_value := _rng.randf_range(2.0, 3.4)
		var key: String = ["tree_pine", "tree_pine_round"][_rng.randi_range(0, 1)]
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
		var x := _rng.randf_range(-51.0, 51.0)
		var z := _rng.randf_range(-51.0, 51.0)
		if maxf(absf(x), absf(z)) > 51.0:
			continue
		# Keep the platform bowl, fissure/bridge lane and glow crack clear.
		if Vector2(x, z).length() < 9.0:
			continue
		if x > 21.0 and x < 39.0 and z > -1.0 and z < 11.0:
			continue
		if _in_traversal_lane(Vector3(x, 0.0, z)):
			continue
		if _near_crystal(Vector3(x, 0.0, z), 3.5):
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


func _near_crystal(pos: Vector3, radius: float) -> bool:
	for spot: Vector3 in CRYSTALS:
		if Vector2(pos.x - spot.x, pos.z - spot.z).length() < radius:
			return true
	return false


func _in_traversal_lane(pos: Vector3) -> bool:
	# Keep the rim ramps, bridge approach, platform ramps and spawn approaches
	# free of scatter. Hero props are hand-placed and checked separately.
	var radius := Vector2(pos.x, pos.z).length()
	if radius > 10.0 and radius < 28.0 and (absf(pos.x) < 4.0 or absf(pos.z) < 4.0):
		return true
	if pos.x > 20.0 and pos.x < 40.0 and pos.z > 0.0 and pos.z < 10.0:
		return true
	if absf(pos.x) < 4.0 and absf(pos.z) > 5.0 and absf(pos.z) < 13.0:
		return true
	return false


func _is_dressing_clear(pos: Vector3, clearance: float) -> bool:
	if Vector2(pos.x, pos.z).length() < 9.0:
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


# --- rendering / collision --------------------------------------------------

func _add_cliff_wall(base_pos: Vector3, size: Vector3, yaw: float) -> void:
	# cliff_block models have their origin at the bottom centre.
	_add_instance("cliff_wall", Transform3D(Basis(Vector3.UP, yaw).scaled(size), base_pos))
	_add_collider_box(base_pos + Vector3(0.0, size.y * 0.5, 0.0), size, yaw)
	_hero_anchors.append(base_pos + Vector3(0.0, size.y * 0.5, 0.0))


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
			if key.begins_with("tree") or key.begins_with("rock") or key == "cliff_wall"
				or key == "ridge_rock" or key == "stone_box" or key == "wreck_box"
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
	# Frost-night restyle: basalt rock, slate walls, ice-blue pines.
	var is_tree := model_key.begins_with("tree")
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material == null:
			continue
		var material_key := String(material.resource_name)
		var color := _restyle_color(material_key, model_key, is_tree)
		if color.a < 0.0:
			continue
		var restyled := StandardMaterial3D.new()
		restyled.resource_name = material_key
		restyled.albedo_color = color
		restyled.metallic = 0.0
		restyled.roughness = 1.0
		restyled.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mesh.surface_set_material(surface, restyled)


func _restyle_color(material_key: String, model_key: String, is_tree: bool) -> Color:
	# Returns an sRGB-authored color already converted to linear, or
	# Color(-1, -1, -1, -1) to leave the surface untouched.
	var authored := Color(-1, -1, -1, -1)
	match material_key:
		"stone":
			authored = Color(0.34, 0.36, 0.43) if model_key == "cliff_wall" else Color(0.30, 0.32, 0.39)
		"dirt":
			authored = Color(0.26, 0.28, 0.35)
		"grass":
			authored = Color(0.42, 0.50, 0.60) if is_tree else Color(0.38, 0.44, 0.52)
		"leafsGreen":
			authored = Color(0.55, 0.70, 0.85) if is_tree else Color(0.40, 0.48, 0.55)
		"leafsDark":
			authored = Color(0.38, 0.55, 0.72) if is_tree else Color(0.32, 0.40, 0.48)
		"woodBark", "woodBarkDark":
			authored = Color(0.22, 0.20, 0.24)
		"woodInner":
			authored = Color(0.35, 0.30, 0.28)
		"colorRed":
			authored = Color(0.55, 0.65, 0.80)
		"colorYellow":
			authored = Color(0.70, 0.78, 0.88)
		"_defaultMat":
			authored = Color(0.70, 0.78, 0.88)
		_:
			return Color(-1, -1, -1, -1)
	return authored.srgb_to_linear()


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


# --- test / report hooks ----------------------------------------------------

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


## Flat crater floor height (the bowl interior).
static func crater_floor_y() -> float:
	return -CRATER_DEPTH


## Rim crest height off the ramp lanes (diagonal bearing, no gap flattening).
static func rim_y() -> float:
	return height_at(14.5, -14.5)


## Ice bridge deck height at mid-span.
static func bridge_deck_y() -> float:
	var west_top := height_at(BRIDGE_X0, BRIDGE_Z)
	var east_top := height_at(BRIDGE_X1, BRIDGE_Z)
	return (west_top + east_top) * 0.5
