class_name WeaponStats
extends Resource
## All weapon tuning lives here; no gameplay magic numbers in the controller.
## The class rotation lives in resources/weapons/class_*.tres and is selected by
## WeaponRegistry from the player's class_id. The legacy rifle resource stays
## for offline play and the later M4 power-weapon pass.

@export var display_name: String = "R-1 Rifle"
@export var weapon_id: StringName = &"rifle"

@export_group("Class")
## 0 Knight, 1 Mage, 2 Rogue, 3 Rogue_Hooded, 4 Barbarian; -1 = legacy rifle.
@export_range(-1, 8, 1) var class_id: int = -1
## semi (edge-triggered), auto (held), charge (release), burst (3-round).
@export var fire_mode: StringName = &"auto"
## Client presentation hooks. Damage is always server-side.
@export var shot_clip: StringName = &"Ranged_1H_Shoot"
@export var charge_clip: StringName = &"Ranged_1H_Aiming"
@export var reload_clip: StringName = &"Ranged_1H_Aiming"
@export var effect: StringName = &"none"

@export_group("Damage")
@export_range(1, 200, 1) var damage: int = 25
@export_range(1.0, 4.0, 0.1) var headshot_multiplier: float = 2.0
@export_range(20.0, 300.0, 1.0) var projectile_speed: float = 81.0
@export_range(0.5, 10.0, 0.1) var projectile_lifetime: float = 2.5

@export_group("Fire control")
@export_range(0.5, 30.0, 0.1) var fire_rate: float = 10.0
@export var automatic: bool = true
@export_range(0.0, 5.0, 0.05) var spread_degrees: float = 0.3
@export_range(1, 100, 1) var magazine_size: int = 30
@export var infinite_reserve: bool = true
@export_range(0.2, 5.0, 0.05) var reload_time: float = 1.6
@export_range(0.0, 5.0, 0.05) var recoil_degrees: float = 0.7

@export_group("Ballistics")
## Downward acceleration in m/s^2. 0 = hitscan-like straight bolt.
@export_range(0.0, 40.0, 0.1) var projectile_gravity: float = 0.0
## Extra targets a round passes through after the first contact.
@export_range(0, 5, 1) var pierce: int = 0
## Presentation/balance hook: arrows ignore the future armour stat.
@export var armour_pierce: bool = false

@export_group("Charge")
@export_range(0.0, 3.0, 0.05) var charge_time: float = 0.0
@export_range(0.0, 200.0, 1.0) var charge_min_speed: float = 0.0
@export_range(0, 200, 1) var charge_min_damage: int = 0
## Fraction of charge_time needed for a release to launch at all.
@export_range(0.0, 1.0, 0.05) var charge_min_ratio: float = 0.1

@export_group("Burst")
@export_range(1, 10, 1) var burst_count: int = 1
@export_range(0.01, 1.0, 0.01) var burst_interval: float = 0.08

@export_group("Heat")
@export_range(0.0, 20.0, 0.1) var heat_max: float = 0.0
@export_range(0.0, 20.0, 0.1) var heat_per_shot: float = 1.0
@export_range(0.0, 20.0, 0.1) var heat_cool_rate: float = 1.0
## Overheat lockout clears once heat falls back under this fraction of max.
@export_range(0.0, 1.0, 0.05) var heat_recover_ratio: float = 0.35

@export_group("Splash")
@export_range(0.0, 10.0, 0.1) var splash_radius: float = 0.0
@export_range(0, 100, 1) var splash_damage: int = 0
## Fraction of splash damage retained at the edge of the radius.
@export_range(0.0, 1.0, 0.05) var splash_edge_scale: float = 0.5

@export_group("Status hooks")
@export_range(0.0, 20.0, 0.1) var knockback: float = 0.0
@export_range(0.0, 1.0, 0.05) var slow_amount: float = 0.0
@export_range(0.0, 10.0, 0.1) var slow_duration: float = 0.0
@export_range(0.0, 50.0, 0.5) var bleed_dps: float = 0.0
@export_range(0.0, 10.0, 0.1) var bleed_duration: float = 0.0

@export_group("Presentation")
@export var projectile_scene: PackedScene
