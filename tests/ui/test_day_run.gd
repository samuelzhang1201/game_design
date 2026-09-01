extends GutTest

func test_day_run_plays_and_finishes_with_top_bar_deltas() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var d: DayRunScreen = load("res://scenes/day_run.tscn").instantiate()
	add_child_autofree(d)
	d.run(report)
	await wait_frames(2)
	assert_true(d.overlay.playing())
	assert_ne(d.top_bar.delta_text("treasury"), "",
		"income always moves treasury, so the TopBar shows its delta (R9)")
	# click-skip immediately finishes
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	d.overlay._on_gui_input(click)
	await wait_for_signal(d.finished, 2.0)
	assert_false(d.overlay.playing())

func test_overlay_speed_comes_from_balance() -> void:
	Game.start_campaign(42)
	var d: DayRunScreen = load("res://scenes/day_run.tscn").instantiate()
	add_child_autofree(d)
	await wait_frames(1)
	assert_almost_eq(d.overlay.day_seconds, Game.data.bal("dayrun_day_seconds"), 0.001)

## User request 2026-08-31: the chronicle is a transparent window pinned to
## the BOTTOM of the UI - left-aligned with the map, growing upward, clear
## of the TopBar, and the TopBar draws above the overlay layer so the
## numbers stay visible while the days pass (R9).
func test_chronicle_window_sits_at_the_bottom_clear_of_bar() -> void:
	Game.start_campaign(42)
	var d: DayRunScreen = load("res://scenes/day_run.tscn").instantiate()
	add_child_autofree(d)
	await wait_frames(2)
	assert_gt(d.top_bar.get_index(), d.overlay.get_index(),
		"TopBar must draw above the overlay layer")
	d.run(Game.next_tick())
	await wait_frames(2)
	var panel := d.overlay.date_panel()
	assert_lt(panel.global_position.x, 200.0, "the window sits at the left")
	assert_almost_eq(panel.global_position.y + panel.size.y,
		d.size.y - (NewsTicker.STRIP_HEIGHT + BottomBar.BAR_HEIGHT + 4.0), 2.0,
		"the window's bottom edge rests just above the bottom chrome")
	assert_false(d.top_bar.get_global_rect().intersects(panel.get_global_rect()),
		"the window never overlaps the metrics bar")
