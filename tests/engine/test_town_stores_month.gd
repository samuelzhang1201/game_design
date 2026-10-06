extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The month's goods into the towns (spec 2026-10-07-army-supply-lines §3.1).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_the_inflow_sums_to_the_purses() -> void:
	var p := RealmEconomy.purses(repo, s)
	var lord := 0
	var crown := 0
	var inflow := TownStores.month_inflow(repo, s)
	for b: String in inflow:
		var row: Dictionary = inflow[b]
		lord += int(row["lord"])
		crown += int(row["crown"])
	assert_eq(lord, int(p["lord"]["strategic"]))
	assert_eq(crown, int(p["realm_share"]["strategic"]))

func test_a_new_campaign_seeds_the_towns_from_the_pools() -> void:
	assert_false(s.town_stock.is_empty())
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "crown")), int(s.metrics["strategic"]))
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "lord")), int(s.metrics["lord_strategic"]))

func test_the_months_settlement_keeps_the_pools_equal_to_the_towns() -> void:
	var engine := TickEngine.new(repo)
	for i in Calendar.DAYS_PER_TICK - 1:
		engine.advance_day(s)
	engine.advance(s)
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "crown")), int(s.metrics["strategic"]))
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "lord")), int(s.metrics["lord_strategic"]))

func test_the_house_stock_is_capped_at_its_months() -> void:
	var inflow := TownStores.month_inflow(repo, s)
	var months := int(repo.bal("town_house_stock_months"))
	for i in months + 3:
		TownStores.deposit_month(repo, s)
	for b: String in inflow:
		var cap := int(inflow[b]["house"]) * months * TownStores.units_per_gold(repo)
		assert_true(int(TownStores.stock_of(s, b)["house"]) <= cap, b)

func test_an_old_save_seeds_on_ensure() -> void:
	var lord := int(s.metrics["lord_strategic"])
	s.town_stock = {}
	TownStores.ensure(repo, s)
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "lord")), lord)
