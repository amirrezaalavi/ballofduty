extends BodTestSuite
## Step 1 HUD dirty-flag contract: every state change requests a redraw, an idle
## frame requests none, and transient animations keep redrawing until they decay.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const HUD_SCRIPT := preload("res://scripts/ui/hud.gd")
const DT := 1.0 / 60.0
const MAX_FRAMES := 240

var _players: Array[PlayerController] = []
var _huds: Array[Control] = []


func after_test() -> void:
	for hud in _huds:
		if is_instance_valid(hud):
			hud.queue_free()
	_huds.clear()
	for player in _players:
		if is_instance_valid(player):
			player.free()
	_players.clear()


func test_idle_process_does_not_request_redraw() -> void:
	var player := await _spawn(0, 201)
	var hud := _make_hud(player)
	expect(is_equal_approx(hud._damage_flash, 0.0), "binding a full-health player does not flash")
	hud.redraw_requests = 0
	for _i in 30:
		hud._process(DT)
	expect(hud.redraw_requests == 0,
		"idle _process requests no redraws (got %d)" % hud.redraw_requests)


func test_bind_player_requests_redraw() -> void:
	var player := await _spawn(0, 202)
	var hud := HUD_SCRIPT.new() as Control
	add_child(hud)
	_huds.append(hud)
	hud.set_process(false)
	hud._debug = false
	hud.redraw_requests = 0
	hud.bind_player(player)
	expect(hud.redraw_requests > 0, "binding a player requests a redraw")
	expect(hud.player == player, "bind_player keeps the player reference")


func test_damage_flash_redraws_until_it_decays() -> void:
	var player := await _spawn(0, 203)
	var hud := _make_hud(player)
	hud.redraw_requests = 0
	hud._on_health(50, 100)
	expect(hud._damage_flash > 0.0, "damage sets the flash timer")
	expect(hud.redraw_requests == 1, "health change requests one redraw")
	expect(hud._health_current == 50, "health value still updates")

	var frames := 0
	while hud._damage_flash > 0.0 and frames < MAX_FRAMES:
		var before: int = hud.redraw_requests
		hud._process(DT)
		expect(hud.redraw_requests == before + 1,
			"flash frame %d requests a redraw" % frames)
		frames += 1
	expect(frames > 0 and frames < MAX_FRAMES,
		"damage flash decays in a bounded number of frames (%d)" % frames)

	var settled: int = hud.redraw_requests
	hud._process(DT)
	expect(hud.redraw_requests == settled, "no redraw once the flash has ended")


func test_hitmarker_and_crosshair_kick_animate_out() -> void:
	var player := await _spawn(0, 204)
	var hud := _make_hud(player)

	hud.redraw_requests = 0
	hud._on_hit(false)
	expect(hud._hit_time > 0.0, "hit sets the hitmarker timer")
	expect(hud._kill_time <= 0.0, "a non-lethal hit shows no kill banner")
	expect(hud.redraw_requests == 1, "hit requests one redraw")
	var hit_frames := 0
	while hud._hit_time > 0.0 and hit_frames < MAX_FRAMES:
		var before: int = hud.redraw_requests
		hud._process(DT)
		expect(hud.redraw_requests == before + 1,
			"hitmarker frame %d requests a redraw" % hit_frames)
		hit_frames += 1
	expect(hit_frames > 0 and hit_frames < MAX_FRAMES,
		"hitmarker animates out (%d frames)" % hit_frames)
	var settled: int = hud.redraw_requests
	hud._process(DT)
	expect(hud.redraw_requests == settled, "hitmarker stops requesting redraws")

	hud.redraw_requests = 0
	hud._on_shot(Vector3.ZERO, Vector3.FORWARD)
	expect(hud._crosshair_kick > 0.0, "shot kicks the crosshair")
	expect(hud.redraw_requests == 1, "shot requests one redraw")
	var kick_frames := 0
	while hud._crosshair_kick > 0.0 and kick_frames < MAX_FRAMES:
		var before: int = hud.redraw_requests
		hud._process(DT)
		expect(hud.redraw_requests == before + 1,
			"crosshair kick frame %d requests a redraw" % kick_frames)
		kick_frames += 1
	expect(kick_frames > 0 and kick_frames < MAX_FRAMES,
		"crosshair kick animates out (%d frames)" % kick_frames)


func test_kill_banner_requests_redraw() -> void:
	var player := await _spawn(0, 205)
	var hud := _make_hud(player)
	hud.redraw_requests = 0
	hud._on_hit(true)
	expect(hud._kill_time > 0.0, "a kill raises the kill banner timer")
	expect(hud.redraw_requests == 1, "kill requests one redraw")
	var frames := 0
	while hud._kill_time > 0.0 and frames < MAX_FRAMES:
		var before: int = hud.redraw_requests
		hud._process(DT)
		expect(hud.redraw_requests == before + 1,
			"kill banner frame %d requests a redraw" % frames)
		frames += 1
	expect(frames > 0 and frames < MAX_FRAMES,
		"kill banner decays in a bounded number of frames (%d)" % frames)


func test_state_setters_request_redraw() -> void:
	var player := await _spawn(0, 206)
	var hud := _make_hud(player)

	hud.redraw_requests = 0
	hud._on_ammo(12, 30)
	expect(hud.redraw_requests == 1, "ammo change requests a redraw")
	expect(hud.ammo_text() == "12", "ammo text still follows the signal")

	hud.redraw_requests = 0
	hud._on_reload(true)
	expect(hud.redraw_requests == 1, "reload change requests a redraw")
	expect(hud.state_label() == "RELOADING", "reload label still shows")
	hud._on_reload(false)

	hud.redraw_requests = 0
	hud._on_heat(2.0, 5.0)
	expect(hud.redraw_requests == 1, "heat change requests a redraw")
	expect(is_equal_approx(hud.heat_ratio(), 0.4), "heat meter still updates")

	hud.redraw_requests = 0
	hud._on_charge(0.5)
	expect(hud.redraw_requests == 1, "charge change requests a redraw")
	expect(is_equal_approx(hud.charge_ratio(), 0.5), "charge meter still updates")

	hud.redraw_requests = 0
	hud._on_weapon_changed("Arcane Staff")
	expect(hud.redraw_requests == 1, "weapon change requests a redraw")
	expect(hud.weapon_name_text() == "Arcane Staff", "weapon label still updates")

	hud.redraw_requests = 0
	hud._on_health(80, 100)
	expect(hud.redraw_requests == 1, "health change requests a redraw")
	expect(hud._health_max == 100, "health maximum still updates")


func test_server_shot_does_not_force_redraw() -> void:
	var player := await _spawn(0, 207)
	var hud := _make_hud(player)
	var before: int = hud._shots_seen
	hud.redraw_requests = 0
	hud._on_server_shot(99, Vector3.ZERO, Vector3.FORWARD)
	expect(hud._shots_seen == before + 1, "server shot still counts")
	expect(hud.redraw_requests == 0,
		"server shot relies on the 4 Hz debug refresh, not a per-shot redraw")


func test_death_and_respawn_request_redraw() -> void:
	var player := await _spawn(0, 208)
	var hud := _make_hud(player)
	expect(not hud._dead, "HUD starts alive")

	hud.redraw_requests = 0
	hud._on_death(player.net_id, 0)
	expect(hud._dead, "local death raises the respawn overlay")
	expect(hud.redraw_requests == 1, "death requests one redraw")

	hud.redraw_requests = 0
	hud._on_death(999, 0)
	expect(hud._dead, "a remote death does not clear the local overlay")
	expect(hud.redraw_requests == 1, "a remote death still marks the HUD dirty")

	hud.redraw_requests = 0
	hud._on_respawn(player.net_id, Vector3.ZERO, 0.0)
	expect(not hud._dead, "respawn clears the overlay")
	expect(hud.redraw_requests == 1, "respawn requests one redraw")


func test_f3_toggles_debug_and_requests_redraw() -> void:
	var player := await _spawn(0, 209)
	var hud := _make_hud(player)
	expect(not hud._debug, "debug strip starts hidden")

	var event := InputEventKey.new()
	event.keycode = KEY_F3
	event.pressed = true
	hud.redraw_requests = 0
	hud._unhandled_input(event)
	expect(hud._debug, "F3 enables the debug strip")
	expect(hud.redraw_requests == 1, "F3 requests one redraw")

	# The debug text refreshes at 4 Hz, not every frame.
	hud._debug_timer = 0.25
	hud.redraw_requests = 0
	hud._process(DT)
	expect(hud.redraw_requests == 0, "debug text does not redraw every frame")

	hud._debug_timer = 0.0
	hud.redraw_requests = 0
	hud._process(DT)
	expect(hud.redraw_requests == 1, "the 4 Hz debug refresh requests a redraw")
	expect(hud._debug_timer > 0.0, "the debug timer is re-armed")

	hud.redraw_requests = 0
	hud._unhandled_input(event)
	expect(not hud._debug, "a second F3 hides the debug strip")
	expect(hud.redraw_requests == 1, "hiding the debug strip requests a redraw")


func _spawn(class_id: int, net_id: int) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.class_id = class_id
	player.net_id = net_id
	add_child(player)
	_players.append(player)
	for _i in 4:
		await get_tree().physics_frame
	for _i in 8:
		await get_tree().process_frame
	player.set_physics_process(false)
	return player


func _make_hud(player: PlayerController) -> Control:
	var hud := HUD_SCRIPT.new() as Control
	add_child(hud)
	_huds.append(hud)
	# Keep _process deterministic: tests drive it by hand.
	hud.set_process(false)
	hud._debug = false
	hud.bind_player(player)
	return hud
