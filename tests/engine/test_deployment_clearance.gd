extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## P4.4d3: a battle unit's deployed groups are the ground it holds. Its blocker
## radius is the larger of its arm radius and the farthest group's distance from
## the anchor (rounded up) + battle_group_spacing_m / 2 (25 m), so a column
## outside the battle keeps clear of the deployment. Hand-computed.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	for g in repo.army_town_reach:
		repo.army_town_reach[g] = 0.0
	Weather.forget()


func _mine() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and MapObjects.regiment_arm(repo, r) == "infantry" \
				and ArmySystem.headcount(repo, r) >= 400:
			out.append(String(r["regiment_code"]))
	out.sort()
	return out


func _alone(keep: Array) -> GameState:
	var s := SuiteData.campaign(repo, 7)
	for c: String in s.army_roster.keys():
		if not c in keep:
			s.army_roster.erase(c)
			s.regiments.erase(c)
			s.foes.erase(c)
	for t: String in s.town_seat.keys():
		if not String(s.town_seat[t]) in keep:
			s.town_seat.erase(t)
	return s


func _stand(s: GameState, code: String, at: Vector2i) -> void:
	var e: Dictionary = s.regiments[code]
	e["x_m"] = at.x
	e["y_m"] = at.y
	e["dest_x_m"] = at.x
	e["dest_y_m"] = at.y
	e["order"] = ArmySystem.ORDER_STANDBY
	e["camp_town"] = ""
	e.erase("route_m")


func _deploy(s: GameState, code: String, at: Array) -> void:
	var rows: Array = []
	for p: Vector2i in at:
		rows.append({"count": 50, "role": "front", "x_m": p.x, "y_m": p.y})
	s.battles = [{"id": 1, "att": [code], "def": [], "rounds": 0, "town": "", "actions": {},
		"groups": {code: rows}}]


func _radius(s: GameState, code: String) -> int:
	return int(ArmySystem.clearance_blockers(repo, s)["r"][code])


func _radius_with(arm_r: int, at: Array) -> int:
	for arm in repo.army_clearance:
		repo.army_clearance[arm] = arm_r
	var q: String = _mine()[0]
	var s := _alone([q])
	_stand(s, q, Vector2i(0, 0))
	_deploy(s, q, at)
	return _radius(s, q)


func test_radius_covers_the_farthest_group() -> void:
	var three: Array = [Vector2i(-50, 0), Vector2i(50, 0), Vector2i(0, 40)]
	assert_eq(_radius_with(40, three), 75, "max(40, 50 + 25)")
	assert_eq(_radius_with(100, three), 100, "a larger arm radius is unchanged")
	assert_eq(_radius_with(10, [Vector2i(30, 40)]), 75, "(30,40) is 50 away: 50 + 25")


func test_radius_rounds_the_distance_up() -> void:
	assert_eq(_radius_with(10, [Vector2i(1, 1)]), 27, "ceil(sqrt 2) = 2, + 25")


func test_no_battle_keeps_the_arm_radius() -> void:
	var q: String = _mine()[0]
	var s := _alone([q])
	_stand(s, q, Vector2i(0, 0))
	assert_eq(_radius(s, q), 1140)


func test_the_cached_day_record_follows_the_groups() -> void:
	var q: String = _mine()[0]
	var s := _alone([q])
	_stand(s, q, Vector2i(0, 0))
	_deploy(s, q, [Vector2i(3000, 0)])
	assert_eq(int(ArmySystem._ahead_blockers(repo, s)["r"][q]), 3025)
	_deploy(s, q, [Vector2i(5000, 0)])
	assert_eq(int(ArmySystem._ahead_blockers(repo, s)["r"][q]), 5025, "a changed layout is not served stale")


func _passer_detours(deployed: bool) -> bool:
	var ids := _mine()
	var q: String = ids[0]
	var r: String = ids[1]
	var s := _alone([q, r])
	for arm in repo.army_speed:
		repo.army_speed[arm] = 3
	var reg := ArmySystem.regiment(repo, r)
	var o := ArmySystem.pack_to_metres(repo, Vector2(float(reg["x"]), float(reg["y"])))
	_stand(s, q, o + Vector2i(10000, 3000))
	_stand(s, r, o)
	if deployed:
		_deploy(s, q, [o + Vector2i(10000, 6000)])
	ArmySystem.set_march_m(repo, s, r, o + Vector2i(20000, 0))
	for day in 6:                       # the disc comes into the day's walk after a few days
		ArmySystem.march_day(repo, s)
		s.day = mini(s.day + 1, Calendar.DAYS_PER_TICK)
		if not (s.regiments[r].get("route_m", []) as Array).is_empty():
			return true
	return false


func test_a_passer_by_goes_round_a_deployment_and_straight_past_a_lone_unit() -> void:
	assert_false(_passer_detours(false), "3000 m off a unit of 1140 + 1140: straight")
	assert_true(_passer_detours(true), "its groups reach 3025, so 1140 + 3025 > 3000: round")
