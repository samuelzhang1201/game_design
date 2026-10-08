extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Supply lines: the road, eligibility, interception (spec 2026-10-07-army-supply-lines §3.2, §3.5).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)

func _land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			return String(c)
	return ""

func test_the_road_runs_from_the_town_to_the_column() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var route := SupplyLines.road_px(repo, s, code, town)
	assert_true(route.size() >= 2)
	var b: Dictionary = repo.burgs[town]
	assert_almost_eq(route[0].distance_to(Vector2(float(b["x"]), float(b["y"]))), 0.0, 1.0)
	assert_almost_eq(route[route.size() - 1].distance_to(
		ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))), 0.0, 1.0)

func test_wagon_days_round_up_and_are_at_least_one() -> void:
	var per := int(repo.bal("supply_wagon_km_per_day"))
	assert_eq(SupplyLines.wagon_days(repo, 0), 1)
	assert_eq(SupplyLines.wagon_days(repo, per), 1)
	assert_eq(SupplyLines.wagon_days(repo, per + 1), 2)

func test_a_town_within_reach_is_eligible_and_a_far_one_says_why() -> void:
	var code := _land()
	var e := SupplyLines.eligibility(repo, s, code)
	assert_false(e.is_empty())
	var max_days := int(repo.bal("supply_point_max_days"))
	var some_ok := false
	for town: String in e:
		var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town))
		var ok := SupplyLines.wagon_days(repo, km) <= max_days
		assert_eq(String(e[town]) == "", ok, town)
		some_ok = some_ok or ok
	assert_true(some_ok, "the town it stands in is always within reach")

func test_no_hostile_regiment_no_cut() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	assert_eq(SupplyLines.cut_point(repo, s, SupplyLines.road_px(repo, s, code, town)), {})

func test_a_hostile_regiment_on_the_road_cuts_it() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var route := SupplyLines.road_px(repo, s, code, town)
	# make a foreign kingdom an Enemy and stand one of its regiments on the road's midpoint
	var realm := repo.resolve_realm("player_realm")
	var foe := ""
	var army := ArmySystem.roster(repo, s)
	var codes := army.keys()
	codes.sort()
	for c: String in codes:
		if String(army[c]["kingdom_code"]) != realm and String(army[c].get("is_naval", "0")) != "1":
			foe = c
			break
	var foe_reg: Dictionary = army[foe]
	var mid := route[route.size() / 2]
	foe_reg["x"] = mid.x
	foe_reg["y"] = mid.y
	repo.world_table("political", "diplomacy")["%s>%s" % [realm, String(foe_reg["kingdom_code"])]] = {"stance": "Enemy"}
	var cut := SupplyLines.cut_point(repo, s, route)
	assert_false(cut.is_empty())
	assert_eq(String(cut["by"]), String(foe_reg["kingdom_code"]))

func test_the_lines_survive_the_save() -> void:
	s.supply_lines["x"] = {"town": "t", "rate": 1000, "state": SupplyLines.FLOWING}
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(String(SupplyLines.line(back, "x")["state"]), SupplyLines.FLOWING)

func test_day_fee_milli_is_the_months_draw_over_the_road_a_day() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town))
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), s)
	var milli := int(repo.bal("supply_cart_milligold_per_unit_km"))
	@warning_ignore("integer_division")
	var want := use * 1200 / 1000 * km * milli / Calendar.DAYS_PER_TICK
	assert_eq(SupplyLines.day_fee_milli(repo, s, code, town, 1200), want)
	assert_eq(SupplyLines.day_fee_milli(repo, s, code, town, 1200, km), want, "a given length is the road's")
	assert_eq(SupplyLines.day_fee_milli(repo, s, code, town, 1200, 0), 0, "no road, no fee")

## Final review 4: under a gold a day the three rates still read apart, in
## tenths of a gold, on a road of 100 km or more.
func test_the_three_rates_read_three_fees_on_a_long_road() -> void:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c))
		if String(reg.get("is_naval", "0")) == "1":
			continue
		for town: String in TownStores.realm_towns(repo, s):
			var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, String(c), town))
			if km < 100:
				continue
			var words: Array = []
			for rate: int in SupplyLines.RATES:
				words.append(SupplyLines.gold_words(SupplyLines.day_fee_milli(repo, s, String(c), town, rate, km)))
			assert_ne(words[0], words[1], str(words))
			assert_ne(words[1], words[2], str(words))
			assert_ne(String(words[1]), "0.0", "not nothing")
			return
	fail_test("no road of 100 km from a realm town")

func test_gold_words_read_tenths() -> void:
	assert_eq(SupplyLines.gold_words(0), "0.0")
	assert_eq(SupplyLines.gold_words(361), "0.4")
	assert_eq(SupplyLines.gold_words(12345), "12.3")


# --- the supply town chosen on the march's confirm (spec 2026-10-08-war-room-draw-orders ruling 13)

func test_the_road_between_a_town_and_any_point() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))
	assert_eq(SupplyLines.road_between_px(repo, town, here), SupplyLines.road_px(repo, s, code, town),
		"to where the column stands it is the line's own road")
	var b: Dictionary = repo.burgs[town]
	var far := here + Vector2(30, 10)
	var route := SupplyLines.road_between_px(repo, town, far)
	assert_almost_eq(route[0].distance_to(Vector2(float(b["x"]), float(b["y"]))), 0.0, 1.0)
	assert_almost_eq(route[route.size() - 1].distance_to(far), 0.0, 0.001, "it ends ON the point")


func test_a_march_supply_town_must_reach_the_column_now_and_the_end() -> void:
	var code := _land()
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))
	var now := SupplyLines.eligibility(repo, s, code)
	assert_eq(SupplyLines.march_eligibility(repo, s, code, here), now, "a march that ends where it stands: the same towns")
	repo.balance["supply_point_max_days"] = 1000
	repo.balance["supply_ahead_km"] = 1000000   # the reach alone (no town ahead: ruling 20 is tested below)
	var lax := SupplyLines.march_eligibility(repo, s, code, here + Vector2(400, 0))
	for town: String in lax:
		assert_eq(String(lax[town]), "", "within a thousand wagon days every town reaches")
	repo.balance["supply_point_max_days"] = int(SupplyLines.wagon_days(repo, 0))   # one day: only a very near town
	var end := here + Vector2(5000, 0)
	var strict := SupplyLines.march_eligibility(repo, s, code, end)
	for town: String in strict:
		if String(SupplyLines.eligibility(repo, s, code)[town]) == "":
			assert_string_contains(String(strict[town]), "end", "a town reaching the column now but not the end says so")


# --- never a town ahead of the column (owner 2026-10-08, spec 2026-10-08-war-room-draw-orders ruling 20)

## supply_ahead_km set so the tolerance is exactly 5 pack px.
func _tol5() -> void:
	repo.balance["supply_ahead_km"] = 5.0 * float(ArmySystem.metres_per_pack_px(repo)) / 1000.0


func test_a_town_behind_or_beside_the_column_is_not_ahead() -> void:
	_tol5()
	var at := Vector2(100, 100)
	var dest := Vector2(200, 100)   # due east, 100 px; the first leg toward the end
	assert_false(SupplyLines.is_ahead(repo, at, dest, dest, Vector2(80, 100)), "behind: 120 px from the end, -20 along")
	assert_false(SupplyLines.is_ahead(repo, at, dest, dest, Vector2(100, 130)), "beside: 104.4 px from the end, 0 along")
	assert_false(SupplyLines.is_ahead(repo, at, dest, dest, Vector2(104, 128)),
		"equidistant (100 px from the end) and 4 px along, inside the 5 px tolerance")


func test_a_town_nearer_the_end_or_beyond_the_column_is_ahead() -> void:
	_tol5()
	var at := Vector2(100, 100)
	var dest := Vector2(200, 100)
	assert_true(SupplyLines.is_ahead(repo, at, dest, dest, Vector2(150, 100)), "50 px from the end against 100 - 5")
	assert_true(SupplyLines.is_ahead(repo, at, dest, dest, Vector2(140, 180)),
		"equidistant (60-80-100 from the end) but 40 px along the advance")
	assert_true(SupplyLines.is_ahead(repo, at, dest, dest, Vector2(106, 100)),
		"94 px from the end: nearer by 6, beyond the tolerance")


func test_the_first_leg_is_the_direction_of_advance() -> void:
	_tol5()
	var at := Vector2(100, 100)
	var wp := Vector2(100, 200)    # south first
	var dest := Vector2(200, 200)  # 141.4 px from the column
	var town := Vector2(40, 150)   # 167.6 px from the end (farther than the column) but 50 px down the first leg
	assert_true(SupplyLines.is_ahead(repo, at, wp, dest, town), "the column passes it on its first leg")
	assert_false(SupplyLines.is_ahead(repo, at, dest, dest, town), "marching straight to the end it lies behind")
	assert_false(SupplyLines.is_ahead(repo, at, at, at, Vector2(300, 300)), "a march that stays: nothing is ahead")


func test_the_rear_order_puts_the_nearest_allowed_town_first_ties_toward_the_capital() -> void:
	var why := {"a": "", "b": "", "c": "ahead of the column", "d": "", "e": ""}
	var km := {"a": 30, "b": 12, "c": 2, "d": 12, "e": 40}
	var to_capital := {"a": 5.0, "b": 90.0, "c": 1.0, "d": 20.0, "e": 0.0}
	assert_eq(SupplyLines.rear_sorted(why, km, to_capital), ["d", "b", "a", "e", "c"],
		"12 km twice: d is nearer the capital; the forbidden town last")


func test_a_march_supply_town_ahead_of_the_column_is_greyed_with_why() -> void:
	var code := _land()
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))
	repo.balance["supply_point_max_days"] = 1000
	_tol5()
	var now := SupplyLines.eligibility(repo, s, code)
	var towns: Array = now.keys()
	towns.sort()
	var town := String(towns[0])
	var b: Dictionary = repo.burgs[town]
	var t := Vector2(float(b["x"]), float(b["y"]))
	if t.distance_to(here) < 10.0:
		pending("the first town stands on the column")
		return
	var past := here + (t - here) * 2.0   # the march ends beyond the town: it lies ahead
	var e := SupplyLines.march_eligibility(repo, s, code, past)
	assert_string_contains(String(e[town]), "ahead", "a town the column marches through is forbidden")
	var away := here - (t - here) * 2.0   # marching away from it: it lies behind
	assert_eq(String(SupplyLines.march_eligibility(repo, s, code, away)[town]), "")
	assert_string_contains(String(SupplyLines.march_eligibility(repo, s, code, away, [t])[town]), "ahead",
		"a first waypoint on the town turns the advance toward it")
