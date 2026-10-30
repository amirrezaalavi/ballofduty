extends SceneTree
## Sixteen-bot authoritative server probe. Proves the protocol-v2 roster cap
## (NetProtocol.MAX_PLAYERS = 16) is real: the server starts 16 bots on the
## default spawn ring, ticks them at 30 Hz, and the real snapshot path encodes
## a 294 B packet (6 B header + 16 x 18 B rows).
##
##   tools/godot --headless --path . --script tests/headless/net16_probe.gd
##
## No clients, no browser, no map scenes: a flat floor plus generated spawn
## points. Machine-readable output starts with "NET16 ".

const NET_SCRIPT := preload("res://scripts/networking/network_manager.gd")
const GM_SCRIPT := preload("res://scripts/game/game_manager.gd")
const BUS_SCRIPT := preload("res://scripts/autoload/event_bus.gd")

const ACTORS := 16
const WARMUP_TICKS := 30
const MEASURED_TICKS := 300
const PORT := 9199
const DT := 1.0 / 30.0
const EXPECTED_BYTES := 294
const P95_LIMIT_US := 20000.0

var _bus: Node
var _damage_events := 0


func _init() -> void:
	_run()


func _run() -> void:
	seed(20261102)
	_ensure_bus()
	print("NET16 config actors=%d ticks=%d port=%d" % [ACTORS, MEASURED_TICKS, PORT])

	var world := _build_world()
	root.add_child(world)
	for _i in 3:
		await physics_frame

	var net: Node = NET_SCRIPT.new()
	var gm: Node = GM_SCRIPT.new()
	root.add_child(net)
	root.add_child(gm)
	gm.net = net
	var err: int = gm.server_start(world, PORT, ACTORS)
	if err != OK:
		await _fail(gm, net, world, "server_start err=%d" % err)
		return
	if gm.server_player_count() != ACTORS:
		await _fail(gm, net, world, "roster=%d/%d" % [gm.server_player_count(), ACTORS])
		return

	# The engine must not also tick the manager: exactly one measured call per
	# physics frame keeps the sample count and the wall clock aligned.
	gm.set_physics_process(false)
	for _i in WARMUP_TICKS:
		gm._physics_process(DT)
		await physics_frame

	var samples: Array = []
	for _i in MEASURED_TICKS:
		var t0 := Time.get_ticks_usec()
		gm._physics_process(DT)
		samples.append(float(Time.get_ticks_usec() - t0))
		await physics_frame

	var stats := _stats(samples)
	var avg_us := float(stats["avg"])
	var p95_us := float(stats["p95"])
	var shots := int(gm._combat.shots_fired) if gm._combat else 0
	var deaths := int(gm._deaths_total)

	# Real snapshot path: the same entries and encoder the server sends, then a
	# decode round-trip so a malformed row cannot slip through.
	var entries: Array = []
	for peer_id in gm._roster:
		var entry: Dictionary = gm._roster[peer_id]
		var actor := entry["node"] as PlayerController
		entries.append(gm._snapshot_entry(entry, actor, int(entry["dead_until"]) > 0))
	var snap := NetProtocol.encode_snapshot(1, entries)
	var decoded := NetProtocol.decode_snapshot(snap)
	var rows := (decoded.get("entries", []) as Array).size()

	if snap.size() != EXPECTED_BYTES:
		await _fail(gm, net, world, "snapshot_bytes=%d expected=%d" % [
			snap.size(), EXPECTED_BYTES])
		return
	if rows != ACTORS:
		await _fail(gm, net, world, "decoded_rows=%d/%d" % [rows, ACTORS])
		return
	if p95_us > P95_LIMIT_US:
		await _fail(gm, net, world, "tick_p95_us=%.0f limit=%.0f" % [
			p95_us, P95_LIMIT_US])
		return

	print("NET16 result=PASS actors=%d bytes=%d tick_avg_us=%.0f tick_p95_us=%.0f shots=%d deaths=%d" % [
		ACTORS, snap.size(), avg_us, p95_us, shots, deaths,
	])
	await _cleanup(gm, net, world)
	quit(0)


## Flat world with a single large floor box. Its top sits at y = 0.45, just
## under the generated spawn feet (0.4), so the bots settle instead of falling.
func _build_world() -> Node3D:
	var world := Node3D.new()
	world.name = "Net16World"
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -0.55, 0.0)
	var collider := CollisionShape3D.new()
	collider.name = "FloorShape"
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 2.0, 200.0)
	collider.shape = box
	floor_body.add_child(collider)
	world.add_child(floor_body)
	return world


func _ensure_bus() -> void:
	_bus = root.get_node_or_null("EventBus")
	if _bus == null:
		_bus = BUS_SCRIPT.new()
		_bus.name = "EventBus"
		root.add_child(_bus)
	if not _bus.damage_dealt.is_connected(_on_damage):
		_bus.damage_dealt.connect(_on_damage)


## Keeps the real damage signal path wired; the server does its own accounting.
func _on_damage(_target_id: int, _source_id: int, _amount: int, _position: Vector3) -> void:
	_damage_events += 1


func _stats(values: Array) -> Dictionary:
	var n := values.size()
	if n == 0:
		return {"avg": 0.0, "p95": 0.0, "max": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in values:
		total += float(v)
	var idx := clampi(int(ceil(float(n) * 0.95)) - 1, 0, n - 1)
	return {
		"avg": total / float(n),
		"p95": float(sorted[idx]),
		"max": float(sorted[n - 1]),
	}


func _fail(gm: Node, net: Node, world: Node, reason: String) -> void:
	print("NET16 result=FAIL reason=%s" % reason)
	await _cleanup(gm, net, world)
	quit(1)


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
