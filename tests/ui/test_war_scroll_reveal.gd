extends GutTest
## The WAR ROOM comes down like a hanging scroll and rolls back up on close
## (owner 2026-10-02): an overlay that draws the share hung and frees itself.

func test_coming_down_goes_from_rolled_to_hanging_and_frees_itself() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var s := WarScrollReveal.play(host, Rect2(0, 0, 900, 600), null, true, 0.2, 16.0)
	assert_almost_eq(s.share(), 0.0, 0.0001, "starts rolled at the rod")
	assert_eq(s.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	await wait_process_frames(2)
	assert_gt(s.share(), 0.0, "coming down")
	assert_lt(s.share(), 1.0, "not yet down")
	await wait_seconds(0.4)
	assert_false(is_instance_valid(s), "freed when done")


func test_rolling_up_starts_hanging() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var s := WarScrollReveal.play(host, Rect2(0, 0, 900, 600), null, false, 0.2, 16.0)
	assert_almost_eq(s.share(), 1.0, 0.0001)


func test_no_capture_headless() -> void:
	assert_null(WarScrollReveal.capture(get_viewport(), Rect2(0, 0, 100, 100)))
