extends GutTest

var _finished_count := 0

func before_each() -> void:
	_finished_count = 0

func test_news_line_deterministic_and_nonempty() -> void:
	var data := DataRepository.load_all("res://data")
	var a := CalendarOverlay.news_line(data, 3, 4)
	var b := CalendarOverlay.news_line(data, 3, 4)
	assert_ne(a, "")
	assert_eq(a, b)
	# different days generally rotate the pool
	assert_ne(CalendarOverlay.news_line(data, 3, 4), CalendarOverlay.news_line(data, 3, 9))

func test_interlude_runs_days_and_finishes() -> void:
	Game.start_campaign(42)
	var overlay := CalendarOverlay.new()
	add_child_autofree(overlay)
	overlay.finished.connect(func(): _finished_count += 1)
	overlay.play(2)
	assert_true(overlay.playing())
	assert_string_contains(overlay.date_label.text, "Spring")
	await wait_for_signal(overlay.finished, 6.0)
	assert_false(overlay.playing())
	assert_eq(_finished_count, 1)
	assert_gt(overlay.news_box.get_child_count(), 0)

func test_click_skips_immediately() -> void:
	Game.start_campaign(42)
	var overlay := CalendarOverlay.new()
	add_child_autofree(overlay)
	overlay.finished.connect(func(): _finished_count += 1)
	overlay.play(2)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	overlay._on_gui_input(click)
	assert_false(overlay.playing())
	assert_eq(_finished_count, 1)
	assert_string_contains(overlay.date_label.text, "Spring 30, Year 1")
