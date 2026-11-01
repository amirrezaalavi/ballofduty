extends Control
## CP3/2A HUD: crosshair, health, class weapon name, ammo, heat/charge,
## hitmarker, damage flash, kill feed. Draws in one CanvasItem to keep the web
## HUD cheap.

const ACCENT := Color(0.2, 0.85, 0.75, 0.9)
const HEAT_COLOR := Color(1.0, 0.55, 0.22, 0.95)
const CHARGE_COLOR := Color(0.36, 0.72, 1.0, 0.95)
const MUTED := Color(0.55, 0.64, 0.8)

var player: PlayerController
var weapon: WeaponController
var health: HealthComponent
var _gm: Node

var _health_current: int = 100
var _health_max: int = 100
var _ammo: int = 30
var _reserve: int = -1
var _reloading: bool = false
var _hit_time: float = 0.0
var _kill_time: float = 0.0
var _damage_flash: float = 0.0
var _crosshair_kick: float = 0.0
var _dead: bool = false
var _font: Font

# Hold-Tab scoreboard + match clock. Repaints ride the same dirty flag: the
# clock dirties on second changes, the table on GameManager.score_revision.
var _scoreboard_visible: bool = false
var _seen_revision: int = -1
var _seen_second: int = -1
var _clock_on: bool = false

# Phase 2A class weapon state.
var _weapon_name: String = "Heavy Javelin"
var _fire_mode: String = "SINGLE"
var _heat: float = 0.0
var _heat_max: float = 0.0
var _charge: float = 0.0

# Cheap debug strip (F3 or --combat-hud). Counters are integers; the two text
# lines are refreshed 4x/s so drawing never allocates per frame.
var _debug: bool = false
var _debug_timer: float = 0.0
var _shots_local: int = 0
var _hits_local: int = 0
var _kills_local: int = 0
var _shots_seen: int = 0
var _deaths_seen: int = 0
var _pool_text: String = ""
var _net_text: String = ""

# Redraw telemetry: incremented by every queue_redraw() request so tests can
# assert that idle frames do not repaint the HUD.
var redraw_requests: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	_debug = OS.get_cmdline_user_args().has("--combat-hud")

	var current := get_tree().current_scene
	var found := current.get_node_or_null("Player") as PlayerController if current else null
	if found == null:
		visible = false
		return
	bind_player(found)


## Bind (or rebind) the HUD to a player. Kept public so class-weapon tests can
## build a HUD without the full main scene.
func bind_player(target: PlayerController) -> void:
	player = target
	health = player.get_node_or_null("HealthComponent") as HealthComponent
	weapon = player.get_node_or_null("WeaponController") as WeaponController
	if health:
		if not health.health_changed.is_connected(_on_health):
			health.health_changed.connect(_on_health)
		_on_health(health.current, health.max_health)
	if weapon:
		_connect(weapon, "ammo_changed", _on_ammo)
		_connect(weapon, "reload_state_changed", _on_reload)
		_connect(weapon, "hit_confirmed", _on_hit)
		_connect(weapon, "shot_fired", _on_shot)
		_connect(weapon, "heat_changed", _on_heat)
		_connect(weapon, "charge_changed", _on_charge)
		_connect(weapon, "weapon_changed", _on_weapon_changed)
		_on_weapon_changed(weapon.weapon_display_name())
		_on_ammo(weapon.ammo, weapon.reserve_count())
		_on_reload(weapon.is_reloading())
		_on_heat(weapon.heat, weapon.heat_max())
		_on_charge(weapon.charge)
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		_gm = gm
		if gm.has_signal("server_hit"):
			_connect(gm, "server_hit", _on_hit)
		if gm.has_signal("server_death"):
			_connect(gm, "server_death", _on_death)
		if gm.has_signal("server_respawn"):
			_connect(gm, "server_respawn", _on_respawn)
		if gm.has_signal("server_shot"):
			_connect(gm, "server_shot", _on_server_shot)
	_seen_revision = -1
	_seen_second = -1
	_scoreboard_visible = false
	visible = true
	_mark_dirty()


## Single redraw entry point. State changes and transient animations call this;
## idle frames do not.
func _mark_dirty() -> void:
	redraw_requests += 1
	queue_redraw()


func _connect(source: Object, signal_name: String, callback: Callable) -> void:
	if source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_debug = not _debug
			_mark_dirty()


func _process(delta: float) -> void:
	# Capture before decrementing so the frame that lands on zero still paints.
	var animating := (
		_hit_time > 0.0
		or _kill_time > 0.0
		or _damage_flash > 0.0
		or _crosshair_kick > 0.0
	)
	_hit_time = maxf(0.0, _hit_time - delta)
	_kill_time = maxf(0.0, _kill_time - delta)
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.2)
	_crosshair_kick = maxf(0.0, _crosshair_kick - delta * 30.0)
	var refreshed_debug := false
	if _debug:
		_debug_timer -= delta
		if _debug_timer <= 0.0:
			_debug_timer = 0.25
			_refresh_debug_text()
			refreshed_debug = true
	if animating or refreshed_debug:
		_mark_dirty()
	_track_match_clock()
	_track_scoreboard()


## Match clock: repaint on second boundaries and on clock on/off edges, never
## per frame.
func _track_match_clock() -> void:
	var secs := _match_seconds()
	var on := secs >= 0
	if on != _clock_on:
		_clock_on = on
		_mark_dirty()
	if on and secs != _seen_second:
		_seen_second = secs
		_mark_dirty()


func _track_scoreboard() -> void:
	# Hold-Tab, polled like every other gameplay key: Tab is focus navigation
	# for the browser and never reliably reaches _unhandled_input.
	var held := Input.is_action_pressed("scoreboard")
	if held != _scoreboard_visible:
		_scoreboard_visible = held
		_mark_dirty()
		return
	if not _scoreboard_visible or _gm == null:
		return
	var revision := _gm_property("score_revision", -1)
	if revision != _seen_revision:
		_seen_revision = revision
		_mark_dirty()


## Single-arg Object.get with a fallback (Object.get takes no default).
func _gm_property(prop: StringName, fallback: int) -> int:
	if _gm == null:
		return fallback
	var value: Variant = _gm.get(prop)
	return int(value) if value != null else fallback


# --- testable state -------------------------------------------------------

func weapon_name_text() -> String:
	return _weapon_name


func ammo_text() -> String:
	return str(_ammo)


func reserve_text() -> String:
	return "∞ reserve" if _reserve < 0 else "%d reserve" % _reserve


func state_label() -> String:
	if _reloading:
		return "RELOADING"
	if _heat_max > 0.0 and _heat >= _heat_max - 0.001:
		return "OVERHEATED"
	if _charge > 0.001:
		return "DRAW %d%%" % int(round(_charge * 100.0))
	if weapon != null:
		return weapon.state_label()
	return _fire_mode


func fire_mode() -> String:
	return _fire_mode


func heat_ratio() -> float:
	return clampf(_heat / _heat_max, 0.0, 1.0) if _heat_max > 0.0 else 0.0


func charge_ratio() -> float:
	return clampf(_charge, 0.0, 1.0)


## Whole seconds left on the match clock, or -1 when there is no clock (solo,
## old server, match over).
func _match_seconds() -> int:
	if _gm == null or not _gm.has_method("client_match_seconds_left"):
		return -1
	return int(_gm.client_match_seconds_left())


func clock_text() -> String:
	var secs := _match_seconds()
	if secs < 0:
		return ""
	return "%d:%02d" % [secs / 60, secs % 60]


func scoreboard_visible() -> bool:
	return _scoreboard_visible


func score_rows() -> Array:
	if _gm == null or not _gm.has_method("client_scores"):
		return []
	return _gm.client_scores()


func _refresh_debug_text() -> void:
	var stats := BulletField.pool_stats()
	if stats.is_empty():
		_pool_text = "bullets=-"
	else:
		_pool_text = "bullets=%d/%d ex=%d peak=%d builds=%d" % [
			int(stats["active"]), int(stats["size"]), int(stats["exhausted"]),
			int(stats["peak"]), int(stats["builds"]),
		]
	var net := get_node_or_null("/root/NetworkManager")
	if net:
		_net_text = "snap=%dB tick=%d rtt=%dms fps=%d" % [
			int(net.last_snapshot_bytes), int(net.server_tick_estimate),
			int(net.rtt_ms), Engine.get_frames_per_second(),
		]
	else:
		_net_text = "fps=%d" % Engine.get_frames_per_second()


func _draw() -> void:
	if size.x < 10.0:
		return
	var center := size * 0.5

	if _dead:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.55))
		draw_string(
			_font, Vector2(center.x - 120.0, center.y), "RESPAWNING",
			HORIZONTAL_ALIGNMENT_CENTER, 240.0, 24, Color(1.0, 0.55, 0.35)
		)
	if _damage_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.1, 0.1, 0.2 * _damage_flash))

	_draw_crosshair(center)

	var bar_width := 220.0
	var bar_pos := Vector2(24.0, size.y - 58.0)
	draw_rect(Rect2(bar_pos, Vector2(bar_width, 18.0)), Color(0.03, 0.05, 0.08, 0.75))
	var ratio := clampf(float(_health_current) / float(maxi(_health_max, 1)), 0.0, 1.0)
	draw_rect(
		Rect2(bar_pos + Vector2(2, 2), Vector2((bar_width - 4) * ratio, 14)),
		Color(0.2, 0.85, 0.6, 0.95)
	)
	draw_string(
		_font, bar_pos + Vector2(8, 13), "%d HP" % _health_current,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.97, 1.0)
	)

	var right := size.x - 24.0
	draw_string(
		_font, Vector2(right - 260.0, size.y - 92.0), _weapon_name.to_upper(),
		HORIZONTAL_ALIGNMENT_RIGHT, 260.0, 14, ACCENT
	)
	draw_string(
		_font, Vector2(right - 180.0, size.y - 56.0), str(_ammo),
		HORIZONTAL_ALIGNMENT_RIGHT, 180.0, 32, Color(0.9, 0.96, 1.0)
	)
	draw_string(
		_font, Vector2(right - 180.0, size.y - 36.0), reserve_text(),
		HORIZONTAL_ALIGNMENT_RIGHT, 180.0, 11, MUTED
	)
	_draw_weapon_meter(right)

	var state := state_label()
	if state == "RELOADING" or state == "OVERHEATED" or state.begins_with("DRAW"):
		var tone := HEAT_COLOR if state == "RELOADING" or state == "OVERHEATED" else CHARGE_COLOR
		draw_string(
			_font, Vector2(center.x - 120.0, size.y - 90.0), state,
			HORIZONTAL_ALIGNMENT_CENTER, 240.0, 16, tone
		)
	elif state.begins_with("BURST"):
		draw_string(
			_font, Vector2(right - 180.0, size.y - 104.0), state,
			HORIZONTAL_ALIGNMENT_RIGHT, 180.0, 10, MUTED
		)

	if _kill_time > 0.0:
		draw_string(
			_font, Vector2(size.x - 260.0, 56.0), "TARGET DOWN",
			HORIZONTAL_ALIGNMENT_RIGHT, 236.0, 16, Color(1.0, 0.55, 0.35)
		)

	draw_string(
		_font, Vector2(24.0, 24.0), "BALL OF DUTY",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.2, 0.85, 0.75, 0.85)
	)

	var clock := clock_text()
	if clock != "":
		var secs := _match_seconds()
		var tone := ACCENT if secs >= 30 else HEAT_COLOR
		draw_string(
			_font, Vector2(center.x - 60.0, 34.0), clock,
			HORIZONTAL_ALIGNMENT_CENTER, 120.0, 20, tone
		)

	if _scoreboard_visible:
		_draw_scoreboard(center)

	if _debug:
		var debug_color := Color(0.55, 0.9, 1.0, 0.8)
		draw_string(
			_font, Vector2(24.0, size.y - 86.0),
			"DBG shots=%d hits=%d kills=%d seen=%d deaths=%d" % [
				_shots_local, _hits_local, _kills_local, _shots_seen, _deaths_seen,
			],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, debug_color
		)
		draw_string(
			_font, Vector2(24.0, size.y - 74.0), "DBG " + _pool_text + "  " + _net_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, debug_color
		)


## Heat (Mage) or charge (Rogue) meter above the reserve line. Burst classes
## get simple pips so the hand crossbow still reads as a 3-round weapon.
func _draw_weapon_meter(right: float) -> void:
	var meter_x := right - 180.0
	var meter_y := size.y - 25.0
	if _heat_max > 0.0:
		draw_rect(Rect2(Vector2(meter_x, meter_y), Vector2(180.0, 5.0)), Color(0.06, 0.08, 0.12, 0.8))
		draw_rect(
			Rect2(Vector2(meter_x, meter_y), Vector2(180.0 * heat_ratio(), 5.0)),
			HEAT_COLOR
		)
		draw_string(
			_font, Vector2(meter_x - 40.0, meter_y + 5.0), "HEAT",
			HORIZONTAL_ALIGNMENT_RIGHT, 36.0, 9, MUTED
		)
	elif _fire_mode == "CHARGE":
		draw_rect(Rect2(Vector2(meter_x, meter_y), Vector2(180.0, 5.0)), Color(0.06, 0.08, 0.12, 0.8))
		draw_rect(
			Rect2(Vector2(meter_x, meter_y), Vector2(180.0 * charge_ratio(), 5.0)),
			CHARGE_COLOR
		)
		draw_string(
			_font, Vector2(meter_x - 40.0, meter_y + 5.0), "DRAW",
			HORIZONTAL_ALIGNMENT_RIGHT, 36.0, 9, MUTED
		)
	elif _fire_mode == "BURST" and weapon != null:
		var count := weapon.burst_count()
		for i in count:
			var pip := Rect2(Vector2(meter_x + float(i) * 14.0, meter_y), Vector2(10.0, 5.0))
			draw_rect(pip, MUTED)


## Hold-Tab standings. One draw pass, no allocations that matter: rows come
## from the client's sorted table, the local row paints in accent.
func _draw_scoreboard(center: Vector2) -> void:
	var rows: Array = score_rows()
	var shown := mini(rows.size(), 16)
	var width := 400.0
	var row_h := 20.0
	var height := 64.0 + float(maxi(shown, 1)) * row_h
	var origin := Vector2(center.x - width * 0.5, center.y - height * 0.5)
	draw_rect(Rect2(origin, Vector2(width, height)), Color(0.02, 0.03, 0.06, 0.88))
	draw_rect(Rect2(origin, Vector2(width, height)), ACCENT, false, 1.0)
	var clock := clock_text()
	var title := "SCOREBOARD" if clock == "" else "SCOREBOARD · %s LEFT" % clock
	draw_string(
		_font, origin + Vector2(0.0, 24.0), title,
		HORIZONTAL_ALIGNMENT_CENTER, width, 15, ACCENT
	)
	draw_string(
		_font, origin + Vector2(16.0, 46.0), "PLAYER",
		HORIZONTAL_ALIGNMENT_LEFT, 240.0, 10, MUTED
	)
	draw_string(
		_font, origin + Vector2(width - 132.0, 46.0), "K",
		HORIZONTAL_ALIGNMENT_CENTER, 40.0, 10, MUTED
	)
	draw_string(
		_font, origin + Vector2(width - 76.0, 46.0), "D",
		HORIZONTAL_ALIGNMENT_CENTER, 40.0, 10, MUTED
	)
	var gm := _gm
	var local_id := _gm_property("local_id", -1) if gm else -1
	for i in shown:
		var row: Dictionary = rows[i]
		var y := origin.y + 46.0 + float(i + 1) * row_h
		var tone := ACCENT if int(row.get("id", -1)) == local_id else Color(0.9, 0.96, 1.0)
		var label := "%d. %s" % [i + 1, String(row.get("name", "?"))]
		draw_string(_font, Vector2(origin.x + 16.0, y), label,
			HORIZONTAL_ALIGNMENT_LEFT, 240.0, 12, tone)
		draw_string(_font, Vector2(origin.x + width - 132.0, y), str(int(row.get("kills", 0))),
			HORIZONTAL_ALIGNMENT_CENTER, 40.0, 12, tone)
		draw_string(_font, Vector2(origin.x + width - 76.0, y), str(int(row.get("deaths", 0))),
			HORIZONTAL_ALIGNMENT_CENTER, 40.0, 12, tone)


func _draw_crosshair(center: Vector2) -> void:
	var gap := 5.0 + _crosshair_kick
	var length := 7.0
	var color := Color(0.88, 0.96, 1.0, 0.9)
	var shadow := Color(0.02, 0.04, 0.06, 0.7)
	for offset: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + offset * (gap + 2.0), center + offset * (gap + length + 2.0), shadow, 3.0)
		draw_line(center + offset * gap, center + offset * (gap + length), color, 1.6)

	if _hit_time > 0.0:
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + dir * 7.0, center + dir * 14.0, Color(0.95, 0.97, 1.0), 2.0)


func _on_health(current: int, maximum: int) -> void:
	if current < _health_current:
		_damage_flash = 1.0
	_health_current = current
	_health_max = maximum
	_mark_dirty()


func _on_ammo(magazine: int, reserve: int) -> void:
	_ammo = magazine
	_reserve = reserve
	_mark_dirty()


func _on_reload(reloading: bool) -> void:
	_reloading = reloading
	_mark_dirty()


func _on_weapon_changed(display_name: String) -> void:
	_weapon_name = display_name
	if weapon != null:
		_fire_mode = weapon.fire_mode()
	else:
		_fire_mode = "SINGLE"
	_mark_dirty()


func _on_heat(value: float, maximum: float) -> void:
	_heat = value
	_heat_max = maximum
	_mark_dirty()


func _on_charge(value: float) -> void:
	_charge = value
	_mark_dirty()


func _on_hit(killed: bool) -> void:
	_hit_time = 0.14
	_hits_local += 1
	if killed:
		_kill_time = 2.2
		_kills_local += 1
	_mark_dirty()


func _on_shot(_origin: Vector3, _direction: Vector3) -> void:
	_shots_local += 1
	_crosshair_kick = 4.0
	_mark_dirty()


## Remote shots only bump a debug counter; the 4 Hz debug refresh paints them.
func _on_server_shot(_shooter_id: int, _origin: Vector3, _direction: Vector3) -> void:
	_shots_seen += 1


func _on_death(victim_id: int, _killer_id: int) -> void:
	_deaths_seen += 1
	if player and victim_id == player.net_id:
		_dead = true
	_mark_dirty()


func _on_respawn(player_id: int, _position: Vector3, _yaw: float) -> void:
	if player and player_id == player.net_id:
		_dead = false
	_mark_dirty()
