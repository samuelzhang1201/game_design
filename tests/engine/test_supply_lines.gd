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
	for r: Dictionary in repo.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) != realm and String(r.get("is_naval", "0")) != "1":
			foe = String(r["regiment_code"])
			break
	var foe_reg: Dictionary = repo.world_table("military", "regiments")[foe]
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
