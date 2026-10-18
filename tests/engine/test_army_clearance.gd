extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## Unit clearance on the march (spec 2026-10-14-unit-clearance-and-scouting-
## design §a-b, owner rulings 2026-10-14 and 2026-10-15): no two land units
## stand within the sum of their arms' clearance radii (data/army/
## army_clearance.csv, D) of each other; a column whose end is occupied halts in
## front of the occupant on the side it came from, FACING it; a unit AT WAR with
## it (a host's column, a raider's standing unit) is never gone round - the
## column halts in front of it wherever on the road it is met; any other unit is
## gone round or waited behind, and a column that has waited two days gives way.
## The cases isolate the units they name on open ground (no towns, no slopes,
## clear skies); distances are expressed in D.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	for g in repo.army_town_reach:
		repo.army_town_reach[g] = 0.0       # no town's reach in the way of a halt point
	Weather.forget()


func _pace(km: int) -> void:
	for arm in repo.army_speed:
		repo.army_speed[arm] = km


## The player's land units of INFANTRY with 400 men or more, in code order (a
## pair of them clears at 2 x 1140).
func _mine() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and MapObjects.regiment_arm(repo, r) == "infantry" \
				and ArmySystem.headcount(repo, r) >= 400:
			out.append(String(r["regiment_code"]))
	out.sort()
	return out


func _foe_codes() -> Array:
	var out: Array = []
	for h: Dictionary in repo.raid_hosts:
		for c: String in EnemyAi.host_units(repo, null, h):
			var reg := ArmySystem.regiment(repo, c)
			if String(reg.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, reg) >= 400:
				out.append(c)
	out.sort()
	return out


## The pair clearance of two units: the sum of their arms' radii.
func _d(a: String, b: String) -> int:
	return ArmyGround.unit_radius(repo, ArmySystem.regiment(repo, a)) + ArmyGround.unit_radius(repo, ArmySystem.regiment(repo, b))


## A campaign with only `keep` in the world: every other unit leaves the roster
## (the crown's state and the foes with it), so a test's geometry meets no one.
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


## The origin the cases are laid out from: the first unit's opening ground.
func _o() -> Vector2i:
	var r := ArmySystem.regiment(repo, _mine()[0])
	return ArmySystem.pack_to_metres(repo, Vector2(float(r["x"]), float(r["y"])))


func _stand(s: GameState, code: String, at: Vector2i) -> void:
	var e: Dictionary = s.foes.get(code, s.regiments.get(code, {}))
	e["x_m"] = at.x
	e["y_m"] = at.y
	e["dest_x_m"] = at.x
	e["dest_y_m"] = at.y
	e["order"] = ArmySystem.ORDER_STANDBY
	e["camp_town"] = ""
	e.erase("route_m")


func _foe(s: GameState, code: String, at: Vector2i) -> void:
	var st := ArmySystem.starting_state(repo, ArmySystem.regiment(repo, code))
	s.foes[code] = st
	_stand(s, code, at)


func _at(s: GameState, code: String) -> Vector2i:
	var e: Dictionary = s.foes.get(code, s.regiments.get(code, {}))
	return Vector2i(int(e["x_m"]), int(e["y_m"]))


func _entry(s: GameState, code: String) -> Dictionary:
	return s.foes.get(code, s.regiments.get(code, {}))


func _march(s: GameState, code: String, to: Vector2i) -> void:
	ArmySystem.set_march_m(repo, s, code, to)


func _day(s: GameState) -> Array:
	var arrived := ArmySystem.march_day(repo, s)
	s.day = mini(s.day + 1, Calendar.DAYS_PER_TICK)
	return arrived


func _dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))


## --- halting in front of an occupied end -----------------------------------------

func test_halts_in_front_of_the_occupant_facing_it() -> void:
	_pace(100)
	var ids := _mine()
	var q: String = ids[0]
	var r: String = ids[1]
	var d := _d(q, r)
	assert_eq(d, 2280, "two foot: 2 x 1140")
	var s := _alone([q, r])
	var o := _o()
	_stand(s, q, o + Vector2i(10000, 0))
	_stand(s, r, o)
	_march(s, r, o + Vector2i(10000, 0))
	assert_eq(_day(s), [r], "a halt is an arrival")
	assert_eq(_at(s, r), o + Vector2i(10000 - d - 1, 0), "D + 1 short of the occupant, on the side it came from")
	var e := _entry(s, r)
	assert_eq(String(e["order"]), ArmySystem.ORDER_GARRISON)
	assert_eq(int(e["facing_deg"]), 0, "facing east, at Q")
	assert_eq(String(e["halted_by"]), q)
	assert_eq(int(e["halt_day"]), s.absolute_day() - 1, "the day it halted (the clock has moved on)")
	assert_eq(int(e["dest_x_m"]), (o + Vector2i(10000 - d - 1, 0)).x)
	assert_false(e.has("route_m"))
	assert_eq(_at(s, q), o + Vector2i(10000, 0), "the occupant has not moved")


func test_halt_facing_on_a_slant() -> void:
	_pace(100)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := _o()
	_stand(s, ids[0], o + Vector2i(6000, 8000))
	_stand(s, ids[1], o)
	_march(s, ids[1], o + Vector2i(6000, 8000))
	_day(s)
	var gap := _dist(_at(s, ids[1]), o + Vector2i(6000, 8000))
	assert_between(gap, float(_d(ids[0], ids[1]) + 1), float(_d(ids[0], ids[1]) + 2), "D + 1 off, along the 3-4-5 road")
	assert_eq(int(_entry(s, ids[1])["facing_deg"]), 53, "atan2(8000 - y, 6000 - x) about 53 degrees")


func test_two_columns_to_one_point_the_second_halts_before_the_first() -> void:
	_pace(100)
	var ids := _mine()
	var a: String = ids[0]
	var b: String = ids[1]
	var d := _d(a, b)
	var s := _alone([a, b])
	var o := _o()
	_stand(s, a, o)
	_stand(s, b, o + Vector2i(12000, 0))
	_march(s, a, o + Vector2i(5000, 0))
	_march(s, b, o + Vector2i(5000, 0))
	var arrived := _day(s)
	assert_eq(arrived, [a, b])
	assert_eq(_at(s, a), o + Vector2i(5000, 0), "code order: A is first and takes the point")
	assert_eq(_at(s, b), o + Vector2i(5000 + d + 1, 0), "B halts D + 1 short of it, on its own side")
	assert_eq(int(_entry(s, b)["facing_deg"]), 180)
	assert_eq(String(_entry(s, b)["halted_by"]), a)
	assert_false(_entry(s, a).has("halted_by"), "A arrived; it halted before no one")


## --- going round a standing unit ---------------------------------------------------

func test_a_passer_by_goes_round_a_standing_unit() -> void:
	_pace(3)    # a slow column: the road round stays ahead of it for days
	var ids := _mine()
	var q: String = ids[0]
	var r: String = ids[1]
	var d := _d(q, r)
	var s := _alone([q, r])
	var o := _o()
	_stand(s, q, o + Vector2i(10000, 0))
	_stand(s, r, o)
	_march(s, r, o + Vector2i(20000, 0))
	var seen_corner := false
	var arrived := false
	for day in 60:
		arrived = _day(s).has(r)
		assert_gte(_dist(_at(s, r), _at(s, q)), float(d), "clear of the standing unit at every day's end")
		var e := _entry(s, r)
		if e.has("route_m") and (MarchRoute.from_pairs(e["route_m"]) as Array).has(o + Vector2i(10000, MarchClearance.r8(d))):
			seen_corner = true
		if arrived:
			break
	assert_true(seen_corner, "its road bends round the octagon's south corner (the right-hand tie)")
	assert_true(arrived)
	assert_eq(_at(s, r), o + Vector2i(20000, 0), "and it gets there")
	assert_false(_entry(s, r).has("halted_by"))


func test_a_unit_inside_the_disc_is_let_go_only_while_it_walks_away() -> void:
	_pace(100)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := _o()
	_stand(s, ids[0], o + Vector2i(800, 0))
	_stand(s, ids[1], o)
	_march(s, ids[1], o - Vector2i(20000, 0))
	_day(s)
	assert_eq(_at(s, ids[1]), o - Vector2i(20000, 0), "it walks away from a unit it stands within D of")
	assert_false(_entry(s, ids[1]).has("halted_by"))


func test_a_unit_walking_at_an_enemy_it_stands_inside_of_halts_on_the_spot() -> void:
	_pace(100)
	var r: String = _mine()[0]
	var f: String = _foe_codes()[0]
	var s := _alone([r, f])
	var o := _o()
	_foe(s, f, o + Vector2i(800, 0))
	_stand(s, r, o)
	_march(s, r, o + Vector2i(20000, 0))
	_day(s)
	assert_eq(_at(s, r), o, "the leg closes on the enemy it stands inside of: it does not walk through")
	assert_eq(String(_entry(s, r)["halted_by"]), f)


func _shut_grid() -> void:
	# 250 m cells, every one a scarp: no way round on either side of a unit
	var bytes := PackedByteArray()
	bytes.resize(200 * 200)
	bytes.fill(150)
	repo.balance["army_march_grid_px"] = 4
	MarchPath.use(repo, MarchPath.build(repo, 200, 200, 250, bytes))


func test_a_column_that_waits_two_days_stops_and_says_the_road_is_blocked() -> void:
	_pace(10)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := Vector2i(20000, 20000)
	var d := _d(ids[0], ids[1])
	_stand(s, ids[0], o + Vector2i(10000, 0))
	_stand(s, ids[1], o)
	_march(s, ids[1], o + Vector2i(20000, 0))
	_shut_grid()
	_day(s)
	assert_eq(String(_entry(s, ids[1])["order"]), ArmySystem.ORDER_MARCH, "the first day it waits; its order stands")
	for day in 4:
		_day(s)
	var e := _entry(s, ids[1])
	assert_eq(String(e["order"]), ArmySystem.ORDER_GARRISON, "two days waiting: it stops where it stands")
	assert_eq(String(e["road_blocked_by"]), ids[0])
	assert_between(_at(s, ids[1]).x - o.x, 10000 - MarchClearance.r8(d) - 12000, 10000 - MarchClearance.r8(d), "short of the hull's entry")
	assert_false(e.has("halted_by"))
	var line := ArmySystem.arrival_headline(repo, s, ids[1])
	assert_true(line.contains("blocked"), line)
	assert_false(line.contains("{"), line)
	MarchPath.forget()


func test_of_two_columns_waiting_on_each_other_the_later_code_gives_way() -> void:
	_pace(10)
	var ids := _mine()
	var a: String = ids[0]
	var b: String = ids[1]
	var s := _alone([a, b])
	var o := Vector2i(20000, 20000)
	_stand(s, a, o)
	_stand(s, b, o + Vector2i(14000, 0))
	_march(s, a, o + Vector2i(30000, 0))
	_march(s, b, o - Vector2i(10000, 0))
	_shut_grid()
	for day in 12:
		_day(s)
		if String(_entry(s, b)["order"]) != ArmySystem.ORDER_MARCH:
			break
	assert_eq(String(_entry(s, b)["order"]), ArmySystem.ORDER_GARRISON, "the later code stops")
	assert_eq(String(_entry(s, b).get("road_blocked_by", "")), a)
	assert_eq(String(_entry(s, a)["order"]), ArmySystem.ORDER_MARCH, "the earlier keeps its order")
	MarchPath.forget()


## --- an enemy is never gone round ---------------------------------------------

func test_an_enemy_mid_road_halts_the_column_in_front_of_it() -> void:
	_pace(15)
	var r: String = _mine()[0]
	var f: String = _foe_codes()[0]
	var d := _d(r, f)
	var s := _alone([r, f])
	var o := _o()
	_foe(s, f, o + Vector2i(14000, 0))
	_stand(s, r, o)
	_march(s, r, o + Vector2i(30000, 0))        # the foe is NOT at the destination
	var halted := false
	for day in 10:
		if _day(s).has(r):
			halted = true
			break
	assert_true(halted)
	assert_eq(_at(s, r), o + Vector2i(14000 - d - 1, 0), "straight in front of it: no detour")
	var e := _entry(s, r)
	assert_eq(String(e["halted_by"]), f)
	assert_eq(int(e["facing_deg"]), 0)
	assert_false(e.has("route_m"))
	assert_eq(_at(s, f), o + Vector2i(14000, 0))


func test_the_raiders_standing_units_are_enemies_too() -> void:
	_pace(100)
	var r: String = _mine()[0]
	# a unit of the raider realm's roster that no host raised stands at its pack place
	var raider := repo.resolve_realm("raider_realm")
	var q := ""
	var all := SuiteData.campaign(repo, 7)
	for c: String in all.army_roster.keys():
		var reg: Dictionary = all.army_roster[c]
		if String(reg.get("kingdom_code", "")) == raider and not all.foes.has(c) and String(reg.get("is_naval", "0")) != "1" \
				and ArmySystem.headcount(repo, reg) > 0:
			q = c
			break
	if q == "":
		pending("the pack has no standing raider unit outside its hosts")
		return
	var s := _alone([r, q])
	var qp := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, q, s)))
	var d := _d(r, q)
	_stand(s, r, qp - Vector2i(20000, 0))
	_march(s, r, qp + Vector2i(20000, 0))        # past it: it would be gone round were it not an enemy
	var halted := false
	for day in 5:
		if _day(s).has(r):
			halted = true
			break
	assert_true(halted)
	assert_eq(String(_entry(s, r)["halted_by"]), q)
	assert_eq(_at(s, r), qp - Vector2i(d + 1, 0))
	assert_eq(int(_entry(s, r)["facing_deg"]), 0)
	# and it is a contact: a letter names it, with ITS realm, not a fixed slot
	Sighting.scout_day(repo, s)
	var letters := Play.letters(s, "contact")
	assert_eq(letters.size(), 1)
	var text := String((letters[0]["facts"] as Array)[0]["text"])
	assert_false(text.contains("{"), text)
	assert_true(text.contains(String(repo.kingdoms[raider]["label"])), text)


func test_a_foe_column_halts_before_a_crown_unit_and_faces_it() -> void:
	_pace(100)
	var r: String = _mine()[0]
	var f: String = _foe_codes()[0]
	var d := _d(r, f)
	var s := _alone([r, f])
	var o := _o()
	_stand(s, r, o + Vector2i(14000, 0))
	_foe(s, f, o)
	ArmySystem.aim_entry(repo, s.foes[f], o + Vector2i(30000, 0))
	_day(s)
	assert_eq(_at(s, f), o + Vector2i(14000 - d - 1, 0))
	assert_eq(String(s.foes[f]["halted_by"]), r)
	assert_eq(ArmySystem.facing_of(s, f), WarFront.facing_vector(0), "facing_of reads a foe's too")


func test_a_foe_standoff_survives_the_hosts_daily_reaim() -> void:
	_pace(100)
	var r: String = _mine()[0]
	var f: String = _foe_codes()[0]
	var s := _alone([r, f])
	var o := _o()
	_stand(s, r, o + Vector2i(14000, 0))
	_foe(s, f, o)
	var aim := o + Vector2i(30000, 0)
	ArmySystem.aim_entry(repo, s.foes[f], aim)
	_day(s)
	var held := _at(s, f)
	assert_eq(String(s.foes[f]["order"]), ArmySystem.ORDER_GARRISON)
	s.foes[f]["host"] = "h_test"
	s.ai_hosts["h_test"] = {"mode": "ADVANCE", "target_kind": "town", "target_id": "", "think_day": 0,
		"plunder": 0, "siege_progress": 0}
	assert_true(EnemyAi._stands_halted(repo, s, f, s.foes[f], aim), "same aim, the blocker in front: it holds")
	assert_false(EnemyAi._stands_halted(repo, s, f, s.foes[f], aim + Vector2i(500, 0)), "a new target releases it")
	_stand(s, r, held + Vector2i(0, 10000))
	assert_false(EnemyAi._stands_halted(repo, s, f, s.foes[f], aim), "a blocker moved sideways off the road releases it")
	s.regiments[r]["x_m"] = held.x + 200000
	assert_false(EnemyAi._stands_halted(repo, s, f, s.foes[f], aim), "the blocker gone, it is released")
	assert_eq(_at(s, f), held)


func test_a_crown_column_halting_at_a_standing_foe_attacks() -> void:
	_pace(100)
	var r: String = _mine()[0]
	var f: String = _foe_codes()[0]
	var s := _alone([r, f])
	var o := _o()
	_foe(s, f, o + Vector2i(10000, 0))
	_stand(s, r, o)
	_march(s, r, o + Vector2i(10000, 0))
	ArmySystem.march_day(repo, s)
	assert_eq(String(_entry(s, r)["order"]), ArmySystem.ORDER_GARRISON, "it no longer marches...")
	var events := BattleSystem.settle_day(repo, s)
	var starts := events.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "start")
	assert_eq(starts.size(), 1, "the halted column and the foe at D + 1 are in contact")
	assert_eq(starts[0]["att"], [r], "...yet it is the attacker: it marched into a standing enemy today")
	assert_eq(starts[0]["def"], [f])


## --- the rest of the rule ---------------------------------------------------------

func test_a_new_march_clears_the_halt() -> void:
	_pace(100)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := _o()
	_stand(s, ids[0], o + Vector2i(10000, 0))
	_stand(s, ids[1], o)
	_march(s, ids[1], o + Vector2i(10000, 0))
	_day(s)
	assert_true(_entry(s, ids[1]).has("halted_by"))
	_march(s, ids[1], o - Vector2i(5000, 0))
	var e := _entry(s, ids[1])
	for k: String in ["halted_by", "halt_day", "halt_aim_m", "facing_deg"]:
		assert_false(e.has(k), k)


func test_march_ahead_shows_the_halt_without_writing() -> void:
	_pace(100)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := _o()
	_stand(s, ids[0], o + Vector2i(10000, 0))
	_stand(s, ids[1], o)
	_march(s, ids[1], o + Vector2i(10000, 0))
	var copy: Dictionary = (s.regiments[ids[1]] as Dictionary).duplicate()
	assert_eq(ArmySystem.march_ahead(repo, s, ids[1], copy), o + Vector2i(10000 - _d(ids[0], ids[1]) - 1, 0))
	assert_eq(_at(s, ids[1]), o, "the state itself stands")


func test_the_days_path_carries_the_corners_a_detour_splices_in() -> void:
	_pace(40)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := _o()
	var d := _d(ids[0], ids[1])
	_stand(s, ids[0], o + Vector2i(10000, 0))
	_stand(s, ids[1], o)
	_march(s, ids[1], o + Vector2i(20000, 0))
	var path := CourierSystem.day_path_of(repo, s, ids[1])
	assert_true(path.has(o + Vector2i(10000, MarchClearance.r8(d))), "the piece walks the unit's far corner, not through it")
	assert_eq(path[path.size() - 1], ArmySystem.march_ahead(repo, s, ids[1], (s.regiments[ids[1]] as Dictionary).duplicate(true)))


func test_clearance_off_walks_through() -> void:
	SuiteData.no_clearance(repo)
	_pace(100)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := _o()
	_stand(s, ids[0], o + Vector2i(10000, 0))
	_stand(s, ids[1], o)
	_march(s, ids[1], o + Vector2i(10000, 0))
	_day(s)
	assert_gt(_at(s, ids[1]).x, o.x + 10000, "with the rule off: it walks to the end through the unit, and camps beyond it")
	assert_false(_entry(s, ids[1]).has("halted_by"))


func test_a_village_is_touched_a_few_metres_past_clearance() -> void:
	var village := ""
	for b: String in repo.burgs:
		if String(repo.burgs[b].get("group", "")) == "village" and (village == "" or b < village):
			village = b
	assert_ne(village, "", "the pack has a village")
	repo.army_town_reach["village"] = 1.0
	var f: String = _foe_codes()[0]
	var s := _alone([f])
	var at := ArmyGround.town_point_m(repo, village)
	var limit := ArmyGround.max_radius(repo) + ArmyGround.unit_radius(repo, ArmySystem.regiment(repo, f)) \
		+ int(repo.bal("army_clearance_touch_m"))
	_foe(s, f, at + Vector2i(limit, 0))
	assert_eq(BattleSystem.town_contact(repo, s, village, f), village, "within the radii + touch")
	_stand(s, f, at + Vector2i(limit + 1, 0))
	assert_eq(BattleSystem.town_contact(repo, s, village, f), "", "a metre out of touch")
	_stand(s, f, at + Vector2i(900, 0))
	assert_eq(BattleSystem.town_contact(repo, s, village, f), village, "inside the reach as ever")


func test_battle_contact_still_holds_two_adjacent_cavalry() -> void:
	assert_lte(2 * ArmyGround.arm_radius(repo, "cavalry") + 1, int(round(repo.bal("battle_contact_km") * 1000.0)),
		"two cavalry halted face to face stand inside battle_contact_km")


## --- the property: no day ever ends nearer than the pair's clearance --------------

func test_no_day_ends_nearer_than_the_pairs_clearance_over_many_approaches() -> void:
	_pace(7)
	var ids := _mine()
	var f: String = _foe_codes()[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var o := _o()
	var worst := 1.0e9
	for trial in 120:
		var enemy := trial % 3 == 0
		var q: String = f if enemy else ids[0]
		var r: String = ids[1]
		var d := _d(q, r)
		var s := _alone([q, r])
		var qpos := o + Vector2i(rng.randi_range(6000, 16000), rng.randi_range(-3000, 3000))
		if enemy:
			_foe(s, q, qpos)
		else:
			_stand(s, q, qpos)
		_stand(s, r, o)
		var dest := o + Vector2i(rng.randi_range(18000, 30000), rng.randi_range(-9000, 9000))
		_march(s, r, dest)
		for day in 14:
			_day(s)
			worst = minf(worst, _dist(_at(s, r), _at(s, q)) - float(d))
			if String(_entry(s, r)["order"]) != ArmySystem.ORDER_MARCH:
				break
	assert_gte(worst, 0.0, "the closest any day ended to a unit, beyond D: %.2f m" % worst)


## --- the opening world and the spawn ----------------------------------------------

func test_the_opening_campaign_has_every_land_unit_clear_of_the_rest() -> void:
	var r2 := SuiteData.repo()
	var s := SuiteData.campaign(r2, 7)
	var b := ArmySystem.clearance_blockers(r2, s)
	var codes: Array = b["codes"]
	assert_gt(codes.size(), 4)
	var bad: Array = []
	for i in codes.size():
		for j in range(i + 1, codes.size()):
			var need := int(b["r"][codes[i]]) + int(b["r"][codes[j]])
			var d := _dist(b["pos"][codes[i]], b["pos"][codes[j]])
			if d < float(need):
				bad.append("%s %s %.0f < %d" % [codes[i], codes[j], d, need])
	assert_eq(bad, [], "no two land units within the sum of their radii at the opening")


func test_a_raised_host_is_spread_round_its_assembly_point() -> void:
	var s := SuiteData.campaign(repo, 7)
	var checked := 0
	for h: Dictionary in repo.raid_hosts:
		var start := ArmySystem.pack_to_metres(repo, Vector2(float(h.get("start_x", 0)), float(h.get("start_y", 0))))
		var units := EnemyAi.host_units(repo, s, h)
		if units.size() < 2:
			continue
		assert_eq(_at(s, units[0]), start, "the first unit stands on the assembly point")
		for i in units.size():
			for j in range(i + 1, units.size()):
				assert_gte(_dist(_at(s, units[i]), _at(s, units[j])), float(_d(units[i], units[j])), "%s and %s" % [units[i], units[j]])
		checked += 1
	assert_gt(checked, 0)


func test_spawn_stacks_when_the_rule_is_off() -> void:
	SuiteData.no_clearance(repo)
	var s := SuiteData.campaign(repo, 7)
	for h: Dictionary in repo.raid_hosts:
		var start := ArmySystem.pack_to_metres(repo, Vector2(float(h.get("start_x", 0)), float(h.get("start_y", 0))))
		for u: String in EnemyAi.host_units(repo, s, h):
			assert_eq(_at(s, u), start, "stacked on the assembly point, as before")


## --- the invasion played ----------------------------------------------------------

func test_the_invasion_keeps_every_pair_clear_each_day_across_a_save() -> void:
	var repo2 := SuiteData.repo()
	Weather.forget()
	var engine := TickEngine.new(repo2)
	var s := Play.opened(repo2, engine)
	var worst := 1.0e9
	var escaped := _within_at_start(repo2, s)
	for d in 70:
		Play.day(engine, s, true)
		if d == 25:
			s = GameState.from_dict(s.to_dict())      # a save and a load in the middle
			engine = TickEngine.new(repo2)
		var b := ArmySystem.clearance_blockers(repo2, s)
		var codes: Array = b["codes"]
		for i in codes.size():
			for j in range(i + 1, codes.size()):
				if "%s|%s" % [codes[i], codes[j]] in escaped:
					continue
				var need := int(b["r"][codes[i]]) + int(b["r"][codes[j]])
				worst = minf(worst, _dist(b["pos"][codes[i]], b["pos"][codes[j]]) - float(need))
	assert_gte(worst, 0.0, "no pair of land units ever ends a day inside its clearance (closest: %.1f m beyond)" % worst)


## The pairs already inside their clearance when the test starts.
func _within_at_start(r: DataRepository, s: GameState) -> Array:
	var out: Array = []
	var b := ArmySystem.clearance_blockers(r, s)
	var codes: Array = b["codes"]
	for i in codes.size():
		for j in range(i + 1, codes.size()):
			if _dist(b["pos"][codes[i]], b["pos"][codes[j]]) < float(int(b["r"][codes[i]]) + int(b["r"][codes[j]])):
				out.append("%s|%s" % [codes[i], codes[j]])
	return out


## --- a host at its target is spread round it, not queued down the road (R-B) -------

func test_each_seed_establishes_a_siege_with_only_physically_deployed_columns() -> void:
	for seed_value in [11, 42, 7]:
		var repo2 := SuiteData.repo()
		repo2.balance["ai_think_days"] = 999.0
		Weather.forget()
		var engine := TickEngine.new(repo2)
		var s := Play.opened(repo2, engine, seed_value)
		while s.absolute_day() <= Play.first_appear(repo2):
			Play.day(engine, s, true)
		var main := Play.host(repo2, "main")
		var town := String(s.ai_hosts[main]["target_id"])
		assert_eq(String(s.ai_hosts[main]["target_kind"]), "town")
		# Defend the actual selected target: an unguarded town is raided,
		# so natural seed variation cannot substitute a raid for this test.
		for c: String in Play.regiment_units(repo2, false, 3):
			Play.arrive(repo2, s, c, Play.town_m(repo2, town))
		var checked := 0
		var saw_remote_column := false
		for d in 60:
			Play.day(engine, s, true)
			if not SiegeSystem.active(repo2, s, main):
				continue
			var expected_attack := 0
			for h: String in SiegeSystem.besiegers(repo2, s, town):
				for c: String in EnemyAi.live_regiments(repo2, s, h):
					var e: Dictionary = s.foes[c]
					if SiegeSystem.deployed_at(repo2, s, c, town):
						assert_true(SiegeSystem.at_town(repo2, s, c, town))
						assert_true((e.get("route_m", []) as Array).is_empty(), "stationed columns have no stale march route")
						expected_attack += ArmySystem.power(repo2, s, c, "attack")
					elif not SiegeSystem.at_town(repo2, s, c, town) and int(e.get("disengaging", 0)) == 0:
						if String(e.get("road_blocked_by", "")) != "":
							# Clearance stops await the next day's host route planning.
							assert_eq(String(e["order"]), ArmySystem.ORDER_GARRISON)
							assert_eq(Vector2i(int(e["dest_x_m"]), int(e["dest_y_m"])), Vector2i(int(e["x_m"]), int(e["y_m"])))
							assert_true((e.get("route_m", []) as Array).is_empty())
						elif BattleSystem.battle_of(s, c).is_empty():
							saw_remote_column = true
							assert_eq(String(e["order"]), ArmySystem.ORDER_MARCH, "free remote columns continue their independent march")
			assert_eq(SiegeSystem.attack_power(repo2, s, town), expected_attack, "only actual stationed strength contributes")
			checked += 1
			if checked >= 3:
				break
		assert_eq(checked, 3, "seed %d genuinely establishes a siege" % seed_value)
		assert_true(saw_remote_column, "seed %d begins before the remote columns arrive" % seed_value)

func test_a_besieging_host_stands_at_the_town_within_days_of_sitting_down() -> void:
	_pace(100)
	var host := Play.host(repo, "main")
	var definition: Dictionary = {}
	for row: Dictionary in repo.raid_hosts:
		if String(row["host_code"]) == host:
			definition = row
	assert_false(definition.is_empty())
	if definition.is_empty():
		return
	var cavalry: Array = []
	for code: String in EnemyAi.host_units(repo, null, definition):
		if MapObjects.regiment_arm(repo, ArmySystem.regiment(repo, code)) == "cavalry":
			cavalry.append(code)
	cavalry.sort()
	assert_false(cavalry.is_empty())
	if cavalry.is_empty():
		return
	var reach := int(repo.bal("army_spread_reach_m"))
	var radius := ArmyGround.unit_radius(repo, ArmySystem.regiment(repo, cavalry[0]))
	var pitch := radius * 2 + 1
	@warning_ignore("integer_division")
	var needed := reach / pitch + 2
	assert_gte(cavalry.size(), needed, "enough columns to queue beyond the spread reach")
	if cavalry.size() < needed:
		return
	cavalry = cavalry.slice(0, needed)
	var garrison := String(_mine()[0])
	for disable_spread: bool in [true, false]:
		var keep: Array = [garrison]
		keep.append_array(cavalry)
		var state := _alone(keep)
		var towns := TownStores.realm_towns(repo, state)
		towns.sort()
		assert_false(towns.is_empty())
		if towns.is_empty():
			return
		var town := String(towns[0])
		var centre := Play.town_m(repo, town)
		state.town_seat.clear()
		_stand(state, garrison, centre)
		state.regiments[garrison]["order"] = ArmySystem.ORDER_GARRISON
		state.town_seat[town] = garrison
		state.ai_hosts = {host: {"mode": EnemyAi.MODE_SIEGE,
			"target_kind": EnemyAi.KIND_TOWN, "target_id": town}}
		for i in cavalry.size():
			var code := String(cavalry[i])
			_foe(state, code, centre + Vector2i(pitch * (i + 1), 0))
			state.foes[code]["host"] = host
		assert_false(SiegeSystem.at_town(repo, state, String(cavalry.back()), town),
			"the approach queue initially extends beyond the town's spread reach")
		assert_eq(_within_at_start(repo, state), [], "the fixture starts without overlapping units")
		# Disable movement's spreading only; both runs use the same final acceptance radius.
		if disable_spread:
			repo.balance["army_spread_reach_m"] = 0
		for day in 3:
			EnemyAi.march_host(repo, state, host)
			_day(state)
		repo.balance["army_spread_reach_m"] = reach
		var outside := 0
		for code: String in cavalry:
			if not SiegeSystem.at_town(repo, state, code, town):
				outside += 1
		if disable_spread:
			assert_gt(outside, 0, "without spreading, the approach queue remains outside")
			continue
		assert_eq(outside, 0, "every besieging column reaches the town within three days")
		assert_eq(_within_at_start(repo, state), [], "spread columns preserve clearance")
		var settled: Dictionary = {}
		for code: String in cavalry:
			settled[code] = _at(state, code)
		EnemyAi.march_host(repo, state, host)
		_day(state)
		for code: String in cavalry:
			assert_eq(_at(state, code), settled[code], "refreshed host orders preserve its camp")


func test_a_detour_then_an_enemy_halt_keeps_the_drawn_corners() -> void:
	_pace(100)
	var ids := _mine()
	var f: String = _foe_codes()[0]
	var s := _alone([ids[0], ids[1], f])
	var o := _o()
	_stand(s, ids[0], o + Vector2i(10000, 0))
	_stand(s, ids[1], o)
	_foe(s, f, o + Vector2i(24000, 0))
	_march(s, ids[1], o + Vector2i(35000, 0))
	var path := CourierSystem.day_path_of(repo, s, ids[1])
	assert_true(path.has(o + Vector2i(10000, MarchClearance.r8(_d(ids[0], ids[1])))),
		"halting after a detour preserves the corner around the standing friendly unit")
	var copy: Dictionary = s.regiments[ids[1]].duplicate(true)
	assert_eq(path.back(), ArmySystem.march_ahead(repo, s, ids[1], copy))
	assert_eq(String(copy.get("halted_by", "")), f)

## A real friendly contact just outside the spread circle can enter an empty
## inner camp slot. Historical halt metadata alone grants no displacement.
func test_spreading_accepts_actual_boundary_contact_but_not_a_remote_old_halt() -> void:
	var codes: Array = _foe_codes().filter(func(c: String) -> bool:
		return MapObjects.regiment_arm(repo, ArmySystem.regiment(repo, c)) == "infantry").slice(0, 3)
	assert_eq(codes.size(), 3)
	var s := _alone(codes)
	var o := _o()
	var reach := int(repo.bal("army_spread_reach_m"))
	_foe(s, codes[0], o)
	_foe(s, codes[1], o + Vector2i(reach, 0))
	var touching := o + Vector2i(reach + _d(codes[1], codes[2]) + 1, 0)
	_foe(s, codes[2], touching)
	var e: Dictionary = s.foes[codes[2]]
	e["halted_by"] = codes[1]
	e["halt_aim_m"] = [o.x, o.y]
	ArmySystem._spread_foe(repo, s, codes[2], e, o, ArmySystem.clearance_blockers(repo, s))
	assert_ne(_at(s, codes[2]), touching)
	assert_lte(_dist(_at(s, codes[2]), o), float(reach))
	for other: String in codes.slice(0, 2):
		assert_gte(_dist(_at(s, codes[2]), _at(s, other)), float(_d(codes[2], other)))
	var far := o + Vector2i(30000, 0)
	_stand(s, codes[2], far)
	e["halted_by"] = codes[1]
	e["halt_aim_m"] = [o.x, o.y]
	ArmySystem._spread_foe(repo, s, codes[2], e, o, ArmySystem.clearance_blockers(repo, s))
	assert_eq(_at(s, codes[2]), far, "a remote stale halt cannot teleport into camp")
