extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A march through waypoints (spec 2026-10-07-march-waypoints §1): the column
## walks the sampled curve (MarchRoute) leg by leg, its days measured along it;
## a march without waypoints walks the straight line exactly as before.

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()


func _marcher() -> Dictionary:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return r
	return {}


func _px(m: Vector2i) -> Vector2:
	return ArmySystem.metres_to_pack(repo, m)


func _here_m(s: GameState, code: String) -> Vector2i:
	return Vector2i(int(s.regiments[code]["x_m"]), int(s.regiments[code]["y_m"]))


func test_a_march_without_waypoints_keeps_no_route() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	ArmySystem.set_march(repo, s, code, _px(_here_m(s, code) + Vector2i(50_000, 0)))
	assert_false(s.regiments[code].has("route_m"), "a straight march is the old march")
	assert_false(s.regiments[code].has("waypoints_m"))
	assert_eq(ArmySystem.route_px(repo, s, code), PackedVector2Array([_px(_here_m(s, code) + Vector2i(50_000, 0))]))


func test_a_march_through_waypoints_keeps_the_sampled_curve_ahead() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var h := _here_m(s, code)
	var wp := h + Vector2i(30_000, 30_000)
	var dest := h + Vector2i(60_000, 0)
	ArmySystem.set_march(repo, s, code, _px(dest), [_px(wp)])
	var curve := MarchRoute.curve([h, wp, dest], int(repo.bal("army_route_sample_m")))
	assert_eq(MarchRoute.from_pairs(s.regiments[code]["route_m"]), curve.slice(1),
		"the curve from where it stands, the start left off")
	assert_eq(s.regiments[code]["waypoints_m"], [[wp.x, wp.y]])
	assert_eq(Vector2i(int(s.regiments[code]["dest_x_m"]), int(s.regiments[code]["dest_y_m"])), dest)
	assert_eq(ArmySystem.waypoints_of(repo, s, code), PackedVector2Array([_px(wp)]))
	assert_eq(ArmySystem.curve_px(repo, _px(h), [_px(wp)], _px(dest)).size(), curve.size(),
		"the maps draw the very points it walks")


## A hand-laid route: S a day east to... a corner a = 1.5 S east, then a south.
## Day 1: S east. Day 2: (a - S) to the corner, the rest S - (a - S) south;
## the corner (a waypoint) is dropped. Day 3: the rest, and it garrisons.
func test_the_column_walks_its_route_leg_by_leg() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var h := _here_m(s, code)
	var big := ArmySystem.day_march_m(repo, s, code)
	@warning_ignore("integer_division")
	var a := big + big / 2
	var corner := h + Vector2i(a, 0)
	var dest := corner + Vector2i(0, a)
	var entry: Dictionary = s.regiments[code]
	entry["order"] = ArmySystem.ORDER_MARCH
	entry["dest_x_m"] = dest.x
	entry["dest_y_m"] = dest.y
	entry["route_m"] = [[corner.x, corner.y], [dest.x, dest.y]]
	entry["waypoints_m"] = [[corner.x, corner.y]]
	assert_eq(ArmySystem.days_out(repo, s, code), 3, "2a = about 3 S: three days")
	assert_eq(ArmySystem.heading_of(repo, s, code), Vector2.RIGHT, "it faces its first leg")
	assert_eq(ArmySystem.march_day(repo, s), [])
	assert_eq(_here_m(s, code), h + Vector2i(big, 0), "day 1: S along the first leg")
	assert_eq(ArmySystem.march_day(repo, s), [])
	assert_eq(_here_m(s, code), corner + Vector2i(0, big - (a - big)), "day 2: round the corner")
	assert_eq(MarchRoute.from_pairs(entry["route_m"]), [dest], "the corner is behind it")
	assert_eq(entry["waypoints_m"], [], "and so is the waypoint")
	assert_eq(ArmySystem.heading_of(repo, s, code), Vector2.DOWN, "it faces the second leg")
	assert_eq(ArmySystem.march_day(repo, s), [code], "day 3: it arrives")
	assert_eq(_here_m(s, code), dest)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON)
	assert_false(entry.has("route_m"), "an arrival keeps no route")
	assert_false(entry.has("waypoints_m"))


func test_march_days_along_a_route_are_the_days_it_walks() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var h := _here_m(s, code)
	var wp := h + Vector2i(40_000, 60_000)
	var dest := h + Vector2i(90_000, 0)
	var promised := ArmySystem.march_days_between(repo, s, code, _px(h), _px(dest), -1, [_px(wp)])
	var straight := ArmySystem.march_days_between(repo, s, code, _px(h), _px(dest))
	assert_gt(promised, straight, "the bent road is the longer")
	ArmySystem.set_march(repo, s, code, _px(dest), [_px(wp)])
	assert_eq(ArmySystem.days_out(repo, s, code), promised, "days out reads the stored route")
	var walked := 0
	while ArmySystem.order_of(repo, s, code) == ArmySystem.ORDER_MARCH and walked < 400:
		walked += 1
		ArmySystem.march_day(repo, s)
	assert_eq(walked, promised, "it takes exactly the days it was promised")


func test_the_day_ahead_preview_never_touches_the_live_route() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var h := _here_m(s, code)
	ArmySystem.set_march(repo, s, code, _px(h + Vector2i(60_000, 0)), [_px(h + Vector2i(5_000, 20_000))])
	var before: Array = (s.regiments[code]["route_m"] as Array).duplicate(true)
	var entry: Dictionary = (s.regiments[code] as Dictionary).duplicate()   # a SHALLOW copy
	ArmySystem.march_ahead(repo, s, code, entry)
	assert_eq(s.regiments[code]["route_m"], before, "the live route is never walked by a preview")


func test_a_load_marches_at_its_own_pace() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var st: Dictionary = s.regiments[code]
	var bare := ArmySystem.pace_tenths(repo, ArmySystem.base_pace_km(repo, r),
		ArmySystem.supply_score(repo, int(st["supplies"]), ArmySystem.supply_use(repo, r)),
		int(st["morale"]), int(st["training"])) * 100
	@warning_ignore("integer_division")
	var heavy := bare * ArmySystem.load_permille(repo, 30) / 1000
	assert_eq(ArmySystem.day_step_m(repo, s, code, 30), heavy, "a thirty-day train at its own pace")
	assert_eq(ArmySystem.day_step_m(repo, s, code), ArmySystem.day_step_m(repo, s, code, ArmySystem.carry_of(repo, st)),
		"no load given is the standing order's")
	var h := _here_m(s, code)
	var far := _px(h + Vector2i(200_000, 0))
	assert_gt(ArmySystem.march_days_between(repo, s, code, _px(h), far, -1, [], 30),
		ArmySystem.march_days_between(repo, s, code, _px(h), far, -1, [], 10), "the heavy train is the slower")


func test_a_halt_drops_the_route() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var h := _here_m(s, code)
	ArmySystem.set_march(repo, s, code, _px(h + Vector2i(60_000, 0)), [_px(h + Vector2i(5_000, 20_000))])
	ArmySystem.set_garrison(repo, s, code)
	assert_false(s.regiments[code].has("route_m"))
	assert_false(s.regiments[code].has("waypoints_m"))
	ArmySystem.set_march(repo, s, code, _px(h + Vector2i(60_000, 0)), [_px(h + Vector2i(5_000, 20_000))])
	ArmySystem.set_march(repo, s, code, _px(h + Vector2i(60_000, 0)))
	assert_false(s.regiments[code].has("route_m"), "a straight march replaces a bent one whole")


func test_a_route_survives_a_save_and_walks_on_the_same() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var h := _here_m(s, code)
	ArmySystem.set_march(repo, s, code, _px(h + Vector2i(70_000, 10_000)), [_px(h + Vector2i(20_000, 30_000))])
	ArmySystem.march_day(repo, s)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.regiments[code]["route_m"], s.regiments[code]["route_m"])
	assert_true(back.regiments[code]["route_m"][0][0] is int, "whole metres, no floats")
	assert_eq(back.regiments[code]["waypoints_m"], s.regiments[code]["waypoints_m"])
	ArmySystem.march_day(repo, s)
	ArmySystem.march_day(repo, back)
	assert_eq(_here_m(back, code), _here_m(s, code), "the loaded march walks on exactly as the live one")
