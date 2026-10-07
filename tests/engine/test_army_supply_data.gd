extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Army supply data (spec 2026-10-07-army-supply-lines §6).

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()

func test_the_new_balance_keys_exist() -> void:
	for key in ["army_start_supply_days", "army_supply_low_days", "army_supply_max_days",
			"army_carry_default_days", "army_morale_hungry_day", "army_morale_starving_day",
			"supply_wagon_km_per_day", "supply_point_max_days", "supply_cut_reach_m",
			"supply_cart_milligold_per_unit_km", "supply_buy_markup_permille",
			"supply_warn_town_days", "town_house_stock_months"]:
		assert_true(data.balance.has(key), key)
	assert_eq(int(data.bal("army_supply_max_days")), 30)
	assert_eq(int(data.bal("army_supply_low_days")), 5)

func test_a_gold_of_goods_is_a_whole_number_of_units() -> void:
	var permille := int(data.bal("army_supply_gold_permille"))
	assert_gt(permille, 0)
	assert_eq(1000 % permille, 0, "army_supply_gold_permille must divide 1000")

func test_the_carry_loads_run_10_to_30_and_slow_as_they_grow() -> void:
	var days: Array = data.army_carry_loads.map(func(r: Dictionary) -> int: return int(r["days"]))
	assert_eq(days, [10, 15, 20, 25, 30])
	for i in range(1, data.army_carry_loads.size()):
		assert_true(int(data.army_carry_loads[i]["pace_permille"]) <= int(data.army_carry_loads[i - 1]["pace_permille"]))
	assert_true(days.has(int(data.bal("army_carry_default_days"))))

func test_the_supply_menu_rows_and_the_hostile_stances_load() -> void:
	for key in ["add", "change", "withdraw", "carry", "pick_far", "confirm", "cancel"]:
		assert_true(data.army_supply_orders.has(key), key)
	assert_true(data.army_hostile_stances.has("Enemy"))
