extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

## One truth (owner ruling 2026-09-09): the player's rates are seeded from
## the pack's economy row through balance factors, and the treasury (owner
## 2026-09-13) from the towns of the provinces the crown controls; grain and
## the drift baselines still come from balance.csv.
func test_new_campaign_seeds_from_the_pack_and_balance() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_eq(s.tick, 0)
	var row: Dictionary = data.world_row("economy", "kingdoms", data.resolve_realm("player_realm"))
	assert_false(row.is_empty(), "the pack has the player's economy row")
	assert_gt(WorldLedger.crown_town_treasury(data, s), 0.0, "the crown's towns hold something")
	assert_eq(s.metrics["treasury"],
		roundf(WorldLedger.crown_town_treasury(data, s) * data.bal("pack_treasury_scale")))
	assert_eq(s.metrics["tax_rate"],
		clampf(roundf(float(row["poll_tax"]) * data.bal("tax_rate_per_poll_tax")), 1.0, 10.0))
	assert_eq(s.metrics["tariff_rate"],
		clampf(roundf(float(row["sales_tax"]) * data.bal("tariff_rate_per_sales_tax")), 0.0, 10.0))
	assert_eq(s.metrics["grain"], data.bal("start_grain"))
	assert_eq(s.metrics["legitimacy"], data.bal("start_metric_default"))
	assert_true(s.world.is_empty(), "seeding writes the metric, not an override")

func test_a_pack_without_an_economy_row_falls_back_to_balance() -> void:
	var stripped := DataRepository.load_all("res://data")
	stripped.world_tables["economy"]["kingdoms"].clear()
	var s := GameState.new_campaign(stripped, 42)
	assert_eq(s.metrics["treasury"], stripped.bal("start_treasury"))
	assert_eq(s.metrics["tax_rate"], stripped.bal("start_tax_rate"))

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
