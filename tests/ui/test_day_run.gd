extends GutTest

func test_day_run_plays_and_finishes_with_card_changes() -> void:
	Game.start_campaign(42)
	var report := Game.next_tick()
	var d: DayRunScreen = load("res://scenes/day_run.tscn").instantiate()
	add_child_autofree(d)
	d.run(report)
	await wait_frames(2)
	assert_true(d.overlay.playing())
	var texts := ""
	for l in d.card.find_children("*", "Label", true, false):
		texts += l.text + "\n"
	assert_string_contains(texts, "→")  # at least one change row (income always moves treasury)
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

## Guard against the card being hidden behind the overlay's full-rect dim
## ColorRect (defeats R9 - the numbers must stay visible while the days
## pass): the card must draw above the overlay. User ruling (2026-08-29):
## the card is pinned top-left, clear of the overlay's centered date panel
## (which therefore needs no vertical offset any more).
func test_card_draws_above_overlay_dim_at_top_left() -> void:
	Game.start_campaign(42)
	var d: DayRunScreen = load("res://scenes/day_run.tscn").instantiate()
	add_child_autofree(d)
	await wait_frames(2)
	assert_gt(d.card.get_index(), d.overlay.get_index(),
		"card must draw above the overlay's dim so it stays visible")
	assert_lt(d.card.position.x, 20.0, "card sits at the left edge")
	assert_lt(d.card.position.y, 20.0, "card sits at the top edge")
	assert_almost_eq(d.overlay.panel_vertical_offset, 0.0, 0.1,
		"no offset needed once the card is out of the panel's way")
	d.run(Game.next_tick())
	await wait_frames(2)
	assert_false(d.card.get_global_rect().intersects(
		d.overlay.date_panel().get_global_rect()),
		"the card must not overlap the overlay's centered date panel")
