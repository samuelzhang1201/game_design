extends GutTest
## The pointer's dwell (spec 2026-10-07-war-room-scale-hover §4.2): still for
## the delay within the still radius shows; any move beyond it clears.


func test_a_still_pointer_dwells_once_after_the_delay() -> void:
	var d := WarHoverDwell.new()
	assert_false(d.moved(Vector2(100, 100), 4.0))
	assert_false(d.step(0.2, 0.35))
	assert_true(d.step(0.2, 0.35), "the delay is over")
	assert_false(d.step(0.2, 0.35), "only once")


func test_a_small_jitter_does_not_restart_the_dwell() -> void:
	var d := WarHoverDwell.new()
	d.moved(Vector2(100, 100), 4.0)
	d.step(0.3, 0.35)
	assert_false(d.moved(Vector2(102, 101), 4.0))
	assert_true(d.step(0.1, 0.35))


func test_a_move_beyond_the_radius_clears_a_shown_dwell() -> void:
	var d := WarHoverDwell.new()
	d.moved(Vector2(100, 100), 4.0)
	d.step(1.0, 0.35)
	assert_true(d.moved(Vector2(140, 100), 4.0), "it was showing: cleared")
	assert_false(d.moved(Vector2(180, 100), 4.0), "nothing showing to clear")
	assert_false(d.step(0.1, 0.35))
	assert_true(d.step(0.3, 0.35))
