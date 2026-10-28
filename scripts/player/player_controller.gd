class_name PlayerController
extends CharacterBody3D
## Local player driver: input sampling + camera presentation, delegating all
## movement to LocomotionComponent. The server will run the same component with
## network input frames in CP4b; nothing here may live inside that component.

@onready var camera_rig: CameraRig = $CameraPivot
@onready var locomotion: LocomotionComponent = $LocomotionComponent
@onready var input_handler: InputHandler = $InputHandler
@onready var visual: Node3D = $Visual
@onready var weapon: WeaponController = $WeaponController

var last_seq: int = 0

var _ignore_look_until_msec: int = 0


func _ready() -> void:
	# Never request pointer lock here: browsers require a user gesture. The first
	# click on the canvas captures the mouse (handled below).
	if DisplayServer.get_name() == "headless":
		return


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Pointer lock can emit a large synthetic delta on the capture frame.
		if Time.get_ticks_msec() < _ignore_look_until_msec:
			return
		var relative: Vector2 = event.relative
		if relative.length() > 180.0:
			relative = relative.normalized() * 180.0
		var scoped := Input.is_action_pressed("aim")
		var yaw_delta := camera_rig.look(relative, scoped)
		rotate_y(yaw_delta)
		# Let the model lag slightly behind the aim direction, then settle.
		visual.rotation.y = wrapf(visual.rotation.y - yaw_delta, -PI, PI)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_ignore_look_until_msec = Time.get_ticks_msec() + 140
			# Consume the capture click so it does not also fire the weapon.
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	camera_rig.update_aim(Input.is_action_pressed("aim"), delta)

	if locomotion.stats:
		var weight := 1.0 - exp(-locomotion.stats.visual_turn_speed * delta)
		visual.rotation.y = lerp_angle(visual.rotation.y, 0.0, weight)


func _physics_process(delta: float) -> void:
	var frame := input_handler.sample(rotation.y, camera_rig.pitch)
	last_seq = frame.seq
	locomotion.simulate(self, frame, delta)
	weapon.tick(delta, frame)
