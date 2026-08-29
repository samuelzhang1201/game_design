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

## Guard against the numbers being hidden behind the overlay's full-rect dim
## ColorRect (defeats R9 - they must stay visible while the days pass): the
## TopBar must draw above the overlay, clear of its centered date panel.
func test_top_bar_draws_above_overlay_dim_clear_of_panel() -> void:
	Game.start_campaign(42)
	var d: DayRunScreen = load("res://scenes/day_run.tscn").instantiate()
	add_child_autofree(d)
	await wait_frames(2)
	assert_gt(d.top_bar.get_index(), d.overlay.get_index(),
		"TopBar must draw above the overlay's dim so it stays visible")
	assert_almost_eq(d.overlay.panel_vertical_offset, 0.0, 0.1,
		"the centered date panel needs no offset")
	d.run(Game.next_tick())
	await wait_frames(2)
	assert_false(d.top_bar.get_global_rect().intersects(
		d.overlay.date_panel().get_global_rect()),
		"the TopBar must not overlap the overlay's centered date panel")
