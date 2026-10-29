extends BodTestSuite
## Phase 1A KayKit acceptance: five deterministic variants, merged skinned
## meshes, shadowless characters, the full clip map, the hand/muzzle contract,
## and the arena draw-call budget with five characters present.

const REQUIRED_CLIPS := [
	"Idle_A", "Walking_A", "Walking_Backwards", "Running_A", "Running_HoldingRifle",
	"Running_Strafe_Left", "Running_Strafe_Right",
	"Jump_Start", "Jump_Idle", "Jump_Land",
	"Ranged_2H_Aiming", "Ranged_2H_Shoot", "Ranged_2H_Reload",
	"Hit_A", "Hit_B", "Death_A", "Death_B",
]
const LOOP_CLIPS := [
	"Idle_A", "Walking_A", "Walking_Backwards", "Running_HoldingRifle",
	"Running_Strafe_Left", "Running_Strafe_Right", "Jump_Idle", "Ranged_2H_Aiming",
]
const MAX_DRAW_CALLS := 150
const MAX_TRIANGLES := 250_000

var _players: Array[PlayerController] = []


func after_test() -> void:
	for player in _players:
		if is_instance_valid(player):
			player.free()
	_players.clear()


func _spawn_player(net_id: int) -> PlayerController:
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	player.net_id = net_id
	add_child(player)
	_players.append(player)
	for _i in 8:
		await get_tree().process_frame
	player.set_physics_process(false)
	return player


func test_variant_selection_is_deterministic() -> void:
	var seen := {}
	for net_id in 5:
		var index := CharacterVisual.variant_index_for(net_id)
		expect(index == net_id, "net_id %d selects variant %d" % [net_id, net_id])
		seen[index] = true
	expect(seen.size() == 5, "ids 0-4 cover all five variants")
	expect(CharacterVisual.variant_index_for(5) == 0, "id 5 wraps back to Knight")
	expect(
		CharacterVisual.variant_index_for(-3) == CharacterVisual.variant_index_for(3),
		"negative ids map like their absolute value"
	)
	expect(CharacterVisual.variant_index_for(42) == CharacterVisual.variant_index_for(7), "large ids are stable")


func test_five_variants_have_one_shadowless_skinned_mesh() -> void:
	var variants := {}
	for net_id in 5:
		var player := await _spawn_player(net_id)
		var character := player.get_node_or_null("Visual/Character") as Node3D
		expect(character != null, "variant %d has a Character node" % net_id)
		if character == null:
			continue
		var variant := String(character.get_meta("kaykit_variant", ""))
		variants[variant] = true
		expect(variant == CharacterVisual.VARIANT_NAMES[net_id], "variant %d is %s" % [net_id, variant])
		expect(
			character.scale.is_equal_approx(Vector3.ONE * CharacterVisual.SCALE),
			"%s uses scale %.5f" % [variant, CharacterVisual.SCALE]
		)
		expect(
			absf(wrapf(character.rotation.y - PI, -PI, PI)) < 0.01,
			"%s faces the game forward axis (180 deg)" % variant
		)

		var meshes := character.find_children("*", "MeshInstance3D", true, false)
		expect(meshes.size() == 1, "%s is one merged mesh (got %d)" % [variant, meshes.size()])
		if meshes.size() == 1:
			var mesh_instance := meshes[0] as MeshInstance3D
			expect(mesh_instance.mesh != null, "%s has a mesh" % variant)
			expect(mesh_instance.mesh.get_surface_count() == 1, "%s is one surface" % variant)
			expect(mesh_instance.skin != null, "%s keeps its skin" % variant)
			expect(
				mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s casts no shadow" % variant
			)
			var material := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
			expect(material != null, "%s keeps its atlas material" % variant)
			if material and material.albedo_texture:
				expect(
					material.albedo_texture.get_width() <= 512,
					"%s atlas is at most 512 px (got %d)" % [variant, material.albedo_texture.get_width()]
				)
			var bounds: AABB = character.transform * mesh_instance.get_aabb()
			var height := bounds.size.y
			print("  %s height=%.3f m tris=%d" % [variant, height, mesh_instance.mesh.get_faces().size() / 3])
			expect(height > 0.65 and height < 0.90, "%s sits inside the 0.82 m silhouette (%.3f m)" % [variant, height])
			expect(absf(bounds.position.y) < 0.02, "%s has feet at y=0" % variant)

		var animation_player := character.find_child("AnimationPlayer", true, false) as AnimationPlayer
		expect(animation_player != null, "%s has an AnimationPlayer" % variant)
		if animation_player:
			for clip: String in REQUIRED_CLIPS:
				expect(animation_player.has_animation(clip), "%s has %s" % [variant, clip])
			for clip: String in LOOP_CLIPS:
				var animation := animation_player.get_animation(clip)
				expect(
					animation != null and animation.loop_mode == Animation.LOOP_LINEAR,
					"%s loops %s" % [variant, clip]
				)
	expect(variants.size() == 5, "all five character variants are reachable")


func test_gun_muzzle_and_reload_contract() -> void:
	var player := await _spawn_player(0)
	var hand := player.get_node_or_null("GunHand") as BoneAttachment3D
	expect(hand != null and hand.bone_name == "handslot.r", "gun is attached to handslot.r")
	expect(hand != null and hand.bone_idx >= 0, "hand bone index resolved")

	var gun := player.get_node_or_null("GunHand/GripSocket/GunMount") as Node3D
	expect(gun != null, "GunMount moved under the hand socket")
	expect(gun != null and gun.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE), "GunMount scale is 1.0")
	expect(player.get_node_or_null("Visual/GunMount") == null, "GunMount no longer floats under Visual")

	var muzzle := player.weapon.muzzle if player.weapon else null
	expect(muzzle != null, "WeaponController received the Muzzle reference")
	if muzzle != null:
		expect(muzzle.name == "Muzzle", "muzzle keeps the Muzzle name")
		expect(muzzle.get_parent() == gun, "muzzle stays under the hand-locked gun")
		expect(
			muzzle.global_position.distance_to(gun.global_position) > 0.20,
			"muzzle sits at the barrel tip, not the grip"
		)

	var gun_meshes := gun.get_node("Gun").find_children("*", "MeshInstance3D", true, false) if gun else []
	var rifle_surfaces := 0
	for node in gun_meshes:
		var mesh_instance := node as MeshInstance3D
		rifle_surfaces += mesh_instance.mesh.get_surface_count()
		expect(mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "rifle casts no shadow")
	expect(rifle_surfaces == 3, "M4 keeps its three material surfaces (got %d)" % rifle_surfaces)

	var reload := player.get_node_or_null("ReloadOverlay") as AnimationPlayer
	expect(reload != null, "reload overlay exists")
	var clip := reload.get_animation(&"Ranged_2H_Reload") if reload else null
	expect(clip != null, "reload clip exists")
	if clip:
		print("  reload clip length=%.2f s" % clip.length)
		expect(is_equal_approx(clip.length, 1.60), "Ranged_2H_Reload is 1.60 s, matching reload_time")
	player.weapon.ammo = 0
	player.weapon.start_reload()
	await get_tree().process_frame
	expect(reload != null and reload.is_playing(), "weapon reload starts the reload overlay")
	expect(reload != null and reload.current_animation == &"Ranged_2H_Reload", "reload overlay uses Ranged_2H_Reload")
	player.weapon.reset_ammo()
	await get_tree().process_frame
	expect(reload != null and not reload.is_playing(), "finishing reload stops the overlay")


func test_remote_force_anim_and_aim_pose() -> void:
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	add_child(player)
	player.make_remote(4)
	_players.append(player)
	for _i in 8:
		await get_tree().process_frame
	player.set_physics_process(false)

	var main := player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var hold := player.get_node_or_null("UpperBodyHold") as AnimationPlayer
	var visual := player.visual as CharacterVisual
	expect(main != null, "remote ghost has a main AnimationPlayer")
	expect(hold != null and hold.is_playing(), "remote ghosts hold the rifle-ready pose")
	expect(hold != null and hold.current_animation == &"Ranged_2H_Aiming", "remote hold uses Ranged_2H_Aiming")

	visual.force_anim = NetProtocol.AnimState.WALK
	await get_tree().process_frame
	expect(main.current_animation == &"Walking_A", "WALK force_anim plays Walking_A (got %s)" % main.current_animation)
	visual.force_anim = NetProtocol.AnimState.SPRINT
	await get_tree().process_frame
	expect(main.current_animation == &"Running_HoldingRifle", "SPRINT force_anim plays the rifle run")
	visual.force_anim = NetProtocol.AnimState.AIR
	await get_tree().process_frame
	expect(main.current_animation == &"Jump_Idle", "AIR force_anim plays Jump_Idle")
	visual.force_anim = NetProtocol.AnimState.STILL
	await get_tree().process_frame
	expect(main.current_animation == &"Idle_A", "STILL force_anim plays Idle_A")


func test_arena_with_five_characters_is_under_budget() -> void:
	var arena := (load("res://scenes/maps/arena_nature.tscn") as PackedScene).instantiate()
	add_child(arena)
	for _i in 4:
		await get_tree().process_frame
	var arena_counts := _count(arena, true)
	var surface_total := int(arena_counts[0])
	var triangle_total := int(arena_counts[1])

	for net_id in 5:
		var player := await _spawn_player(net_id)
		player.global_position = Vector3(-4.0 + float(net_id) * 2.0, 0.4, 0.0)
		await get_tree().process_frame
		var counts := _count(player, true)
		surface_total += int(counts[0])
		triangle_total += int(counts[1])

	print("  arena + 5 players: surfaces=%d triangles=%d" % [surface_total, triangle_total])
	expect(surface_total <= MAX_DRAW_CALLS, "surface/draw budget %d <= %d" % [surface_total, MAX_DRAW_CALLS])
	expect(triangle_total <= MAX_TRIANGLES, "triangle budget %d <= %d" % [triangle_total, MAX_TRIANGLES])

	arena.free()


func _count(node: Node, visible_only: bool) -> Array:
	var surfaces := 0
	var triangles := 0
	if node is MultiMeshInstance3D:
		var multi := node as MultiMeshInstance3D
		if multi.multimesh and multi.multimesh.mesh:
			surfaces += multi.multimesh.mesh.get_surface_count()
			triangles += (multi.multimesh.mesh.get_faces().size() / 3) * multi.multimesh.instance_count
	elif node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh and (not visible_only or mesh_instance.is_visible_in_tree()):
			surfaces += mesh_instance.mesh.get_surface_count()
			triangles += mesh_instance.mesh.get_faces().size() / 3
	for child in node.get_children():
		var child_counts := _count(child, visible_only)
		surfaces += int(child_counts[0])
		triangles += int(child_counts[1])
	return [surfaces, triangles]
