class_name WeaponController
extends Node
## Local weapon simulation. CP3 applies damage through CombatResolver; CP4c
## moves the same resolver call to the server after validating the fire intent.

signal ammo_changed(magazine: int, reserve: int)
signal reload_state_changed(reloading: bool)
signal shot_fired(origin: Vector3, direction: Vector3)
signal hit_confirmed(headshot: bool, killed: bool)

@export var stats: WeaponStats
@export var camera_rig_path: NodePath = ^"../CameraPivot"
@export var muzzle_path: NodePath = ^"../Muzzle"

var ammo: int = 0
var service_rifle_id: int = 0
var spawn_projectiles: bool = true

var _cooldown: float = 0.0
var _reload_left: float = 0.0
var _reloading: bool = false
var _trigger_was_down: bool = false
var _flash_left: float = 0.0

@onready var player: PlayerController = get_parent() as PlayerController
@onready var camera_rig: CameraRig = get_node_or_null(camera_rig_path) as CameraRig
@onready var muzzle: Marker3D = get_node_or_null(muzzle_path) as Marker3D
@onready var muzzle_flash: MeshInstance3D = (
	get_node_or_null(muzzle_path).get_node_or_null("Flash") if muzzle else null
) as MeshInstance3D


func _ready() -> void:
	if stats == null:
		push_error("WeaponController.stats is not assigned")
		return
	ammo = stats.magazine_size
	if muzzle_flash:
		muzzle_flash.visible = false
	ammo_changed.emit(ammo, -1 if stats.infinite_reserve else 0)


func tick(delta: float, frame: PlayerInputFrame) -> void:
	if stats == null:
		return

	_cooldown = maxf(0.0, _cooldown - delta)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and muzzle_flash:
			muzzle_flash.visible = false

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

	var trigger_edge := frame.fire and not _trigger_was_down
	_trigger_was_down = frame.fire
	var wants_fire := frame.fire if stats.automatic else trigger_edge
	if wants_fire and _cooldown <= 0.0:
		_fire()


func reset_ammo() -> void:
	ammo = stats.magazine_size if stats else 0
	_cooldown = 0.0
	_reload_left = 0.0
	_reloading = false
	_trigger_was_down = false
	ammo_changed.emit(ammo, -1 if stats and stats.infinite_reserve else 0)
	reload_state_changed.emit(false)


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


func _finish_reload() -> void:
	_reloading = false
	_reload_left = 0.0
	ammo = stats.magazine_size
	ammo_changed.emit(ammo, -1 if stats.infinite_reserve else 0)
	reload_state_changed.emit(false)


func _fire() -> void:
	if ammo <= 0 or _reloading or muzzle == null or camera_rig == null or player == null:
		return

	ammo -= 1
	_cooldown = 1.0 / maxf(stats.fire_rate, 0.1)
	ammo_changed.emit(ammo, -1 if stats.infinite_reserve else 0)

	# Cosmetic events happen even when authority owns the projectile (CP4c sets
	# spawn_projectiles = false and still needs the tracer/flash/audio/recoil).
	var direction := _aim_direction()
	var origin := muzzle.global_position
	Tracer.spawn(get_tree().current_scene, origin, direction)
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
