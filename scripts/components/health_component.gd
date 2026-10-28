class_name HealthComponent
extends Node
## Health state only. Damage application is server-authoritative from CP4c;
## clients observe signals and render effects.

signal health_changed(current: int, maximum: int)
signal player_died(source_id: int, position: Vector3)

@export var max_health: int = 100

var current: int = 100


func _ready() -> void:
	current = max_health
	health_changed.emit(current, max_health)


func reset() -> void:
	current = max_health
	health_changed.emit(current, max_health)


## Server-only from CP4c. Returns true if this damage killed the entity.
func apply_damage(amount: int, source_id: int, position: Vector3) -> bool:
	if amount <= 0 or current <= 0:
		return false
	current = maxi(0, current - amount)
	health_changed.emit(current, max_health)
	if current == 0:
		player_died.emit(source_id, position)
		return true
	return false
