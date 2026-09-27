extends GutTest
## Dispatch (spec 2026-09-27-courier-core §1): from the capital, along the
## road network, to the regiment where it stands.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _skies(kind: String) -> void:
	for key in repo.weather_odds:
		var w: Dictionary = {}
		for k: String in repo.weather_kinds:
			w[k] = 1 if k == kind else 0
		repo.weather_odds[key] = w


func _marcher() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _capital_px() -> Vector2:
	var b: Dictionary = repo.burgs[String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])]
	return Vector2(float(b["x"]), float(b["y"]))


func test_a_courier_rides_from_the_capital_to_the_regiment() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	var home := ArmySystem.pack_to_metres(repo, _capital_px())
	assert_eq(Vector2i(int(c["x_m"]), int(c["y_m"])), home, "he sets out from the capital")
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	var last: Array = (c["path"] as Array).back()
	assert_eq(Vector2i(int(last[0]), int(last[1])), at, "his road ends at the column")
	assert_eq(int(c["id"]), 1)
	assert_eq(s.next_courier_id, 1)
	assert_eq(s.couriers.size(), 1)
	assert_eq(int(c["days"]), 0)
	assert_eq(String(c["target"]), code)


func test_most_of_the_way_is_on_the_roads() -> void:
	var s := GameState.new_campaign(repo, 7)
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, _marcher(), {"action_code": "ARMY_GARRISON"})
	var kinds: Dictionary = {}
	for p: Array in c["path"]:
		kinds[String(p[2])] = true
	for k: String in kinds:
		assert_true(k in ["road", "trail", "offroad", "sea"], k)


func test_the_capital_lost_he_rides_from_the_realms_largest_town() -> void:
	var s := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	var cap_code := String(repo.kingdoms[realm]["capital_burg"])
	var prov := String(repo.burgs[cap_code]["province_code"])
	var other := ""
	var ks := repo.kingdoms.keys()
	ks.sort()
	for k: String in ks:
		if k != realm:
			other = k
			break
	MapOwnership.set_owner(repo, s, prov, other, "test: the capital falls")
	var from := CourierSystem.origin(repo, s)
	assert_ne(from, _capital_px(), "not from a capital the realm no longer holds")
	var held := false
	for b: Dictionary in repo.burgs.values():
		if Vector2(float(b["x"]), float(b["y"])) == from:
			held = MapOwnership.owner_of(repo, s, String(b["province_code"])) == realm
	assert_true(held, "from a town of the realm")


func test_need_along_a_path_by_hand() -> void:
	var s := GameState.new_campaign(repo, 7)
	_skies("clear")
	repo.road_speed = {"road": 1000, "trail": 800, "offroad": 500, "sea": 625,
		"tier_plains": 1000, "tier_hills": 1000, "tier_mountains": 1000, "tier_peak": 1000}
	# 100 km of road + 100 km across country at 500‰ = 100,000 + 200,000.
	var path := [[100000, 0, "road"], [200000, 0, "offroad"]]
	assert_eq(CourierSystem.need_along(repo, s, Vector2i(0, 0), path, 10), 300000)
	# 160 km a day at 1000‰: 300,000 / 160,000 -> 2 days, rounded up.
	assert_eq(CourierSystem.days_for(repo, CourierSystem.ORDINARY, 300000), 2)
	assert_eq(CourierSystem.days_for(repo, CourierSystem.ORDINARY, 0), 1, "never less than a day")
	assert_eq(CourierSystem.days_for(repo, CourierSystem.SECRET, 300000), 3, "750‰: 120 km a day")


func test_the_estimate_is_the_dispatched_couriers() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var eta := CourierSystem.eta_days(repo, s, CourierSystem.ORDINARY, code)
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	assert_eq(CourierSystem.days_left(repo, s, c), eta)
	assert_gt(eta, 0)


func test_a_fleet_takes_no_courier() -> void:
	assert_false(CourierSystem.carries_orders({"is_naval": "1"}))
	assert_true(CourierSystem.carries_orders({"is_naval": "0"}))


## Found through the real game (2026-09-28): the capital is itself a road
## node, so the road began with a zero-length leg back to where he stood,
## "offroad" — and his card read "Across country" while he sat in the capital.
func test_his_road_does_not_begin_where_he_stands() -> void:
	var s := GameState.new_campaign(repo, 7)
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, _marcher(), {"action_code": "ARMY_GARRISON"})
	var first: Array = (c["path"] as Array)[0]
	assert_ne(Vector2i(int(first[0]), int(first[1])), Vector2i(int(c["x_m"]), int(c["y_m"])),
		"no zero-length first leg")
	var card := CourierCard.card(repo, s, int(c["id"]))
	for f: Array in card["fields"]:
		if String(f[0]) == "Ground":
			assert_ne(String(f[1]), "Across country", "a courier in the capital is on the road")
