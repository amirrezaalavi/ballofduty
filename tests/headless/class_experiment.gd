extends SceneTree
## Controlled class race on the current nature arena: one authoritative server,
## five bots (exactly one per class), five 60 s matches, fresh world each run.
## No clients, no time-scale tricks, no gameplay changes — this only observes.
##
##   tools/godot --headless --path . --script tests/headless/class_experiment.gd
##
## Every machine-readable line starts with "CLASS_EXPERIMENT ". The human
## report is rewritten at res://docs/experiments/2026-10-30-class-race.md.
##
## Winner rule: most kills, then fewest deaths, then most dealt damage.
## Server roster order is bot index % 5, i.e. Knight, Mage, Rogue,
## Rogue_Hooded, Barbarian.

const ARENA := preload("res://scenes/maps/arena_nature.tscn")
const NET_SCRIPT := preload("res://scripts/networking/network_manager.gd")
const GM_SCRIPT := preload("res://scripts/game/game_manager.gd")
const BUS_SCRIPT := preload("res://scripts/autoload/event_bus.gd")

const OUTPUT_PATH := "res://docs/experiments/2026-10-30-class-race.md"
const RUN_COUNT := 5
const MATCH_SECONDS := 60.0
const BOT_COUNT := 5
const PORT := 9197
const CLASS_NAMES: Array[String] = [
	"Knight", "Mage", "Rogue", "Rogue_Hooded", "Barbarian",
]
const SPAWN_PROTECTION_NOTE := "3 s respawn delay; 5 min match timer ignored"

var _bus: Node
var _damage_by_source: Dictionary = {}
var _worlds: Array = []
var _runs: Array = []
var _fail_reason := ""


func _init() -> void:
	_run()


func _run() -> void:
	seed(20261030)
	_ensure_bus()
	print("CLASS_EXPERIMENT config arena=arena_nature runs=%d seconds=%.0f bots=%d port=%d classes=%s" % [
		RUN_COUNT, MATCH_SECONDS, BOT_COUNT, PORT, ",".join(PackedStringArray(CLASS_NAMES)),
	])

	for run_index in range(1, RUN_COUNT + 1):
		var result := await _run_match(run_index)
		if result.has("error"):
			_fail(result["error"])
			break
		_runs.append(result)
		_print_run(result)
		if run_index == 1:
			var sanity := _sanity(result)
			if not bool(sanity["ok"]):
				_fail("sanity: " + String(sanity["reason"]))
				break
			print("CLASS_EXPERIMENT sanity run=1 result=PASS shots=%d kills=%d deaths=%d" % [
				int(sanity["shots"]), int(sanity["kills"]), int(sanity["deaths"]),
			])

	if _fail_reason == "":
		_write_report(_runs)
		_print_aggregate(_aggregate(_runs))
		print("CLASS_EXPERIMENT result=PASS runs=%d total_kills=%d" % [
			_runs.size(), _total_kills(_runs),
		])
	else:
		_write_report(_runs, _fail_reason)
		print("CLASS_EXPERIMENT result=FAIL reason=%s runs_completed=%d" % [
			_fail_reason, _runs.size(),
		])

	await _cleanup()
	quit(0 if _fail_reason == "" else 1)


func _ensure_bus() -> void:
	# --script mode does not register autoloads; the authoritative hit/death
	# path needs the same EventBus the real game uses.
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


func _run_match(run_index: int) -> Dictionary:
	_damage_by_source.clear()

	var world := ARENA.instantiate() as Node3D
	world.name = "ClassRaceWorld_%d" % run_index
	root.add_child(world)
	_worlds.append(world)
	await physics_frame

	var net: Node = NET_SCRIPT.new()
	var gm: Node = GM_SCRIPT.new()
	root.add_child(net)
	root.add_child(gm)
	gm.net = net

	var err: int = gm.server_start(world, PORT, BOT_COUNT)
	if err != OK:
		await _teardown(gm, net, world)
		return {"error": "server_start err=%d port=%d" % [err, PORT]}
	if gm.server_player_count() != BOT_COUNT:
		await _teardown(gm, net, world)
		return {"error": "spawned %d/%d bots" % [gm.server_player_count(), BOT_COUNT]}

	for _i in 3:
		await physics_frame

	var start_msec := Time.get_ticks_msec()
	var duration_msec := int(MATCH_SECONDS * 1000.0)
	var next_progress_msec := 15000
	while Time.get_ticks_msec() - start_msec < duration_msec:
		await physics_frame
		var elapsed := Time.get_ticks_msec() - start_msec
		if elapsed >= next_progress_msec:
			print("CLASS_EXPERIMENT run=%d progress=%.0fs tick=%d shots=%d deaths=%d" % [
				run_index, float(elapsed) / 1000.0, int(gm._server_tick),
				_combat_shots(gm), int(gm._deaths_total),
			])
			next_progress_msec += 15000

	var duration := float(Time.get_ticks_msec() - start_msec) / 1000.0
	var stats := _snapshot(gm)
	var shots := _combat_shots(gm)
	var hits := int(gm._hits_total)
	var deaths_total := int(gm._deaths_total)
	var decision := _decide_winner(stats)

	await _teardown(gm, net, world)

	return {
		"run": run_index,
		"stats": stats,
		"winner": String(decision["winner"]),
		"tied": decision["tied"],
		"shots": shots,
		"hits": hits,
		"deaths_total": deaths_total,
		"duration": duration,
	}


func _teardown(gm: Node, net: Node, world: Node) -> void:
	if is_instance_valid(gm):
		gm.stop_all()
	if is_instance_valid(net):
		net.stop()
	if is_instance_valid(world):
		world.queue_free()
		_worlds.erase(world)
	await process_frame
	await process_frame
	await create_timer(0.3).timeout


func _snapshot(gm: Node) -> Array:
	var stats: Array = []
	for peer_id in gm._roster:
		var entry: Dictionary = gm._roster[peer_id]
		var class_id := int(entry["class_id"])
		stats.append({
			"id": int(entry["id"]),
			"name": String(entry["name"]),
			"class_id": class_id,
			"cls": CLASS_NAMES[class_id],
			"kills": int(entry["kills"]),
			"deaths": int(entry["deaths"]),
			"damage": int(_damage_by_source.get(int(entry["id"]), 0)),
		})
	stats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["class_id"]) < int(b["class_id"]))
	return stats


func _combat_shots(gm: Node) -> int:
	return int(gm._combat.shots_fired) if gm._combat else 0


func _decide_winner(stats: Array) -> Dictionary:
	var order := stats.duplicate()
	order.sort_custom(_stat_better)
	var top: Dictionary = order[0]
	var tied: Array = []
	for entry: Dictionary in order:
		if (
			int(entry["kills"]) == int(top["kills"])
			and int(entry["deaths"]) == int(top["deaths"])
			and int(entry["damage"]) == int(top["damage"])
		):
			tied.append(entry)
	if tied.size() == 1:
		return {"winner": String(top["cls"]), "tied": tied}
	var names: Array[String] = []
	for entry: Dictionary in tied:
		names.append(String(entry["cls"]))
	return {"winner": "TIE(" + ", ".join(names) + ")", "tied": tied}


func _stat_better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["kills"]) != int(b["kills"]):
		return int(a["kills"]) > int(b["kills"])
	if int(a["deaths"]) != int(b["deaths"]):
		return int(a["deaths"]) < int(b["deaths"])
	if int(a["damage"]) != int(b["damage"]):
		return int(a["damage"]) > int(b["damage"])
	return int(a["class_id"]) < int(b["class_id"])


func _sanity(run: Dictionary) -> Dictionary:
	var kills := 0
	var deaths := 0
	for entry: Dictionary in run["stats"]:
		kills += int(entry["kills"])
		deaths += int(entry["deaths"])
	if int(run["shots"]) <= 0:
		return {"ok": false, "reason": "bots did not fire", "shots": 0, "kills": kills, "deaths": deaths}
	if kills <= 0 or deaths <= 0:
		return {
			"ok": false, "reason": "no kills/deaths in run 1",
			"shots": int(run["shots"]), "kills": kills, "deaths": deaths,
		}
	return {"ok": true, "reason": "", "shots": int(run["shots"]), "kills": kills, "deaths": deaths}


func _print_run(run: Dictionary) -> void:
	for entry: Dictionary in run["stats"]:
		print("CLASS_EXPERIMENT run=%d bot=%s class=%s kills=%d deaths=%d damage=%d winner=%s" % [
			int(run["run"]), String(entry["name"]), String(entry["cls"]),
			int(entry["kills"]), int(entry["deaths"]), int(entry["damage"]),
			String(run["winner"]),
		])
	print("CLASS_EXPERIMENT run=%d summary winner=%s shots=%d hits=%d deaths=%d duration=%.1fs" % [
		int(run["run"]), String(run["winner"]), int(run["shots"]), int(run["hits"]),
		int(run["deaths_total"]), float(run["duration"]),
	])


func _aggregate(runs: Array) -> Array:
	var agg: Array = []
	for class_id in CLASS_NAMES.size():
		agg.append({
			"class_id": class_id, "cls": CLASS_NAMES[class_id],
			"kills": 0, "deaths": 0, "damage": 0, "wins": 0, "matches": 0,
		})
	for run: Dictionary in runs:
		for entry: Dictionary in run["stats"]:
			var row: Dictionary = agg[int(entry["class_id"])]
			row["kills"] = int(row["kills"]) + int(entry["kills"])
			row["deaths"] = int(row["deaths"]) + int(entry["deaths"])
			row["damage"] = int(row["damage"]) + int(entry["damage"])
			row["matches"] = int(row["matches"]) + 1
		for entry: Dictionary in run["tied"]:
			var winner_row: Dictionary = agg[int(entry["class_id"])]
			winner_row["wins"] = int(winner_row["wins"]) + 1
	return agg


func _print_aggregate(agg: Array) -> void:
	for row: Dictionary in agg:
		var matches := maxi(int(row["matches"]), 1)
		print("CLASS_EXPERIMENT_AGG class=%s runs=%d kills=%d deaths=%d wins=%d avg_kills=%.2f damage=%d" % [
			String(row["cls"]), int(row["matches"]), int(row["kills"]), int(row["deaths"]),
			int(row["wins"]), float(row["kills"]) / float(matches), int(row["damage"]),
		])


func _total_kills(runs: Array) -> int:
	var total := 0
	for run: Dictionary in runs:
		for entry: Dictionary in run["stats"]:
			total += int(entry["kills"])
	return total


func _write_report(runs: Array, fail_reason: String = "") -> void:
	var lines: Array[String] = []
	var agg := _aggregate(runs)

	lines.append("# Class Race Experiment — 2026-10-30")
	lines.append("")
	lines.append("Generated by `tests/headless/class_experiment.gd` on the current map ")
	lines.append("`res://scenes/maps/arena_nature.tscn` (`%s`)." % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("## Setup")
	lines.append("")
	lines.append("- 5 authoritative server bots, one per class (no clients).")
	lines.append("- 5 runs × 60 s of real-time headless physics per match ")
	lines.append("  (`%s`)." % SPAWN_PROTECTION_NOTE)
	lines.append("- Port %d; a fresh arena world, NetworkManager and GameManager per run." % PORT)
	lines.append("- No `Engine.time_scale` changes and no gameplay/balance edits.")
	lines.append("- Winner: most kills, then fewest deaths, then most dealt damage. ")
	lines.append("  A full tie is marked as a shared win.")
	lines.append("")

	if fail_reason != "":
		lines.append("> **RUN FAILED:** %s. Results below are partial." % fail_reason)
		lines.append("")

	lines.append("## Per-run results")
	lines.append("")
	lines.append("| Run | Class | Kills | Deaths | Damage | Match winner |")
	lines.append("|---:|---|---:|---:|---:|---|")
	for run: Dictionary in runs:
		for entry: Dictionary in run["stats"]:
			lines.append("| %d | %s | %d | %d | %d | %s |" % [
				int(run["run"]), String(entry["cls"]), int(entry["kills"]),
				int(entry["deaths"]), int(entry["damage"]), String(run["winner"]),
			])
	lines.append("")

	lines.append("## Aggregate")
	lines.append("")
	lines.append("| Class | Kills | Deaths | Wins | Avg kills/match | Damage |")
	lines.append("|---|---:|---:|---:|---:|---:|")
	var total_kills := 0
	var total_deaths := 0
	for row: Dictionary in agg:
		var matches := maxi(int(row["matches"]), 1)
		total_kills += int(row["kills"])
		total_deaths += int(row["deaths"])
		lines.append("| %s | %d | %d | %d | %.2f | %d |" % [
			String(row["cls"]), int(row["kills"]), int(row["deaths"]), int(row["wins"]),
			float(row["kills"]) / float(matches), int(row["damage"]),
		])
	lines.append("| **Total** | **%d** | **%d** | **%d** | — | — |" % [
		total_kills, total_deaths, runs.size(),
	])
	lines.append("")

	lines.append("## Match winners")
	lines.append("")
	for run: Dictionary in runs:
		lines.append("- Run %d: **%s** (%d kills by the winner)" % [
			int(run["run"]), String(run["winner"]), _winner_kills(run),
		])
	lines.append("")
	lines.append("## Conclusion")
	lines.append("")
	lines.append(_conclusion(agg, runs, fail_reason, total_kills))
	lines.append("")
	lines.append("## Rerun")
	lines.append("")
	lines.append("```")
	lines.append("./tools/godot --headless --path . --script tests/headless/class_experiment.gd")
	lines.append("```")
	lines.append("")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/experiments"))
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		print("CLASS_EXPERIMENT warn report_write_failed=%s" % OUTPUT_PATH)
		return
	file.store_string("\n".join(PackedStringArray(lines)) + "\n")
	file.close()
	print("CLASS_EXPERIMENT report=%s" % OUTPUT_PATH)


func _winner_kills(run: Dictionary) -> int:
	var best := 0
	for entry: Dictionary in run["tied"]:
		best = maxi(best, int(entry["kills"]))
	return best


func _conclusion(agg: Array, runs: Array, fail_reason: String, total_kills: int) -> String:
	if fail_reason != "":
		return "Run aborted: %s. No balance conclusion is drawn from partial data." % fail_reason
	if runs.is_empty():
		return "No runs completed."
	var best_wins := -1
	var leaders: Array[String] = []
	for row: Dictionary in agg:
		var wins := int(row["wins"])
		if wins > best_wins:
			best_wins = wins
			leaders.clear()
			leaders.append(String(row["cls"]))
		elif wins == best_wins:
			leaders.append(String(row["cls"]))
	var leader_text := _join_names(leaders)
	var kill_best := -1
	var kill_leaders: Array[String] = []
	var kill_leader_row: Dictionary = {}
	for row: Dictionary in agg:
		var kills := int(row["kills"])
		if kills > kill_best:
			kill_best = kills
			kill_leaders.clear()
			kill_leaders.append(String(row["cls"]))
			kill_leader_row = row
		elif kills == kill_best:
			kill_leaders.append(String(row["cls"]))
	var kill_matches := maxi(int(kill_leader_row.get("matches", 1)), 1)
	var kill_note := "%s led raw kills with %d (%.2f per match)" % [
		_join_names(kill_leaders), kill_best, float(kill_best) / float(kill_matches),
	]
	if leaders.size() == 1:
		var leader_row: Dictionary = {}
		for row: Dictionary in agg:
			if String(row["cls"]) == leaders[0]:
				leader_row = row
		var matches := maxi(int(leader_row["matches"]), 1)
		return (
			"**%s wins the most matches (%d/%d)**, with %d kills and %d deaths "
			+ "(%.2f kills per match). %d kills were scored across %d runs; %s. "
			+ "Single-seed evidence from one map and one bot behaviour profile; "
			+ "treat it as a baseline, not a final tier list."
		) % [
			leaders[0], best_wins, runs.size(), int(leader_row["kills"]),
			int(leader_row["deaths"]), float(leader_row["kills"]) / float(matches),
			total_kills, runs.size(), kill_note,
		]
	return (
		"**%s tie on match wins (%d each).** %d kills were scored across %d "
		+ "runs; %s. Single-seed evidence from one map and one bot behaviour "
		+ "profile; treat it as a baseline, not a final tier list."
	) % [leader_text, best_wins, total_kills, runs.size(), kill_note]


func _join_names(names: Array[String]) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return names[0] + " and " + names[1]
	var head := ", ".join(PackedStringArray(names.slice(0, names.size() - 1)))
	return head + " and " + names[-1]


func _fail(reason: String) -> void:
	_fail_reason = reason
	print("CLASS_EXPERIMENT ERROR %s" % reason)


func _cleanup() -> void:
	for world: Node in _worlds:
		if is_instance_valid(world):
			world.queue_free()
	_worlds.clear()
	await process_frame
	await process_frame
