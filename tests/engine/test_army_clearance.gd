extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
## Unit clearance on the march (spec 2026-10-14-unit-clearance-and-scouting-
## design §a-b, owner rulings 2026-10-14): no two land units stand within
## army_clearance_m (1400) of each other; a column whose end is occupied halts in
## front of the occupant on the side it came from, FACING it; an ENEMY is never
## gone round — the column halts in front of it wherever on the road it is met;
## any other unit is gone round or waited behind. Geometry in the cases is the
## spec's hand-computed numbers (test_march_clearance.gd); each case isolates
## the units it names on open ground (no towns, no slopes, clear skies).

const C := 1400

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


## The player's land units of 400 men or more, in code order.
func _mine() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.headcount(repo, r) >= 400:
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


## --- halting in front of an occupied end (cases 6-8) --------------------------

func test_halts_in_front_of_the_occupant_facing_it() -> void:
	_pace(100)
	var ids := _mine()
	var q: String = ids[0]
	var r: String = ids[1]
	var s := _alone([q, r])
	var o := _o()
	_stand(s, q, o + Vector2i(10000, 0))
	_stand(s, r, o)
	_march(s, r, o + Vector2i(10000, 0))
	assert_eq(_day(s), [r], "a halt is an arrival")
	assert_eq(_at(s, r), o + Vector2i(8600, 0), "C short of the occupant, on the side it came from")
	var e := _entry(s, r)
	assert_eq(String(e["order"]), ArmySystem.ORDER_GARRISON)
	assert_eq(int(e["facing_deg"]), 0, "facing east, at Q")
	assert_eq(String(e["halted_by"]), q)
	assert_eq(int(e["halt_day"]), s.absolute_day() - 1, "the day it halted (the clock has moved on)")
	assert_eq(int(e["dest_x_m"]), (o + Vector2i(8600, 0)).x)
	assert_false(e.has("route_m"))
	assert_eq(_at(s, q), o + Vector2i(10000, 0), "the occupant has not moved")


func test_halt_facing_on_a_slant() -> void:
	_pace(100)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := _o()
	_stand(s, ids[0], o + Vector2i(3000, 4000))
	_stand(s, ids[1], o)
	_march(s, ids[1], o + Vector2i(3000, 4000))
	_day(s)
	assert_eq(_at(s, ids[1]), o + Vector2i(2160, 2880))
	assert_eq(int(_entry(s, ids[1])["facing_deg"]), 53, "atan2(1120, 840) = 53.13 degrees")


func test_two_columns_to_one_point_the_second_halts_before_the_first() -> void:
	_pace(100)
	var ids := _mine()
	var a: String = ids[0]
	var b: String = ids[1]
	var s := _alone([a, b])
	var o := _o()
	_stand(s, a, o)
	_stand(s, b, o + Vector2i(10000, 0))
	_march(s, a, o + Vector2i(5000, 0))
	_march(s, b, o + Vector2i(5000, 0))
	var arrived := _day(s)
	assert_eq(arrived, [a, b])
	assert_eq(_at(s, a), o + Vector2i(5000, 0), "code order: A is first and takes the point")
	assert_eq(_at(s, b), o + Vector2i(6400, 0), "B halts C short of it, on its own side")
	assert_eq(int(_entry(s, b)["facing_deg"]), 180)
	assert_eq(String(_entry(s, b)["halted_by"]), a)
	assert_false(_entry(s, a).has("halted_by"), "A arrived; it halted before no one")


## --- going round a standing unit (cases 9, 10) --------------------------------

func test_a_passer_by_goes_round_a_standing_unit() -> void:
	_pace(3)    # a slow column: the road round stays ahead of it for days
	var ids := _mine()
	var q: String = ids[0]
	var r: String = ids[1]
	var s := _alone([q, r])
	var o := _o()
	_stand(s, q, o + Vector2i(10000, 0))
	_stand(s, r, o)
	_march(s, r, o + Vector2i(20000, 0))
	var seen_corner := false
	var arrived := false
	for d in 40:
		arrived = _day(s).has(r)
		assert_gte(_dist(_at(s, r), _at(s, q)), float(C), "clear of the standing unit at every day's end")
		var e := _entry(s, r)
		if e.has("route_m") and (MarchRoute.from_pairs(e["route_m"]) as Array).has(o + Vector2i(10000, 1516)):
			seen_corner = true
		if arrived:
			break
	assert_true(seen_corner, "its road bends round the octagon's south corner (the right-hand tie)")
	assert_true(arrived)
	assert_eq(_at(s, r), o + Vector2i(20000, 0), "and it gets there")
	assert_false(_entry(s, r).has("halted_by"))


func test_a_unit_already_inside_the_disc_is_let_go() -> void:
	_pace(100)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := _o()
	_stand(s, ids[0], o + Vector2i(800, 0))
	_stand(s, ids[1], o)
	_march(s, ids[1], o - Vector2i(20000, 0))
	_day(s)
	assert_eq(_at(s, ids[1]), o - Vector2i(20000, 0), "it walks away from a unit it stands within C of")
	assert_false(_entry(s, ids[1]).has("halted_by"))


func test_waits_behind_when_both_sides_are_closed() -> void:
	_pace(10)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := Vector2i(20000, 20000)
	_stand(s, ids[0], o + Vector2i(10000, 0))
	_stand(s, ids[1], o)
	_march(s, ids[1], o + Vector2i(20000, 0))
	# 250 m cells, every one a scarp: no way round on either side of the unit
	var bytes := PackedByteArray()
	bytes.resize(200 * 200)
	bytes.fill(150)
	repo.balance["army_march_grid_px"] = 4
	MarchPath.use(repo, MarchPath.build(repo, 200, 200, 250, bytes))
	for d in 6:
		_day(s)
	var e := _entry(s, ids[1])
	assert_eq(String(e["order"]), ArmySystem.ORDER_MARCH, "it waits; its order stands")
	assert_between(_at(s, ids[1]).x - o.x, 7000, 8484, "short of the hull's entry (8484), nearer than a halt")
	assert_false(e.has("halted_by"))
	MarchPath.forget()


## --- an enemy is never gone round ---------------------------------------------

func test_an_enemy_mid_road_halts_the_column_in_front_of_it() -> void:
	_pace(15)
	var r: String = _mine()[0]
	var f: String = _foe_codes()[0]
	var s := _alone([r, f])
	var o := _o()
	_foe(s, f, o + Vector2i(10000, 0))
	_stand(s, r, o)
	_march(s, r, o + Vector2i(30000, 0))        # the foe is NOT at the destination
	var halted := false
	for d in 10:
		if _day(s).has(r):
			halted = true
			break
	assert_true(halted)
	assert_eq(_at(s, r), o + Vector2i(8600, 0), "straight in front of it: no detour")
	var e := _entry(s, r)
	assert_eq(String(e["halted_by"]), f)
	assert_eq(int(e["facing_deg"]), 0)
	assert_false(e.has("route_m"))
	assert_eq(_at(s, f), o + Vector2i(10000, 0))


func test_a_foe_column_halts_before_a_crown_unit_and_faces_it() -> void:
	_pace(100)
	var r: String = _mine()[0]
	var f: String = _foe_codes()[0]
	var s := _alone([r, f])
	var o := _o()
	_stand(s, r, o + Vector2i(10000, 0))
	_foe(s, f, o)
	ArmySystem.aim_entry(repo, s.foes[f], o + Vector2i(30000, 0))
	_day(s)
	assert_eq(_at(s, f), o + Vector2i(8600, 0))
	assert_eq(String(s.foes[f]["halted_by"]), r)
	assert_eq(ArmySystem.facing_of(s, f), WarFront.facing_vector(0), "facing_of reads a foe's too")


func test_a_crown_column_halting_at_a_standing_foe_attacks() -> void:
	_pace(100)
	var r: String = _mine()[0]
	var f: String = _foe_codes()[0]
	var s := _alone([r, f])
	var o := _o()
	_foe(s, f, o + Vector2i(10000, 0))
	_stand(s, r, o)
	_march(s, r, o + Vector2i(10000, 0))
	var today := s.absolute_day()
	ArmySystem.march_day(repo, s)
	assert_eq(String(_entry(s, r)["order"]), ArmySystem.ORDER_GARRISON, "it no longer marches...")
	var events := BattleSystem.settle_day(repo, s)
	var starts := events.filter(func(e: Dictionary) -> bool: return String(e["kind"]) == "start")
	assert_eq(starts.size(), 1, "the halted column and the foe at 1400 m are in contact")
	assert_eq(starts[0]["att"], [r], "...yet it is the attacker: it marched into a standing enemy today (%d)" % today)
	assert_eq(starts[0]["def"], [f])


## --- the rest of the rule -----------------------------------------------------

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
	assert_false(e.has("halted_by"))
	assert_false(e.has("halt_day"))
	assert_false(e.has("facing_deg"))


func test_march_ahead_shows_the_halt_without_writing() -> void:
	_pace(100)
	var ids := _mine()
	var s := _alone([ids[0], ids[1]])
	var o := _o()
	_stand(s, ids[0], o + Vector2i(10000, 0))
	_stand(s, ids[1], o)
	_march(s, ids[1], o + Vector2i(10000, 0))
	var copy: Dictionary = (s.regiments[ids[1]] as Dictionary).duplicate()
	assert_eq(ArmySystem.march_ahead(repo, s, ids[1], copy), o + Vector2i(8600, 0))
	assert_eq(_at(s, ids[1]), o, "the state itself stands")


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
	assert_gt(_at(s, ids[1]).x, o.x + 10000, "with army_clearance_m 0 the old march: it walks to the end through the unit, and camps beyond it")
	assert_false(_entry(s, ids[1]).has("halted_by"))


func test_a_village_is_touched_a_few_metres_past_clearance() -> void:
	var village := ""
	for b: String in repo.burgs:
		if String(repo.burgs[b].get("group", "")) == "village" and (village == "" or b < village):
			village = b
	assert_ne(village, "", "the pack has a village")
	repo.army_town_reach["village"] = 1.0
	var s := _alone([_foe_codes()[0]])
	var f: String = _foe_codes()[0]
	var at := ArmyGround.town_point_m(repo, village)
	_foe(s, f, at + Vector2i(1405, 0))
	assert_eq(BattleSystem._town_contact(repo, s, village, f), village, "1405 m: within C + touch (1410)")
	_stand(s, f, at + Vector2i(1411, 0))
	assert_eq(BattleSystem._town_contact(repo, s, village, f), "", "1411 m: out of touch")
	_stand(s, f, at + Vector2i(900, 0))
	assert_eq(BattleSystem._town_contact(repo, s, village, f), village, "inside the reach as ever")


## --- the opening world and the spawn (cases 11, 12) ----------------------------

func test_the_opening_campaign_has_every_land_unit_clear_of_the_rest() -> void:
	var s := SuiteData.campaign(SuiteData.repo(), 7)
	var repo2 := SuiteData.repo()
	var b := ArmySystem.clearance_blockers(repo2, s)
	var codes: Array = b["codes"]
	assert_gt(codes.size(), 4)
	var bad: Array = []
	for i in codes.size():
		for j in range(i + 1, codes.size()):
			var d := _dist(b["pos"][codes[i]], b["pos"][codes[j]])
			if d < float(C):
				bad.append("%s %s %.0f" % [codes[i], codes[j], d])
	assert_eq(bad, [], "no two land units within 1400 m at the opening")


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
				assert_gte(_dist(_at(s, units[i]), _at(s, units[j])), float(C), "%s and %s" % [units[i], units[j]])
		var second := ArmySystem.regiment(repo, units[1], s)
		if MapObjects.regiment_arm(repo, second) == "infantry":
			assert_eq(_at(s, units[1]), start + Vector2i(1500, 0), "an infantry second takes ring 1's east slot")
		checked += 1
	assert_gt(checked, 0)


func test_spawn_stacks_when_the_rule_is_off() -> void:
	SuiteData.no_clearance(repo)
	var s := SuiteData.campaign(repo, 7)
	for h: Dictionary in repo.raid_hosts:
		var start := ArmySystem.pack_to_metres(repo, Vector2(float(h.get("start_x", 0)), float(h.get("start_y", 0))))
		for u: String in EnemyAi.host_units(repo, s, h):
			assert_eq(_at(s, u), start, "stacked on the assembly point, as before")


## --- the invasion played (case 15) --------------------------------------------

func test_the_invasion_keeps_every_pair_clear_each_day_across_a_save() -> void:
	var repo2 := SuiteData.repo()
	Weather.forget()
	var engine := TickEngine.new(repo2)
	var s := Play.opened(repo2, engine)
	var worst := 1.0e9
	var escaped := _within_at_start(repo2, s)
	for d in 70:
		Play.day(engine, s)
		if d == 25:
			s = GameState.from_dict(s.to_dict())      # a save and a load in the middle
			engine = TickEngine.new(repo2)
		var b := ArmySystem.clearance_blockers(repo2, s)
		var codes: Array = b["codes"]
		for i in codes.size():
			for j in range(i + 1, codes.size()):
				if "%s|%s" % [codes[i], codes[j]] in escaped:
					continue
				worst = minf(worst, _dist(b["pos"][codes[i]], b["pos"][codes[j]]))
	assert_gte(worst, float(C), "no pair of land units ever ends a day within 1400 m")


## The pairs already within C of each other when the test starts (none at an
## opening, but a pair that closed in a battle's contact is let go on its own).
func _within_at_start(r: DataRepository, s: GameState) -> Array:
	var out: Array = []
	var b := ArmySystem.clearance_blockers(r, s)
	var codes: Array = b["codes"]
	for i in codes.size():
		for j in range(i + 1, codes.size()):
			if _dist(b["pos"][codes[i]], b["pos"][codes[j]]) < float(C):
				out.append("%s|%s" % [codes[i], codes[j]])
	return out
