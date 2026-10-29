extends Control
## CP3 HUD: crosshair, health, ammo/reload, hitmarker, damage flash, kill feed.
## Draws in one CanvasItem to keep the web HUD cheap.

var player: PlayerController
var weapon: WeaponController
var health: HealthComponent

var _health_current: int = 100
var _health_max: int = 100
var _ammo: int = 30
var _reserve: int = -1
var _reloading: bool = false
var _hit_time: float = 0.0
var _hit_headshot: bool = false
var _kill_time: float = 0.0
var _damage_flash: float = 0.0
var _crosshair_kick: float = 0.0
var _dead: bool = false
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font

	player = get_tree().current_scene.get_node_or_null("Player") as PlayerController
	if player == null:
		visible = false
		return

	health = player.get_node_or_null("HealthComponent") as HealthComponent
	weapon = player.get_node_or_null("WeaponController") as WeaponController
	if health:
		health.health_changed.connect(_on_health)
		_on_health(health.current, health.max_health)
	if weapon:
		weapon.ammo_changed.connect(_on_ammo)
		weapon.reload_state_changed.connect(_on_reload)
		weapon.hit_confirmed.connect(_on_hit)
		weapon.shot_fired.connect(_on_shot)
		_on_ammo(weapon.ammo, -1)
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		if gm.has_signal("server_hit"):
			gm.server_hit.connect(_on_hit)
		if gm.has_signal("server_death"):
			gm.server_death.connect(_on_death)
		if gm.has_signal("server_respawn"):
			gm.server_respawn.connect(_on_respawn)


func _process(delta: float) -> void:
	_hit_time = maxf(0.0, _hit_time - delta)
	_kill_time = maxf(0.0, _kill_time - delta)
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.2)
	_crosshair_kick = maxf(0.0, _crosshair_kick - delta * 30.0)
	queue_redraw()


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
		_font, Vector2(right - 180.0, size.y - 40.0), str(_ammo),
		HORIZONTAL_ALIGNMENT_RIGHT, 180.0, 32, Color(0.9, 0.96, 1.0)
	)
	draw_string(
		_font, Vector2(right - 180.0, size.y - 20.0),
		"∞ reserve" if _reserve < 0 else "%d reserve" % _reserve,
		HORIZONTAL_ALIGNMENT_RIGHT, 180.0, 11, Color(0.55, 0.64, 0.8)
	)
	if _reloading:
		draw_string(
			_font, Vector2(center.x - 100.0, size.y - 90.0), "RELOADING",
			HORIZONTAL_ALIGNMENT_CENTER, 200.0, 16, Color(1.0, 0.75, 0.35)
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


func _draw_crosshair(center: Vector2) -> void:
	var gap := 5.0 + _crosshair_kick
	var length := 7.0
	var color := Color(0.88, 0.96, 1.0, 0.9)
	var shadow := Color(0.02, 0.04, 0.06, 0.7)
	for offset: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(center + offset * (gap + 2.0), center + offset * (gap + length + 2.0), shadow, 3.0)
		draw_line(center + offset * gap, center + offset * (gap + length), color, 1.6)

	if _hit_time > 0.0:
		var hit_color := Color(1.0, 0.65, 0.25) if _hit_headshot else Color(0.95, 0.97, 1.0)
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(center + dir * 7.0, center + dir * 14.0, hit_color, 2.0)


func _on_health(current: int, maximum: int) -> void:
	if current < _health_current:
		_damage_flash = 1.0
	_health_current = current
	_health_max = maximum


func _on_ammo(magazine: int, reserve: int) -> void:
	_ammo = magazine
	_reserve = reserve


func _on_reload(reloading: bool) -> void:
	_reloading = reloading


func _on_hit(headshot: bool, killed: bool) -> void:
	_hit_time = 0.14
	_hit_headshot = headshot
	if killed:
		_kill_time = 2.2


func _on_shot(_origin: Vector3, _direction: Vector3) -> void:
	_crosshair_kick = 4.0


func _on_death(victim_id: int, _killer_id: int) -> void:
	if player and victim_id == player.net_id:
		_dead = true


func _on_respawn(player_id: int, _position: Vector3, _yaw: float) -> void:
	if player and player_id == player.net_id:
		_dead = false
