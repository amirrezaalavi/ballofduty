extends Node
## L9 performance probe. Opt-in and disabled by default:
##   web build:  ?perf=1 on the page URL
##   native:     --perf in OS.get_cmdline_user_args()
##
## Samples frame deltas into a preallocated ring so the probe never allocates
## per frame. A 10 s warm-up is discarded before the 60 s measurement window.
## On web it also publishes `window.__bod_perf()`, `window.__bod_perf_reset()`
## and `window.__bod_state` for tools/ci/browser_smoke.mjs. Headless builds have
## no JavaScriptBridge, so every bridge call is a guarded no-op there.
##
## The probe only reports. It never changes quality, settings or gameplay; the
## LOW/MEDIUM/HIGH choice stays a manual user decision (L6).

const WINDOW_SECONDS := 60.0
const WARMUP_SECONDS := 10.0
const SAMPLE_HZ := 60.0
## 3,600 frames = 60 s at 60 Hz; 600 frames ≈ 10 s at 60 Hz.
const WINDOW_FRAMES := int(WINDOW_SECONDS * SAMPLE_HZ)
const WARMUP_FRAMES := int(WARMUP_SECONDS * SAMPLE_HZ)
const LONG_FRAME_MS := 33.3
const STALL_FRAME_MS := 250.0
const HITCH_FRAME_MS := 500.0
## Refresh the JSON the JS bridge reads about four times per second.
const BRIDGE_REFRESH_FRAMES := 15

var enabled: bool = false

var _samples := PackedFloat32Array()
var _write_index: int = 0
var _sample_count: int = 0
var _frames_total: int = 0
var _warmup_left: int = 0
var _bridge_refresh: int = 0

var _js: Object = null
var _js_ready: bool = false

var _state_in_game: bool = false
var _state_phase: StringName = &""
var _state_class_id: int = -1
var _state_net: StringName = &""


func _ready() -> void:
	_samples.resize(WINDOW_FRAMES)
	_samples.fill(0.0)
	enabled = _requested_by_cmdline() or _requested_by_url()
	if not enabled:
		set_process(false)
		return
	_warmup_left = WARMUP_FRAMES
	_install_bridge()


func _process(delta: float) -> void:
	if not enabled:
		return
	_frames_total += 1
	if _warmup_left > 0:
		_warmup_left -= 1
	else:
		_samples[_write_index] = delta * 1000.0
		_write_index = (_write_index + 1) % WINDOW_FRAMES
		if _sample_count < WINDOW_FRAMES:
			_sample_count += 1

	_bridge_refresh += 1
	if _bridge_refresh < BRIDGE_REFRESH_FRAMES:
		return
	_bridge_refresh = 0
	if not _js_ready:
		return
	if _consume_reset_flag():
		reset()
	_publish_report()


## Restart the measurement window (including the warm-up) without disabling
## the probe. Called by `window.__bod_perf_reset()` on web.
func reset() -> void:
	_write_index = 0
	_sample_count = 0
	_frames_total = 0
	_warmup_left = WARMUP_FRAMES
	_bridge_refresh = 0
	if _samples.size() == WINDOW_FRAMES:
		_samples.fill(0.0)


## Current report. Safe to call headless: monitor values are still real, the JS
## heap is null because `performance.memory` is a browser-only API.
func report() -> Dictionary:
	var out := summarize(_window_values(), 0)
	out["enabled"] = enabled
	out["frames_total"] = _frames_total
	out["warmup_remaining"] = _warmup_left
	out["window_seconds"] = WINDOW_SECONDS
	out["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	out["primitives"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	out["js_heap_bytes"] = _js_heap_bytes()
	return out


## Publish `{in_game, phase, class_id, net}` to the page. Cheap when unchanged:
## only primitive comparisons until a phase transition actually happens.
func set_match_state(in_game: bool, phase: StringName, class_id: int, net: StringName) -> void:
	if in_game == _state_in_game and phase == _state_phase \
			and class_id == _state_class_id and net == _state_net:
		return
	_state_in_game = in_game
	_state_phase = phase
	_state_class_id = class_id
	_state_net = net
	if _js == null:
		return
	var state := {
		"in_game": in_game,
		"phase": String(phase),
		"class_id": class_id,
		"net": String(net),
	}
	_js.eval("window.__bod_state = %s;" % JSON.stringify(state), true)


# --- pure math (unit-testable headless) -----------------------------------

## Nearest-rank percentile over an ascending array. p is clamped to [0, 1].
## Empty input returns 0.0; a single sample is returned unchanged.
static func percentile(sorted_values: PackedFloat32Array, p: float) -> float:
	var count := sorted_values.size()
	if count == 0:
		return 0.0
	if count == 1:
		return sorted_values[0]
	var rank := int(ceil(clampf(p, 0.0, 1.0) * float(count))) - 1
	return sorted_values[clampi(rank, 0, count - 1)]


## Summarize frame times in milliseconds. `warmup_frames` leading samples are
## discarded, matching the probe's 10 s JIT/shader-compile warm-up.
static func summarize(samples: PackedFloat32Array, warmup_frames: int = 0) -> Dictionary:
	var start := clampi(warmup_frames, 0, samples.size())
	var count := samples.size() - start
	var out := {
		"frames": count,
		"fps_avg": 0.0,
		"frame_ms_p50": 0.0,
		"frame_ms_p95": 0.0,
		"frame_ms_p99": 0.0,
		"frames_over_33_3ms": 0,
		"frames_over_250ms": 0,
		"frames_over_500ms": 0,
	}
	if count <= 0:
		return out

	var values := PackedFloat32Array()
	values.resize(count)
	var total := 0.0
	var over_long := 0
	var over_stall := 0
	var over_hitch := 0
	for index in count:
		var frame_ms := samples[start + index]
		values[index] = frame_ms
		total += frame_ms
		if frame_ms > LONG_FRAME_MS:
			over_long += 1
		if frame_ms > STALL_FRAME_MS:
			over_stall += 1
		if frame_ms > HITCH_FRAME_MS:
			over_hitch += 1

	values.sort()
	var mean_ms := total / float(count)
	out["fps_avg"] = 1000.0 / mean_ms if mean_ms > 0.0 else 0.0
	out["frame_ms_p50"] = percentile(values, 0.5)
	out["frame_ms_p95"] = percentile(values, 0.95)
	out["frame_ms_p99"] = percentile(values, 0.99)
	out["frames_over_33_3ms"] = over_long
	out["frames_over_250ms"] = over_stall
	out["frames_over_500ms"] = over_hitch
	return out


# --- internals ------------------------------------------------------------

func _requested_by_cmdline() -> bool:
	return OS.get_cmdline_user_args().has("--perf")


func _requested_by_url() -> bool:
	var js := _bridge()
	if js == null:
		return false
	var query := str(js.eval("window.location.search", true))
	return query.contains("perf=1")


func _bridge() -> Object:
	if not OS.has_feature("web"):
		return null
	if not Engine.has_singleton("JavaScriptBridge"):
		return null
	return Engine.get_singleton("JavaScriptBridge")


func _install_bridge() -> void:
	var js := _bridge()
	if js == null:
		return
	_js = js
	_js_ready = true
	js.eval(
		"window.__bod_perf = function () { return window.__bod_perf_json || '{}'; };\n"
		+ "window.__bod_perf_reset = function () { window.__bod_perf_reset_flag = true; };\n"
		+ "window.__bod_perf_json = '{}';\n"
		+ "window.__bod_state = window.__bod_state || "
		+ "{in_game: false, phase: 'menu', class_id: 0, net: 'offline'};",
		true
	)
	_publish_report()


func _consume_reset_flag() -> bool:
	if _js == null:
		return false
	return bool(_js.eval(
		"(function () { var f = window.__bod_perf_reset_flag === true;"
		+ " window.__bod_perf_reset_flag = false; return f; })()",
		true
	))


func _publish_report() -> void:
	if _js == null:
		return
	var payload := JSON.stringify(report())
	_js.eval("window.__bod_perf_json = %s;" % JSON.stringify(payload), true)


func _js_heap_bytes() -> Variant:
	if _js == null:
		return null
	var value: Variant = _js.eval(
		"(typeof performance !== 'undefined' && performance.memory)"
		+ " ? performance.memory.usedJSHeapSize : null",
		true
	)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return null


## Ring contents in chronological order. Allocates, so it is only called when a
## report is requested (about four times per second), never per frame.
func _window_values() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _sample_count <= 0:
		return out
	out.resize(_sample_count)
	if _sample_count < WINDOW_FRAMES:
		for index in _sample_count:
			out[index] = _samples[index]
		return out
	for index in WINDOW_FRAMES:
		out[index] = _samples[(_write_index + index) % WINDOW_FRAMES]
	return out
