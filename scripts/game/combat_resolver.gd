class_name CombatResolver
extends RefCounted
## The only writer of health. CP3 runs it locally; CP4c calls the same method
## from the authoritative server after validating a fire request.

static func apply_hit(
	hurtbox: HurtboxComponent,
	damage: int,
	source_id: int,
	position: Vector3
) -> bool:
	if not hurtbox.damage_enabled:
		return false
	var health := hurtbox.get_health()
	if health == null:
		return false

	var killed := health.apply_damage(damage, source_id, position)

	var tree := Engine.get_main_loop() as SceneTree
	var bus := tree.root.get_node_or_null("EventBus") if tree else null
	if bus:
		bus.damage_dealt.emit(hurtbox.entity_id, source_id, damage, position)
		if killed:
			bus.player_died.emit(hurtbox.entity_id, source_id, position)
	return killed
