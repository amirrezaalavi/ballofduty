extends SceneTree
## One-time build for the five Phase 2A class weapons.
##
##   ./tools/godot --headless --path . --script res://assets/weapons/class/build_weapons.gd
##
## Outputs `assets/weapons/class/<class>.scn`. Each wrapper has its origin at
## the hand grip and points the business end down -Z so it slots straight into
## the existing `Visual/GunMount` / `Muzzle` contract.
##
## KayKit Adventurers free tier ships staff, crossbow and axe (plus an arrow),
## but no spear and no bow. Knight spear and Rogue bow are therefore marked
## low-poly proxies (`proxy=true`, `provenance=...`) built from primitives. All
## meshes are shadowless like the characters.

const OUT_DIR := "res://assets/weapons/class"
const SRC_DIR := "res://assets/weapons/class/source"

const WOOD := Color(0.36, 0.23, 0.13)
const DARK_WOOD := Color(0.24, 0.15, 0.09)
const STEEL := Color(0.62, 0.66, 0.72)
const GOLD := Color(0.72, 0.54, 0.2)
const STRING := Color(0.86, 0.86, 0.78)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_knight_spear()
	_build_mage_staff()
	_build_rogue_bow()
	_build_hooded_crossbow()
	_build_barbarian_axe()
	quit(0)


# --- Knight: spear proxy --------------------------------------------------

func _build_knight_spear() -> void:
	var root := _root("KnightSpear_Proxy")
	root.set_meta("proxy", true)
	root.set_meta("provenance", "proxy: KayKit Adventurers free tier has no spear model")
	root.set_meta("weapon_length_m", 0.795)

	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.011
	shaft.bottom_radius = 0.011
	shaft.height = 0.70
	shaft.radial_segments = 6
	shaft.rings = 2
	_add_mesh(root, "Shaft", shaft, _at(Vector3(-PI * 0.5, 0.0, 0.0), Vector3(0.0, 0.0, -0.02)), _wood())

	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.028
	tip.height = 0.13
	tip.radial_segments = 6
	_add_mesh(root, "Spearhead", tip, _at(Vector3(-PI * 0.5, 0.0, 0.0), Vector3(0.0, 0.0, -0.40)), _steel())

	for spec: Array in [[-0.27, 0.020], [0.20, 0.018]]:
		var ring := CylinderMesh.new()
		ring.top_radius = float(spec[1])
		ring.bottom_radius = float(spec[1])
		ring.height = 0.024
		ring.radial_segments = 6
		_add_mesh(
			root, "Binding", ring,
			_at(Vector3(-PI * 0.5, 0.0, 0.0), Vector3(0.0, 0.0, float(spec[0]))),
			_gold()
		)

	var butt := CylinderMesh.new()
	butt.top_radius = 0.016
	butt.bottom_radius = 0.012
	butt.height = 0.035
	butt.radial_segments = 6
	_add_mesh(
		root, "ButtCap", butt,
		_at(Vector3(-PI * 0.5, 0.0, 0.0), Vector3(0.0, 0.0, 0.315)), _gold()
	)
	_save(root, "knight_spear.scn", "knight")


# --- Mage: KayKit staff ---------------------------------------------------

func _build_mage_staff() -> void:
	var root := _root("MageStaff")
	root.set_meta("proxy", false)
	root.set_meta("provenance", "%s/staff.gltf" % SRC_DIR)
	root.set_meta("weapon_length_m", 0.776)
	# Source is 2.15 m tall (Y). Scale 0.36 and lay +Y down -Z. Grip at y=-0.15.
	var xf := Transform3D(
		Basis(Vector3.UP, 0.0).rotated(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3.ONE * 0.36),
		Vector3(-0.0154, 0.0, -0.054)
	)
	_add_source(root, "staff.gltf", "StaffModel", xf)
	_save(root, "mage_staff.scn", "mage")


# --- Rogue: bow proxy + KayKit arrow --------------------------------------

func _build_rogue_bow() -> void:
	var root := _root("RogueBow_Proxy")
	root.set_meta("proxy", true)
	root.set_meta("provenance", "proxy: KayKit Adventurers free tier has no bow model; arrow is KayKit arrow.gltf")
	root.set_meta("weapon_length_m", 0.71)

	var grip := BoxMesh.new()
	grip.size = Vector3(0.038, 0.16, 0.05)
	_add_mesh(root, "Grip", grip, _at(Vector3.ZERO, Vector3.ZERO), _dark_wood())

	var upper := BoxMesh.new()
	upper.size = Vector3(0.030, 0.30, 0.038)
	_add_mesh(
		root, "UpperLimb", upper,
		_at(Vector3(0.15, 0.0, 0.0), Vector3(0.0, 0.205, 0.0)), _wood()
	)
	var lower := BoxMesh.new()
	lower.size = Vector3(0.030, 0.30, 0.038)
	_add_mesh(
		root, "LowerLimb", lower,
		_at(Vector3(-0.15, 0.0, 0.0), Vector3(0.0, -0.205, 0.0)), _wood()
	)

	var string := CylinderMesh.new()
	string.top_radius = 0.0032
	string.bottom_radius = 0.0032
	string.height = 0.70
	string.radial_segments = 4
	_add_mesh(root, "String", string, _at(Vector3.ZERO, Vector3(0.0, 0.0, 0.055)), _string())

	# Nocked arrow borrowed from the KayKit pack; points down -Z with the bow.
	var arrow_xf := Transform3D(
		Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3.ONE * 0.62),
		Vector3(0.0, 0.0, -0.15)
	)
	_add_source(root, "arrow.gltf", "NockedArrow", arrow_xf)
	_save(root, "rogue_bow.scn", "rogue")


# --- Rogue_Hooded: KayKit hand crossbow -----------------------------------

func _build_hooded_crossbow() -> void:
	var root := _root("HoodedCrossbow")
	root.set_meta("proxy", false)
	root.set_meta("provenance", "%s/crossbow_1handed.gltf" % SRC_DIR)
	root.set_meta("weapon_length_m", 0.672)
	# Source stock runs +Z (tip at z=0.944). Yaw 180 so it points -Z, grip at z=0.10.
	var xf := Transform3D(
		Basis(Vector3.UP, PI) * Basis.from_scale(Vector3.ONE * 0.55),
		Vector3(0.0, -0.0174, 0.055)
	)
	_add_source(root, "crossbow_1handed.gltf", "CrossbowModel", xf)
	_save(root, "hooded_crossbow.scn", "rogue_hooded")


# --- Barbarian: KayKit throwing axe ---------------------------------------

func _build_barbarian_axe() -> void:
	var root := _root("BarbarianAxe")
	root.set_meta("proxy", false)
	root.set_meta("provenance", "%s/axe_1handed.gltf" % SRC_DIR)
	root.set_meta("weapon_length_m", 0.622)
	# Source handle runs Y, head at +Y. Lay it forward (-Z), grip at y=-0.10.
	var xf := Transform3D(
		Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3.ONE * 0.5),
		Vector3(0.115, 0.0, -0.05)
	)
	_add_source(root, "axe_1handed.gltf", "AxeModel", xf)
	_save(root, "barbarian_axe.scn", "barbarian")


# --- helpers --------------------------------------------------------------

func _root(node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	return root


func _at(euler: Vector3, position: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(euler), position)


func _add_source(parent: Node3D, file: String, node_name: String, xf: Transform3D) -> void:
	var packed := load("%s/%s" % [SRC_DIR, file]) as PackedScene
	if packed == null:
		push_error("cannot load %s" % file)
		return
	var inst := packed.instantiate() as Node3D
	parent.add_child(inst)
	inst.name = node_name
	inst.transform = xf
	# Own only the instance root. Owning the GLTF children too bakes a second
	# copy of every mesh into the wrapper; owning none drops the subtree.
	inst.owner = parent
	for mesh_node in inst.find_children("*", "MeshInstance3D", true, false):
		(mesh_node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_mesh(
	parent: Node3D, node_name: String, mesh: Mesh, xf: Transform3D, material: Material
) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.transform = xf
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	inst.owner = parent
	return inst


func _material(color: Color, metallic: float = 0.0, roughness: float = 0.72) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _wood() -> StandardMaterial3D:
	return _material(WOOD, 0.0, 0.85)


func _dark_wood() -> StandardMaterial3D:
	return _material(DARK_WOOD, 0.0, 0.88)


func _steel() -> StandardMaterial3D:
	return _material(STEEL, 0.55, 0.38)


func _gold() -> StandardMaterial3D:
	return _material(GOLD, 0.45, 0.45)


func _string() -> StandardMaterial3D:
	return _material(STRING, 0.0, 1.0)


func _save(root: Node3D, file: String, class_name_hint: String) -> void:
	# Do not rewrite owner on instanced GLTF subtrees: that bakes a second copy
	# of every mesh into the wrapper, doubling the draw cost.
	var scene := PackedScene.new()
	var pack_error := scene.pack(root)
	var path := "%s/%s" % [OUT_DIR, file]
	if pack_error != OK:
		push_error("pack failed for %s (%d)" % [path, pack_error])
		root.free()
		return
	var save_error := ResourceSaver.save(scene, path)
	if save_error != OK:
		push_error("save failed for %s (%d)" % [path, save_error])
	else:
		print("built %s (%s)" % [path, class_name_hint])
	root.free()
