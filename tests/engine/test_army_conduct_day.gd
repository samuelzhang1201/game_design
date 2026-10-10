extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
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
		e["deserted"] = 0
		e["desert_rem"] = 0
		e["wounded"] = 0
		e["dead"] = 0


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
	_men(a, 100000)
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
	# 100000 fit men, 3 lines x 3 per mille x 1000 / 1000 = 900 per 100000 per day... a lost > 0
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
		gone.append(int(state.regiments[a]["deserted"]))
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
	while ArmySystem.fit_heads(10, state.regiments[a]) > 0 and guard < 4000:
		state.day = 1 + guard % 29
		ArmyConduct.day_step(repo, state)
		guard += 1
	assert_lt(guard, 4000)
	assert_eq(int(state.regiments[a]["deserted"]), 10)
	assert_eq(ArmySystem.fit_heads(10, state.regiments[a]), 0)
	assert_eq(int(state.regiments[a]["desert_rem"]), 0)
	var snap: Dictionary = (state.regiments[a] as Dictionary).duplicate(true)
	state.day = 3
	var ev := ArmyConduct.day_step(repo, state)
	assert_eq(state.regiments[a], snap)
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
	state.foes["foe_x"] = {"morale": 0, "training": 0, "supplies": 0, "forage": "", "deserted": 0,
		"x_m": state.regiments[a]["x_m"], "y_m": state.regiments[a]["y_m"]}
	var fleet_before: Dictionary = (state.regiments.get(fleet, {}) as Dictionary).duplicate(true)
	var foes_before: Dictionary = state.foes.duplicate(true)
	ArmyConduct.day_step(repo, state)
	assert_eq(state.foes, foes_before)
	if fleet != "":
		assert_eq(state.regiments[fleet], fleet_before)


func test_month_end_settles_on_day_30() -> void:
	_place(a, home)
	_men(a, 1000)
	_put(a, 30, 90, 90)
	state.regiments[a]["morale"] = 50
	state.regiments[a]["training"] = 10
	state.regiments[a]["forage_days"] = 30
	state.day = 29
	ArmyConduct.day_step(repo, state)
	assert_eq(int(state.regiments[a]["morale"]), 50)
	assert_eq(int(state.regiments[a]["wounded"]), 0)
	assert_eq(int(state.regiments[a]["forage_days"]), 30)
	state.day = 30
	ArmyConduct.day_step(repo, state)
	assert_eq(int(state.regiments[a]["morale"]), 54, "50 + 4 x 30 / 30")
	assert_eq(int(state.regiments[a]["training"]), 7, "10 - 3")
	assert_eq(int(state.regiments[a]["wounded"]), 10, "1000 x 10 x 30 / 30000")
	assert_eq(int(state.regiments[a]["forage_days"]), 0)


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


func test_twenty_four_months_twice_identical() -> void:
	pending("needs Task 8: day_step is wired into TickEngine there")
	var runs: Array = []
	for i in range(2):
		var s := SuiteData.campaign(repo, 11)
		var engine := TickEngine.new(repo)
		for m in range(24):
			for d in range(Calendar.DAYS_PER_TICK - 1):
				engine.advance_day(s)
			engine.advance(s)
		runs.append(JSON.stringify([s.regiments, s.forage_stripped, s.grievance, s.conduct_marks]))
	assert_eq(runs[0], runs[1])
