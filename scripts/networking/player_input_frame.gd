class_name PlayerInputFrame
extends RefCounted
## One simulation tick's intent. Serializable field-by-field for CP4b; do not
## put node references in here.

var seq: int = 0
var move: Vector2 = Vector2.ZERO
var jump: bool = false
var sprint: bool = false
var aim: bool = false
var fire: bool = false
var reload: bool = false
var yaw: float = 0.0
var pitch: float = 0.0
