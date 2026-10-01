extends GutTest
## The roll-up's timing: the midpoint lays, the table's depth goes 1 -> sliver -> 1.


func test_it_is_idle_until_started_and_stands_at_full_depth() -> void:
	var s := WarSheetSwap.new()
	assert_false(s.active())
	assert_eq(s.z_scale(), 1.0)


func test_the_midpoint_is_crossed_exactly_once() -> void:
	var s := WarSheetSwap.new()
	s.start(3, 1.0)
	assert_false(s.step(0.3), "before the midpoint")
	assert_true(s.step(0.3), "crossing it")
	assert_false(s.step(0.3), "past it")
	assert_true(s.active())
	s.step(0.5)
	assert_false(s.active())
	assert_eq(s.to, 3)


func test_the_depth_is_smallest_at_the_midpoint() -> void:
	var s := WarSheetSwap.new()
	s.start(1, 1.0)
	s.step(0.5)
	assert_almost_eq(s.z_scale(), 0.02, 0.0001)
	s.step(0.25)
	assert_almost_eq(s.z_scale(), 0.5, 0.0001)


func test_cancel_stops_it() -> void:
	var s := WarSheetSwap.new()
	s.start(1, 1.0)
	s.cancel()
	assert_false(s.active())
