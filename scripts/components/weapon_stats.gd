class_name WeaponStats
extends Resource
## All rifle tuning lives here; no gameplay magic numbers in the controller.

@export var display_name: String = "R-1 Rifle"
@export var weapon_id: StringName = &"rifle"

@export_group("Damage")
@export_range(1, 200, 1) var damage: int = 25
@export_range(1.0, 4.0, 0.1) var headshot_multiplier: float = 2.0
@export_range(20.0, 300.0, 1.0) var projectile_speed: float = 90.0
@export_range(0.5, 10.0, 0.1) var projectile_lifetime: float = 2.5

@export_group("Fire control")
@export_range(0.5, 30.0, 0.1) var fire_rate: float = 10.0
@export var automatic: bool = true
@export_range(0.0, 5.0, 0.05) var spread_degrees: float = 0.3
@export_range(1, 100, 1) var magazine_size: int = 30
@export var infinite_reserve: bool = true
@export_range(0.2, 5.0, 0.05) var reload_time: float = 1.6
@export_range(0.0, 5.0, 0.05) var recoil_degrees: float = 0.7

@export_group("Presentation")
@export var projectile_scene: PackedScene
