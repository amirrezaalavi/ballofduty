class_name WeaponController
extends Node
## Local weapon simulation. CP3 applies damage through CombatResolver; CP4c
## moves the same resolver call to the server after validating the fire intent.
##
## Phase 2A: the client loads a per-class stats resource at runtime and drives
## cosmetic ammo/heat/charge/burst state so the HUD and animation overlays can
## react before Agent D's server resources are merged. Damage stays 100%
## server-authoritative.

signal ammo_changed(magazine: int, reserve: int)
signal reload_state_changed(reloading: bool)
signal shot_fired(origin: Vector3, direction: Vector3)
signal hit_confirmed(headshot: bool, killed: bool)
signal heat_changed(heat: float, maximum: float)
signal charge_changed(charge: float)
signal weapon_changed(display_name: String)

const RIFLE_STATS := preload("res://resources/weapons/rifle_stats.tres")
const CLASS_KEYS := ["knight", "mage", "rogue", "rogue_hooded", "barbarian"]
## Server profile filenames from Phase 2D.
const CLASS_STAT_FILES := [
	"knight_javelin", "mage_staff", "rogue_bow",
	"rogue_hooded_crossbow", "barbarian_axes",
]
const CLASS_WEAPON_NAMES := [
	"Heavy Javelin",
	"Arcane Staff",
	"Recurve Longbow",
	"Repeating Crossbow",
	"Heavy Throwing Axes",
]
const CLASS_WEAPON_ROLES := [
	"Frontline anchor · thrown pierce",
	"Artillery · plasma splash",
	"Skirmisher · charge shot",
	"Flanker · 3-bolt burst",
	"Bruiser · arcing axes",
]

@export var stats: WeaponStats
@export var camera_rig_path: NodePath = ^"../CameraPivot"
@export var muzzle_path: NodePath = ^"../Muzzle"

var ammo: int = 0
var service_rifle_id: int = 0
var spawn_projectiles: bool = true

## Class channel. Starts at -1 so the first tick always applies the actor class.
var class_id: int = -1
var heat: float = 0.0
var charge: float = 0.0

var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _reloading: bool = false
var _trigger_was_down: bool = false
var _flash_left: float = 0.0
var _burst_left: int = 0
var _class_applied: bool = false
var _using_class_stats: bool = false

@onready var player: PlayerController = get_parent() as PlayerController
@onready var camera_rig: CameraRig = get_node_or_null(camera_rig_path) as CameraRig
@onready var muzzle: Marker3D = get_node_or_null(muzzle_path) as Marker3D
@onready var muzzle_flash: MeshInstance3D = (
	get_node_or_null(muzzle_path).get_node_or_null("Flash") if muzzle else null
) as MeshInstance3D


func _ready() -> void:
	if stats == null:
		stats = RIFLE_STATS
	if stats == null:
		push_error("WeaponController.stats is not assigned and no rifle fallback exists")
		return
	_apply_class(player.class_id if player else 0)
	if muzzle_flash:
		muzzle_flash.visible = false


func tick(delta: float, frame: PlayerInputFrame) -> void:
	if stats == null:
		return
	_sync_class()

	_cooldown = maxf(0.0, _cooldown - delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and muzzle_flash:
			muzzle_flash.visible = false
	_cool_heat(delta)

	if _reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()
		return

	if frame.reload:
		start_reload()

	if ammo <= 0:
		start_reload()
		return

	if charge_time() > 0.0:
		_tick_charge(delta, frame)
		return
	if burst_count() > 1:
		_tick_burst(frame)
		return

	var trigger_edge := frame.fire and not _trigger_was_down
	_trigger_was_down = frame.fire
	var wants_fire := frame.fire if stats.automatic else trigger_edge
	if _heat_locked():
		wants_fire = false
	if wants_fire and _cooldown <= 0.0:
		_fire()


func reset_ammo() -> void:
	ammo = stats.magazine_size if stats else 0
	_cooldown = 0.0
	_reload_left = 0.0
	_reloading = false
	_trigger_was_down = false
	_burst_left = 0
	heat = 0.0
	charge = 0.0
	ammo_changed.emit(ammo, reserve_count())
	reload_state_changed.emit(false)
	heat_changed.emit(heat, heat_max())
	charge_changed.emit(charge)


func start_reload() -> void:
	if _reloading or stats == null or ammo >= stats.magazine_size:
		return
	_reloading = true
	_reload_left = stats.reload_time
	reload_state_changed.emit(true)
	_audio("play_reload")


func get_spread_degrees() -> float:
	return stats.spread_degrees if stats else 0.0


func is_reloading() -> bool:
	return _reloading


func reserve_count() -> int:
	if stats == null:
		return 0
	if stats.infinite_reserve:
		return -1
	return int(_stat("reserve_ammo", 0))


func weapon_display_name() -> String:
	var id := clampi(class_id, 0, CLASS_WEAPON_NAMES.size() - 1)
	if stats != null and _using_class_stats:
		var shown := String(stats.display_name).strip_edges()
		if shown != "":
			return shown
	return CLASS_WEAPON_NAMES[id]


func class_role() -> String:
	return CLASS_WEAPON_ROLES[clampi(class_id, 0, CLASS_WEAPON_ROLES.size() - 1)]


func fire_mode() -> String:
	if charge_time() > 0.0:
		return "CHARGE"
	if heat_max() > 0.0:
		return "HEAT"
	if burst_count() > 1:
		return "BURST"
	return "SINGLE"


func heat_max() -> float:
	if stats == null:
		return 0.0
	var value := float(_stat("max_heat", _stat("heat_max", 0.0)))
	if value <= 0.0 and class_id == 1:
		value = 6.0
	return maxf(0.0, value)


func heat_ratio() -> float:
	var maximum := heat_max()
	return clampf(heat / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0


func charge_time() -> float:
	if stats == null:
		return 0.0
	var value := float(_stat("charge_time", 0.0))
	if value <= 0.0 and class_id == 2:
		value = 0.85
	return maxf(0.0, value)


func charge_ratio() -> float:
	return clampf(charge, 0.0, 1.0)


func burst_count() -> int:
	if stats == null:
		return 1
	var value := int(_stat("burst_count", _stat("burst", 0)))
	if value <= 1 and class_id == 3:
		value = 3
	return maxi(1, value)


func is_heat_locked() -> bool:
	return _heat_locked()


func state_label() -> String:
	if stats == null:
		return ""
	if _reloading:
		return "RELOADING"
	if _heat_locked():
		return "OVERHEATED"
	if charge_time() > 0.0:
		if charge > 0.001:
			return "DRAW %d%%" % int(round(charge_ratio() * 100.0))
		return "READY"
	if burst_count() > 1:
		return "BURST %d" % burst_count()
	return "READY"


## Apply a class at runtime: load `class_<name>.tres` (or `class_<id>.tres`)
## when Agent D's resources exist, otherwise keep the serialized rifle stats as
## a compiling fallback while class labels/indicators come from the table above.
func set_class(new_class_id: int) -> void:
	_apply_class(NetProtocol.sanitize_class(new_class_id))


func _apply_class(new_class_id: int) -> void:
	new_class_id = NetProtocol.sanitize_class(new_class_id)
	if _class_applied and new_class_id == class_id:
		return
	class_id = new_class_id
	_class_applied = true
	var loaded := load_class_stats(class_id)
	if loaded != null:
		stats = loaded
		_using_class_stats = true
	else:
		_using_class_stats = false
		if stats == null:
			stats = RIFLE_STATS
	ammo = stats.magazine_size if stats else 0
	_cooldown = 0.0
	_reload_left = 0.0
	_reloading = false
	_trigger_was_down = false
	_burst_left = 0
	heat = 0.0
	charge = 0.0
	ammo_changed.emit(ammo, reserve_count())
	reload_state_changed.emit(false)
	heat_changed.emit(heat, heat_max())
	charge_changed.emit(charge)
	weapon_changed.emit(weapon_display_name())


func _sync_class() -> void:
	if player != null and player.class_id != class_id:
		_apply_class(player.class_id)


static func load_class_stats(id: int) -> WeaponStats:
	id = clampi(id, 0, CLASS_KEYS.size() - 1)
	for path: String in [
		"res://resources/weapons/class_%s.tres" % CLASS_STAT_FILES[id],
		"res://resources/weapons/class_%s.tres" % CLASS_KEYS[id],
		"res://resources/weapons/class_%d.tres" % id,
	]:
		if ResourceLoader.exists(path):
			var resource := load(path)
			if resource is WeaponStats:
				return resource
	return null


static func class_weapon_name(id: int) -> String:
	return CLASS_WEAPON_NAMES[clampi(id, 0, CLASS_WEAPON_NAMES.size() - 1)]


## `Resource.get()` takes one argument; this wrapper supplies the contract's
## default for fields that Agent D's WeaponStats may not export yet.
func _stat(key: String, fallback: Variant) -> Variant:
	if stats == null:
		return fallback
	var value: Variant = stats.get(key)
	return fallback if value == null else value


func _finish_reload() -> void:
	_reloading = false
	_reload_left = 0.0
	ammo = stats.magazine_size
	ammo_changed.emit(ammo, reserve_count())
	reload_state_changed.emit(false)


func _tick_charge(delta: float, frame: PlayerInputFrame) -> void:
	var wanted := charge_time()
	if frame.fire and not _heat_locked():
		var before := charge
		charge = minf(1.0, charge + delta / maxf(wanted, 0.01))
		if not is_equal_approx(before, charge):
			charge_changed.emit(charge)
		_trigger_was_down = true
		return
	if _trigger_was_down or charge > 0.0:
		var released := charge
		charge = 0.0
		charge_changed.emit(charge)
		_trigger_was_down = false
		if released > 0.0 and _cooldown <= 0.0 and not _heat_locked():
			_fire()


func _tick_burst(frame: PlayerInputFrame) -> void:
	var edge := frame.fire and not _trigger_was_down
	_trigger_was_down = frame.fire
	if edge and _burst_left <= 0 and _cooldown <= 0.0:
		_burst_left = burst_count()
	if _burst_left > 0 and _cooldown <= 0.0:
		if ammo <= 0:
			_burst_left = 0
			return
		_fire()
		_burst_left -= 1
		_cooldown = 0.055 if _burst_left > 0 else 1.0 / maxf(stats.fire_rate, 0.1)


func _cool_heat(delta: float) -> void:
	if heat <= 0.0:
		return
	var before := heat
	heat = maxf(0.0, heat - heat_cool_rate() * delta)
	if not is_equal_approx(before, heat):
		heat_changed.emit(heat, heat_max())


func heat_cool_rate() -> float:
	if stats == null:
		return 0.0
	var value := float(_stat("heat_cool_rate", _stat("cool_rate", 0.0)))
	if value <= 0.0 and class_id == 1:
		value = 1.6
	return maxf(0.0, value)


func heat_per_shot() -> float:
	if stats == null:
		return 0.0
	var value := float(_stat("heat_per_shot", _stat("heat_gain", 0.0)))
	if value <= 0.0 and class_id == 1:
		value = 1.0
	return maxf(0.0, value)


func _heat_locked() -> bool:
	var maximum := heat_max()
	return maximum > 0.0 and heat >= maximum - 0.001


func _fire() -> void:
	if ammo <= 0 or _reloading or muzzle == null or camera_rig == null or player == null:
		return

	ammo -= 1
	_cooldown = 1.0 / maxf(stats.fire_rate, 0.1)
	ammo_changed.emit(ammo, reserve_count())
	var gain := heat_per_shot()
	if gain > 0.0:
		heat = minf(heat_max(), heat + gain)
		heat_changed.emit(heat, heat_max())

	# Cosmetic events happen even when authority owns the projectile (CP4c sets
	# spawn_projectiles = false and still needs the tracer/flash/audio/recoil).
	var direction := _aim_direction()
	var origin := muzzle.global_position
	# Networked clients do not spawn local projectiles, so draw the round here.
	# Offline play already has a visible Projectile node.
	if not spawn_projectiles:
		BulletField.spawn(
			player.get_parent(), origin, direction, stats.projectile_speed, true, _exclusion_rids()
		)
	shot_fired.emit(origin, direction)
	_audio("play_shoot")
	_show_muzzle_flash()
	camera_rig.add_recoil(stats.recoil_degrees)

	if not spawn_projectiles:
		return
	if stats.projectile_scene == null:
		push_error("WeaponStats.projectile_scene is not assigned")
		return

	var projectile := stats.projectile_scene.instantiate() as Projectile
	var scene := get_tree().current_scene
	if projectile == null or scene == null:
		return
	scene.add_child(projectile)
	projectile.global_position = origin
	projectile.setup(direction, stats, service_rifle_id, _exclusion_rids())
	projectile.hit_confirmed.connect(_on_hit_confirmed)


func _aim_direction() -> Vector3:
	var camera := camera_rig.camera
	var viewport_size := player.get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_normal := camera.project_ray_normal(center)
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin, ray_origin + ray_normal * 250.0, 1 | 8
	)
	query.collide_with_areas = true
	query.exclude = _exclusion_rids()
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point: Vector3 = hit.position if not hit.is_empty() else ray_origin + ray_normal * 250.0

	var direction := (aim_point - muzzle.global_position).normalized()
	var spread := deg_to_rad(stats.spread_degrees)
	if spread > 0.0:
		var right := camera.global_transform.basis.x.normalized()
		direction = direction.rotated(Vector3.UP, randf_range(-spread, spread))
		direction = direction.rotated(right, randf_range(-spread, spread))
	return direction.normalized()


func _exclusion_rids() -> Array[RID]:
	var rids: Array[RID] = [player.get_rid()]
	for path: String in ["BodyHurtbox", "HeadHurtbox"]:
		var area := player.get_node_or_null(path) as Area3D
		if area:
			rids.append(area.get_rid())
	return rids


func _show_muzzle_flash() -> void:
	_flash_left = 0.045
	if muzzle_flash:
		muzzle_flash.visible = true


func _on_hit_confirmed(headshot: bool, killed: bool) -> void:
	hit_confirmed.emit(headshot, killed)
	_audio("play_hit")


func _audio(method: StringName) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method(method):
		audio.call(method)
