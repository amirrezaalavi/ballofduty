class_name BodTestSuite
extends GdUnitTestSuite
## Shared helpers for Ball of Duty suites. gdUnit4 owns assertions and reporting;
## these helpers only replace the duplicated harness plumbing from the old
## SceneTree scripts (`_check`, `_wait_for`, `_finish`).


## Assert with a human-readable label. On failure gdUnit4 reports the label plus
## the expression, and the suite continues (the CLI runs with fail-fast off).
func expect(condition: bool, label: String) -> void:
	assert_bool(condition).override_failure_message(label).is_true()


## Pump physics frames until the predicate holds. Returns the final predicate
## value so callers can assert on the timeout case separately.
func wait_for(predicate: Callable, frames: int = 300) -> bool:
	for _i in frames:
		if predicate.call():
			return true
		await get_tree().physics_frame
	return predicate.call()
