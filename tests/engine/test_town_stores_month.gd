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

func test_a_months_deposit_lands_in_the_towns_that_earned_it() -> void:
	var inflow := TownStores.month_inflow(repo, s)
	var upg := TownStores.units_per_gold(repo)
	var towns: Array = inflow.keys()
	towns.sort()
	var pick := ""
	for t: String in towns:
		if t != TownStores.depot(repo, s) and int(inflow[t]["lord"]) > 0:
			pick = t
			break
	assert_ne(pick, "", "a non-depot town earns lord goods")
	var before: Dictionary = {}
	for t: String in towns:
		before[t] = TownStores.stock_of(s, t)
	TownStores.deposit_month(repo, s)
	for t: String in towns:
		var now := TownStores.stock_of(s, t)
		assert_eq(int(now["lord"]) - int(before[t]["lord"]), int(inflow[t]["lord"]) * upg, "lord " + t)
		assert_eq(int(now["crown"]) - int(before[t]["crown"]), int(inflow[t]["crown"]) * upg, "crown " + t)
	var got := TownStores.stock_of(s, pick)
	assert_eq(int(got["lord"]) - int(before[pick]["lord"]), int(inflow[pick]["lord"]) * upg)

func test_a_workshops_make_is_stored_in_its_own_town() -> void:
	var cells: Array = MapManors.manors_of_province(repo, MapManors.home_province(repo, s), s)
	var cell: int = cells[0]
	for c: int in cells:
		if TownStores.town_of_cell(repo, s, c) != TownStores.depot(repo, s):
			cell = c
			break
	assert_true(MapManors.build(repo, s, cell, WorkshopSystem.BUILDING, "a test workshop"))
	s.metrics["lord_civil"] = float(int(repo.bal("workshop_capacity_gold")) * 3)
	var town := TownStores.town_of_cell(repo, s, cell)
	var made := 0
	for row: Dictionary in WorkshopSystem.plan(repo, s):
		if int(row["cell"]) == cell:
			made = int(row["make"])
	assert_gt(made, 0, "the workshop makes something")
	var before := int(TownStores.stock_of(s, town)["lord"])
	var depot_before := int(TownStores.stock_of(s, TownStores.depot(repo, s))["lord"])
	WorkshopSystem.settle_month(repo, s)
	var upg := TownStores.units_per_gold(repo)
	assert_eq(int(TownStores.stock_of(s, town)["lord"]) - before, made * upg)
	if town != TownStores.depot(repo, s):
		assert_eq(int(TownStores.stock_of(s, TownStores.depot(repo, s))["lord"]), depot_before, "not in the depot")

func test_ensure_leaves_existing_stores_alone() -> void:
	var towns: Array = TownStores.realm_towns(repo, s)
	s.town_stock[towns[0]] = {"crown": 7, "lord": 8, "house": 9}
	var snap: Dictionary = s.town_stock.duplicate(true)
	TownStores.ensure(repo, s)
	assert_eq(s.town_stock, snap)
