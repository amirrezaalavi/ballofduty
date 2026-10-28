class_name HurtboxComponent
extends Area3D
## Damageable volume. The projectile never touches health directly; it hands the
## hurtbox to CombatResolver.

@export var entity_id: int = 0
@export var hitbox_name: StringName = &"body"
@export var health_path: NodePath


func get_health() -> HealthComponent:
	return get_node_or_null(health_path) as HealthComponent
