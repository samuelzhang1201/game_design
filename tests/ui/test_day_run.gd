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
