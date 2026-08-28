extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_new_campaign_reads_balance() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_eq(s.tick, 0)
	assert_eq(s.metrics["treasury"], 500.0)
	assert_eq(s.metrics["grain"], 120.0)
	assert_eq(s.metrics["tax_rate"], 5.0)
	assert_eq(s.metrics["legitimacy"], 50.0)

func test_seasons_and_years() -> void:
	var s := GameState.new_campaign(data, 1)
	assert_eq(s.season(), "spring")
	s.tick = 13
	assert_eq(s.season(), "autumn")
	s.tick = 23
	assert_eq(s.season(), "winter")
	s.tick = 24
	assert_eq(s.season(), "winter")
	assert_eq(s.year(), 1)
	s.tick = 25
	assert_eq(s.season(), "spring")
	assert_eq(s.year(), 2)

func test_round_trip() -> void:
	var s := GameState.new_campaign(data, 42)
	s.tick = 9
	s.metrics["treasury"] = 123.5
	s.cooldowns["LEVY_RAISE"] = 12
	var s2 := GameState.from_dict(s.to_dict())
	assert_eq(s2.tick, 9)
	assert_eq(s2.metrics["treasury"], 123.5)
	assert_eq(s2.cooldowns["LEVY_RAISE"], 12)
	assert_eq(s2.rng.randi_range(0, 9999), s.rng.randi_range(0, 9999))
