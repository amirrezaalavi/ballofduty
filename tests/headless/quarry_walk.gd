extends SceneTree
## Real-physics walkthrough of the Sunken Quarry.
##
##   tools/godot --headless --path . --script tests/headless/quarry_walk.gd
##
## The harness drives PlayerController.simulate_tick (the same 30 Hz step used by
## the client/server) across every terrain chunk, both cave directions, all
## terrace ramps, the bridge/tower/lookout, all spawns, the four map edges and
## several platform falls. It fails loudly on fall-through, long stuck states,
## unreachable spawns, cave camera clipping or boundary escape.

const DT := 1.0 / 30.0
const ARENA := preload("res://scenes/maps/arena_quarry.tscn")
const PLAYER := preload("res://scenes/characters/player.tscn")
const ARENA_SCRIPT := preload("res://scripts/game/quarry_arena.gd")
const BOUNDARY_LIMIT := 69.8
const STUCK_LIMIT := 1.5

var _arena: Node3D
var _player: PlayerController
var _seq := 0
var _sections: Array[Dictionary] = []
var _failures := 0
var _only := ""


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	_run()


func _run() -> void:
	_arena = ARENA.instantiate() as Node3D
	root.add_child(_arena)
	await process_frame
	await physics_frame
	await physics_frame

	_player = PLAYER.instantiate() as PlayerController
	_arena.add_child(_player)
	_player.net_role = PlayerController.NetRole.LOCAL
	_player.set_physics_process(false)
	_player.set_process(false)
	await physics_frame
	await physics_frame

	# Terrain chunks. Exact centres of the north-centre and centre chunks are
	# occupied by the cave ridge and central ruin, so those sections start at the
	# nearest walkable point inside the same 50 m cell.
	await _section("chunk_0_0", _ground(-50, -50), [Vector3(-46, 0, -50)], false, 8.0)
	await _section("chunk_1_0", _ground(0, -32), [Vector3(4, 0, -32)], false, 8.0)
	await _section("chunk_2_0", _ground(50, -50), [Vector3(54, 0, -50)], false, 8.0)
	await _section("chunk_0_1", _ground(-50, 0), [Vector3(-46, 0, 0)], false, 8.0)
	await _section("chunk_1_1", _ground(4, 4), [Vector3(8, 0, 4)], false, 8.0)
	await _section("chunk_2_1", _ground(58, 0), [Vector3(62, 0, 0)], false, 8.0)
	await _section("chunk_0_2", _ground(-50, 50), [Vector3(-46, 0, 50)], false, 8.0)
	await _section("chunk_1_2", _ground(0, 50), [Vector3(4, 0, 50)], false, 8.0)
	await _section("chunk_2_2", _ground(50, 50), [Vector3(54, 0, 50)], false, 8.0)

	# Cave: enter one mouth, traverse the bore, exit the other.
	await _section("cave_west_to_east", _ground(-46, -54),
		[Vector3(-34, 0, -54), Vector3(-24, 0, -54), Vector3(0, 0, -54),
		Vector3(24, 0, -54), Vector3(34, 0, -54), Vector3(46, 0, -54)],
		true, 55.0, true)
	await _section("cave_east_to_west", _ground(46, -54),
		[Vector3(34, 0, -54), Vector3(24, 0, -54), Vector3(0, 0, -54),
		Vector3(-24, 0, -54), Vector3(-34, 0, -54), Vector3(-46, 0, -54)],
		true, 55.0, true)

	# Terrace ramps, up and down.
	await _section("west_up", _ground(-20, 0),
		[Vector3(-30, 0, 0), Vector3(-40, 0, 0), Vector3(-50, 0, 0), Vector3(-62, 0, 0)],
		true, 25.0)
	await _section("west_down", _ground(-62, 0),
		[Vector3(-50, 0, 0), Vector3(-40, 0, 0), Vector3(-30, 0, 0), Vector3(-20, 0, 0)],
		true, 25.0)
	await _section("east_up", _ground(20, -20),
		[Vector3(32, 0, -20), Vector3(44, 0, -20), Vector3(56, 0, -20), Vector3(64, 0, -20)],
		true, 25.0)
	await _section("east_down", _ground(64, -20),
		[Vector3(56, 0, -20), Vector3(44, 0, -20), Vector3(32, 0, -20), Vector3(20, 0, -20)],
		true, 25.0)
	await _section("south_up", _ground(8, 38),
		[Vector3(8, 0, 46), Vector3(8, 0, 56), Vector3(8, 0, 64)],
		true, 20.0)
	await _section("south_down", _ground(8, 64),
		[Vector3(8, 0, 56), Vector3(8, 0, 46), Vector3(8, 0, 38)],
		true, 20.0)

	# Bridge, tower and lookout.
	await _section("bridge", Vector3(41, 2.9, 6),
		[Vector3(46, 2.6, 6), Vector3(54, 2.6, 6), Vector3(60, 2.6, 6)],
		false, 18.0)
	await _section("ruined_tower", _ground(-56, 22),
		[Vector3(-56, 0, 18), Vector3(-56, 0, 22)],
		false, 18.0)
	var lookout_base := ARENA_SCRIPT.height_at(-62.0, 48.0)
	await _section("lookout", _ground(-62, 56),
		[Vector3(-62, 0, 54), Vector3(-62, 0, 52), Vector3(-62, 0, 48),
		Vector3(-62, 0, 52), Vector3(-62, 0, 56)],
		false, 24.0)

	# Every spawn, walked 5 m toward the arena centre.
	var spawns: Array = []
	for child in _arena.get_children():
		if child is Marker3D and child.name.begins_with("Spawn"):
			spawns.append(child)
	spawns.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	for i in spawns.size():
		var marker := spawns[i] as Marker3D
		var pos := marker.global_position
		var toward := Vector2(-pos.x, -pos.z)
		if toward.length_squared() < 0.01:
			toward = Vector2(1, 0)
		toward = toward.normalized() * 5.0
		await _section("spawn_%02d" % (i + 1), pos + Vector3(0, 0.35, 0),
			[Vector3(pos.x + toward.x, 0, pos.z + toward.y)], true, 7.0)

	# Map edges: push outward, must stay inside the 150 m footprint.
	await _edge("edge_east", _ground(60, 0), Vector3(75, 0, 0))
	await _edge("edge_west", _ground(-60, 0), Vector3(-75, 0, 0))
	await _edge("edge_south", _ground(0, 60), Vector3(0, 0, 75))
	await _edge("edge_north", _ground(40, -60), Vector3(40, 0, -75))

	# Falls from the elevated platforms. The bridge drop is the real 4.5 m one;
	# the lookout and central plinth verify the shorter drops and landing.
	var bridge_top := lerpf(2.55, ARENA_SCRIPT.height_at(57.0, 6.0), 7.0 / 14.0)
	await _fall("fall_bridge", Vector3(50, bridge_top + 0.3, 6),
		Vector3(50, bridge_top + 0.3, 10), 2.0)
	await _fall("fall_lookout", Vector3(-62, lookout_base + 2.3, 48),
		Vector3(-58, lookout_base + 2.3, 48), 1.5)
	await _fall("fall_central_plinth", Vector3(0, 0.3, 0), Vector3(0, 0.3, 5), 0.2)

	_print_summary()
	_arena.free()
	quit(0 if _failures == 0 else 1)


# --- section drivers ------------------------------------------------------

func _section(name: String, start: Vector3, waypoints: Array, sprint: bool,
		max_seconds: float, fail_on_clip: bool = false) -> void:
	if _only != "" and not name.begins_with(_only):
		return
	var start_yaw := _yaw_to(_player_target(waypoints[0], start))
	await _teleport(start, start_yaw)
	var start_pos := _player.global_position
	var last_pos := start_pos
	var min_y := start_pos.y
	var max_y := start_pos.y
	var max_stuck := 0.0
	var stuck_run := 0.0
	var clip_ticks := 0
	var floor_ticks := 0
	var ticks := 0
	var elapsed := 0.0
	var index := 0
	var fall_through := false
	var path_distance := 0.0

	while index < waypoints.size() and elapsed < max_seconds:
		var target: Vector3 = waypoints[index]
		var flat := Vector2(target.x - _player.global_position.x,
			target.z - _player.global_position.z)
		if flat.length() < 0.9:
			index += 1
			continue
		var yaw := _yaw_to(Vector3(target.x, 0, target.z) - _player.global_position)
		_player.set_view_yaw(yaw)
		await _step(Vector2(0, -1), yaw, sprint)
		elapsed += DT
		ticks += 1

		var pos := _player.global_position
		min_y = minf(min_y, pos.y)
		max_y = maxf(max_y, pos.y)
		var ground := ARENA_SCRIPT.height_at(pos.x, pos.z)
		if pos.y < ground - 0.5:
			fall_through = true
		if _player.is_on_floor():
			floor_ticks += 1
		if _camera_clipped():
			clip_ticks += 1
		var moved := Vector2(pos.x - last_pos.x, pos.z - last_pos.z).length()
		path_distance += moved
		if moved < 0.006 and elapsed > 0.7:
			stuck_run += DT
			max_stuck = maxf(max_stuck, stuck_run)
		else:
			stuck_run = 0.0
		last_pos = pos

	var end_pos := _player.global_position
	var reached := index >= waypoints.size()
	var floor_ratio := float(floor_ticks) / float(maxi(ticks, 1))
	var ok := reached and not fall_through and max_stuck <= STUCK_LIMIT
	if fail_on_clip and clip_ticks > 0:
		ok = false
	if not reached:
		ok = false
	var reason := ""
	if not reached:
		reason = "timeout at waypoint %d/%d" % [index, waypoints.size()]
	elif fall_through:
		reason = "fell through terrain"
	elif max_stuck > STUCK_LIMIT:
		reason = "stuck %.2f s" % max_stuck
	elif fail_on_clip and clip_ticks > 0:
		reason = "camera clipped %d ticks" % clip_ticks
	_record(name, start_pos, end_pos, min_y, max_y, max_stuck, clip_ticks,
		floor_ratio, ok, reason, "", path_distance)


func _edge(name: String, start: Vector3, target: Vector3) -> void:
	if _only != "" and not name.begins_with(_only):
		return
	await _teleport(start, _yaw_to(target - start))
	var start_pos := _player.global_position
	var last_pos := start_pos
	var max_stuck := 0.0
	var stuck_run := 0.0
	var clip_ticks := 0
	var min_y := start_pos.y
	var max_y := start_pos.y
	var fall_through := false
	var max_coord := 0.0
	var floor_ticks := 0
	var ticks := 0
	var elapsed := 0.0
	var path_distance := 0.0
	while elapsed < 8.0:
		var yaw := _yaw_to(target - _player.global_position)
		_player.set_view_yaw(yaw)
		await _step(Vector2(0, -1), yaw, true)
		elapsed += DT
		ticks += 1
		var pos := _player.global_position
		min_y = minf(min_y, pos.y)
		max_y = maxf(max_y, pos.y)
		max_coord = maxf(max_coord, maxf(absf(pos.x), absf(pos.z)))
		var ground := ARENA_SCRIPT.height_at(pos.x, pos.z)
		if pos.y < ground - 0.5:
			fall_through = true
		if _camera_clipped():
			clip_ticks += 1
		if _player.is_on_floor():
			floor_ticks += 1
		var moved := Vector2(pos.x - last_pos.x, pos.z - last_pos.z).length()
		path_distance += moved
		if moved < 0.006 and elapsed > 0.7:
			stuck_run += DT
			max_stuck = maxf(max_stuck, stuck_run)
		else:
			stuck_run = 0.0
		last_pos = pos
	var end_pos := _player.global_position
	var moved_total := Vector2(end_pos.x - start_pos.x, end_pos.z - start_pos.z).length()
	var escaped := max_coord > BOUNDARY_LIMIT
	var ok := not escaped and not fall_through and moved_total >= 1.0
	var reason := ""
	if escaped:
		reason = "escaped to %.2f m" % max_coord
	elif fall_through:
		reason = "fell through terrain"
	elif moved_total < 1.0:
		reason = "did not approach the edge (%.2f m)" % moved_total
	_record(name, start_pos, end_pos, min_y, max_y, max_stuck, clip_ticks,
		float(floor_ticks) / float(maxi(ticks, 1)), ok, reason,
		"max_coord=%.2f" % max_coord, path_distance)


func _fall(name: String, platform: Vector3, drop: Vector3, min_drop: float) -> void:
	if _only != "" and not name.begins_with(_only):
		return
	await _teleport(platform, 0.0)
	var start_pos := _player.global_position
	var min_y := start_pos.y
	var max_y := start_pos.y
	var fall_through := false
	var clip_ticks := 0
	var landed := false
	# Step off the platform (teleport the body to the drop point, then let the
	# real gravity/move_and_slide path do the fall).
	_player.global_position = drop
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	var elapsed := 0.0
	while elapsed < 3.0:
		await _step(Vector2.ZERO, 0.0, false)
		elapsed += DT
		var pos := _player.global_position
		min_y = minf(min_y, pos.y)
		max_y = maxf(max_y, pos.y)
		var ground := ARENA_SCRIPT.height_at(pos.x, pos.z)
		if pos.y < ground - 0.5:
			fall_through = true
		if _camera_clipped():
			clip_ticks += 1
		if _player.is_on_floor():
			landed = true
	var end_pos := _player.global_position
	var drop_height := start_pos.y - min_y
	var ok := landed and not fall_through and drop_height >= min_drop
	var reason := ""
	if not landed:
		reason = "never landed"
	elif fall_through:
		reason = "fell through terrain"
	elif drop_height < min_drop:
		reason = "drop only %.2f m" % drop_height
	_record(name, start_pos, end_pos, min_y, max_y, 0.0, clip_ticks,
		1.0 if landed else 0.0, ok, reason, "drop=%.2f" % drop_height,
		Vector2(end_pos.x - start_pos.x, end_pos.z - start_pos.z).length())


# --- helpers --------------------------------------------------------------

func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, ARENA_SCRIPT.height_at(x, z) + 0.35, z)


func _player_target(target: Vector3, fallback: Vector3) -> Vector3:
	return target if target.distance_to(fallback) > 0.01 else fallback + Vector3(1, 0, 0)


func _yaw_to(delta: Vector3) -> float:
	return atan2(-delta.x, -delta.z)


func _teleport(pos: Vector3, yaw: float) -> void:
	_player.global_position = pos
	_player.rotation.y = yaw
	_player.set_view_yaw(yaw)
	_player.velocity = Vector3.ZERO
	_player.camera_rig.pitch = 0.0
	_player.camera_rig.rotation.x = 0.0
	_player.reset_physics_interpolation()
	for _i in 4:
		await _step(Vector2.ZERO, yaw, false)


func _step(move: Vector2, yaw: float, sprint: bool) -> void:
	var frame := PlayerInputFrame.new()
	_seq += 1
	frame.seq = _seq
	frame.yaw = yaw
	frame.move = move
	frame.sprint = sprint
	_player.simulate_tick(frame, DT)
	await physics_frame


func _camera_clipped() -> bool:
	var rig := _player.get_node_or_null("CameraPivot") as CameraRig
	if rig == null:
		return false
	var pivot := rig.spring_arm.global_position
	var camera_pos := rig.camera.global_position
	var distance := pivot.distance_to(camera_pos)
	if distance < 0.1:
		return false
	var query := PhysicsRayQueryParameters3D.create(pivot, camera_pos, 1)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return pivot.distance_to(hit["position"]) < distance - 0.12


func _record(name: String, start_pos: Vector3, end_pos: Vector3, min_y: float,
		max_y: float, stuck: float, clips: int, floor_ratio: float, ok: bool,
		reason: String, extra: String, path_distance: float) -> void:
	var distance := path_distance
	_sections.append({
		"name": name, "distance": distance, "min_y": min_y, "max_y": max_y,
		"stuck": stuck, "clips": clips, "floor": floor_ratio, "ok": ok,
		"reason": reason, "extra": extra,
	})
	if not ok:
		_failures += 1
	print("WALK %-22s %s dist=%6.2f y=[%6.2f,%6.2f] stuck=%4.2fs clips=%d floor=%4.0f%% %s%s" % [
		name, "PASS" if ok else "FAIL", distance, min_y, max_y, stuck, clips,
		floor_ratio * 100.0, extra, ("  " + reason) if reason != "" else "",
	])


func _print_summary() -> void:
	var total_distance := 0.0
	var total_stuck := 0.0
	var total_clips := 0
	for section: Dictionary in _sections:
		total_distance += float(section["distance"])
		total_stuck += float(section["stuck"])
		total_clips += int(section["clips"])
	print("QUARRY_WALK sections=%d failures=%d distance=%.1f m stuck_total=%.2fs camera_clips=%d result=%s" % [
		_sections.size(), _failures, total_distance, total_stuck, total_clips,
		"PASS" if _failures == 0 else "FAIL",
	])
	for section: Dictionary in _sections:
		if not bool(section["ok"]):
			print("QUARRY_WALK_FAIL %s %s" % [section["name"], section["reason"]])
