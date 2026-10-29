extends BodTestSuite
## CP4c end-to-end: a client fire intent becomes a server projectile and hit
## event; the shooter gets a hitmarker only after confirmation; death and
## respawn round-trip; a spoofed damage event is rejected.

const PORT := 9179
const DT := 1.0 / 30.0

var _server_net: Node
var _client_a_net: Node
var _client_b_net: Node
var _worlds: Array[Node] = []


func after_test() -> void:
	for net in [_server_net, _client_a_net, _client_b_net]:
		if is_instance_valid(net):
			net.stop()
	for world in _worlds:
		if is_instance_valid(world):
			world.queue_free()
	_worlds.clear()


func test_authoritative_combat_roundtrip() -> void:
	var gm_script := load("res://scripts/game/game_manager.gd")
	var net_script := load("res://scripts/networking/network_manager.gd")
	var world := _add_world("ServerWorld")
	var world_a := _add_world("ClientAWorld")
	var world_b := _add_world("ClientBWorld")
	var local_a := _make_local_player(world_a)
	var local_b := _make_local_player(world_b)
	await get_tree().physics_frame

	_server_net = net_script.new()
	var server_gm = gm_script.new()
	add_child(_server_net)
	add_child(server_gm)
	server_gm.net = _server_net
	expect(server_gm.server_start(world, PORT) == OK, "server starts")

	_client_a_net = net_script.new()
	var client_a_gm = gm_script.new()
	_client_b_net = net_script.new()
	var client_b_gm = gm_script.new()
	for node in [_client_a_net, client_a_gm, _client_b_net, client_b_gm]:
		add_child(node)
	client_a_gm.net = _client_a_net
	client_b_gm.net = _client_b_net
	expect(client_a_gm.client_start(world_a, "127.0.0.1", PORT, "Shooter") == OK, "client A connects")
	expect(client_b_gm.client_start(world_b, "127.0.0.1", PORT, "Target") == OK, "client B connects")
	await wait_for(func() -> bool: return server_gm.server_player_count() == 2, 300)
	await wait_for(func() -> bool: return client_a_gm.remote_count() == 1 and client_b_gm.remote_count() == 1, 300)
	for _i in 12:
		await get_tree().physics_frame
	local_a.set_physics_process(false)
	local_b.set_physics_process(false)
	var local_weapon := local_a.get_node("WeaponController") as WeaponController
	expect(not local_weapon.spawn_projectiles, "client weapon is cosmetic-only (no local damage)")

	# Settle on the floor, then make both test actors immediately vulnerable.
	var server_a := _server_actor_of(server_gm, client_a_gm.local_id)
	var server_b := _server_actor_of(server_gm, client_b_gm.local_id)
	expect(server_a != null and server_b != null, "server actors exist")
	for peer_id in server_gm._roster:
		var entry: Dictionary = server_gm._roster[peer_id]
		entry["protected_until"] = 0
		server_gm._set_hurtboxes(entry["node"], true)
	var health_b := local_b.get_node("HealthComponent") as HealthComponent
	expect(health_b.current == 100, "target starts at full health")

	# A client cannot inject damage: EVENT is server->client only.
	var rejected_before := int(_server_net.packets_rejected)
	var peer_b := 0
	for peer_id in server_gm._roster:
		if int(server_gm._roster[peer_id]["id"]) == client_b_gm.local_id:
			peer_b = int(peer_id)
	_server_net._route(peer_b, NetProtocol.encode_event_hit(
		client_b_gm.local_id, client_a_gm.local_id, 100, false, true, Vector3.ZERO
	))
	expect(int(_server_net.packets_rejected) == rejected_before + 1, "spoofed damage event is rejected")
	expect(health_b.current == 100, "spoofed damage changes nothing")

	var hits: Array = []
	client_a_gm.server_hit.connect(func(headshot: bool, killed: bool) -> void:
		hits.append([headshot, killed]))
	var target_shape := server_b.get_node("BodyHurtbox/CollisionShape3D") as Node3D
	var aim := ServerCombat.aim_angles(server_a.global_position, target_shape.global_position)
	var seq: int = int(client_a_gm.local_id) * 1000
	for i in 4:
		seq += 1
		var frame := PlayerInputFrame.new()
		frame.seq = seq
		frame.yaw = aim.x
		frame.pitch = aim.y
		frame.fire = true
		local_a.simulate_tick(frame, DT)
		client_a_gm.client_send_input(frame)
		for _k in 8:
			await get_tree().physics_frame
		if i == 0:
			expect(health_b.current == 75, "first confirmed shot deals 25 (hp %d)" % health_b.current)
		if i == 2:
			expect(health_b.current == 25, "third shot leaves 25 (hp %d)" % health_b.current)

	expect(hits.size() >= 4, "shooter received server hit confirmations (%d)" % hits.size())
	await wait_for(func() -> bool: return health_b.current == 0, 30)
	expect(health_b.current == 0, "target reaches zero (hp %d)" % health_b.current)
	expect(local_b.dead, "target client is marked dead by the server event")
	expect(int(server_gm._combat.projectiles_fired) == 4,
		"server fired exactly four authoritative projectiles (%d)" % int(server_gm._combat.projectiles_fired))

	# Respawn is server-owned: 3 s later the client is moved and healed.
	await wait_for(func() -> bool: return not local_b.dead, 140)
	expect(not local_b.dead, "target respawns after the server delay")
	expect(health_b.current == 100, "respawn restores health (hp %d)" % health_b.current)
	expect(local_b.global_position.distance_to(server_b.global_position) < 0.5,
		"respawn teleports the client to the server pose")
	expect(local_b.global_position.distance_to(server_a.global_position) >= 10.0,
		"respawn is at least 10 m from the nearest enemy")
	var respawn_hurtbox := server_b.get_node("BodyHurtbox") as HurtboxComponent
	expect(not respawn_hurtbox.damage_enabled, "respawn protection is active")

	_server_net.stop()
	_client_a_net.stop()
	_client_b_net.stop()
	await get_tree().process_frame


func _add_world(world_name: String) -> Node3D:
	var world := Node3D.new()
	world.name = world_name
	add_child(world)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	col.shape = box
	floor_body.add_child(col)
	world.add_child(floor_body)
	floor_body.position = Vector3(0, -0.55, 0)
	_worlds.append(world)
	return world


func _make_local_player(world: Node3D) -> PlayerController:
	var player := (load("res://scenes/characters/player.tscn") as PackedScene).instantiate() as PlayerController
	player.name = "Player"
	world.add_child(player)
	player.set_physics_process(false)
	return player


func _server_actor_of(server_gm, player_id: int) -> PlayerController:
	for peer_id in server_gm._roster:
		var entry: Dictionary = server_gm._roster[peer_id]
		if int(entry["id"]) == player_id:
			return entry["node"] as PlayerController
	return null
