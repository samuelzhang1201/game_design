extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()

## One truth (owner ruling 2026-09-09): the player's rates are seeded from
## the pack's economy row through balance factors, and the treasury (owner
## 2026-09-13) from the towns of the provinces the crown controls; the two
## goods pools from months of the crown's own production (spec 2026-09-14
## §5), and the drift baselines still from balance.csv.
func test_new_campaign_seeds_from_the_pack_and_balance() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_eq(s.tick, 0)
	var row: Dictionary = data.world_row("economy", "kingdoms", data.resolve_realm("player_realm"))
	assert_false(row.is_empty(), "the pack has the player's economy row")
	assert_gt(WorldLedger.crown_town_treasury(data, s), 0.0, "the crown's towns hold something")
	# Two purses (owner 2026-09-14): the lord's gold is what the towns of the
	# crown's own provinces hold; the crown's treasury its share of the rest.
	assert_eq(s.metrics["lord_gold"],
		roundf(WorldLedger.crown_town_treasury(data, s) * data.bal("pack_treasury_scale")
			* data.bal("start_lord_gold_scale")))
	assert_eq(s.metrics["treasury"],
		roundf(WorldLedger.realm_share_town_treasury(data, s) * data.bal("pack_treasury_scale")))
	assert_eq(s.metrics["tax_rate"],
		clampf(roundf(float(row["poll_tax"]) * data.bal("tax_rate_per_poll_tax")), 1.0, 10.0))
	assert_eq(s.metrics["tariff_rate"],
		clampf(roundf(float(row["sales_tax"]) * data.bal("tariff_rate_per_sales_tax")), 0.0, 10.0))
	var p := RealmEconomy.purses(data, s)
	var cv := int(data.bal("start_civil_months"))
	var st := int(data.bal("start_strategic_months"))
	assert_eq(s.metrics["lord_civil"], float(int(p["lord"]["civil"]) * cv))
	assert_eq(s.metrics["lord_strategic"], float(int(p["lord"]["strategic"]) * st))
	assert_eq(s.metrics["grain"], float(int(p["realm_share"]["civil"]) * cv))
	assert_eq(s.metrics["strategic"], float(int(p["realm_share"]["strategic"]) * st))
	assert_eq(s.metrics["legitimacy"], data.bal("start_metric_default"))
	assert_true(s.world.is_empty(), "seeding writes the metric, not an override")

func test_a_pack_without_an_economy_row_falls_back_to_balance() -> void:
	var stripped := SuiteData.repo()
	stripped.world_tables["economy"]["kingdoms"].clear()
	var s := GameState.new_campaign(stripped, 42)
	assert_eq(s.metrics["treasury"], stripped.bal("start_treasury"))
	assert_eq(s.metrics["tax_rate"], stripped.bal("start_tax_rate"))

func test_seasons_and_years() -> void:
	var s := GameState.new_campaign(data, 1)
	assert_eq(s.season(), "spring")
	s.tick = 7
	assert_eq(s.season(), "autumn")
	s.tick = 11
	assert_eq(s.season(), "winter")
	s.tick = 12
	assert_eq(s.season(), "winter")
	assert_eq(s.year(), 1)
	s.tick = 13
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

## A save written before the pools existed carries neither key. Loading one
## must not leave the top bar indexing a metric that is not there: from_dict
## fills every key of the campaign's template it is missing.
func test_a_save_from_before_the_pools_loads_with_them_empty() -> void:
	var s := GameState.new_campaign(data, 42)
	var d := s.to_dict()
	d["metrics"].erase("strategic")
	d["metrics"].erase("grain")
	var s2 := GameState.from_dict(d)
	assert_eq(s2.metrics["strategic"], 0.0)
	assert_eq(s2.metrics["grain"], 0.0)
	for key: String in GameState.default_metrics().keys():
		assert_true(s2.metrics.has(key), "the loaded metrics hold %s" % key)
