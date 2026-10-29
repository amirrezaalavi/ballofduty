class_name NetworkInterpolator
extends Node
## Render-rate smoothing for remote players.
##
## The interpolator keeps a short tick history and advances its own virtual
## server clock every rendered frame. It renders 2.5 ticks behind the newest
## snapshot (83 ms), which is enough to survive browser event-loop coalescing at
## 25-45 ms RTT while still feeling responsive. If the buffer runs dry it
## extrapolates at most one tick with damped velocity; corrections are hidden by
## a decaying render offset in PlayerController, never by a teleport.
##
## Physics interpolation must be OFF on remote puppets: this node writes the
## root transform from _process at render rate, and Godot's physics
## interpolation would otherwise fight it.

const TICK_RATE := 30.0
const TICK_INTERVAL := 1.0 / TICK_RATE
const INTERP_DELAY := 2.5 * TICK_INTERVAL
const MAX_EXTRAPOLATION := TICK_INTERVAL
const EXTRAPOLATION_DAMPING := 0.65
const MAX_SAMPLES := 16
const TELEPORT_DISTANCE := 4.0

var samples_dropped: int = 0
var extrapolated_ticks: int = 0

var _samples: Array = [] # {tick, pos, yaw, state, vel}
var _newest_tick: int = -1
var _render_time: float = -1.0
var _teleported: bool = false


func reset() -> void:
	_samples.clear()
	_newest_tick = -1
	_render_time = -1.0
	_teleported = false
	samples_dropped = 0
	extrapolated_ticks = 0


func push_sample(tick: int, pos: Vector3, yaw: float, state: int, vel: Vector3 = Vector3.ZERO) -> void:
	if tick <= _newest_tick:
		samples_dropped += 1
		return
	if not _samples.is_empty():
		var last: Dictionary = _samples.back()
		if (last["pos"] as Vector3).distance_to(pos) > TELEPORT_DISTANCE:
			# Respawn or server teleport: do not slide across the arena.
			reset()
			_teleported = true
	if _render_time < 0.0:
		_render_time = float(tick) * TICK_INTERVAL
	_newest_tick = tick
	_samples.append({"tick": tick, "pos": pos, "yaw": yaw, "state": state, "vel": vel})
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


func latest_state() -> int:
	return int(_samples.back()["state"]) if not _samples.is_empty() else NetProtocol.AnimState.STILL


func has_data() -> bool:
	return not _samples.is_empty()


func consume_teleport() -> bool:
	var was := _teleported
	_teleported = false
	return was


## Advance the virtual clock and return the pose to render this frame.
## Also returns the newest state byte so animation selection stays in sync.
func sample(delta: float) -> Dictionary:
	if _samples.is_empty():
		return {}
	_render_time += delta
	var render_time := _render_time - INTERP_DELAY

	var newest: Dictionary = _samples.back()
	var newest_time := float(int(newest["tick"])) * TICK_INTERVAL

	# Keep the virtual clock near the snapshot timeline without snapping the
	# rendered pose when a packet arrives late or early.
	var target := newest_time - INTERP_DELAY
	var drift := render_time - target
	if absf(drift) > 0.30:
		_render_time = target + INTERP_DELAY
	elif absf(drift) > 0.004:
		_render_time -= drift * 0.02

	var pos: Vector3
	var yaw: float
	var state := int(_samples.front()["state"])
	if render_time <= float(int(_samples.front()["tick"])) * TICK_INTERVAL:
		pos = _samples.front()["pos"]
		yaw = float(_samples.front()["yaw"])
		state = int(_samples.front()["state"])
	elif render_time >= newest_time:
		var over := minf(render_time - newest_time, MAX_EXTRAPOLATION)
		var vel: Vector3 = newest.get("vel", Vector3.ZERO)
		pos = (newest["pos"] as Vector3) + vel * EXTRAPOLATION_DAMPING * over
		yaw = float(newest["yaw"])
		state = int(newest["state"])
		extrapolated_ticks += 1
	else:
		var lower := 0
		for i in _samples.size() - 1:
			if float(int(_samples[i]["tick"])) * TICK_INTERVAL <= render_time:
				lower = i
			else:
				break
		var a: Dictionary = _samples[lower]
		var b: Dictionary = _samples[lower + 1]
		var a_time := float(int(a["tick"])) * TICK_INTERVAL
		var b_time := float(int(b["tick"])) * TICK_INTERVAL
		var span := b_time - a_time
		var t := 0.0 if span <= 0.0 else clampf((render_time - a_time) / span, 0.0, 1.0)
		pos = (a["pos"] as Vector3).lerp(b["pos"] as Vector3, t)
		yaw = _lerp_angle(float(a["yaw"]), float(b["yaw"]), t)
		state = int(a["state"])

	return {"pos": pos, "yaw": yaw, "state": state}


func _lerp_angle(a: float, b: float, t: float) -> float:
	return a + wrapf(b - a, -PI, PI) * t
