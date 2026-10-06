extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Town stores (spec 2026-10-07-army-supply-lines §2, §3.1).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_apportion_is_largest_remainder_with_ties_by_code() -> void:
	assert_eq(TownStores.apportion(10, {"a": 1, "b": 1, "c": 1}), {"a": 4, "b": 3, "c": 3})
	assert_eq(TownStores.apportion(7, {"a": 0, "b": 0}), {"a": 4, "b": 3}, "no weight: shared evenly")
	assert_eq(TownStores.apportion(0, {"a": 5}), {"a": 0})

func test_units_and_gold_convert_at_the_supply_price() -> void:
	# army_supply_gold_permille 100: a gold is 10 units
	assert_eq(TownStores.units_per_gold(repo), 1000 / int(repo.bal("army_supply_gold_permille")))
	assert_eq(TownStores.gold_of_units(repo, 129), 129 * int(repo.bal("army_supply_gold_permille")) / 1000)

func test_every_realm_manor_feeds_the_nearest_town_of_its_province() -> void:
	var c := TownStores.catchment(repo, s)
	assert_false(c.is_empty())
	for cell: int in c:
		var burg := String(c[cell])
		assert_true(TownStores.is_realm_town(repo, s, burg), burg)
		var prov := MapManors.province_of(repo, cell, s)
		var here := MapTerrain.cell_center(repo, repo.cells[cell])
		var best := ""
		var best_d := INF
		for b: String in TownStores.realm_towns(repo, s):
			if String(repo.burgs[b]["province_code"]) != prov:
				continue
			var d := here.distance_squared_to(Vector2(float(repo.burgs[b]["x"]), float(repo.burgs[b]["y"])))
			if d < best_d or (d == best_d and b < best):
				best_d = d
				best = b
		if best != "":
			assert_eq(burg, best, "cell %d" % cell)

func test_take_never_goes_below_empty() -> void:
	var b: String = TownStores.realm_towns(repo, s)[0]
	s.town_stock[b] = {"crown": 5, "lord": 0, "house": 0}
	assert_eq(TownStores.take(s, b, "crown", 8), 5)
	assert_eq(int(TownStores.stock_of(s, b)["crown"]), 0)

func test_reconcile_follows_a_metric_moved_elsewhere() -> void:
	var towns: Array = TownStores.realm_towns(repo, s)
	s.town_stock[towns[0]] = {"crown": 1000, "lord": 0, "house": 0}
	s.town_stock[towns[1]] = {"crown": 1000, "lord": 0, "house": 0}
	TownStores.sync_metrics(repo, s)
	var before := TownStores.total(s, "crown")
	# an order cost takes 20 gold of the crown's strategic goods (LEVY_RAISE)
	s.metrics["strategic"] = float(s.metrics["strategic"]) - 20.0
	TownStores.reconcile(repo, s)
	assert_eq(TownStores.total(s, "crown"), before - 20 * TownStores.units_per_gold(repo))
	assert_eq(int(s.metrics["strategic"]), TownStores.gold_of_units(repo, TownStores.total(s, "crown")))
	for b: String in s.town_stock:
		assert_true(int(s.town_stock[b]["crown"]) >= 0)
	# an event gives 7 gold: it lands in the depot
	var depot := TownStores.depot(repo, s)
	var had := int(TownStores.stock_of(s, depot)["crown"])
	s.metrics["strategic"] = float(s.metrics["strategic"]) + 7.0
	TownStores.reconcile(repo, s)
	assert_eq(int(TownStores.stock_of(s, depot)["crown"]), had + 7 * TownStores.units_per_gold(repo))

func test_the_stores_survive_the_save() -> void:
	var b: String = TownStores.realm_towns(repo, s)[0]
	s.town_stock[b] = {"crown": 11, "lord": 22, "house": 33}
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(TownStores.stock_of(back, b), {"crown": 11, "lord": 22, "house": 33})
