extends SceneTree
## One-time asset build for the KayKit Phase 1 art pass.
##
##   ./tools/godot --headless --path . --script res://assets/kaykit/tools/build_assets.gd
##
## Produces:
##   assets/kaykit/adventurers/<name>.scn      merged, skinned, shadowless variants
##   assets/kaykit/animations/kaykit_medium.res full clip library (loops baked)
##   assets/kaykit/animations/kaykit_upper.res  upper-body overlay clips
##   assets/weapons/rifle/rifle.scn             M4 wrapper (0.1 scale, barrel -Z)
##
## The generated files are committed; this script exists so the merge can be
## reproduced after a source-pack update.

const SCALE := 0.32244
const CHARACTERS := [
	{"id": "knight", "src": "res://assets/kaykit/adventurers/knight.glb", "out": "res://assets/kaykit/adventurers/knight.scn", "variant": "Knight"},
	{"id": "mage", "src": "res://assets/kaykit/adventurers/mage.glb", "out": "res://assets/kaykit/adventurers/mage.scn", "variant": "Mage"},
	{"id": "rogue", "src": "res://assets/kaykit/adventurers/rogue.glb", "out": "res://assets/kaykit/adventurers/rogue.scn", "variant": "Rogue"},
	{"id": "rogue_hooded", "src": "res://assets/kaykit/adventurers/rogue_hooded.glb", "out": "res://assets/kaykit/adventurers/rogue_hooded.scn", "variant": "Rogue_Hooded"},
	{"id": "barbarian", "src": "res://assets/kaykit/adventurers/barbarian.glb", "out": "res://assets/kaykit/adventurers/barbarian.scn", "variant": "Barbarian"},
]

const ANIMATION_SETS := [
	"res://assets/kaykit/animations/rig_medium_general.glb",
	"res://assets/kaykit/animations/rig_medium_movement_basic.glb",
	"res://assets/kaykit/animations/rig_medium_movement_advanced.glb",
	"res://assets/kaykit/animations/rig_medium_combat_ranged.glb",
]

const LOOP_CLIPS := [
	"Idle_A", "Idle_B",
	"Walking_A", "Walking_B", "Walking_C", "Walking_Backwards",
	"Running_A", "Running_B", "Running_HoldingRifle",
	"Running_Strafe_Left", "Running_Strafe_Right",
	"Jump_Idle", "Ranged_2H_Aiming", "Ranged_2H_Shooting",
]

const UPPER_BONES := [
	"spine", "chest", "head",
	"upperarm.l", "upperarm.r", "lowerarm.l", "lowerarm.r",
	"wrist.l", "wrist.r", "hand.l", "hand.r", "handslot.l", "handslot.r",
]

const UPPER_CLIPS := [
	"Ranged_2H_Aiming", "Ranged_2H_Shoot", "Ranged_2H_Shooting",
	"Ranged_2H_Reload", "Hit_A", "Hit_B",
	# Phase 2A class map: every class aims and shoots from the upper body.
	"Throw",
	"Ranged_Magic_Spellcasting", "Ranged_Magic_Shoot",
	"Ranged_Bow_Draw", "Ranged_Bow_Release",
	"Ranged_1H_Aiming", "Ranged_1H_Shoot", "Ranged_1H_Reload",
]

const UPPER_LOOP_CLIPS := [
	"Ranged_2H_Aiming", "Ranged_2H_Shooting", "Ranged_Magic_Spellcasting",
	"Ranged_Bow_Draw", "Ranged_1H_Aiming",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _build_library()
	await _build_upper_library()
	for spec: Dictionary in CHARACTERS:
		await _build_character(spec)
	await _build_rifle()
	quit(0)


func _build_character(spec: Dictionary) -> void:
	var packed := load(spec["src"]) as PackedScene
	if packed == null:
		push_error("cannot load " + spec["src"])
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame

	var skeleton := inst.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_error("no Skeleton3D in " + spec["src"])
		inst.free()
		return

	var meshes: Array[MeshInstance3D] = []
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			meshes.append(child as MeshInstance3D)
	if meshes.is_empty():
		push_error("no meshes in " + spec["src"])
		inst.free()
		return

	# Keep the array layout that every part shares. A missing tangent on one part
	# drops tangents for the whole merged surface; the material has no normal map.
	var common: Array[int] = []
	for key in Mesh.ARRAY_MAX:
		var present := true
		for mesh_instance in meshes:
			if mesh_instance.mesh.surface_get_arrays(0)[key] == null:
				present = false
				break
		if present:
			common.append(key)
	for required: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS, Mesh.ARRAY_INDEX]:
		if not common.has(required):
			push_error("missing required surface array %d in %s" % [required, spec["src"]])
			inst.free()
			return

	var combined: Array = []
	combined.resize(Mesh.ARRAY_MAX)
	for key in common:
		match key:
			Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL:
				combined[key] = PackedVector3Array()
			Mesh.ARRAY_TANGENT:
				combined[key] = PackedFloat32Array()
			Mesh.ARRAY_TEX_UV:
				combined[key] = PackedVector2Array()
			Mesh.ARRAY_COLOR:
				combined[key] = PackedColorArray()
			Mesh.ARRAY_BONES, Mesh.ARRAY_INDEX:
				combined[key] = PackedInt32Array()
			Mesh.ARRAY_WEIGHTS:
				combined[key] = PackedFloat32Array()
			_:
				push_error("unsupported surface array %d in %s" % [key, spec["src"]])
				inst.free()
				return

	var vertex_offset := 0
	var index_count := 0
	for mesh_instance in meshes:
		var arrays := mesh_instance.mesh.surface_get_arrays(0)
		for key in common:
			var destination: Variant = combined[key]
			if key == Mesh.ARRAY_INDEX:
				var indices: PackedInt32Array = arrays[key]
				for index in indices:
					destination.append(index + vertex_offset)
				index_count += indices.size()
			else:
				destination.append_array(arrays[key])
			combined[key] = destination
		vertex_offset += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, combined)
	merged.surface_set_material(0, meshes[0].mesh.surface_get_material(0))

	var merged_instance := MeshInstance3D.new()
	merged_instance.name = "%s_Merged" % spec["variant"]
	merged_instance.mesh = merged
	merged_instance.skin = meshes[0].skin
	merged_instance.skeleton = NodePath("..")
	merged_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for mesh_instance in meshes:
		skeleton.remove_child(mesh_instance)
		mesh_instance.free()
	skeleton.add_child(merged_instance)
	merged_instance.owner = inst

	# The animation library is assigned at runtime so all variants share one copy
	# of the clip data. Keep the player inside the character scene so tools and
	# tests can find it the same way they found the old mannequin's player.
	var animation_player := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player == null:
		animation_player = AnimationPlayer.new()
		animation_player.name = "AnimationPlayer"
		inst.add_child(animation_player)
		animation_player.owner = inst
	animation_player.root_node = NodePath("..")
	# Bake the shared library into the scene so tools and tests can inspect clips
	# without waiting for CharacterVisual._ready().
	var library := load("res://assets/kaykit/animations/kaykit_medium.res") as AnimationLibrary
	if library and animation_player.get_animation_library_list().is_empty():
		animation_player.add_animation_library("", library)

	inst.scale = Vector3.ONE * SCALE
	inst.rotation.y = PI
	inst.set_meta("kaykit_variant", spec["variant"])
	inst.set_meta("kaykit_source", spec["src"])

	var scene := PackedScene.new()
	var pack_error := scene.pack(inst)
	if pack_error != OK:
		push_error("pack failed for " + spec["out"])
	else:
		var save_error := ResourceSaver.save(scene, spec["out"])
		if save_error != OK:
			push_error("save failed for %s (%d)" % [spec["out"], save_error])
		else:
			print("built %s: parts=%d verts=%d tris=%d" % [
				spec["out"], meshes.size(), vertex_offset, index_count / 3,
			])
	inst.free()
	await process_frame


func _build_library() -> void:
	var library := AnimationLibrary.new()
	var clip_count := 0
	for set_path: String in ANIMATION_SETS:
		var inst := (load(set_path) as PackedScene).instantiate()
		root.add_child(inst)
		await process_frame
		var player := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null:
			push_error("no AnimationPlayer in " + set_path)
			inst.free()
			continue
		for library_name in player.get_animation_library_list():
			var source := player.get_animation_library(library_name)
			for clip_name in source.get_animation_list():
				if clip_name == "T-Pose" or library.has_animation(clip_name):
					continue
				var clip := _clean_clip(source.get_animation(clip_name))
				clip.loop_mode = (
					Animation.LOOP_LINEAR if LOOP_CLIPS.has(clip_name) else Animation.LOOP_NONE
				)
				library.add_animation(clip_name, clip)
				clip_count += 1
		inst.free()
		await process_frame
	var error := ResourceSaver.save(library, "res://assets/kaykit/animations/kaykit_medium.res")
	print("built kaykit_medium.res clips=%d err=%d" % [clip_count, error])


func _build_upper_library() -> void:
	var full := load("res://assets/kaykit/animations/kaykit_medium.res") as AnimationLibrary
	if full == null:
		push_error("kaykit_medium.res missing; build the base library first")
		return
	var upper := AnimationLibrary.new()
	for clip_name: String in UPPER_CLIPS:
		if not full.has_animation(clip_name):
			push_error("missing clip for upper library: " + clip_name)
			continue
		var clip := full.get_animation(clip_name).duplicate() as Animation
		for track in range(clip.get_track_count() - 1, -1, -1):
			var path := String(clip.track_get_path(track))
			var bone := path.get_slice(":", 1)
			if not UPPER_BONES.has(bone):
				clip.remove_track(track)
		clip.loop_mode = (
			Animation.LOOP_LINEAR if clip_name in UPPER_LOOP_CLIPS else Animation.LOOP_NONE
		)
		upper.add_animation(clip_name, clip)
	var error := ResourceSaver.save(upper, "res://assets/kaykit/animations/kaykit_upper.res")
	print("built kaykit_upper.res clips=%d err=%d" % [upper.get_animation_list().size(), error])


func _clean_clip(source: Animation) -> Animation:
	var clip := source.duplicate() as Animation
	# Server-authoritative movement: never let a clip translate the root bone.
	for track in range(clip.get_track_count() - 1, -1, -1):
		if clip.track_get_type(track) != 1: # Animation.TYPE_POSITION
			continue
		if String(clip.track_get_path(track)).ends_with(":root"):
			clip.remove_track(track)
	return clip


func _build_rifle() -> void:
	var packed := load("res://assets/weapons/rifle/quat_assault_rifle.glb") as PackedScene
	if packed == null:
		push_error("cannot load rifle")
		return
	var inst := packed.instantiate()
	root.add_child(inst)
	await process_frame
	# The source child has scale 100, so the wrapper's 0.1 gives a ~0.52 m rifle.
	# The source barrel points +X; +90 deg yaw points it down the character's -Z.
	inst.scale = Vector3.ONE * 0.1
	inst.rotation.y = PI * 0.5
	inst.position = Vector3(0.0, 0.04, 0.08)
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var scene := PackedScene.new()
	var pack_error := scene.pack(inst)
	var save_error := ResourceSaver.save(scene, "res://assets/weapons/rifle/rifle.scn")
	print("built rifle.scn pack=%d save=%d" % [pack_error, save_error])
	inst.free()
