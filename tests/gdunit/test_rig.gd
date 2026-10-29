extends BodTestSuite
## Phase 1A rig: the KayKit gun follows handslot.r, and firing overlays a
## filtered Ranged_2H_Shoot clip without touching the locomotion legs.

var _player: PlayerController


func after_test() -> void:
	if is_instance_valid(_player):
		_player.free()


func _setup() -> void:
	_player = (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	add_child(_player)
	for _i in 8:
		await get_tree().process_frame
	_player.set_physics_process(false)


func test_gun_follows_the_right_hand() -> void:
	await _setup()
	var hand_attachment := _player.get_node_or_null("GunHand") as BoneAttachment3D
	expect(hand_attachment != null, "right-hand attachment exists")
	expect(hand_attachment.bone_name == "handslot.r", "attachment targets handslot.r")
	expect(hand_attachment.bone_idx >= 0, "bone index resolved (got %d)" % hand_attachment.bone_idx)

	var gun := _player.get_node_or_null("GunHand/GripSocket/GunMount") as Node3D
	expect(gun != null, "gun was reparented under the hand socket")
	expect(_player.get_node_or_null("Visual/GunMount") == null, "gun no longer floats under the body visual")
	expect(
		is_equal_approx(gun.global_transform.basis.get_scale().x, 1.0),
		"gun keeps world scale 1.0 (got %.3f)" % gun.global_transform.basis.get_scale().x
	)

	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var hand := skeleton.find_bone("handslot.r")
	var hand_pos := (skeleton.global_transform * skeleton.get_bone_global_pose(hand)).origin
	var gap := gun.global_position.distance_to(hand_pos)
	print("  gun-to-hand gap=%.3f m" % gap)
	expect(gap < 0.06, "gun sits at the hand (gap %.3f m)" % gap)

	var weapon := _player.get_node("WeaponController") as WeaponController
	expect(weapon.muzzle != null, "WeaponController resolved the muzzle at _ready")
	expect(weapon.muzzle.name == "Muzzle", "muzzle is still named Muzzle")
	expect(weapon.muzzle.get_parent() == gun, "muzzle is under the hand-locked GunMount")


func test_shoot_overlay_is_upper_body_only() -> void:
	await _setup()
	var hold := _player.get_node_or_null("UpperBodyHold") as AnimationPlayer
	expect(hold != null, "upper-body hold overlay exists")
	expect(hold != null and not hold.is_playing(), "idle does not force the aim pose")
	_player.aiming = true
	_player.aim_hold_until_msec = Time.get_ticks_msec() + 500
	for _i in 12:
		await get_tree().process_frame
	expect(hold != null and hold.is_playing(), "hold overlay runs while aiming")
	expect(hold != null and hold.current_animation == &"Ranged_2H_Aiming", "hold uses the rifle aim pose")
	_player.aiming = false
	_player.aim_hold_until_msec = 0

	var overlay := _player.get_node_or_null("ShotOverlay") as AnimationPlayer
	expect(overlay != null, "shot overlay player exists")
	var clip := overlay.get_animation(&"Ranged_2H_Shoot") if overlay else null
	expect(clip != null, "filtered Ranged_2H_Shoot clip exists")
	if clip:
		var tracks := clip.get_track_count()
		var lower_body := 0
		for i in tracks:
			var bone := String(clip.track_get_path(i)).get_slice(":", 1)
			if bone in ["root", "hips", "upperleg.l", "upperleg.r", "lowerleg.l", "lowerleg.r", "foot.l", "foot.r", "toes.l", "toes.r"]:
				lower_body += 1
		print("  shot clip tracks=%d lower_body=%d" % [tracks, lower_body])
		expect(tracks > 10, "shot clip keeps upper-body tracks (%d)" % tracks)
		expect(lower_body == 0, "shot clip has no lower-body tracks")

	# Fire through the real weapon path; the overlay should start.
	var weapon := _player.get_node("WeaponController") as WeaponController
	weapon.spawn_projectiles = false
	var frame := PlayerInputFrame.new()
	frame.fire = true
	weapon.tick(1.0 / 30.0, frame)
	await get_tree().process_frame
	expect(overlay != null and overlay.is_playing(), "firing starts the shot overlay")
	expect(overlay.current_animation == &"Ranged_2H_Shoot", "shot overlay plays Ranged_2H_Shoot")
	var main := _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	expect(main.current_animation != &"Ranged_2H_Shoot", "main locomotion player keeps its clip")
