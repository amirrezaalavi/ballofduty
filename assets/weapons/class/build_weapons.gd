extends SceneTree
## One-time build for the five Phase 2A class weapons.
##
##   ./tools/godot --headless --path . --script res://assets/weapons/class/build_weapons.gd
##
## Outputs `assets/weapons/class/<class>.scn`. Each wrapper has its origin at
## the hand grip and points the business end down -Z so it slots straight into
## the existing `Visual/GunMount` / `Muzzle` contract.
##
## KayKit Adventurers supplies staff, crossbow, axe and arrow. The spear and
## bow are Quaternius CC0 models (Poly Pizza), scaled to the same hand-grip
## contract. All meshes are shadowless like the characters.

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


# --- Knight: Quaternius spear ---------------------------------------------

func _build_knight_spear() -> void:
	var root := _root("KnightSpear")
	root.set_meta("proxy", false)
	root.set_meta("provenance", "https://poly.pizza/m/fH1zmvjPNx (Quaternius, CC0)")
	root.set_meta("weapon_length_m", 1.465)
	# Quaternius spear is authored along +Y. Lay it down -Z, scale the 9.72 m
	# source to a 1.46 m javelin, and slide it so the hand grips the balance
	# point (the shaft also projects behind the hand, so it reads from the
	# third-person camera instead of pointing straight away).
	var xf := Transform3D(
		Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3.ONE * 0.15),
		Vector3(0.0, 0.04, 0.35)
	)
	_add_source(root, "spear.glb", "SpearModel", xf)
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


# --- Rogue: Quaternius bow + KayKit arrow --------------------------------

func _build_rogue_bow() -> void:
	var root := _root("RogueBow")
	root.set_meta("proxy", false)
	root.set_meta("provenance", "https://poly.pizza/m/QnpqjLSKFU (Quaternius, CC0); arrow KayKit arrow.gltf")
	root.set_meta("weapon_length_m", 0.72)
	# Quaternius bow is authored along +Y (1.97 m). Scale to a 0.71 m recurve and
	# keep its X-Y plane facing the third-person camera; yawing it 90 degrees
	# made the bow edge-on and effectively invisible. The KayKit arrow stays
	# nocked along -Z for the release path.
	var xf := Transform3D(
		Basis.from_scale(Vector3.ONE * 0.36),
		Vector3(0.02, 0.01, -0.05)
	)
	_add_source(root, "bow.glb", "BowModel", xf)
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
