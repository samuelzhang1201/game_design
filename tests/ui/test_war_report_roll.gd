extends GutTest
## The steward's report rolls up when the WAR ROOM opens and down when it
## closes (spec 2026-10-02-war-room-v2 §1.2): an overlay that draws the share
## of the paper left and frees itself.

func test_rolling_up_goes_from_open_to_rolled_and_frees_itself() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var roll := WarReportRoll.play(host, Rect2(0, 0, 240, 600), null, true, 0.2, 12.0, true)
	assert_almost_eq(roll.share(), 1.0, 0.0001)
	await wait_process_frames(2)
	assert_lt(roll.share(), 1.0, "rolling")
	assert_gt(roll.share(), 0.0, "not yet rolled")
	await wait_seconds(0.4)
	assert_false(is_instance_valid(roll), "freed when done")


func test_rolling_down_starts_rolled_and_takes_no_clicks() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var roll := WarReportRoll.play(host, Rect2(0, 0, 240, 600), null, false, 0.2, 12.0, true)
	assert_almost_eq(roll.share(), 0.0, 0.0001)
	assert_eq(roll.mouse_filter, Control.MOUSE_FILTER_IGNORE)
