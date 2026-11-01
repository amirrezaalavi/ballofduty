extends BodTestSuite
## Match lifecycle: the server runs a 5-minute clock, broadcasts the final
## table on expiry, restarts rounds after the intermission, and the client
## mirrors scores + clock for the HUD scoreboard. Direct logic calls with
## shrunken durations keep everything deterministic (no real-time waits).

const GM_SCRIPT := preload("res://scripts/game/game_manager.gd")
const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const HUD_SCRIPT := preload("res://scripts/ui/hud.gd")

var _world: Node3D
var _gms: Array = []
var _actors: Array = []
var _huds: Array = []
var _players: Array = []
var _match_events: Array = []
var _score_events: Array = []


func after_test() -> void:
	Input.action_release("scoreboard")
	for hud in _huds:
		if is_instance_valid(hud):
			hud.queue_free()
	_huds.clear()
	for player in _players:
		if is_instance_valid(player):
			player.free()
	_players.clear()
	for gm in _gms:
		if is_instance_valid(gm):
			gm.queue_free()
	_gms.clear()
	if is_instance_valid(_world):
		_world.free()
	_world = null
	_actors.clear()
	_match_events.clear()
	_score_events.clear()


func _bus() -> Node:
	return get_tree().root.get_node("EventBus")


func _new_world() -> void:
	_world = Node3D.new()
	add_child(_world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.55, 0.0)
	_world.add_child(floor_body)


## Server-mode GM with two hand-built roster entries (bot peers, no sockets).
## Match durations stay default until the test shrinks them, so the awaits in
## the build cannot trip a transition.
func _server_gm() -> Node:
	_new_world()
	var gm := GM_SCRIPT.new()
	add_child(gm)
	_gms.append(gm)
	gm._world = _world
	gm._spawns = [Vector3(-10.0, 0.0, 0.0), Vector3(10.0, 0.0, 0.0)]
	gm.net_mode = GM_SCRIPT.NetMode.SERVER
	for i in 2:
		var actor := PLAYER_SCENE.instantiate() as PlayerController
		_world.add_child(actor)
		actor.make_server(i + 1)
		actor.global_position = Vector3(-10.0 + 20.0 * float(i), 0.2, 0.0)
		_actors.append(actor)
		var entry: Dictionary = gm._new_entry(i + 1, "FIGHTER %d" % (i + 1), actor, -1001 - i)
		gm._roster[-1001 - i] = entry
		gm._by_id[i + 1] = entry
	return gm


func _client_gm() -> Node:
	var gm := GM_SCRIPT.new()
	add_child(gm)
	_gms.append(gm)
	gm._world = _world
	gm.net_mode = GM_SCRIPT.NetMode.CLIENT
	gm.local_id = 5
	return gm


func test_match_finish_emits_over_once() -> void:
	var gm := _server_gm()
	_bus().match_state_changed.connect(_on_match_state)
	gm.match_length_msec = 200
	gm._match_start_msec = Time.get_ticks_msec() - 1000
	gm._tick_match(Time.get_ticks_msec())
	expect(gm._match_over, "expired clock finishes the match")
	expect(_match_events.size() == 1, "exactly one match event (got %d)" % _match_events.size())
	expect(_match_events[0][0] == &"over" and float(_match_events[0][1]) == 0.0,
		"finish emits over with zero seconds")
	# A second tick while over must not re-emit: the UI reacts once per round.
	gm._tick_match(Time.get_ticks_msec())
	expect(_match_events.size() == 1, "no duplicate over emission while over")
	_bus().match_state_changed.disconnect(_on_match_state)


func test_round_restart_resets_scores_and_clock() -> void:
	var gm := _server_gm()
	_bus().match_state_changed.connect(_on_match_state)
	gm.match_length_msec = 200
	gm.match_intermission_msec = 200
	gm._on_server_death(2, 1, Vector3.ZERO)
	expect(int(gm._by_id[1]["kills"]) == 1, "killer banks the kill")
	gm._match_start_msec = Time.get_ticks_msec() - 1000
	gm._tick_match(Time.get_ticks_msec())
	expect(gm._match_over, "match is over")
	gm._tick_match(Time.get_ticks_msec() + 500)
	expect(not gm._match_over, "intermission ends into a new round")
	expect(int(gm._by_id[1]["kills"]) == 0 and int(gm._by_id[2]["deaths"]) == 0,
		"new round resets kills and deaths")
	expect(_match_events.size() == 2 and _match_events[1][0] == &"running",
		"restart emits running (got %s)" % str(_match_events))
	expect(float(_match_events[1][1]) > 0.0, "running carries the round length")
	_bus().match_state_changed.disconnect(_on_match_state)


func test_death_updates_scores_and_emits() -> void:
	var gm := _server_gm()
	_bus().score_changed.connect(_on_score)
	gm._on_server_death(2, 1, Vector3.ZERO)
	var table: Array = gm.server_match_scores()
	expect(table.size() == 2, "standings cover the roster")
	expect(int(table[0]["id"]) == 1 and int(table[0]["kills"]) == 1,
		"killer tops the table at 1-0")
	expect(int(table[1]["id"]) == 2 and int(table[1]["deaths"]) == 1,
		"victim sits second at 0-1")
	expect(_score_events.size() == 2, "killer and victim each emit score_changed")
	_bus().score_changed.disconnect(_on_score)


func test_client_scores_sort_and_merge() -> void:
	_new_world()
	var gm := _client_gm()
	gm._on_roster_updated([
		{"id": 5, "class_id": 0, "name": "Me"},
		{"id": 3, "class_id": 1, "name": "Zed"},
		{"id": 7, "class_id": 2, "name": "Alf"},
	])
	var rows: Array = gm.client_scores()
	expect(rows.size() == 3, "roster seeds three zeroed rows (got %d)" % rows.size())
	gm._on_score_received(NetProtocol.decode_score(NetProtocol.encode_score([
		{"id": 5, "kills": 2, "deaths": 1},
		{"id": 3, "kills": 5, "deaths": 0},
		{"id": 7, "kills": 2, "deaths": 0},
	]))["entries"])
	rows = gm.client_scores()
	expect([int(rows[0]["id"]), int(rows[1]["id"]), int(rows[2]["id"])] == [3, 7, 5],
		"scores sort kills desc, deaths asc (got %s)" % str([rows[0]["id"], rows[1]["id"], rows[2]["id"]]))
	expect(String(rows[0]["name"]) == "Zed", "authoritative scores keep roster names")
	# Incremental DEATH fallback (old servers): victim 7 dies to 5.
	gm._on_server_event({"type": NetProtocol.EventType.DEATH, "victim_id": 7, "killer_id": 5})
	rows = gm.client_scores()
	expect(int(rows[0]["id"]) == 3, "leader keeps the table after a mid-table kill")
	var credited := {}
	for row in rows:
		if int(row["id"]) == 5:
			credited = row
		if int(row["id"]) == 7:
			expect(int(row["deaths"]) == 1, "death event marks the victim")
	expect(int(credited.get("kills", -1)) == 3, "death event credits the killer")


func test_solo_death_is_not_a_kill() -> void:
	# Solo has no bots, so a death is always the local player's. The first
	# implementation incremented kills here and the scoreboard credited you for
	# dying.
	_new_world()
	var gm := GM_SCRIPT.new()
	add_child(gm)
	_gms.append(gm)
	gm.net_mode = GM_SCRIPT.NetMode.OFFLINE
	var rows: Array = gm.client_scores()
	expect(rows.size() == 1, "solo has one YOU row")
	expect(int(rows[0]["kills"]) == 0 and int(rows[0]["deaths"]) == 0, "solo starts 0-0")
	gm._on_bus_player_died(1, 2, Vector3.ZERO)
	rows = gm.client_scores()
	expect(int(rows[0]["kills"]) == 0, "dying never counts as a kill (got %d)" % int(rows[0]["kills"]))
	expect(int(rows[0]["deaths"]) == 1, "dying counts as a death (got %d)" % int(rows[0]["deaths"]))


func test_client_match_edges_and_countdown() -> void:
	_new_world()
	var gm := _client_gm()
	_bus().match_state_changed.connect(_on_match_state)
	expect(gm.client_match_seconds_left() == -1.0, "no clock before the first heartbeat")
	expect(not gm.match_is_over(), "not over before the first heartbeat")
	gm._on_match_received({"state": NetProtocol.MatchState.RUNNING, "seconds_left": 300})
	gm._on_match_received({"state": NetProtocol.MatchState.RUNNING, "seconds_left": 299})
	expect(_match_events.size() == 1 and _match_events[0][0] == &"running",
		"heartbeats refresh without re-emitting (got %d)" % _match_events.size())
	var left: float = gm.client_match_seconds_left()
	expect(left > 290.0 and left <= 299.0, "countdown extrapolates from the heartbeat (%.1f)" % left)
	gm._match_stamp_msec -= 310000
	expect(gm.client_match_seconds_left() == 0.0, "stale countdown floors at zero, never negative")
	gm._on_match_received({"state": NetProtocol.MatchState.OVER, "seconds_left": 0})
	expect(gm.match_is_over(), "over state latches")
	expect(gm.client_match_seconds_left() == -1.0, "no countdown once over")
	expect(_match_events.size() == 2 and _match_events[1][0] == &"over",
		"over emits exactly once")
	_bus().match_state_changed.disconnect(_on_match_state)


func test_hud_scoreboard_toggle_and_rows() -> void:
	var actor := PLAYER_SCENE.instantiate() as PlayerController
	add_child(actor)
	_players.append(actor)
	var hud := HUD_SCRIPT.new() as Control
	add_child(hud)
	_huds.append(hud)
	hud.bind_player(actor)
	expect(not hud.scoreboard_visible(), "scoreboard starts hidden")

	# Polled like gameplay input (Tab never reliably reaches _unhandled_input).
	Input.action_press("scoreboard")
	var before: int = hud.redraw_requests
	hud._process(1.0 / 60.0)
	expect(hud.scoreboard_visible(), "held Tab shows the scoreboard")
	expect(hud.redraw_requests == before + 1, "toggle requests one redraw")
	var rows: Array = hud.score_rows()
	expect(rows.size() == 1 and String(rows[0]["name"]) == "YOU",
		"solo scoreboard lists the local row")
	expect(hud.clock_text() == "", "solo practice shows no match clock")

	Input.action_release("scoreboard")
	hud._process(1.0 / 60.0)
	expect(not hud.scoreboard_visible(), "released Tab hides the scoreboard")


func _on_match_state(state: StringName, seconds_left: float) -> void:
	_match_events.append([state, seconds_left])


func _on_score(player_id: int, kills: int, deaths: int) -> void:
	_score_events.append([player_id, kills, deaths])
