extends Node
## Cross-system events. Keep payloads serializable; authority-only events are
## emitted by CombatResolver / the server, never by presentation code.

signal health_changed(entity_id: int, current: int, maximum: int)
signal damage_dealt(target_id: int, source_id: int, amount: int, position: Vector3)
signal player_died(entity_id: int, source_id: int, position: Vector3)
signal kill_credited(killer_id: int, victim_id: int, weapon_id: StringName)
signal shot_fired(shooter_id: int, origin: Vector3, direction: Vector3, weapon_id: StringName)
signal match_state_changed(state: StringName, seconds_left: float)
signal score_changed(player_id: int, kills: int, deaths: int)
