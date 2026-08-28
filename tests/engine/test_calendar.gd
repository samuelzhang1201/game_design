extends GutTest

func test_first_day_of_campaign() -> void:
	assert_eq(Calendar.absolute_day(1, 1), 1)
	assert_eq(Calendar.date_string(1, 1), "Spring 1, Year 1")

func test_season_blocks_are_six_ticks() -> void:
	assert_eq(Calendar.season_name(6), "Spring")   # days 76..90
	assert_eq(Calendar.season_name(7), "Summer")   # day 91
	assert_eq(Calendar.season_name(13), "Autumn")
	assert_eq(Calendar.season_name(19), "Winter")

func test_year_boundary() -> void:
	assert_eq(Calendar.date_string(24, 15), "Winter 90, Year 1")
	assert_eq(Calendar.date_string(25, 1), "Spring 1, Year 2")

func test_day_within_tick_advances() -> void:
	# tick 2 covers days 16..30 of spring
	assert_eq(Calendar.day_of_season(2, 1), 16)
	assert_eq(Calendar.day_of_season(2, 15), 30)

func test_game_state_agrees_with_calendar() -> void:
	var data := DataRepository.load_all("res://data")
	var s := GameState.new_campaign(data, 42)
	for t in [1, 6, 7, 12, 13, 18, 19, 24, 25]:
		s.tick = t
		assert_eq(s.season(), Calendar.season_name(t).to_lower(), "tick %d" % t)
		assert_eq(s.year(), Calendar.year_of(t), "tick %d" % t)
