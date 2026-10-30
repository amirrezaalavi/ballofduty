extends SceneTree
## Headless performance probe for the shipping maps, the authoritative server
## tick, the wire codec, projectile churn and the heaviest client scripts.
##
##   tools/godot --headless --path . --script tests/headless/perf_probe.gd
##   tools/godot --headless --path . --script tests/headless/perf_probe.gd -- --quick
##
## Everything is measured with Time.get_ticks_usec() and reported as
## avg / p95 / max. Machine-readable lines start with "PERF ". This harness is
## read-only: it never edits gameplay, balance, protocol or visuals. The only
## mutation is spawning/despawning throwaway actors, projectiles and map
## instances inside its own worlds.
##
## Caveats stated in the report:
##   * headless uses the dummy renderer, so GPU/draw and shader costs are absent;
##   * the CPU is a shared container vCPU, not a browser;
##   * "client script" numbers are CPU-only lower bounds.

const DT := 1.0 / 30.0
const FRAME_DT := 1.0 / 60.0

const ARENA_QUARRY := "res://scenes/maps/arena_quarry.tscn"
const ARENA_NATURE := "res://scenes/maps/arena_nature.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const PLAYER_SCENE_PATH := "res://scenes/characters/player.tscn"
const PROJECTILE_SCENE_PATH := "res://scenes/weapons/projectile.tscn"
const RIFLE_STATS_PATH := "res://resources/weapons/rifle_stats.tres"

# Loaded lazily so the cold-load section is not warmed by this harness itself.
var _bus_script: Script
var _gm_script: Script
var _net_script: Script
var _hud_script: Script
var _bullet_field_script: Script

var _quick := false
var _tick_samples: Dictionary = {}
var _ray_samples: Array = []


## Minimal transport stand-in. Isolates server CPU from socket scheduling so the
## tick numbers are comparable across machines. Packets are counted, not sent.
class FakeNet extends Node:
	signal peer_joined(peer_id, player_name, class_id)
	signal peer_left(peer_id)
	signal remote_input(peer_id, frame)
	signal join_accepted(player_id, spawn)
	signal join_denied(reason)
	signal roster_updated(entries)
	signal snapshot_received(tick, entries)
	signal event_received(event)
	signal disconnected_from_server

	var packets: int = 0
	var bytes: int = 0

	func start_server(_port: int) -> int:
		return OK

	func server_send(_peer_id: int, pkt: PackedByteArray) -> void:
		packets += 1
		bytes += pkt.size()

	func stop() -> void:
		pass

	func connection_status() -> int:
		return MultiplayerPeer.CONNECTION_DISCONNECTED

	func jitter_ticks() -> int:
		return 0


func _init() -> void:
	_run()


func _run() -> void:
	_quick = OS.get_cmdline_user_args().has("--quick")
	await process_frame
	_print_context()
	await _cold_loads()
	_bus_script = load("res://scripts/autoload/event_bus.gd")
	_gm_script = load("res://scripts/game/game_manager.gd")
	_net_script = load("res://scripts/networking/network_manager.gd")
	_hud_script = load("res://scripts/ui/hud.gd")
	_bullet_field_script = load("res://scripts/weapons/bullet_field.gd")
	await _arena_section(ARENA_QUARRY, "quarry")
	await _arena_section(ARENA_NATURE, "nature")
	await _main_boot()
	await _server_section()
	await _collider_cost_section()
	await _codec_section()
	await _projectile_section()
	await _client_script_section()
	_print_memory_summary()
	print("PERF done")
	quit(0)


# --- output helpers -------------------------------------------------------

func _print_context() -> void:
	var info := Engine.get_version_info()
	var cpu_name := "unknown"
	var f := FileAccess.open("/proc/cpuinfo", FileAccess.READ)
	if f:
		for _i in 64:
			var line := f.get_line()
			if line.begins_with("model name"):
				cpu_name = line.split(":", true, 1)[1].strip_edges()
				break
		f.close()
	print("PERF_CONTEXT engine=%s renderer=%s display=%s os=%s cpu=%s cores=%d physics_hz=%d max_fps=%d" % [
		String(info["string"]), ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		DisplayServer.get_name(), OS.get_name(), cpu_name, OS.get_processor_count(),
		Engine.physics_ticks_per_second, Engine.max_fps,
	])
	print("PERF_CONTEXT static_mem_mb=%.1f node_count=%d orphan=%d" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	])


func _mem() -> Dictionary:
	return {
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


func _mem_line(tag: String, m: Dictionary) -> void:
	print("PERF_MEM tag=%s static_mb=%.1f nodes=%d orphans=%d objects=%d resources=%d" % [
		tag, float(m["static_mb"]), int(m["nodes"]), int(m["orphans"]),
		int(m["objects"]), int(m["resources"]),
	])


func _stats(values: Array) -> Dictionary:
	var n := values.size()
	if n == 0:
		return {"n": 0, "avg": 0.0, "p95": 0.0, "max": 0.0, "total": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in values:
		total += float(v)
	var idx := clampi(int(ceil(float(n) * 0.95)) - 1, 0, n - 1)
	return {
		"n": n, "avg": total / float(n), "p95": float(sorted[idx]),
		"max": float(sorted[n - 1]), "total": total,
	}


func _stat_text(values: Array) -> String:
	var s := _stats(values)
	return "n=%d avg=%.1f p95=%.1f max=%.1f total=%.1f" % [
		int(s["n"]), float(s["avg"]), float(s["p95"]), float(s["max"]), float(s["total"]),
	]


func _print_stat(tag: String, unit: String, values: Array) -> void:
	var s := _stats(values)
	print("PERF_STAT tag=%s unit=%s n=%d avg=%.2f p95=%.2f max=%.2f total=%.2f" % [
		tag, unit, int(s["n"]), float(s["avg"]), float(s["p95"]),
		float(s["max"]), float(s["total"]),
	])


func _usec(callable: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	callable.call()
	return float(Time.get_ticks_usec() - t0)


# --- cold resource loads --------------------------------------------------

func _cold_loads() -> void:
	print("PERF_SECTION cold_loads")
	for path: String in [
		PLAYER_SCENE_PATH, ARENA_QUARRY, ARENA_NATURE, PROJECTILE_SCENE_PATH,
		RIFLE_STATS_PATH, MAIN_SCENE,
	]:
		var t0 := Time.get_ticks_usec()
		var res: Resource = load(path)
		var us := float(Time.get_ticks_usec() - t0)
		print("PERF_LOAD path=%s ok=%s us=%.0f" % [path, str(res != null), us])
		await process_frame


# --- arena build ----------------------------------------------------------

func _arena_section(path: String, label: String) -> void:
	print("PERF_SECTION arena_%s" % label)
	var before := _mem()
	var t0 := Time.get_ticks_usec()
	var packed := load(path) as PackedScene
	var load_us := float(Time.get_ticks_usec() - t0)
	t0 = Time.get_ticks_usec()
	var arena := packed.instantiate() as Node3D
	var inst_us := float(Time.get_ticks_usec() - t0)
	t0 = Time.get_ticks_usec()
	root.add_child(arena)
	var gen_us := float(Time.get_ticks_usec() - t0)
	await process_frame
	await physics_frame
	await physics_frame
	var after := _mem()
	var counts := _count_arena(arena)
	print("PERF_ARENA map=%s load_us=%.0f instantiate_us=%.0f generate_us=%.0f total_us=%.0f nodes=%d meshes=%d multimesh_instances=%d colliders=%d triangles=%d surfaces=%d static_mb=%.1f node_delta=%d orphan_delta=%d" % [
		label, load_us, inst_us, gen_us, load_us + inst_us + gen_us,
		int(counts["nodes"]), int(counts["meshes"]), int(counts["instances"]),
		int(counts["colliders"]), int(counts["triangles"]), int(counts["surfaces"]),
		float(after["static_mb"]) - float(before["static_mb"]),
		int(after["nodes"]) - int(before["nodes"]),
		int(after["orphans"]) - int(before["orphans"]),
	])
	_mem_line("after_%s" % label, after)
	arena.free()
	await process_frame
	await physics_frame
	var freed := _mem()
	_mem_line("freed_%s" % label, freed)
	print("PERF_ARENA_FREE map=%s orphan=%d node=%d" % [
		label, int(freed["orphans"]), int(freed["nodes"]),
	])
	# Breakdown runs on a detached instance so the real total above stays clean.
	_breakdown(path, label, packed)


func _count_arena(root_node: Node) -> Dictionary:
	var out := {"nodes": 0, "meshes": 0, "instances": 0, "colliders": 0,
		"triangles": 0, "surfaces": 0}
	_count_node(root_node, out)
	return out


func _count_node(node: Node, out: Dictionary) -> void:
	out["nodes"] = int(out["nodes"]) + 1
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm and mm.mesh:
			out["meshes"] = int(out["meshes"]) + 1
			out["surfaces"] = int(out["surfaces"]) + mm.mesh.get_surface_count()
			out["triangles"] = int(out["triangles"]) + (
				(mm.mesh.get_faces().size() / 3) * mm.instance_count
			)
			out["instances"] = int(out["instances"]) + mm.instance_count
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			out["meshes"] = int(out["meshes"]) + 1
			out["surfaces"] = int(out["surfaces"]) + mi.mesh.get_surface_count()
			out["triangles"] = int(out["triangles"]) + mi.mesh.get_faces().size() / 3
	if node is CollisionShape3D:
		out["colliders"] = int(out["colliders"]) + 1
	for child in node.get_children():
		_count_node(child, out)


## Replays the arena's own build steps one at a time on an off-tree instance.
## Underscore methods are convention-private; calling them from the probe keeps
## the measurement on the real code path without editing the arena.
func _breakdown(path: String, label: String, packed: PackedScene) -> void:
	var arena := packed.instantiate() as Node3D
	var steps: Array = [] # [name, usec]
	var t0 := 0

	t0 = Time.get_ticks_usec()
	if label == "quarry":
		arena._props_root = arena._node_or_new("Props")
		arena._terrain_root = arena._node_or_new("Terrain")
		arena._cave_root = arena._node_or_new("Cave")
		arena._boundary_root = arena._node_or_new("Boundary")
	else:
		arena._props_root = arena.get_node_or_null("Props") as Node3D
		if arena._props_root == null:
			arena._props_root = Node3D.new()
			arena._props_root.name = "Props"
			arena.add_child(arena._props_root)
	steps.append(["roots", Time.get_ticks_usec() - t0])

	t0 = Time.get_ticks_usec()
	if label == "quarry":
		arena._snap_spawn_markers()
	for child in arena.get_children():
		if child is Marker3D and child.name.begins_with("Spawn"):
			arena._spawns.append((child as Marker3D).position)
	if arena._spawns.is_empty():
		if label == "quarry":
			for spot: Vector3 in arena.SPAWN_LAYOUT:
				arena._spawns.append(spot)
	steps.append(["spawns", Time.get_ticks_usec() - t0])

	arena._rng.seed = arena.SEED

	if label == "quarry":
		t0 = Time.get_ticks_usec()
		arena._detail_texture()
		steps.append(["detail_texture_256px", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._build_materials()
		steps.append(["materials_incl_texture", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		for cz in arena.CHUNK_GRID:
			for cx in arena.CHUNK_GRID:
				var origin := Vector3(
					-arena.MAP_HALF + float(cx) * arena.CHUNK_SIZE, 0.0,
					-arena.MAP_HALF + float(cz) * arena.CHUNK_SIZE)
				arena._build_chunk_mesh(origin)
		steps.append(["terrain_chunk_meshes_x9", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		for cz in arena.CHUNK_GRID:
			for cx in arena.CHUNK_GRID:
				var ox: float = -float(arena.MAP_HALF) + float(cx) * float(arena.CHUNK_SIZE)
				var oz: float = -float(arena.MAP_HALF) + float(cz) * float(arena.CHUNK_SIZE)
				for iz in arena.CHUNK_SAMPLES:
					for ix in arena.CHUNK_SAMPLES:
						arena.height_at(ox + float(ix), oz + float(iz))
		steps.append(["heightmap_sample_23409", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._build_terrain()
		steps.append(["terrain_nodes_shape_total", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._build_boundary()
		steps.append(["boundary", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._build_cave()
		steps.append(["cave", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._dress_cave_ridge()
		steps.append(["dress_cave_ridge", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._place_hero_props()
		steps.append(["hero_props", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._scatter_dressing()
		steps.append(["scatter_dressing", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		for i in 200:
			arena._is_dressing_clear(Vector3(30.0 + float(i % 3), 0.0, 30.0), 1.1)
		steps.append(["dressing_clear_x200", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._build_multimeshes()
		steps.append(["multimesh_build", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._build_colliders()
		steps.append(["colliders_build", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		arena._connect_cave_atmosphere()
		steps.append(["cave_atmosphere", Time.get_ticks_usec() - t0])
	else:
		t0 = Time.get_ticks_usec()
		arena._place_hero_props()
		steps.append(["hero_props", Time.get_ticks_usec() - t0])
		t0 = Time.get_ticks_usec()
		arena._place_border()
		steps.append(["border", Time.get_ticks_usec() - t0])
		t0 = Time.get_ticks_usec()
		arena._scatter_foliage()
		steps.append(["scatter_foliage", Time.get_ticks_usec() - t0])

		t0 = Time.get_ticks_usec()
		for i in 200:
			arena._is_clear(Vector3(12.0 + float(i % 3), 0.0, 12.0), 1.2)
		steps.append(["is_clear_x200", Time.get_ticks_usec() - t0])
		t0 = Time.get_ticks_usec()
		arena._build_multimeshes()
		steps.append(["multimesh_build", Time.get_ticks_usec() - t0])
		t0 = Time.get_ticks_usec()
		arena._build_colliders()
		steps.append(["colliders_build", Time.get_ticks_usec() - t0])

	var sum := 0
	var real_sum := 0
	for step: Array in steps:
		sum += int(step[1])
		var name := String(step[0])
		if name != "detail_texture_256px" and name != "terrain_chunk_meshes_x9" \
				and name != "heightmap_sample_23409" and name != "dressing_clear_x200" \
				and name != "is_clear_x200":
			real_sum += int(step[1])
		print("PERF_BUILD map=%s step=%s us=%d" % [label, name, int(step[1])])
	print("PERF_BUILD map=%s step=sum_of_steps us=%d real_sequence_sum us=%d placements=%d colliders=%d" % [
		label, sum, real_sum, _placement_count(arena), arena._colliders.size(),
	])
	arena.free()


func _placement_count(arena: Node3D) -> int:
	var total := 0
	for key in arena._placements:
		total += (arena._placements[key] as Array).size()
	return total


# --- main scene boot (join-latency proxy) ---------------------------------

func _main_boot() -> void:
	print("PERF_SECTION main_boot")
	var before := _mem()
	var t0 := Time.get_ticks_usec()
	var packed := load(MAIN_SCENE) as PackedScene
	var load_us := float(Time.get_ticks_usec() - t0)
	t0 = Time.get_ticks_usec()
	var main := packed.instantiate()
	var inst_us := float(Time.get_ticks_usec() - t0)
	t0 = Time.get_ticks_usec()
	root.add_child(main)
	var ready_us := float(Time.get_ticks_usec() - t0)
	t0 = Time.get_ticks_usec()
	await process_frame
	var first_frame_us := float(Time.get_ticks_usec() - t0)
	t0 = Time.get_ticks_usec()
	await process_frame
	var second_frame_us := float(Time.get_ticks_usec() - t0)
	var after := _mem()
	_print_orphans("main_boot")
	print("PERF_MAIN load_us=%.0f instantiate_us=%.0f ready_us=%.0f first_frame_us=%.0f second_frame_us=%.0f total_us=%.0f nodes=%d orphan=%d static_mb=%.1f" % [
		load_us, inst_us, ready_us, first_frame_us, second_frame_us,
		load_us + inst_us + ready_us, int(after["nodes"]), int(after["orphans"]),
		float(after["static_mb"]) - float(before["static_mb"]),
	])
	main.queue_free()
	await process_frame
	await process_frame
	await process_frame
	_mem_line("after_main_free", _mem())


# --- server tick ----------------------------------------------------------

func _server_section() -> void:
	print("PERF_SECTION server_tick")
	var bus := root.get_node_or_null("EventBus")
	if bus == null:
		bus = _bus_script.new()
		bus.name = "EventBus"
		root.add_child(bus)
	var packed := load(ARENA_QUARRY) as PackedScene
	var world := packed.instantiate() as Node3D
	world.name = "PerfWorld"
	root.add_child(world)
	await physics_frame
	await physics_frame
	var base_children := world.get_children()

	var net := FakeNet.new()
	net.name = "FakeNet"
	root.add_child(net)

	var gm: Node = null
	for bots: int in [0, 5, 8]:
		if gm != null:
			gm.stop_all()
			gm.queue_free()
			gm = null
		for child in world.get_children():
			if not base_children.has(child):
				child.queue_free()
		await process_frame
		await physics_frame

		gm = _gm_script.new()
		gm.name = "PerfGM"
		root.add_child(gm)
		gm.net = net
		var boot0 := Time.get_ticks_usec()
		var err: int = gm.server_start(world, 0, bots)
		var boot_us := float(Time.get_ticks_usec() - boot0)
		if err != OK:
			print("PERF_SERVER bots=%d result=FAIL err=%d" % [bots, err])
			continue
		print("PERF_SERVER_START bots=%d us=%.0f" % [bots, boot_us])
		gm.set_physics_process(false)
		for _i in 4:
			gm._physics_process(DT)
			await physics_frame
		var ticks := 120 if _quick else 300
		var samples: Array = []
		var wall: Array = []
		var ray_count := 0
		var start_us := Time.get_ticks_usec()
		for _i in ticks:
			var w0 := Time.get_ticks_usec()
			gm._physics_process(DT)
			var us := float(Time.get_ticks_usec() - w0)
			samples.append(us)
			await physics_frame
			wall.append(float(Time.get_ticks_usec() - w0))
		var elapsed_ms := float(Time.get_ticks_usec() - start_us) / 1000.0
		var roster_size: int = int(gm.server_player_count())
		var shots := int(gm._combat.shots_fired) if gm._combat else 0
		var active_proj := int(gm._combat.projectiles_active()) if gm._combat else 0
		# Bot LOS + feeler per actor, one aim trace per shot, one sweep per live
		# projectile per tick. This is the analytic query count, not a counter.
		ray_count = roster_size * 2
		_tick_samples[bots] = samples
		_print_stat("server_tick_bots_%d" % bots, "us", samples)
		var s := _stats(samples)
		var ws := _stats(wall)
		print("PERF_SERVER bots=%d ticks=%d roster=%d avg_us=%.1f p95_us=%.1f max_us=%.1f avg_ms=%.2f p95_ms=%.2f tick_budget_pct=%.1f wall_avg_ms=%.1f approx_raycasts_per_tick=%d elapsed_ms=%.0f" % [
			bots, ticks, roster_size, float(s["avg"]), float(s["p95"]), float(s["max"]),
			float(s["avg"]) / 1000.0, float(s["p95"]) / 1000.0,
			float(s["p95"]) / 33333.3 * 100.0, float(ws["avg"]) / 1000.0,
			ray_count, elapsed_ms,
		])
		print("PERF_SERVER_DETAIL bots=%d shots_total=%d projectiles_active_end=%d rays_per_tick_est=%.2f (bot_los+feeler=%d, aim_traces=%.2f, projectile_sweeps=%.2f)" % [
			bots, shots, active_proj,
			float(ray_count) + float(shots) / float(ticks) + float(active_proj) / float(ticks),
			ray_count, float(shots) / float(ticks), float(active_proj) / float(ticks),
		])
		if bots == 8:
			await _measure_tick_breakdown(gm, ticks)
			_measure_snapshot_entries(gm)

	if gm != null and is_instance_valid(gm):
		gm.stop_all()
		gm.queue_free()
	for child in world.get_children():
		if not base_children.has(child):
			child.queue_free()
	await process_frame
	world.queue_free()
	net.queue_free()
	await process_frame
	await process_frame
	await physics_frame


func _measure_tick_breakdown(gm: Node, ticks: int) -> void:
	var bot_us: Array = []
	var combat_us: Array = []
	var move_us: Array = []
	var snap_us: Array = []
	var los_us: Array = []
	var feeler_us: Array = []
	var entries: Array = []
	for _i in ticks:
		for peer_id in gm._roster:
			var entry: Dictionary = gm._roster[peer_id]
			var actor_ref: Variant = entry["node"]
			if not is_instance_valid(actor_ref):
				continue
			var actor := actor_ref as PlayerController
			var t0 := Time.get_ticks_usec()
			var frame: PlayerInputFrame = gm._bot_frame(entry, actor, DT)
			bot_us.append(float(Time.get_ticks_usec() - t0))
			t0 = Time.get_ticks_usec()
			var shot: Dictionary = gm._combat.process(entry, actor, frame, DT)
			combat_us.append(float(Time.get_ticks_usec() - t0))
			if not shot.is_empty():
				pass
			t0 = Time.get_ticks_usec()
			actor.server_step(frame, DT)
			move_us.append(float(Time.get_ticks_usec() - t0))
			t0 = Time.get_ticks_usec()
			entries.append(gm._snapshot_entry(entry, actor))
			snap_us.append(float(Time.get_ticks_usec() - t0))
		# Raw primitive raycast costs, same query shape the bot uses.
		var actors: Array = []
		for peer_id in gm._roster:
			var e: Dictionary = gm._roster[peer_id]
			if is_instance_valid(e["node"]):
				actors.append(e["node"])
		if actors.size() >= 2:
			var a := actors[0] as PlayerController
			var b := actors[1] as PlayerController
			var t1 := Time.get_ticks_usec()
			gm._has_los(a, b)
			los_us.append(float(Time.get_ticks_usec() - t1))
			var fwd := -a.global_transform.basis.z
			var q := PhysicsRayQueryParameters3D.create(
				a.global_position + Vector3(0.0, 0.45, 0.0),
				a.global_position + Vector3(0.0, 0.45, 0.0) + fwd * 1.3, 1)
			t1 = Time.get_ticks_usec()
			a.get_world_3d().direct_space_state.intersect_ray(q)
			feeler_us.append(float(Time.get_ticks_usec() - t1))
		await physics_frame
	_print_stat("tick_breakdown_bot_ai_8", "us", bot_us)
	_print_stat("tick_breakdown_combat_8", "us", combat_us)
	_print_stat("tick_breakdown_movement_8", "us", move_us)
	_print_stat("tick_breakdown_snapshot_entry_8", "us", snap_us)
	_print_stat("raycast_los", "us", los_us)
	_print_stat("raycast_feeler", "us", feeler_us)
	var n := float(ticks)
	print("PERF_TICK_BREAKDOWN bots=8 ticks=%d bot_ai_per_tick_us=%.1f combat_per_tick_us=%.1f move_per_tick_us=%.1f snapshot_per_tick_us=%.1f los_per_ray_us=%.1f feeler_per_ray_us=%.1f" % [
		ticks, _sum(bot_us) / n, _sum(combat_us) / n, _sum(move_us) / n,
		_sum(snap_us) / n, _sum(los_us) / maxf(1.0, float(los_us.size())),
		_sum(feeler_us) / maxf(1.0, float(feeler_us.size())),
	])


func _measure_snapshot_entries(gm: Node) -> void:
	var entries: Array = []
	for peer_id in gm._roster:
		var entry: Dictionary = gm._roster[peer_id]
		var actor_ref: Variant = entry["node"]
		if is_instance_valid(actor_ref):
			entries.append(gm._snapshot_entry(entry, actor_ref as PlayerController))
	if entries.is_empty():
		return
	var pkt := NetProtocol.encode_snapshot(12345, entries)
	print("PERF_SNAPSHOT_SAMPLE actors=%d bytes=%d" % [entries.size(), pkt.size()])


func _print_orphans(tag: String) -> void:
	var ids: Array = Node.get_orphan_node_ids()
	if ids.is_empty():
		print("PERF_ORPHANS tag=%s count=0" % tag)
		return
	var classes: Dictionary = {}
	for id in ids:
		var node: Object = instance_from_id(int(id))
		if node == null:
			continue
		var key := String(node.get_class())
		classes[key] = int(classes.get(key, 0)) + 1
	var parts: PackedStringArray = []
	for key in classes:
		parts.append("%s:%d" % [String(key), int(classes[key])])
	print("PERF_ORPHANS tag=%s count=%d classes=%s" % [tag, ids.size(), ",".join(parts)])


func _no_rids() -> Array[RID]:
	var out: Array[RID] = []
	return out


func _sum(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += float(v)
	return total


# --- static collider cost -------------------------------------------------

func _collider_cost_section() -> void:
	print("PERF_SECTION collider_cost")
	var packed := load(ARENA_QUARRY) as PackedScene
	var world := packed.instantiate() as Node3D
	world.name = "ColliderWorld"
	root.add_child(world)
	await physics_frame
	await physics_frame
	var pscene := load(PLAYER_SCENE_PATH) as PackedScene
	var actor := pscene.instantiate() as PlayerController
	world.add_child(actor)
	actor.make_server(1, 0)
	actor.global_position = Vector3(-20.0, 1.2, 20.0)
	var frame := PlayerInputFrame.new()
	frame.move = Vector2(0.0, -1.0)
	frame.yaw = 0.0
	var with_us := _step_actor(actor, frame, 200)
	var bodies := world.find_children("*", "StaticBody3D", true, false)
	var props := 0
	for body in bodies:
		if String(body.name).begins_with("PropCollider"):
			props += 1
			body.queue_free()
	await process_frame
	await physics_frame
	await physics_frame
	var without_us := _step_actor(actor, frame, 200)
	var a := _stats(with_us)
	var b := _stats(without_us)
	print("PERF_COLLIDERS static_bodies=%d prop_colliders=%d airborne_with_avg_us=%.1f airborne_without_avg_us=%.1f delta_us=%.1f" % [
		bodies.size(), props, float(a["avg"]), float(b["avg"]),
		float(a["avg"]) - float(b["avg"]),
	])
	_print_stat("server_step_airborne_all_colliders", "us", with_us)
	_print_stat("server_step_airborne_terrain_only", "us", without_us)

	# Grounded cost: a heightfield contact does far more work than a free fall.
	actor.global_position = Vector3(0.0, 0.6, 20.0)
	actor.velocity = Vector3.ZERO
	for _i in 12:
		await physics_frame
	var grounded_us: Array = []
	for _i in 200:
		var t0 := Time.get_ticks_usec()
		actor.server_step(frame, DT)
		grounded_us.append(float(Time.get_ticks_usec() - t0))
	_print_stat("server_step_grounded_one", "us", grounded_us)
	var g := _stats(grounded_us)
	print("PERF_MOVEMENT_COST grounded_one_avg_us=%.1f p95_us=%.1f airborne_one_avg_us=%.1f" % [
		float(g["avg"]), float(g["p95"]), float(a["avg"]),
	])

	# Eight grounded actors, clustered vs spread: player-player contacts.
	var group: Array = []
	for i in 8:
		var p := pscene.instantiate() as PlayerController
		world.add_child(p)
		p.make_server(10 + i, i % 5)
		group.append(p)
		await physics_frame
	var cluster_us := await _measure_group(group, frame, 90, 2.0)
	var spread_us := await _measure_group(group, frame, 90, 10.0)
	var cs := _stats(cluster_us)
	var ss := _stats(spread_us)
	print("PERF_MOVEMENT_GROUP actors=8 cluster_per_actor_us=%.1f spread_per_actor_us=%.1f delta_us=%.1f" % [
		float(cs["avg"]), float(ss["avg"]), float(cs["avg"]) - float(ss["avg"]),
	])
	_print_stat("server_step_group_clustered", "us", cluster_us)
	_print_stat("server_step_group_spread", "us", spread_us)
	world.queue_free()
	await process_frame
	await process_frame
	await physics_frame


func _measure_group(group: Array, frame: PlayerInputFrame, ticks: int, spacing: float) -> Array:
	for i in group.size():
		var p := group[i] as PlayerController
		var col := i % 4
		var row := i / 4
		p.global_position = Vector3(-20.0 + float(col) * spacing, 0.8, 20.0 + float(row) * spacing)
		p.velocity = Vector3.ZERO
	for _i in 10:
		await physics_frame
	var out: Array = []
	for _i in ticks:
		for p in group:
			var t0 := Time.get_ticks_usec()
			(p as PlayerController).server_step(frame, DT)
			out.append(float(Time.get_ticks_usec() - t0))
		await physics_frame
	return out


func _step_actor(actor: PlayerController, frame: PlayerInputFrame, n: int) -> Array:
	var out: Array = []
	for _i in n:
		actor.global_position = Vector3(-20.0, 1.2, 20.0)
		actor.velocity = Vector3.ZERO
		var t0 := Time.get_ticks_usec()
		actor.server_step(frame, DT)
		out.append(float(Time.get_ticks_usec() - t0))
	return out


# --- codec ----------------------------------------------------------------

func _codec_section() -> void:
	print("PERF_SECTION codec")
	var entries: Array = []
	for i in 8:
		entries.append({
			"id": i + 1,
			"pos": Vector3(-40.0 + float(i) * 12.0, 0.4 + float(i % 3), -30.0 + float(i) * 8.0),
			"yaw": float(i) * 0.7 - 2.0,
			"state": i % 4,
			"vel": Vector3(1.5, -0.2, -2.0 + float(i) * 0.1),
			"on_floor": true,
			"hp": 100 - i * 3,
			"ack": 100000 + i * 37,
		})
	var encode_us: Array = []
	var decode_us: Array = []
	var pkt := PackedByteArray()
	for _i in 2000:
		var t0 := Time.get_ticks_usec()
		pkt = NetProtocol.encode_snapshot(999999, entries)
		encode_us.append(float(Time.get_ticks_usec() - t0))
		t0 = Time.get_ticks_usec()
		NetProtocol.decode_snapshot(pkt)
		decode_us.append(float(Time.get_ticks_usec() - t0))
	_print_stat("snapshot_encode_8", "us", encode_us)
	_print_stat("snapshot_decode_8", "us", decode_us)
	var enc := _stats(encode_us)
	var dec := _stats(decode_us)
	print("PERF_CODEC snapshot_8 bytes=%d encode_avg_us=%.2f encode_p95_us=%.2f decode_avg_us=%.2f decode_p95_us=%.2f" % [
		pkt.size(), float(enc["avg"]), float(enc["p95"]), float(dec["avg"]), float(dec["p95"]),
	])
	# Input packet: 12 B at 30 Hz upstream.
	var inp_us: Array = []
	for _i in 2000:
		var t0 := Time.get_ticks_usec()
		var ip := NetProtocol.encode_input(42, Vector2(0.4, -0.8), false, true, false, 1.2, -0.3, true, false)
		NetProtocol.decode_input(ip)
		inp_us.append(float(Time.get_ticks_usec() - t0))
	_print_stat("input_encode_decode", "us", inp_us)


# --- projectile churn -----------------------------------------------------

func _projectile_section() -> void:
	print("PERF_SECTION projectile")
	var packed := load(ARENA_QUARRY) as PackedScene
	var world := packed.instantiate() as Node3D
	world.name = "ProjWorld"
	root.add_child(world)
	await physics_frame
	await physics_frame
	var stats := load(RIFLE_STATS_PATH) as WeaponStats
	var pscene := load(PROJECTILE_SCENE_PATH) as PackedScene
	var before := _mem()
	var spawn_us: Array = []
	var burst := 60
	var spawned: Array = []
	for i in burst:
		var t0 := Time.get_ticks_usec()
		var p := pscene.instantiate() as Projectile
		world.add_child(p)
		p.global_position = Vector3(-20.0 + float(i % 10) * 4.0, 3.0, -10.0 + float(i / 10) * 4.0)
		var down := Vector3(0.02, -1.0, 0.02).normalized()
		p.setup(down, stats, 1, _no_rids(), -1, -1, Vector3.ZERO)
		spawn_us.append(float(Time.get_ticks_usec() - t0))
		spawned.append(p)
	var peak := _mem()
	var frames := 0
	var resolve_start := Time.get_ticks_usec()
	while frames < 90:
		var alive := 0
		for child in world.get_children():
			if child is Projectile:
				alive += 1
		if alive == 0:
			break
		await physics_frame
		frames += 1
	var resolve_ms := float(Time.get_ticks_usec() - resolve_start) / 1000.0
	var after := _mem()
	_print_stat("projectile_spawn", "us", spawn_us)
	var s := _stats(spawn_us)
	print("PERF_PROJECTILE burst=%d spawn_avg_us=%.1f spawn_p95_us=%.1f resolve_frames=%d resolve_ms=%.1f node_delta_peak=%d node_delta_after=%d orphan_after=%d" % [
		burst, float(s["avg"]), float(s["p95"]), frames, resolve_ms,
		int(peak["nodes"]) - int(before["nodes"]),
		int(after["nodes"]) - int(before["nodes"]), int(after["orphans"]),
	])
	# Isolate the per-projectile swept-ray cost: 30 rounds, one physics step.
	var ray_us: Array = []
	for _i in 120:
		var p := pscene.instantiate() as Projectile
		world.add_child(p)
		p.global_position = Vector3(0.0, 20.0, 0.0)
		p.setup(Vector3(0.02, -1.0, 0.02).normalized(), stats, 1, _no_rids(), -1, -1, Vector3.ZERO)
		var t0 := Time.get_ticks_usec()
		p._physics_process(DT)
		ray_us.append(float(Time.get_ticks_usec() - t0))
		p.free()
	_print_stat("projectile_physics_step", "us", ray_us)
	world.queue_free()
	await process_frame
	await process_frame
	await physics_frame


# --- client scripts -------------------------------------------------------

func _client_script_section() -> void:
	print("PERF_SECTION client_scripts")
	var packed := load(ARENA_QUARRY) as PackedScene
	var world := packed.instantiate() as Node3D
	world.name = "ClientWorld"
	root.add_child(world)
	await physics_frame
	await physics_frame
	var pscene := load(PLAYER_SCENE_PATH) as PackedScene

	# Local player + seven remotes: the live 8-actor client shape.
	var actors: Array = []
	for i in 8:
		var p := pscene.instantiate() as PlayerController
		world.add_child(p)
		p.global_position = Vector3(-30.0 + float(i) * 8.0, 1.0, 0.0)
		if i == 0:
			# Keep the first actor LOCAL so its script path matches the player.
			p.enable_prediction()
			p.set_physics_process(false)
		else:
			p.make_remote(i + 1, i % 5)
		actors.append(p)
	for _i in 6:
		await physics_frame
		await process_frame

	var local := actors[0] as PlayerController
	var vis_local := local.get_node_or_null("Visual") as CharacterVisual
	var vis_remote := (actors[1] as PlayerController).get_node_or_null("Visual") as CharacterVisual
	vis_local.set_process(false)
	vis_remote.set_process(false)
	var vis_local_us: Array = []
	var vis_remote_us: Array = []
	var vis_blocks: Array = []
	for block in 3:
		var block_us: Array = []
		for _i in 100:
			var t0 := Time.get_ticks_usec()
			vis_local._process(FRAME_DT)
			vis_local_us.append(float(Time.get_ticks_usec() - t0))
			block_us.append(vis_local_us[-1])
			t0 = Time.get_ticks_usec()
			vis_remote._process(FRAME_DT)
			vis_remote_us.append(float(Time.get_ticks_usec() - t0))
		vis_blocks.append(_stats(block_us)["avg"])
	_print_stat("char_visual_local", "us", vis_local_us)
	_print_stat("char_visual_remote", "us", vis_remote_us)
	print("PERF_CHARVISUAL_BLOCKS local_avg_us=%s" % str(vis_blocks))
	var lv := _stats(vis_local_us)
	var rv := _stats(vis_remote_us)
	print("PERF_CHARVISUAL local_avg_us=%.1f local_p95_us=%.1f remote_avg_us=%.1f remote_p95_us=%.1f seven_remotes_ms=%.2f" % [
		float(lv["avg"]), float(lv["p95"]), float(rv["avg"]), float(rv["p95"]),
		float(rv["avg"]) * 7.0 / 1000.0,
	])

	# NetworkInterpolator: 8 streams pushed once per snapshot at 30 Hz.
	var interps: Array = []
	for i in 8:
		var interp := NetworkInterpolator.new()
		root.add_child(interp)
		interps.append(interp)
	var interp_us: Array = []
	for tick in 300:
		var t0 := Time.get_ticks_usec()
		for i in 8:
			interps[i].push_sample(
				tick, Vector3(float(i), 0.0, float(tick) * 0.1),
				float(tick) * 0.02, tick % 4, Vector3(1.0, 0.0, 0.0))
		interp_us.append(float(Time.get_ticks_usec() - t0))
	_print_stat("interpolator_push_8", "us", interp_us)
	var interp_sample_us: Array = []
	for tick in 300:
		var t0 := Time.get_ticks_usec()
		interps[0].sample(FRAME_DT)
		interp_sample_us.append(float(Time.get_ticks_usec() - t0))
		interps[0].push_sample(tick, Vector3(float(tick) * 0.05, 0.0, 0.0), 0.0, 1, Vector3(1.0, 0.0, 0.0))
	_print_stat("interpolator_sample_one", "us", interp_sample_us)
	for interp in interps:
		interp.free()
	var local_pc_us: Array = []
	var remote_pc_us: Array = []
	var remote_actor := actors[1] as PlayerController
	for i in 300:
		if i % 2 == 0:
			var ri := remote_actor.get_node_or_null("NetworkInterpolator") as NetworkInterpolator
			if ri:
				ri.push_sample(1000 + i, remote_actor.global_position, 0.0, 1, Vector3.ZERO)
		var t0 := Time.get_ticks_usec()
		local._process(FRAME_DT)
		local_pc_us.append(float(Time.get_ticks_usec() - t0))
		t0 = Time.get_ticks_usec()
		remote_actor._process(FRAME_DT)
		remote_pc_us.append(float(Time.get_ticks_usec() - t0))
	_print_stat("player_controller_local_process", "us", local_pc_us)
	_print_stat("player_controller_remote_process", "us", remote_pc_us)

	# Local reconciliation of one authoritative row.
	local.enable_prediction()
	local.last_seq = 9999
	var ack_us: Array = []
	for i in 300:
		var entry := {
			"id": 0, "pos": Vector3(float(i % 10), 0.5, 0.0), "yaw": 0.0,
			"state": 1, "vel": Vector3.ZERO, "on_floor": true, "hp": 100,
			"ack": 9000 + i,
		}
		var t0 := Time.get_ticks_usec()
		local.accept_server_state(entry)
		local._process(FRAME_DT)
		ack_us.append(float(Time.get_ticks_usec() - t0))
	_print_stat("local_accept_state", "us", ack_us)

	# HUD. queue_redraw itself is trivial; measure the per-frame string work and
	# the full draw pass A/B (headless still runs CanvasItem command recording).
	var hud := _hud_script.new() as Control
	root.add_child(hud)
	hud.bind_player(local)
	hud.set_process(false)
	var hud_process_us: Array = []
	var fmt_us: Array = []
	for _i in 300:
		var t0 := Time.get_ticks_usec()
		hud._process(FRAME_DT)
		hud_process_us.append(float(Time.get_ticks_usec() - t0))
		t0 = Time.get_ticks_usec()
		var hp_text := "%d HP" % 100
		var ammo_text := str(30)
		var reserve: String = String(hud.reserve_text())
		var state: String = String(hud.state_label())
		var name_upper: String = String(hud.weapon_name_text()).to_upper()
		fmt_us.append(float(Time.get_ticks_usec() - t0))
		if hp_text == "" or ammo_text == "" or reserve == "" or state == "" or name_upper == "":
			pass
	_print_stat("hud_process_queue_redraw", "us", hud_process_us)
	_print_stat("hud_per_frame_strings", "us", fmt_us)
	var draw_seen := 0
	hud.draw.connect(func() -> void: draw_seen += 1)
	hud.queue_redraw()
	await process_frame
	print("PERF_HUD draw_signal_count=%d note=headless_dummy_renderer_skips_canvas_draw" % draw_seen)
	_print_stat("hud_debug_text_refresh", "us", _repeat(300, func() -> void: hud._refresh_debug_text()))
	hud.free()

	# Transport decode + signal emit path (NetworkManager._route_client).
	var nm := _net_script.new() as Node
	root.add_child(nm)
	var codec_entries: Array = []
	for i in 8:
		codec_entries.append({
			"id": i + 1, "pos": Vector3(float(i), 0.5, 0.0), "yaw": 0.0,
			"state": 0, "vel": Vector3.ZERO, "on_floor": true, "hp": 100, "ack": 0,
		})
	var snap_pkt := NetProtocol.encode_snapshot(500, codec_entries)
	var route_us: Array = []
	for _i in 500:
		var t0 := Time.get_ticks_usec()
		nm._route_client(NetProtocol.Msg.SNAPSHOT, snap_pkt)
		route_us.append(float(Time.get_ticks_usec() - t0))
	_print_stat("netmanager_route_snapshot", "us", route_us)
	nm.free()

	# BulletField pool: build cost, launch cost, and the per-bullet render ray.
	var field := _bullet_field_script.new() as Node3D
	var pool_before := _mem()
	var t0 := Time.get_ticks_usec()
	field._ensure_pool()
	var pool_us := float(Time.get_ticks_usec() - t0)
	var pool_after := _mem()
	world.add_child(field)
	var launch_us: Array = []
	for _i in 300:
		var lt := Time.get_ticks_usec()
		field._launch(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0), 81.0, true, _no_rids())
		launch_us.append(float(Time.get_ticks_usec() - lt))
	var bullet_us: Array = []
	for _i in 120:
		for bullet: BulletVisual in field._bullets:
			bullet.launch(
				Vector3(0.0, 1.5, 0.0), Vector3(0.0, 0.0, -1.0), 81.0, 1.2, _no_rids(),
				field._body_materials[0], field._trail_materials[0], field._rim_materials[0])
		var bt := Time.get_ticks_usec()
		for bullet: BulletVisual in field._bullets:
			bullet._process(FRAME_DT)
		bullet_us.append(float(Time.get_ticks_usec() - bt))
	_print_stat("bulletfield_pool_build", "us", [pool_us])
	_print_stat("bulletfield_launch", "us", launch_us)
	_print_stat("bulletfield_64_process_frames", "us", bullet_us)
	var bu := _stats(bullet_us)
	print("PERF_BULLETFIELD pool_build_us=%.0f pool_nodes=%d pool_static_mb=%.1f launch_avg_us=%.1f sixtyfour_avg_us=%.1f per_bullet_us=%.2f" % [
		pool_us, int(pool_after["nodes"]) - int(pool_before["nodes"]),
		float(pool_after["static_mb"]) - float(pool_before["static_mb"]),
		float(_stats(launch_us)["avg"]), float(bu["avg"]), float(bu["avg"]) / 64.0,
	])
	BulletField._instance = null
	field.queue_free()

	world.queue_free()
	await process_frame
	await process_frame
	await physics_frame
	_mem_line("after_client_scripts", _mem())


func _repeat(n: int, callable: Callable) -> Array:
	var out: Array = []
	for _i in n:
		var t0 := Time.get_ticks_usec()
		callable.call()
		out.append(float(Time.get_ticks_usec() - t0))
	return out


func _print_memory_summary() -> void:
	print("PERF_SECTION memory_summary")
	_mem_line("final", _mem())
	print("PERF_STATIC os_static_mb=%.1f os_static_peak_mb=%.1f" % [
		OS.get_static_memory_usage() / 1048576.0,
		OS.get_static_memory_peak_usage() / 1048576.0,
	])
