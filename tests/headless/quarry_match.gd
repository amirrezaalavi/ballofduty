extends SceneTree
## Quick four-bot match on the Sunken Quarry. Proves the new map is playable by
## the existing server bots: they spawn on the 8 markers, run across terrain and
## cover, fire, hit and kill each other.
##
##   tools/godot --headless --path . --script tests/headless/quarry_match.gd
##
## No clients, no balance edits. Prints machine-readable QUARRY_MATCH lines.

const ARENA := preload("res://scenes/maps/arena_quarry.tscn")
const NET_SCRIPT := preload("res://scripts/networking/network_manager.gd")
const GM_SCRIPT := preload("res://scripts/game/game_manager.gd")
const BUS_SCRIPT := preload("res://scripts/autoload/event_bus.gd")

const BOT_COUNT := 4
const MATCH_SECONDS := 45.0
const PORT := 9198

var _bus: Node
var _damage_by_source: Dictionary = {}
var _max_moved: Dictionary = {}
var _start_positions: Dictionary = {}


func _init() -> void:
	_run()


func _run() -> void:
	seed(20261101)
	_ensure_bus()
	print("QUARRY_MATCH config arena=arena_quarry bots=%d seconds=%.0f port=%d" % [
		BOT_COUNT, MATCH_SECONDS, PORT,
	])
	var world := ARENA.instantiate() as Node3D
	world.name = "QuarryMatchWorld"
	root.add_child(world)
	for _i in 3:
		await physics_frame

	var net: Node = NET_SCRIPT.new()
	var gm: Node = GM_SCRIPT.new()
	root.add_child(net)
	root.add_child(gm)
	gm.net = net
	var err: int = gm.server_start(world, PORT, BOT_COUNT)
	if err != OK:
		print("QUARRY_MATCH result=FAIL reason=server_start err=%d" % err)
		await _cleanup(gm, net, world)
		quit(1)
		return
	if gm.server_player_count() != BOT_COUNT:
		print("QUARRY_MATCH result=FAIL reason=spawned=%d/%d" % [
			gm.server_player_count(), BOT_COUNT])
		await _cleanup(gm, net, world)
		quit(1)
		return

	for peer_id in gm._roster:
		var actor := gm._roster[peer_id]["node"] as Node3D
		_start_positions[int(gm._roster[peer_id]["id"])] = actor.global_position
		_max_moved[int(gm._roster[peer_id]["id"])] = 0.0
	for _i in 3:
		await physics_frame

	var start_msec := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_msec < int(MATCH_SECONDS * 1000.0):
		await physics_frame
		for peer_id in gm._roster:
			var entry: Dictionary = gm._roster[peer_id]
			var actor := entry["node"] as Node3D
			var id := int(entry["id"])
			var distance := actor.global_position.distance_to(_start_positions[id])
			_max_moved[id] = maxf(float(_max_moved.get(id, 0.0)), distance)

	var shots := int(gm._combat.shots_fired) if gm._combat else 0
	var hits := int(gm._hits_total)
	var deaths := int(gm._deaths_total)
	var damage := 0
	for source_id in _damage_by_source:
		damage += int(_damage_by_source[source_id])
	var min_move := INF
	for id in _max_moved:
		min_move = minf(min_move, float(_max_moved[id]))
	var moved_bots := 0
	for id in _max_moved:
		if float(_max_moved[id]) >= 2.0:
			moved_bots += 1
	var result := "PASS"
	var reason := ""
	if shots <= 0:
		result = "FAIL"
		reason = "bots did not fire"
	elif hits <= 0 or damage <= 0:
		result = "FAIL"
		reason = "no damage landed"
	elif deaths <= 0:
		result = "FAIL"
		reason = "no bot died"
	elif moved_bots < BOT_COUNT:
		result = "FAIL"
		reason = "%d/%d bots moved at least 2 m" % [moved_bots, BOT_COUNT]
	print("QUARRY_MATCH result=%s reason=%s bots=%d moved=%d min_move=%.1f shots=%d hits=%d damage=%d deaths=%d tick=%d" % [
		result, reason, BOT_COUNT, moved_bots, min_move, shots, hits, damage, deaths,
		int(gm._server_tick),
	])
	for id in _max_moved:
		print("QUARRY_MATCH bot id=%d moved=%.1f m" % [int(id), float(_max_moved[id])])
	await _cleanup(gm, net, world)
	quit(0 if result == "PASS" else 1)


func _ensure_bus() -> void:
	_bus = root.get_node_or_null("EventBus")
	if _bus == null:
		_bus = BUS_SCRIPT.new()
		_bus.name = "EventBus"
		root.add_child(_bus)
	if not _bus.damage_dealt.is_connected(_on_damage):
		_bus.damage_dealt.connect(_on_damage)


func _on_damage(_target_id: int, source_id: int, amount: int, _position: Vector3) -> void:
	if source_id <= 0:
		return
	_damage_by_source[source_id] = int(_damage_by_source.get(source_id, 0)) + amount


func _cleanup(gm: Node, net: Node, world: Node) -> void:
	if is_instance_valid(gm):
		gm.stop_all()
	if is_instance_valid(net):
		net.stop()
	if is_instance_valid(world):
		world.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
