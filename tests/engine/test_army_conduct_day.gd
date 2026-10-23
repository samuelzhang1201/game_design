extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const H := preload("res://tests/engine/conduct_helpers.gd")
## ArmyConduct.day_step (spec 2026-10-10-foraging-and-desertion §3.3), hand-
## computed from the balance defaults: desertion 3 per mille a day per line
## held (x law: fine 1000, lenient 2000), news at 50 per mille of the heads,
## stop/start lines as in test_army_conduct_switch, 30 supply per food unit.

var repo: DataRepository
var state: GameState
var a: String
var b: String
var home: String
var foreign: String
var _follower_before := 0


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 11)
	var two := H.land_units(repo, state)
	assert_gte(two.size(), 2)
	a = String(two[0])
	b = String(two[1])
	home = H.home_province(repo, state)
	foreign = H.foreign_province(repo, state)
	H.set_stance(repo, MapOwnership.owner_of(repo, state, foreign), "Enemy")
	state.tick = 5
	for t in range(0, 12):
		state.tick = t
		if Forage.season_permille(repo, state) == 1000:
			break
	state.day = 1
	state.forage_stripped.clear()
	state.conduct_marks.clear()
	state.hazards.clear()
	state.grievance.clear()
	state.metrics["legitimacy"] = 50.0
	for c: String in state.regiments:
		var e: Dictionary = state.regiments[c]
		e["forage"] = ""
		e["forage_days"] = 0
		e["desert_rem"] = 0


## Stand `c` in the first manor cell of `province`.
func _place(c: String, province: String) -> void:
	var cells: Array = MapManors.manors_of_province(repo, province, state)
	assert_false(cells.is_empty())
	var at := MapTerrain.cell_center(repo, repo.cells[int(cells[0])])
	var m := ArmySystem.pack_to_metres(repo, at)
	state.regiments[c]["x_m"] = m.x
	state.regiments[c]["y_m"] = m.y
	assert_eq(ArmySystem.province_of(repo, state, ArmySystem.regiment(repo, c, state)), province)


func _men(c: String, n: int) -> void:
	var row: Dictionary = state.army_roster[c]
	for arm: String in repo.world_table("military", "unit_types"):
		if row.has(arm):
			row[arm] = "0"
	row["infantry"] = str(n)
	var source: Dictionary = row.source_parts[0].duplicate(true)
	source.arm = "infantry"
	source.equipment_count = n
	source.crew_per_element = int(repo.world_row("military", "unit_types", "infantry").crew)
	row.source_parts = [source]
	assert_false(Personnel.replace(repo, state, c, n).has("error"))


func _law(c: String, law: String, value: String) -> void:
	var key: String = LawSystem.UNIT_PREFIX + c
	var row: Dictionary = state.law_in_force.get(key, {})
	row[law] = {"value": value, "decree_id": 1}
	state.law_in_force[key] = row


## `days` whole days in hand (at least), with the given morale and training.
func _put(c: String, days: int, morale: int, training: int) -> void:
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c, state), state)
	var s := 0
	while ArmySystem.days_in_hand(s, use) < days:
		s += 1
	state.regiments[c]["supplies"] = s
	state.regiments[c]["morale"] = morale
	state.regiments[c]["training"] = training


func _starve(c: String) -> void:
	state.regiments[c]["supplies"] = 0
	state.regiments[c]["morale"] = 0
	state.regiments[c]["training"] = 0


func _types(events: Array) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		out.append(String(e["type"]))
	return out


func test_day_order_and_events() -> void:
	_place(a, home)
	_men(a, 1000)
	repo.balance["desert_permille_per_day"] = 30
	_starve(a)
	_law(a, "desertion_penalty", "fine")
	_place(b, foreign)
	_law(b, "plunder", "forbid")
	_put(b, 0, 50, 50)
	H.set_food(repo, foreign, 9)
	for c: String in H.land_units(repo, state):
		if c != a and c != b:
			state.regiments[c]["x_m"] = state.regiments[a]["x_m"]
			state.regiments[c]["y_m"] = state.regiments[a]["y_m"]
			_put(c, 30, 90, 90)
	var before_supplies := int(state.regiments[b]["supplies"])
	var ev := ArmyConduct.day_step(repo, state)
	# 1000 fit × 3 lines × 30 per mille = 90 lost, above the 50-person news threshold.
	assert_eq(_types(ev), ["deserting", "forage_unlawful"])
	assert_eq(String(ev[0]["regiment"]), a)
	assert_gt(int(ev[0]["lost"]), 0)
	assert_eq(String(ev[1]["regiment"]), b)
	assert_eq(String(state.regiments[b]["forage"]), "desperate")
	assert_gt(int(state.regiments[b]["supplies"]), before_supplies)


func test_desertion_news_once_a_month_and_big_once() -> void:
	_place(a, home)
	_men(a, 1000)
	_starve(a)
	_law(a, "desertion_penalty", "fine")
	for c: String in H.land_units(repo, state):
		if c != a:
			state.regiments[c]["x_m"] = state.regiments[a]["x_m"]
			state.regiments[c]["y_m"] = state.regiments[a]["y_m"]
			_put(c, 30, 90, 90)
	# rate = 3 x 100 x 3 lines x 1000 / 1000 = 900 per 100000 of the fit men:
	# day1 1000x900 = 900000 -> 9 (rem 0); day2 991x900 = 891900 -> 8 (rem 91900);
	# day3 983x900 + 91900 = 976600 -> 9 (rem 76600); day4 974x900 + 76600 = 953200
	# -> 9; day5 965x900 + 53200 = 921700 -> 9 (44 gone); day6 956x900 + 21700 =
	# 882100 -> 8 (52 gone): 5% of 1000 = 50 is crossed on day 6 and only then.
	var gone: Array = []
	var deserting := 0
	var big_days: Array = []
	for d in range(1, 11):
		state.day = d
		for e: Dictionary in ArmyConduct.day_step(repo, state):
			if e["type"] == "deserting":
				deserting += 1
			elif e["type"] == "deserting_big":
				big_days.append(d)
		gone.append(Desertion.total(state, a))
	assert_eq(gone.slice(0, 6), [9, 17, 26, 35, 44, 52])
	assert_eq(deserting, 1, "told once in the month")
	assert_eq(big_days, [6], "the 5% line is crossed once, on day 6")
	# the next month tells the news again, the big one never twice
	state.tick += 1
	state.day = 1
	var next := ArmyConduct.day_step(repo, state)
	assert_true("deserting" in _types(next))
	assert_false("deserting_big" in _types(next))


func test_desertion_clamp_end_to_end() -> void:
	_place(a, home)
	_men(a, 10)
	_starve(a)
	_law(a, "desertion_penalty", "lenient")
	for c: String in H.land_units(repo, state):
		if c != a:
			state.regiments[c]["x_m"] = state.regiments[a]["x_m"]
			state.regiments[c]["y_m"] = state.regiments[a]["y_m"]
			_put(c, 30, 90, 90)
	var guard := 0
	var start_tick := state.tick
	while ArmySystem.fit_count(repo, state, a) > 0 and guard < 4000:
		@warning_ignore("integer_division")  # real months advance along with day
		state.tick = start_tick + guard / Calendar.DAYS_PER_TICK
		state.day = 1 + guard % Calendar.DAYS_PER_TICK
		ArmyConduct.day_step(repo, state)
		guard += 1
	assert_lt(guard, 4000)
	assert_eq(Desertion.total(state, a), 10)
	assert_eq(ArmySystem.fit_count(repo, state, a), 0)
	assert_eq(int(state.regiments[a]["desert_rem"]), 0)
	var snap: Dictionary = (state.regiments[a] as Dictionary).duplicate(true)
	var people_before: Dictionary = state.military_cohorts.duplicate(true)
	var ev := ArmyConduct.day_step(repo, state)
	assert_eq(state.regiments[a], snap)
	assert_eq(state.military_cohorts, people_before)
	assert_false("deserting" in _types(ev))


func test_fleet_and_foe_untouched() -> void:
	var fleet := ""
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c: String in codes:
		if String(ArmySystem.regiment(repo, c, state).get("is_naval", "0")) == "1":
			fleet = c
			break
	if fleet != "":
		_starve(fleet)
		state.regiments[fleet]["forage"] = ""
	else:
		pending("no fleet in this pack's roster")
		return
	state.foes["foe_x"] = {"morale": 0, "training": 0, "supplies": 0, "forage": "",
		"x_m": state.regiments[a]["x_m"], "y_m": state.regiments[a]["y_m"]}
	var fleet_before: Dictionary = (state.regiments.get(fleet, {}) as Dictionary).duplicate(true)
	var foes_before: Dictionary = state.foes.duplicate(true)
	ArmyConduct.day_step(repo, state)
	assert_eq(state.foes, foes_before)
	if fleet != "":
		assert_eq(state.regiments[fleet], fleet_before)


func test_units_settle_apart_from_day_30() -> void:
	_place(a, home)
	_men(a, 1000)
	_put(a, 30, 90, 90)
	state.regiments[a]["morale"] = 50
	state.regiments[a]["training"] = 10
	state.regiments[a]["forage_days"] = 30
	state.day = 29
	ArmyConduct.day_step(repo, state)
	assert_eq(int(state.regiments[a]["morale"]), 50)
	assert_eq(ArmySystem.wounded_count(repo, state, a), 0)
	assert_eq(int(state.regiments[a]["forage_days"]), 30)
	state.day = 30
	ArmyConduct.day_step(repo, state)
	assert_eq(int(state.regiments[a]["forage_days"]), 30, "day 30 settles the provinces only")
	ArmyConduct.settle_units(repo, state)
	assert_eq(int(state.regiments[a]["morale"]), 54, "50 + 4 x 30 / 30")
	assert_eq(int(state.regiments[a]["training"]), 7, "10 - 3")
	assert_eq(ArmySystem.wounded_count(repo, state, a), 10, "1000 x 10 x 30 / 30000")
	assert_eq(int(state.regiments[a]["forage_days"]), 0)


func test_tick_settles_foraging_after_the_regiments_month() -> void:
	# ruling R8: the unit settlement runs in TickEngine.advance right after
	# ArmySystem.settle_month, so the drift and the wound recovery do not eat it.
	for c: String in H.land_units(repo, state):
		_place(c, home)
		_put(c, 30, 90, 90)
	_men(a, 1000)
	var reg := ArmySystem.regiment(repo, a, state)
	var use := ArmySystem.supply_use(repo, reg, state)
	state.regiments[a]["supplies"] = ArmySystem.max_units(repo, use)   # stores full: supply score 1000
	# morale already at its mark, so the month's drift leaves it there
	var mark := clampi(ArmySystem.morale_mark(repo, 1000, ArmyGround.seated_in(repo, state, a) != "")
		+ LawEffects.unit_mark(repo, state, a), 0, 100)
	assert_lte(mark + 4, 100)
	state.regiments[a]["morale"] = mark
	state.regiments[a]["training"] = 10
	state.regiments[a]["forage_days"] = 30
	if state.tick == 0:
		state.tick = 12
	state.day = Calendar.DAYS_PER_TICK
	TickEngine.new(repo).advance(state)
	var e: Dictionary = state.regiments[a]
	assert_eq(ArmySystem.supply_score(repo, int(e["supplies"]), use), 1000, "the mark held")
	assert_eq(int(e["morale"]), mark + 4, "drift(mark -> mark) = mark, then + 4 x 30 / 30")
	assert_eq(int(e["training"]), 7, "10 - 3 x 30 / 30 (army_training_per_month 0)")
	assert_eq(ArmySystem.wounded_count(repo, state, a), 10, "1000 x 10 x 30 / 30000, after the month's recovery of 0")
	assert_eq(int(e["forage_days"]), 0)


func _two_foragers(first: String, second: String) -> void:
	for c: String in [first, second]:
		_place(c, foreign)
		_law(c, "plunder", "allow")
		state.regiments[c]["carry_days"] = 30
	for c: String in H.land_units(repo, state):
		if c != first and c != second:
			_place(c, home)
			_put(c, 30, 90, 90)
	# needs 20 and 10: supplies = full - need (a month's use or the carry cap)
	var needs := {first: 20, second: 10}
	for c: String in [first, second]:
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c, state), state)
		var full := mini(ArmySystem.max_units(repo, use), use)
		assert_gte(full, 20)
		state.regiments[c]["supplies"] = full - int(needs[c])
		assert_eq(Forage.need_of(repo, state, c), int(needs[c]))
	H.set_food(repo, foreign, 6)   # 6 x 30 / 30 = 6 a day on day 1


func test_two_units_same_province_share_by_need() -> void:
	_two_foragers(a, b)
	var sa := int(state.regiments[a]["supplies"])
	var sb := int(state.regiments[b]["supplies"])
	ArmyConduct.day_step(repo, state)
	assert_eq(int(state.regiments[a]["supplies"]) - sa, 4, "6 x 20 / 30")
	assert_eq(int(state.regiments[b]["supplies"]) - sb, 2, "6 x 10 / 30")
	# mirrored: the second code has the larger need
	state = SuiteData.campaign(repo, 11)
	before_each_reset_for_mirror()
	_two_foragers(b, a)
	sa = int(state.regiments[a]["supplies"])
	sb = int(state.regiments[b]["supplies"])
	ArmyConduct.day_step(repo, state)
	assert_eq(int(state.regiments[b]["supplies"]) - sb, 4)
	assert_eq(int(state.regiments[a]["supplies"]) - sa, 2)


func before_each_reset_for_mirror() -> void:
	state.tick = 5
	for t in range(0, 12):
		state.tick = t
		if Forage.season_permille(repo, state) == 1000:
			break
	state.day = 1
	for c: String in state.regiments:
		var e: Dictionary = state.regiments[c]
		e["forage"] = ""
		e["forage_days"] = 0


## A starter (0 days, forbid) and a healthy follower in one enemy province.
func _havoc_day(starter: String, follower: String, no_havoc: bool) -> Array:
	for c: String in H.land_units(repo, state):
		_place(c, home)
		_put(c, 30, 90, 90)
	for c: String in [starter, follower]:
		_place(c, foreign)
		_law(c, "plunder", "forbid")
	_put(starter, 0, 50, 50)
	_put(follower, 10, 80, 80)
	state.regiments[follower]["carry_days"] = 30
	_follower_before = int(state.regiments[follower]["supplies"])
	if no_havoc:
		_law(starter, "no_havoc", "on")
	H.set_food(repo, foreign, 6)
	return ArmyConduct.day_step(repo, state)


func _check_havoc(starter: String, follower: String) -> void:
	var ev := _havoc_day(starter, follower, false)
	assert_gt(int(state.regiments[follower]["supplies"]), _follower_before, "the follower took today")
	assert_eq(String(state.regiments[starter]["forage"]), "desperate")
	assert_eq(String(state.regiments[follower]["forage"]), "desperate")
	assert_eq(int(state.regiments[follower]["forage_days"]), 1)
	assert_eq(int(state.regiments[starter]["forage_days"]), 1)
	assert_true("forage_havoc" in _types(ev))
	assert_almost_eq(float(state.metrics["legitimacy"]), 47.0, 0.001, "charged once, for the starter")


func test_havoc_follower_takes_the_same_day_starter_first() -> void:
	_check_havoc(a, b)


func test_havoc_follower_takes_the_same_day_starter_last() -> void:
	_check_havoc(b, a)


func test_no_havoc_leaves_the_follower() -> void:
	_havoc_day(a, b, true)
	assert_eq(String(state.regiments[a]["forage"]), "desperate")
	assert_eq(String(state.regiments[b]["forage"]), "")
	assert_eq(int(state.regiments[b]["forage_days"]), 0)
