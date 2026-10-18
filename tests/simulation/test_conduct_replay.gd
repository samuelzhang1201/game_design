extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const H := preload("res://tests/engine/conduct_helpers.gd")
## Explicit opt-in: 24-month conduct replay, twice, with the same seed.

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


func test_twenty_four_months_twice_identical() -> void:
	var runs: Array = []
	var busy := false
	for i in range(2):
		state = SuiteData.campaign(repo, 11)
		_place(a, foreign)
		state.regiments[a]["camp_town"] = ""   # in the field, no town feeds it
		_law(a, "plunder", "forbid")
		_place(b, home)
		_put(b, 30, 90, 90)
		var engine := TickEngine.new(repo)
		var run_log: Array = []
		for m in range(24):
			state.regiments[a]["supplies"] = 0
			for d in range(Calendar.DAYS_PER_TICK - 1):
				engine.advance_day(state)
			engine.advance(state)
			run_log.append(JSON.stringify([state.regiments, state.military_cohorts, state.forage_stripped, state.grievance, state.conduct_marks]))
			busy = busy or not state.forage_stripped.is_empty() or not state.conduct_marks.is_empty() \
				or int(state.regiments[a].get("forage_days", 0)) > 0
		runs.append(run_log)
	assert_true(busy, "something happened during the 24 months")
	assert_eq(runs[0], runs[1])
