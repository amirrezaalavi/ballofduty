class_name NetworkInterpolator
extends Node
## CP4a remote-player smoothing. Tick-indexed buffer, newest-wins (stale ticks
## dropped, never snapped back to), render at newest - 2 ticks (67 ms) minus
## the jitter margin. Extrapolation is capped at 1 tick; beyond that hold.

const BUFFER_TICKS := 2
const MAX_SAMPLES := 12
const MAX_EXTRAPOLATION_TICKS := 1

var samples_dropped: int = 0
var extrapolated_ticks: int = 0

var _samples: Array = [] # {tick: int, pos: Vector3, yaw: float, state: int}
var _newest_tick: int = -1


func reset() -> void:
	_samples.clear()
	_newest_tick = -1
	samples_dropped = 0
	extrapolated_ticks = 0


func push_sample(tick: int, pos: Vector3, yaw: float, state: int) -> void:
	if tick <= _newest_tick:
		samples_dropped += 1
		return
	_newest_tick = tick
	_samples.append({"tick": tick, "pos": pos, "yaw": yaw, "state": state})
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()


func latest_state() -> int:
	return int(_samples.back()["state"]) if not _samples.is_empty() else NetProtocol.AnimState.STILL


func has_data() -> bool:
	return not _samples.is_empty()


## Returns {pos, yaw}; also writes body velocity so animation/lean keep working.
func sample(body: CharacterBody3D, jitter_ticks: int) -> Dictionary:
	if _samples.is_empty():
		return {"pos": body.global_position, "yaw": body.rotation.y}
	var render_tick := float(_newest_tick - BUFFER_TICKS - jitter_ticks)
	var first_tick := int(_samples.front()["tick"])
	var last_tick := int(_samples.back()["tick"])

	var pos: Vector3
	var yaw: float
	if render_tick <= float(first_tick):
		pos = _samples.front()["pos"]
		yaw = float(_samples.front()["yaw"])
	elif render_tick >= float(last_tick):
		var over := render_tick - float(last_tick)
		if over > float(MAX_EXTRAPOLATION_TICKS) or _samples.size() < 2:
			pos = _samples.back()["pos"]
			yaw = float(_samples.back()["yaw"])
		else:
			extrapolated_ticks += 1
			var a: Dictionary = _samples[_samples.size() - 2]
			var b: Dictionary = _samples.back()
			var pa: Vector3 = a["pos"]
			var pb: Vector3 = b["pos"]
			var step: Vector3 = pb - pa
			pos = pb + step * over
			yaw = _lerp_angle(float(a["yaw"]), float(b["yaw"]), over)
	else:
		var lower := 0
		for i in _samples.size():
			if int(_samples[i]["tick"]) <= int(render_tick):
				lower = i
		var a2: Dictionary = _samples[lower]
		var b2: Dictionary = _samples[lower + 1]
		var span := float(int(b2["tick"]) - int(a2["tick"]))
		var t := 0.0 if span <= 0.0 else (render_tick - float(int(a2["tick"]))) / span
		var pa2: Vector3 = a2["pos"]
		var pb2: Vector3 = b2["pos"]
		pos = pa2.lerp(pb2, clampf(t, 0.0, 1.0))
		yaw = _lerp_angle(float(a2["yaw"]), float(b2["yaw"]), clampf(t, 0.0, 1.0))

	var dt := 1.0 / 30.0
	body.velocity = (pos - body.global_position) / dt
	return {"pos": pos, "yaw": yaw}


func _lerp_angle(a: float, b: float, t: float) -> float:
	return a + wrapf(b - a, -PI, PI) * t
