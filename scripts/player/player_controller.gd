class_name PlayerController
extends CharacterBody3D
## Player driver with three roles:
## LOCAL  - input sampling + camera + weapon (solo play and net clients).
## REMOTE - client-side ghost of another player; NetworkInterpolator poses it.
## SERVER - authoritative sim body; GameManager feeds it network input frames.
## Movement itself always runs through LocomotionComponent with shared data.

enum NetRole { LOCAL, REMOTE, SERVER }

@onready var camera_rig: CameraRig = $CameraPivot
@onready var locomotion: LocomotionComponent = $LocomotionComponent
@onready var input_handler: InputHandler = $InputHandler
@onready var visual: Node3D = $Visual
@onready var weapon: WeaponController = $WeaponController

var net_role: NetRole = NetRole.LOCAL
var net_id: int = 0
var last_seq: int = 0

var _ignore_look_until_msec: int = 0


func _ready() -> void:
	# Never request pointer lock here: browsers require a user gesture. The first
	# click on the canvas captures the mouse (handled below).
	if DisplayServer.get_name() == "headless":
		return
	if net_role != NetRole.LOCAL:
		var camera := get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
		if camera:
			camera.current = false


func make_remote(remote_id: int) -> void:
	net_role = NetRole.REMOTE
	net_id = remote_id
	collision_layer = 0
	collision_mask = 0
	var camera := get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if camera:
		camera.current = false
	visual.rotation.y = 0.0
	# Pose from snapshots only; do not let the local state machine drive a ghost.
	var character_visual := visual as CharacterVisual
	if character_visual:
		character_visual.force_anim = NetProtocol.AnimState.STILL
	# A ghost is a picture, not an authority. Keep hurtboxes so shots stop on the
	# body, but never let a client apply damage to another player locally: that
	# produced hitmarkers and drained ghost HP with no server involvement.
	for hurtbox_path in ["BodyHurtbox", "HeadHurtbox"]:
		var hurtbox := get_node_or_null(hurtbox_path) as HurtboxComponent
		if hurtbox:
			hurtbox.damage_enabled = false
	if not has_node("NetworkInterpolator"):
		var interp := NetworkInterpolator.new()
		interp.name = "NetworkInterpolator"
		add_child(interp)


func make_server(server_id: int) -> void:
	net_role = NetRole.SERVER
	net_id = server_id
	var camera := get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if camera:
		camera.current = false
	var visual_node := get_node_or_null("Visual") as Node3D
	if visual_node:
		visual_node.process_mode = Node.PROCESS_MODE_DISABLED


func _unhandled_input(event: InputEvent) -> void:
	if net_role != NetRole.LOCAL:
		return
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
			# Consume the capture click so it does not fire the weapon.
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if net_role != NetRole.LOCAL:
		return
	camera_rig.update_aim(Input.is_action_pressed("aim"), delta)

	if locomotion.stats:
		var weight := 1.0 - exp(-locomotion.stats.visual_turn_speed * delta)
		visual.rotation.y = lerp_angle(visual.rotation.y, 0.0, weight)


func _physics_process(delta: float) -> void:
	match net_role:
		NetRole.LOCAL:
			var frame := input_handler.sample(rotation.y, camera_rig.pitch)
			last_seq = frame.seq
			locomotion.simulate(self, frame, delta)
			weapon.tick(delta, frame)
			_forward_input(frame)
		NetRole.REMOTE:
			_apply_remote(delta)
		NetRole.SERVER:
			pass # GameManager drives server_step once per tick for all actors.


## Server-side step with an already-validated network frame. Until the client
## sends its first frame the spawn yaw is authoritative; after that the client
## owns aim yaw, so a dropped packet can never snap a player to a default angle.
func server_step(frame: PlayerInputFrame, delta: float, apply_yaw: bool = true) -> void:
	if apply_yaw:
		rotation.y = frame.yaw
	locomotion.simulate(self, frame, delta)


## Coarse animation byte for snapshots: still / walk / sprint / air.
func anim_state_byte() -> int:
	if not is_on_floor():
		return NetProtocol.AnimState.AIR
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 6.4:
		return NetProtocol.AnimState.SPRINT
	if speed > 0.25:
		return NetProtocol.AnimState.WALK
	return NetProtocol.AnimState.STILL


func _forward_input(frame: PlayerInputFrame) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.is_net_client():
		gm.client_send_input(frame)


func _apply_remote(_delta: float) -> void:
	var interp := get_node_or_null("NetworkInterpolator") as NetworkInterpolator
	if interp == null or not interp.has_data():
		return
	var gm := get_node_or_null("/root/GameManager")
	var jitter: int = gm.remote_jitter_ticks() if gm != null else 0
	var sample: Dictionary = interp.sample(self, jitter)
	visible = true
	global_position = sample["pos"]
	rotation.y = sample["yaw"]
	visual.rotation.y = 0.0
	var character_visual := visual as CharacterVisual
	if character_visual:
		character_visual.force_anim = interp.latest_state()
