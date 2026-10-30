extends BodTestSuite
## L9 performance probe. The percentile/summarize math is pure static GDScript,
## so most cases run directly. The Node cases also exercise the headless path:
## there is no JavaScriptBridge, and the probe must stay a silent no-op.

const PERF_SCRIPT := preload("res://scripts/autoload/perf_probe.gd")

var _nodes: Array[Node] = []


func after_test() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func test_percentile_handles_empty_single_and_known_data() -> void:
	var empty := PackedFloat32Array()
	expect(is_equal_approx(PERF_SCRIPT.percentile(empty, 0.95), 0.0),
		"an empty sample set has no percentile")

	var single := PackedFloat32Array([12.5])
	expect(is_equal_approx(PERF_SCRIPT.percentile(single, 0.5), 12.5),
		"a single sample is its own median")
	expect(is_equal_approx(PERF_SCRIPT.percentile(single, 0.99), 12.5),
		"a single sample is its own p99")

	var known := PackedFloat32Array([1.0, 2.0, 3.0, 4.0])
	expect(is_equal_approx(PERF_SCRIPT.percentile(known, 0.5), 2.0),
		"nearest-rank median of 1..4 is 2")
	expect(is_equal_approx(PERF_SCRIPT.percentile(known, 0.0), 1.0),
		"p0 returns the smallest sample")
	expect(is_equal_approx(PERF_SCRIPT.percentile(known, 1.0), 4.0),
		"p100 returns the largest sample")


func test_percentile_p95_and_p99_are_correct() -> void:
	var values := PackedFloat32Array()
	for index in 100:
		values.append(float(index + 1))
	expect(is_equal_approx(PERF_SCRIPT.percentile(values, 0.95), 95.0),
		"p95 of 1..100 is 95")
	expect(is_equal_approx(PERF_SCRIPT.percentile(values, 0.99), 99.0),
		"p99 of 1..100 is 99")


func test_summarize_excludes_warmup_frames() -> void:
	var samples := PackedFloat32Array([1000.0, 1000.0, 10.0, 20.0, 30.0])
	var summary: Dictionary = PERF_SCRIPT.summarize(samples, 2)
	expect(int(summary["frames"]) == 3, "warm-up frames are not counted")
	expect(is_equal_approx(float(summary["fps_avg"]), 50.0),
		"20 ms mean frame time is 50 fps")
	expect(is_equal_approx(float(summary["frame_ms_p50"]), 20.0),
		"median ignores the two warm-up spikes")
	expect(int(summary["frames_over_500ms"]) == 0,
		"warm-up spikes do not trip the long-frame counter")


func test_summarize_counts_long_frames() -> void:
	var samples := PackedFloat32Array([10.0, 20.0, 40.0, 300.0, 600.0])
	var summary: Dictionary = PERF_SCRIPT.summarize(samples, 0)
	expect(int(summary["frames_over_33_3ms"]) == 3,
		"40/300/600 ms frames exceed 33.3 ms")
	expect(int(summary["frames_over_250ms"]) == 2,
		"300/600 ms frames exceed 250 ms")
	expect(int(summary["frames_over_500ms"]) == 1,
		"only the 600 ms frame exceeds 500 ms")
	expect(is_equal_approx(float(summary["frame_ms_p95"]), 600.0),
		"nearest-rank p95 of five samples is the maximum")


func test_report_shape() -> void:
	var probe := _make_probe()
	probe.enabled = true
	probe._warmup_left = 0
	for _index in 5:
		probe._process(0.02)

	var report: Dictionary = probe.report()
	for key in [
		"frames", "fps_avg", "frame_ms_p50", "frame_ms_p95", "frame_ms_p99",
		"frames_over_33_3ms", "frames_over_250ms", "frames_over_500ms",
		"draw_calls", "primitives", "js_heap_bytes", "enabled", "frames_total",
		"warmup_remaining", "window_seconds",
	]:
		expect(report.has(key), "report exposes %s" % key)
	expect(int(report["frames"]) == 5, "five post-warm-up frames were sampled")
	expect(is_equal_approx(float(report["fps_avg"]), 50.0), "20 ms frames average 50 fps")
	expect(report["js_heap_bytes"] == null,
		"performance.memory is unavailable headless, so the heap is null (not invented)")
	expect(is_equal_approx(float(report["window_seconds"]), PERF_SCRIPT.WINDOW_SECONDS),
		"report names the 60 s window")


func test_headless_safety_without_javascript_bridge() -> void:
	var probe := _make_probe()
	expect(probe._js == null, "headless builds have no JavaScriptBridge")
	probe.enabled = true
	probe.set_match_state(true, &"match", 2, &"client")
	probe.set_match_state(true, &"match", 2, &"client")
	probe.reset()
	probe._process(0.016)

	var report: Dictionary = probe.report()
	expect(report.has("frames"), "report works without the JS bridge")
	expect(probe._state_phase == &"match", "match state is cached headless")
	expect(probe._state_net == &"client", "net state is cached headless")


func test_probe_is_disabled_by_default() -> void:
	var probe := _make_probe()
	expect(not probe.enabled, "the probe is off without ?perf=1 or --perf")
	for _index in 10:
		probe._process(0.5)

	var report: Dictionary = probe.report()
	expect(int(report["frames"]) == 0, "a disabled probe samples nothing")
	expect(int(report["frames_total"]) == 0, "a disabled probe counts nothing")


func _make_probe() -> Node:
	var probe := PERF_SCRIPT.new() as Node
	add_child(probe)
	_nodes.append(probe)
	return probe
