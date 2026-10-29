extends GdUnitTestSuite
## Toolchain sanity check: proves the gdUnit4 CLI runner works headless.


func test_engine_runs() -> void:
	assert_int(2 + 2).is_equal(4)


func test_scene_instantiation() -> void:
	var packed := load("res://scenes/characters/player.tscn") as PackedScene
	var player := auto_free(packed.instantiate()) as PlayerController
	add_child(player)
	await await_idle_frame()
	assert_that(player.locomotion).is_not_null()
