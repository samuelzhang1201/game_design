extends GutTest
## The courier core's tables (spec 2026-09-27-courier-core §3).

var repo: DataRepository


func before_all() -> void:
	repo = DataRepository.load_all("res://data")


func test_the_courier_kinds() -> void:
	assert_eq(int(repo.courier_kinds["ordinary"]["speed_permille"]), 1000)
	assert_true(bool(repo.courier_kinds["ordinary"]["offered"]), "A offers the ordinary courier")
	assert_eq(int(repo.courier_kinds["secret"]["speed_permille"]), 750)
	assert_false(bool(repo.courier_kinds["secret"]["offered"]), "the secret one waits for C")
	for kind: String in repo.courier_kinds:
		assert_gt(int(repo.courier_kinds[kind]["fee_gold"]), 0, kind + " has a fee")
		assert_true(repo.courier_art.has(kind), kind + " has an art row")


func test_the_road_speeds() -> void:
	for key in ["road", "trail", "offroad", "sea", "tier_plains", "tier_hills", "tier_mountains", "tier_peak"]:
		assert_gt(int(repo.road_speed.get(key, 0)), 0, key)
	assert_gt(int(repo.road_speed["road"]), int(repo.road_speed["trail"]), "a road beats a trail")
	assert_gt(int(repo.road_speed["trail"]), int(repo.road_speed["offroad"]), "a trail beats open country")


func test_every_season_and_tier_has_odds() -> void:
	for season in ["spring", "summer", "autumn", "winter"]:
		for row: Dictionary in repo.army_height_supply:
			var key := "%s|%s" % [season, String(row["tier"])]
			assert_true(repo.weather_odds.has(key), key)
			var total := 0
			for kind: String in repo.weather_odds[key]:
				assert_true(repo.weather_kinds.has(kind), kind + " is a weather kind")
				total += int(repo.weather_odds[key][kind])
			assert_gt(total, 0, key + " can roll something")


func test_every_weather_kind_has_a_speed() -> void:
	assert_eq(repo.weather_kinds.keys(), ["clear", "rain", "mud", "snow", "blizzard"])
	assert_eq(int(repo.weather_kinds["clear"]["speed_permille"]), 1000)
	for kind: String in repo.weather_kinds:
		assert_gt(int(repo.weather_kinds[kind]["speed_permille"]), 0, kind)


func test_the_balance_keys() -> void:
	for key in ["courier_base_km_per_day", "courier_graph_snap_px", "courier_offroad_max_km",
			"courier_reaim_m", "courier_max_days", "courier_slow_news_permille",
			"courier_sea_sample_km", "weather_spell_days"]:
		assert_true(repo.balance.has(key), key)
	assert_eq(int(repo.bal("courier_base_km_per_day")), 160, "owner 2026-09-27: four times the cavalry")


func test_the_seed_is_readable_and_survives_a_save() -> void:
	var r := Rng.new(1234)
	assert_eq(r.seed_value(), 1234)
	r.randi_range(0, 10)
	assert_eq(Rng.from_dict(r.to_dict()).seed_value(), 1234)


func test_the_season_of_an_absolute_day() -> void:
	assert_eq(Calendar.season_of_day(1), "spring")
	assert_eq(Calendar.season_of_day(90), "spring")
	assert_eq(Calendar.season_of_day(91), "summer")
	assert_eq(Calendar.season_of_day(360), "winter")
	assert_eq(Calendar.season_of_day(361), "spring")
