extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const H := preload("res://tests/engine/conduct_helpers.gd")
## ArmyConduct taking and the month's settlement (spec
## 2026-10-10-foraging-and-desertion §3.3 steps 7-8), hand-computed from the
## balance defaults: 30 supply per food unit, summer 1000, share 1000, strip_k
## 500, recover 100, hazard line 500 (750 protected), bare 900, morale +4,
## training -3 and harass 10 per mille a month.

var repo: DataRepository
var state: GameState
var code: String
var prov: String


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 11)
	code = _biggest(H.land_units(repo, state))
	prov = H.home_province(repo, state)
	state.tick = 5
	for t in range(0, 12):
		state.tick = t
		if Forage.season_permille(repo, state) == 1000:
			break
	state.day = 1
	state.forage_stripped.clear()
	state.conduct_marks.clear()
	state.hazards.clear()
	var entry: Dictionary = state.regiments[code]
	entry["supplies"] = 0
	entry["carry_days"] = 30
	entry["forage"] = "desperate"
	entry["forage_days"] = 0
	entry["morale"] = 50
	entry["training"] = 10
	entry["wounded"] = 0


## The unit that eats the most (so its need is far over a day's take).
func _biggest(codes: Array) -> String:
	var best := ""
	var most := -1
	for c: String in codes:
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c, state), state)
		if use > most:
			most = use
			best = c
	return best


## The unit's roster row pinned to `n` infantry (so fit is exactly n).
func _men(n: int) -> void:
	var row: Dictionary = state.army_roster[code]
	for arm: String in repo.world_table("military", "unit_types"):
		if row.has(arm):
			row[arm] = "0"
	row["infantry"] = str(n)


func _law(c: String, law: String, value: String) -> void:
	var key: String = LawSystem.UNIT_PREFIX + c
	var row: Dictionary = state.law_in_force.get(key, {})
	row[law] = {"value": value, "decree_id": 1}
	state.law_in_force[key] = row


func test_take_adds_supplies_and_strips() -> void:
	H.set_food(repo, prov, 9)   # 9 x 30 x 1000/1000 = 270 a month; day 1 = 270/30 = 9
	assert_eq(Forage.day_capacity(repo, state, prov, 1), 9)
	assert_gte(Forage.need_of(repo, state, code), 60)
	var events := ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(state.regiments[code]["supplies"]), 9)
	assert_eq(int(state.regiments[code]["forage_days"]), 1)
	assert_eq(int(state.forage_stripped[prov]), 16, "9 x 500 / 270 = 16")
	assert_eq(events.size(), 0)


func test_take_never_past_the_carry_cap() -> void:
	H.set_food(repo, prov, 9)
	var entry: Dictionary = state.regiments[code]
	var reg := ArmySystem.regiment(repo, code, state)
	var cap := ArmySystem.max_units(repo, ArmySystem.supply_use(repo, reg, state))
	entry["supplies"] = cap - 2
	ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(entry["supplies"]), cap)
	assert_eq(int(entry["forage_days"]), 1)


func test_stripped_land_yields_less() -> void:
	H.set_food(repo, prov, 9)
	ArmyConduct.take_day(repo, state, prov, [code])
	state.day = 2
	# 270 x (1000-16)/1000 = 265; day 2 = 265 x 2 / 30 - 265 / 30 = 17 - 8 = 9
	assert_eq(Forage.stripped_capacity(repo, state, prov), 265)
	assert_eq(Forage.day_capacity(repo, state, prov, 2), 9)
	var before := int(state.regiments[code]["supplies"])
	ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(state.regiments[code]["supplies"]) - before, 9)
	assert_eq(int(state.forage_stripped[prov]), 32, "16 + 9 x 500 / 270")


func test_hazard_past_half_stripped() -> void:
	H.set_food(repo, prov, 90)   # 2700 a month
	# 495: 2700 x 505/1000 = 1363, day 1 = 45, strip 45 x 500 / 2700 = 8 -> 503
	state.forage_stripped[prov] = 495
	ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(state.forage_stripped[prov]), 503)
	var id := ArmyConduct.HAZARD_PREFIX + prov
	assert_true(state.hazards.has(id))
	var h: Dictionary = state.hazards[id]
	assert_eq(String(h["kind"]), "Raided")
	var months := int(Hazards.kind_of(repo, "Raided")["months"])
	assert_eq(int(h["end"]), state.tick + months)
	assert_true(Hazards.is_active(state, id))


func test_hazard_waits_for_the_protected_line() -> void:
	H.set_food(repo, prov, 90)
	_law(code, "protect_church", "on")
	# 495: day 1 = 45, x 900/1000 = 40, strip 40 x 500 / 2700 = 7 -> 502, under 750
	state.forage_stripped[prov] = 495
	ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(state.forage_stripped[prov]), 502)
	assert_false(state.hazards.has(ArmyConduct.HAZARD_PREFIX + prov))
	# 748: 2700 x 252/1000 = 680, day 1 = 22, x 900/1000 = 19, strip 19 x 500 / 2700 = 3 -> 751
	state.forage_stripped[prov] = 748
	state.regiments[code]["supplies"] = 0
	ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(state.forage_stripped[prov]), 751)
	assert_true(state.hazards.has(ArmyConduct.HAZARD_PREFIX + prov))


func test_bare_news_once_per_crossing() -> void:
	H.set_food(repo, prov, 90)
	# 899: 2700 x 101/1000 = 272, day 1 = 9, strip 9 x 500 / 2700 = 1 -> 900
	state.forage_stripped[prov] = 899
	var events := ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(state.forage_stripped[prov]), 900)
	assert_eq(events.size(), 1)
	assert_eq(String(events[0]["type"]), "stripped_bare")
	assert_eq(String(events[0]["regiment"]), code, "the last taker names the report")
	assert_eq(String(events[0]["province"]), prov)
	state.forage_stripped[prov] = 950
	state.regiments[code]["supplies"] = 0
	assert_eq(ArmyConduct.take_day(repo, state, prov, [code]).size(), 0)


func _settle_with(d: int) -> Dictionary:
	_men(1000)
	state.day = Calendar.DAYS_PER_TICK
	state.regiments[code]["forage_days"] = d
	var reg := ArmySystem.regiment(repo, code, state)
	var fit := ArmySystem.fit_heads(ArmySystem.headcount(repo, reg), state.regiments[code])
	ArmyConduct.settle_month(repo, state)
	return {"fit": fit, "entry": state.regiments[code]}


func test_month_settlement_full_month() -> void:
	var r := _settle_with(30)
	var e: Dictionary = r["entry"]
	assert_eq(int(e["morale"]), 54, "50 + 4 x 30 / 30")
	assert_eq(int(e["training"]), 7, "10 - 3 x 30 / 30")
	assert_eq(int(e["wounded"]), 10, "1000 x 10 x 30 / 30000")
	assert_eq(int(e["forage_days"]), 0)


func test_month_settlement_partial_month() -> void:
	var r := _settle_with(15)
	var e: Dictionary = r["entry"]
	assert_eq(int(e["morale"]), 52, "4 x 15 / 30 = 2")
	assert_eq(int(e["training"]), 9, "3 x 15 / 30 = 1")
	assert_eq(int(e["wounded"]), 5, "1000 x 10 x 15 / 30000")
	assert_eq(int(e["forage_days"]), 0)


func test_settle_caps_morale_and_floors_training() -> void:
	state.regiments[code]["morale"] = 99
	state.regiments[code]["training"] = 1
	var r := _settle_with(30)
	assert_eq(int(r["entry"]["morale"]), 100)
	assert_eq(int(r["entry"]["training"]), 1, "already under forage_training_floor 5: unchanged")


func test_training_loss_stops_at_the_floor() -> void:
	# ruling R7: forage_training_floor 5; 6 - 3 x 30 / 30 = 3 -> 5
	assert_eq(repo.bal("forage_training_floor"), 5.0)
	state.regiments[code]["training"] = 6
	var r := _settle_with(30)
	assert_eq(int(r["entry"]["training"]), 5)


func test_training_under_the_floor_is_kept() -> void:
	# 4 - 3 = 1, but foraging never takes it below min(4, 5) = 4
	state.regiments[code]["training"] = 4
	var r := _settle_with(30)
	assert_eq(int(r["entry"]["training"]), 4)


func test_a_day_that_takes_nothing_is_no_forage_day() -> void:
	# ruling R7: full stores take 0, so the day does not count
	H.set_food(repo, prov, 9)
	var entry: Dictionary = state.regiments[code]
	var reg := ArmySystem.regiment(repo, code, state)
	entry["supplies"] = ArmySystem.max_units(repo, ArmySystem.supply_use(repo, reg, state))
	ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(entry["forage_days"]), 0)
	# stripped bare land takes 0 too
	entry["supplies"] = 0
	state.forage_stripped[prov] = 1000
	ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(entry["supplies"]), 0)
	assert_eq(int(entry["forage_days"]), 0)


func test_settle_waits_for_the_month_end() -> void:
	state.day = 29
	state.regiments[code]["forage_days"] = 12
	state.forage_stripped[prov] = 500
	ArmyConduct.settle_month(repo, state)
	assert_eq(int(state.regiments[code]["forage_days"]), 12)
	assert_eq(int(state.forage_stripped[prov]), 500)


func test_settle_runs_after_marching_home() -> void:
	# Review Focus 1: the unit stands on home land now, forage "" - it still settles
	state.regiments[code]["forage"] = ""
	var r := _settle_with(12)
	assert_eq(int((r["entry"] as Dictionary)["morale"]), 51, "4 x 12 / 30 = 1")
	assert_eq(int((r["entry"] as Dictionary)["training"]), 9, "3 x 12 / 30 = 1")
	assert_eq(int((r["entry"] as Dictionary)["forage_days"]), 0)
	assert_eq(int((r["entry"] as Dictionary)["wounded"]), 4, "1000 x 10 x 12 / 30000")


func test_recovery_erases_zeros() -> void:
	var other := ""
	var codes: Array = repo.provinces.keys()
	codes.sort()
	for p: String in codes:
		if p != prov:
			other = p
			break
	state.forage_stripped[prov] = 100
	state.forage_stripped[other] = 950
	state.day = Calendar.DAYS_PER_TICK
	ArmyConduct.settle_month(repo, state)
	assert_false(state.forage_stripped.has(prov))
	assert_eq(int(state.forage_stripped[other]), 850)


func test_settle_drops_old_marks() -> void:
	state.conduct_marks["incident:a"] = state.tick - 1
	state.conduct_marks["incident:b"] = state.tick
	state.day = Calendar.DAYS_PER_TICK
	ArmyConduct.settle_month(repo, state)
	assert_false(state.conduct_marks.has("incident:a"))
	assert_true(state.conduct_marks.has("incident:b"))


func test_hazard_drags_the_march_too() -> void:
	# Review Focus 7: a point inside the province is slowed to the kind's pace
	ArmyConduct.lay_hazard(repo, state, prov)
	var kind_pace := int(Hazards.kind_of(repo, "Raided")["pace_permille"])
	assert_eq(kind_pace, 800)
	var cells: Array = MapManors.manors_of_province(repo, prov, state)
	assert_false(cells.is_empty())
	var at := MapTerrain.cell_center(repo, repo.cells[int(cells[0])])
	assert_eq(Hazards.at_cell(state, int(cells[0])).size(), 1)
	assert_eq(Hazards.pace_permille(repo, state, at), 800)


func test_stripping_is_floored_per_taker() -> void:
	# Two takers of equal need 100; food 11 -> monthly 330, day capacity 11, each
	# share 11 x 100 / 200 = 5. Per taker 5 x 500 / 330 = 7 (7.57), two = 14;
	# summed it would be 10 x 500 / 330 = 15.
	H.set_food(repo, prov, 11)
	var two := H.land_units(repo, state)
	var a := _biggest(two)
	two.erase(a)
	var b := _biggest(two)
	var targets: Dictionary = {}
	for c: String in [a, b]:
		state.regiments[c]["carry_days"] = 30
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c, state), state)
		targets[c] = mini(ArmySystem.max_units(repo, use), use)   # carry 30 days = a month's use
	var n := mini(int(targets[a]), int(targets[b]))   # one need for both
	assert_gte(n, 10, "needs of 10 or more: each share is cap x n / 2n = 5")
	for c: String in [a, b]:
		state.regiments[c]["supplies"] = int(targets[c]) - n
		assert_eq(Forage.need_of(repo, state, c), n)
	ArmyConduct.take_day(repo, state, prov, [a, b])
	assert_eq(int(state.regiments[a]["supplies"]), int(targets[a]) - n + 5)
	assert_eq(int(state.regiments[b]["supplies"]), int(targets[b]) - n + 5)
	assert_eq(int(state.forage_stripped[prov]), 14)


func test_hazard_laid_when_already_past_the_line() -> void:
	H.set_food(repo, prov, 90)
	state.forage_stripped[prov] = 600
	assert_false(state.hazards.has(ArmyConduct.HAZARD_PREFIX + prov))
	ArmyConduct.take_day(repo, state, prov, [code])
	assert_true(state.hazards.has(ArmyConduct.HAZARD_PREFIX + prov))


func test_bare_news_with_protect_church_on() -> void:
	H.set_food(repo, prov, 90)
	_law(code, "protect_church", "on")
	# 899: day 1 = 9, x 900/1000 = 8, strip 8 x 500 / 2700 = 1 -> 900
	state.forage_stripped[prov] = 899
	var events := ArmyConduct.take_day(repo, state, prov, [code])
	assert_eq(int(state.forage_stripped[prov]), 900)
	assert_eq(events.size(), 1)
	assert_eq(String(events[0]["type"]), "stripped_bare")
	assert_eq(String(events[0]["regiment"]), code, "the last taker names the report")
