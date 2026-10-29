class_name PlayerController
extends CharacterBody3D
## Player driver with three roles:
## LOCAL  - input sampling + camera + weapon (solo play and net clients).
## REMOTE - client-side ghost of another player; NetworkInterpolator poses it.
## SERVER - authoritative sim body; GameManager feeds it network input frames.
## Movement itself always runs through LocomotionComponent with shared data.

enum NetRole { LOCAL, REMOTE, SERVER }

const MAX_PREDICTION_FRAMES := 64
const CORRECTION_EPSILON_M := 0.01
const VISUAL_OFFSET_DECAY := 14.0
const VISUAL_OFFSET_MAX := 2.0
const AIM_ALIGN_DEG := 8.0
const AIM_ALIGN_CAP_MSEC := 150
const AIM_HOLD_MSEC := 1500

@onready var camera_rig: CameraRig = $CameraPivot
@onready var locomotion: LocomotionComponent = $LocomotionComponent
@onready var input_handler: InputHandler = $InputHandler
@onready var visual: Node3D = $Visual
@onready var weapon: WeaponController = $WeaponController

var net_role: NetRole = NetRole.LOCAL
var net_id: int = 0
var class_id: int = 0
var last_seq: int = 0
var dead: bool = false
var net_dead: bool = false
## Camera/view yaw. Independent of body facing: the body turns toward movement,
## while the camera can orbit freely (counter-rotated on the CameraPivot).
var view_yaw: float = 0.0

# CP4b prediction. Every locally simulated frame is kept with its resulting
# state; a snapshot ack rewinds to the authoritative pose and replays the tail.
var prediction_enabled: bool = false
var last_acked_seq: int = 0
var last_ack_error_m: float = -1.0
var last_position_error_m: float = 0.0
var corrections_total: int = 0
var replay_depth: int = 0

var _prediction: Array[Dictionary] = []
var _pending_correction: Dictionary = {}
var _correction_events: Array[int] = []
var _ack_error_events: Array[Dictionary] = []
var _visual_offset := Vector3.ZERO
var _remote_offset := Vector3.ZERO
var _visual_base := Vector3.ZERO
var _camera_base := Vector3.ZERO
var _offset_active := false

var _ignore_look_until_msec: int = 0

## Combat intent shaping: body turns to the camera before a shot, and it stays
## aimed for a short window after firing. CharacterVisual reads these.
var aiming: bool = false
var aim_hold_until_msec: int = 0
var _fire_buffer_until_msec: int = 0


func _ready() -> void:
	# Capture child rest poses before any correction offset is applied.
	_visual_base = visual.position
	_camera_base = camera_rig.position
	view_yaw = rotation.y
	# Never request pointer lock here: browsers require a user gesture. The first
	# click on the canvas captures the mouse (handled below).
	if DisplayServer.get_name() == "headless":
		return
	if net_role != NetRole.LOCAL:
		var camera := get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
		if camera:
			camera.current = false


func make_remote(remote_id: int, player_class: int = 0) -> void:
	disable_prediction()
	net_role = NetRole.REMOTE
	class_id = player_class
	# Remote puppets are driven from _process; engine physics interpolation
	# would add a second, conflicting 30 Hz interpolation pass.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if is_instance_valid(visual):
		visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if weapon:
		weapon.spawn_projectiles = false
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


func make_server(server_id: int, player_class: int = 0) -> void:
	disable_prediction()
	net_role = NetRole.SERVER
	net_id = server_id
	class_id = player_class
	if weapon:
		weapon.spawn_projectiles = false
	for path: String in ["BodyHurtbox", "HeadHurtbox"]:
		var hurtbox := get_node_or_null(path) as HurtboxComponent
		if hurtbox:
			hurtbox.entity_id = server_id
	var camera := get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if camera:
		camera.current = false
	var visual_node := get_node_or_null("Visual") as Node3D
	if visual_node:
		visual_node.process_mode = Node.PROCESS_MODE_DISABLED


func _unhandled_input(event: InputEvent) -> void:
	if net_role != NetRole.LOCAL or dead:
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
		view_yaw = wrapf(view_yaw + yaw_delta, -PI, PI)
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
	if net_role == NetRole.REMOTE:
		_apply_remote(delta)
		return
	if net_role != NetRole.LOCAL:
		return
	# Counter-rotate the pivot so the camera keeps the view yaw while the body
	# turns underneath it.
	camera_rig.rotation.y = wrapf(view_yaw - rotation.y, -PI, PI)
	camera_rig.update_aim(Input.is_action_pressed("aim"), delta)
	_decay_visual_offset(delta)

	if locomotion.stats:
		var weight := 1.0 - exp(-locomotion.stats.visual_turn_speed * delta)
		visual.rotation.y = lerp_angle(visual.rotation.y, 0.0, weight)


func _physics_process(delta: float) -> void:
	match net_role:
		NetRole.LOCAL:
			if dead:
				return
			var frame := input_handler.sample(view_yaw, camera_rig.pitch)
			_shape_combat_intent(frame)
			simulate_tick(frame, delta)
			weapon.tick(delta, frame)
			_forward_input(frame)
		NetRole.REMOTE:
			pass # posed from _process at render rate
		NetRole.SERVER:
			pass # GameManager drives server_step once per tick for all actors.


## Server-side step with an already-validated network frame. `frame.yaw` is the
## client's view yaw used to convert movement; body facing is derived by the
## shared locomotion step, so a missing packet cannot snap anyone to a default.
func server_step(frame: PlayerInputFrame, delta: float) -> void:
	locomotion.simulate(self, frame, delta, -1, frame.yaw)


## One local simulation step: reconcile any pending snapshot, simulate, record.
## Used by _physics_process for real input and by tests/bots with explicit frames,
## so the predicted path is identical in both cases.
func simulate_tick(frame: PlayerInputFrame, delta: float) -> void:
	if dead:
		return
	if prediction_enabled and not _pending_correction.is_empty():
		_apply_correction()
	last_seq = frame.seq
	locomotion.simulate(self, frame, delta, -1, frame.yaw)
	if prediction_enabled:
		_record_prediction(frame)


## Start predicting after JOIN_OK; clear any history from the pre-join pose.
func enable_prediction() -> void:
	prediction_enabled = true
	view_yaw = rotation.y
	last_acked_seq = 0
	last_ack_error_m = -1.0
	last_position_error_m = 0.0
	corrections_total = 0
	replay_depth = 0
	_prediction.clear()
	_pending_correction.clear()
	_correction_events.clear()
	_ack_error_events.clear()
	_visual_offset = Vector3.ZERO
	_offset_active = false
	visual.position = _visual_base
	camera_rig.position = _camera_base


func set_dead(value: bool) -> void:
	dead = value
	aiming = false
	aim_hold_until_msec = 0
	_fire_buffer_until_msec = 0
	if dead:
		velocity = Vector3.ZERO
		if weapon:
			weapon.spawn_projectiles = false


func respawn_at(position: Vector3, yaw: float) -> void:
	dead = false
	aiming = false
	aim_hold_until_msec = 0
	_fire_buffer_until_msec = 0
	global_position = position
	rotation.y = yaw
	view_yaw = yaw
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	var health := get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.reset()
	if weapon:
		weapon.reset_ammo()
	enable_prediction()


## Turn-then-shoot: hold the fire bit until the body is aligned with the view,
## capped at 150 ms so a very fast flick still fires. ADS locks facing without
## delaying the shot (the aim bit already makes locomotion turn).
func _shape_combat_intent(frame: PlayerInputFrame) -> void:
	var wants_fire := frame.fire
	frame.aim = frame.aim or wants_fire
	aiming = frame.aim
	var now := Time.get_ticks_msec()
	if not wants_fire:
		_fire_buffer_until_msec = 0
		return
	if _aim_aligned():
		aim_hold_until_msec = now + AIM_HOLD_MSEC
		_fire_buffer_until_msec = 0
		return
	if _fire_buffer_until_msec == 0:
		_fire_buffer_until_msec = now + AIM_ALIGN_CAP_MSEC
	if now < _fire_buffer_until_msec:
		frame.fire = false
	else:
		aim_hold_until_msec = now + AIM_HOLD_MSEC
		_fire_buffer_until_msec = 0


func _aim_aligned() -> bool:
	return absf(wrapf(view_yaw - rotation.y, -PI, PI)) <= deg_to_rad(AIM_ALIGN_DEG)


func set_view_yaw(yaw: float) -> void:
	view_yaw = wrapf(yaw, -PI, PI)
	camera_rig.rotation.y = wrapf(view_yaw - rotation.y, -PI, PI)


func disable_prediction() -> void:
	prediction_enabled = false
	_prediction.clear()
	_pending_correction.clear()
	_correction_events.clear()
	_ack_error_events.clear()
	_visual_offset = Vector3.ZERO
	_offset_active = false
	visual.position = _visual_base
	camera_rig.position = _camera_base


## Called from GameManager when a snapshot row matches the local player id.
## The newest ack wins; stale/older snapshots are ignored.
func accept_server_state(entry: Dictionary) -> void:
	# Observe HP even while dead: the death event can arrive one snapshot before
	# the hp=0 row, and the HUD should not stay at the pre-death value.
	var health := get_node_or_null("HealthComponent") as HealthComponent
	if health and entry.has("hp"):
		health.observe(int(entry["hp"]))
	if dead:
		return
	if not prediction_enabled:
		return
	var ack := int(entry.get("ack", -1))
	if ack <= last_acked_seq or ack > last_seq:
		return
	_pending_correction = entry


func prediction_stats() -> Dictionary:
	var now := Time.get_ticks_msec()
	while not _correction_events.is_empty() and now - _correction_events[0] > 1000:
		_correction_events.pop_front()
	while not _ack_error_events.is_empty() and now - int(_ack_error_events[0]["msec"]) > 1000:
		_ack_error_events.pop_front()
	var recent_ack_error := 0.0
	for event in _ack_error_events:
		recent_ack_error = maxf(recent_ack_error, float(event["m"]))
	return {
		"enabled": prediction_enabled,
		"ack": last_acked_seq,
		"pending": _prediction.size(),
		"ack_error_m": last_ack_error_m,
		"recent_ack_error_m": recent_ack_error,
		"visual_error_m": _visual_offset.length(),
		"last_correction_m": last_position_error_m,
		"corrections": corrections_total,
		"corrections_per_sec": _correction_events.size(),
		"replay_depth": replay_depth,
	}


## Coarse animation byte for snapshots: still / walk / sprint / air.
func anim_state_byte() -> int:
	if not is_on_floor():
		return NetProtocol.AnimState.AIR
	var speed := Vector2(velocity.x, velocity.z).length()
	if speed > 1.9:
		return NetProtocol.AnimState.SPRINT
	if speed > 0.15:
		return NetProtocol.AnimState.WALK
	return NetProtocol.AnimState.STILL


func _record_prediction(frame: PlayerInputFrame) -> void:
	_prediction.append({
		"seq": frame.seq,
		"frame": frame,
		"pos": global_position,
		"yaw": rotation.y,
		"vel": velocity,
		"on_floor": is_on_floor(),
	})
	while _prediction.size() > MAX_PREDICTION_FRAMES:
		_prediction.pop_front()


func _apply_correction() -> void:
	var entry := _pending_correction
	_pending_correction = {}
	if entry.is_empty():
		return

	var ack := int(entry["ack"])
	var first_authority := last_acked_seq == 0
	# Drop history up to and including the acked input, keeping its state for
	# the authoritative-error metric (server pose vs our prediction for that seq).
	var stored: Dictionary = {}
	while not _prediction.is_empty() and int(_prediction[0]["seq"]) <= ack:
		stored = _prediction.pop_front()
	var server_pos: Vector3 = entry["pos"]
	last_ack_error_m = (
		(stored["pos"] as Vector3).distance_to(server_pos) if stored.has("pos") else -1.0
	)

	var before := global_position
	global_position = server_pos
	rotation.y = float(entry["yaw"])
	velocity = entry.get("vel", Vector3.ZERO)

	# Replay every unacked input from the authoritative pose. The first frame
	# needs the server's ground flag because the teleport has not moved yet.
	var on_floor_first := 1 if bool(entry.get("on_floor", true)) else 0
	var first := true
	replay_depth = _prediction.size()
	for item in _prediction:
		locomotion.simulate(
			self, item["frame"], 1.0 / 30.0,
			on_floor_first if first else -1, item["frame"].yaw
		)
		item["pos"] = global_position
		item["yaw"] = rotation.y
		item["vel"] = velocity
		item["on_floor"] = is_on_floor()
		first = false

	last_acked_seq = ack
	# Hide the visible jump by offsetting the render children, then letting the
	# offset decay over ~100 ms. The collision body is already authoritative.
	var visual_delta := before - global_position
	visual_delta.y = 0.0
	last_position_error_m = visual_delta.length()
	# The very first authoritative state is the spawn baseline: snap to it
	# instead of smoothing a 30 cm settle into the camera. Every later
	# correction is hidden by the decaying render offset.
	if last_position_error_m > CORRECTION_EPSILON_M and not first_authority:
		corrections_total += 1
		_correction_events.append(Time.get_ticks_msec())
		if last_ack_error_m >= 0.0:
			_ack_error_events.append({"msec": Time.get_ticks_msec(), "m": last_ack_error_m})
		_visual_offset += visual_delta
		if _visual_offset.length() > VISUAL_OFFSET_MAX:
			_visual_offset = _visual_offset.normalized() * VISUAL_OFFSET_MAX
		_offset_active = true
		_apply_visual_offset()


func _apply_visual_offset() -> void:
	var local_offset := global_transform.basis.inverse() * _visual_offset
	visual.position = _visual_base + local_offset
	camera_rig.position = _camera_base + local_offset


func _decay_visual_offset(delta: float) -> void:
	if not _offset_active:
		return
	_visual_offset *= exp(-VISUAL_OFFSET_DECAY * delta)
	if _visual_offset.length_squared() < 0.000001:
		_visual_offset = Vector3.ZERO
		_offset_active = false
		visual.position = _visual_base
		camera_rig.position = _camera_base
		return
	_apply_visual_offset()


func _forward_input(frame: PlayerInputFrame) -> void:
	var gm := get_node_or_null("/root/GameManager")
	if gm != null and gm.is_net_client():
		gm.client_send_input(frame)


func _apply_remote(delta: float) -> void:
	if net_dead:
		# Keep the corpse visible so CharacterVisual can play Death_A and the
		# red death marker; do not keep interpolating the body.
		visible = true
		return
	var interp := get_node_or_null("NetworkInterpolator") as NetworkInterpolator
	if interp == null or not interp.has_data():
		return
	var sample: Dictionary = interp.sample(delta)
	if sample.is_empty():
		return
	visible = true
	var target_pos: Vector3 = sample["pos"]
	var target_yaw: float = sample["yaw"]
	var teleported := interp.consume_teleport()
	var error := target_pos - global_position
	global_position = target_pos
	rotation.y = target_yaw
	if teleported or error.length() > 4.0:
		_remote_offset = Vector3.ZERO
	else:
		# Show the old pose for a few frames instead of snapping the mesh when
		# interpolation is corrected. The collision body is already at target.
		_remote_offset = (_remote_offset + error).limit_length(1.5)
	_remote_offset *= exp(-18.0 * delta)
	if _remote_offset.length_squared() < 0.000001:
		_remote_offset = Vector3.ZERO
	visual.position = _visual_base + global_transform.basis.inverse() * _remote_offset
	visual.rotation.y = 0.0
	var character_visual := visual as CharacterVisual
	if character_visual:
		character_visual.force_anim = int(sample["state"])


func reset_remote_smoothing() -> void:
	_remote_offset = Vector3.ZERO
	visual.position = _visual_base
