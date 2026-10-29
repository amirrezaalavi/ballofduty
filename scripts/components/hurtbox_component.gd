class_name HurtboxComponent
extends Area3D
## Damageable volume. The projectile never touches health directly; it hands the
## hurtbox to CombatResolver.

@export var entity_id: int = 0
@export var health_path: NodePath
## False for non-authoritative bodies (remote ghosts, spectators) and for
## spawn protection. The ray still stops here, but damage is never applied.
@export var damage_enabled: bool = true


func get_health() -> HealthComponent:
	return get_node_or_null(health_path) as HealthComponent
