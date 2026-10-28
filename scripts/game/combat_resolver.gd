class_name CombatResolver
extends RefCounted
## The only writer of health. CP3 runs it locally; CP4c calls the same method
## from the authoritative server after validating a fire request.

static func apply_hit(
	hurtbox: HurtboxComponent,
	base_damage: int,
	headshot_multiplier: float,
	source_id: int,
	position: Vector3
) -> bool:
	var health := hurtbox.get_health()
	if health == null:
		return false

	var multiplier := headshot_multiplier if hurtbox.hitbox_name == &"head" else 1.0
	var damage := int(round(base_damage * multiplier))
	var killed := health.apply_damage(damage, source_id, position)

	var tree := Engine.get_main_loop() as SceneTree
	var bus := tree.root.get_node_or_null("EventBus") if tree else null
	if bus:
		bus.damage_dealt.emit(hurtbox.entity_id, source_id, damage, hurtbox.hitbox_name, position)
		if killed:
			bus.player_died.emit(hurtbox.entity_id, source_id, position)
	return killed
