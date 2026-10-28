class_name TrainingDummy
extends AnimatableBody3D
## Local practice target. Dies, hides, and respawns with full health. The same
## health/hurtbox path will be driven by the server later.

@export var strafe_enabled: bool = false
@export var strafe_speed: float = 1.1
@export var strafe_range: float = 2.0
@export var respawn_time: float = 2.0

@onready var health: HealthComponent = $HealthComponent
@onready var label: Label3D = $Label3D

var _origin: Vector3
var _elapsed: float = 0.0
var _alive: bool = true


func _ready() -> void:
	_origin = position
	health.health_changed.connect(_on_health_changed)
	health.player_died.connect(_on_died)
	_update_label(health.current, health.max_health)


func _physics_process(delta: float) -> void:
	if not strafe_enabled or not _alive:
		return
	_elapsed += delta
	position.x = _origin.x + sin(_elapsed * strafe_speed) * strafe_range


func _on_health_changed(current: int, maximum: int) -> void:
	_update_label(current, maximum)


func _on_died(_source_id: int, _position: Vector3) -> void:
	_alive = false
	visible = false
	collision_layer = 0
	_set_hurtboxes(false)
	await get_tree().create_timer(respawn_time).timeout
	_respawn()


func _respawn() -> void:
	health.reset()
	position = _origin
	visible = true
	collision_layer = 1
	_set_hurtboxes(true)
	_alive = true
	_update_label(health.current, health.max_health)


func _set_hurtboxes(enabled: bool) -> void:
	for child in get_children():
		var area := child as Area3D
		if area:
			area.collision_layer = 8 if enabled else 0
			area.monitorable = enabled
			area.visible = enabled


func _update_label(current: int, maximum: int) -> void:
	if label:
		label.text = "%d / %d" % [current, maximum]
