extends GutTest
## A tick is a month of 30 days (owner 2026-09-14), twelve a year, three a season.

func test_first_day_of_campaign() -> void:
	assert_eq(Calendar.DAYS_PER_TICK, 30)
	assert_eq(Calendar.TICKS_PER_YEAR, 12)
	assert_eq(Calendar.absolute_day(1, 1), 1)
	assert_eq(Calendar.date_string(1, 1), "Spring 1, Year 1")

func test_season_blocks_are_three_ticks() -> void:
	assert_eq(Calendar.season_name(3), "Spring")   # days 61..90
	assert_eq(Calendar.season_name(4), "Summer")   # day 91
	assert_eq(Calendar.season_name(7), "Autumn")
	assert_eq(Calendar.season_name(10), "Winter")

func test_year_boundary() -> void:
	assert_eq(Calendar.date_string(12, 30), "Winter 90, Year 1")
	assert_eq(Calendar.date_string(13, 1), "Spring 1, Year 2")

func test_day_within_tick_advances() -> void:
	# tick 2 covers days 31..60 of spring
	assert_eq(Calendar.day_of_season(2, 1), 31)
	assert_eq(Calendar.day_of_season(2, 30), 60)

## Fix round 1 finding 3: the steward's report titles must be unique per
## month, not per season (three months a season shared one title). Calendar
## has no named month, so the title is the season plus the month's ordinal
## within it in Roman numerals.
func test_month_label_is_unique_within_a_season() -> void:
	assert_eq(Calendar.month_label(1), "Spring I")
	assert_eq(Calendar.month_label(2), "Spring II")
	assert_eq(Calendar.month_label(3), "Spring III")
	assert_eq(Calendar.month_label(4), "Summer I")
	assert_eq(Calendar.month_label(13), "Spring I")   # year 2, same month as tick 1


func test_game_state_agrees_with_calendar() -> void:
	var data := DataRepository.load_all("res://data")
	var s := GameState.new_campaign(data, 42)
	for t in [1, 3, 4, 6, 7, 9, 10, 12, 13]:
		s.tick = t
		assert_eq(s.season(), Calendar.season_name(t).to_lower(), "tick %d" % t)
		assert_eq(s.year(), Calendar.year_of(t), "tick %d" % t)
