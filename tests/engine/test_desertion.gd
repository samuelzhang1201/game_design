extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const H := preload("res://tests/engine/conduct_helpers.gd")
## Desertion (spec 2026-10-10-foraging-and-desertion §3.2): the conditions held,
## the law's multiplier and the day's loss with its remainder, hand-computed.
## With desert_permille_per_day 3: rate = 3 * 100 * n * mult / 1000 per 100000.

var repo: DataRepository
var state: GameState
var code: String


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 11)
	code = H.land_unit(repo, state)
	_men(1000)
	_cond(50, 50, true)


## The unit's men set by hand: all infantry, every other arm none.
func _men(n: int) -> void:
	var row: Dictionary = state.army_roster[code]
	for arm: String in repo.world_table("military", "unit_types"):
		if row.has(arm):
			row[arm] = "0"
	row["infantry"] = str(n)


## Morale and training as given; supplies for 30 days in hand (fed) or none.
func _cond(morale: int, training: int, fed: bool) -> void:
	var reg := ArmySystem.regiment(repo, code, state)
	var entry: Dictionary = state.regiments[code]
	entry["morale"] = morale
	entry["training"] = training
	entry["supplies"] = ArmySystem.supply_use(repo, reg, state) if fed else 0
	entry["wounded"] = 0
	entry["dead"] = 0
	entry["deserted"] = 0
	entry["desert_rem"] = 0


func _law(value: String) -> void:
	state.law_in_force[LawSystem.UNIT_PREFIX + code] = {"desertion_penalty": {"value": value, "decree_id": 1}}


func test_conditions_counts_each_line() -> void:
	assert_eq(Desertion.conditions(repo, state, code), 0)
	_cond(10, 50, true)
	assert_eq(Desertion.conditions(repo, state, code), 1)
	_cond(10, 1, true)
	assert_eq(Desertion.conditions(repo, state, code), 2)
	_cond(10, 1, false)
	assert_eq(Desertion.conditions(repo, state, code), 3)


func test_loss_by_conditions_and_law() -> void:
	_cond(10, 50, true)
	_law("fine")
	assert_eq(Desertion.multiplier_permille(repo, state, code), 1000)
	assert_eq(Desertion.daily_loss(repo, state, code), 3)
	assert_eq(int(state.regiments[code]["deserted"]), 3)
	_cond(10, 1, true)
	_men(1000)
	_law("lenient")
	assert_eq(Desertion.multiplier_permille(repo, state, code), 2000)
	assert_eq(Desertion.daily_loss(repo, state, code), 12)
	_cond(10, 1, false)
	_law("hanging")
	assert_eq(Desertion.multiplier_permille(repo, state, code), 400)
	assert_eq(Desertion.daily_loss(repo, state, code), 3)
	assert_eq(int(state.regiments[code]["desert_rem"]), 60000)


func test_small_unit_remainder() -> void:
	_men(100)
	_cond(10, 50, true)
	_law("fine")
	var rems := [30000, 60000, 90000]
	for i in 3:
		assert_eq(Desertion.daily_loss(repo, state, code), 0)
		assert_eq(int(state.regiments[code]["desert_rem"]), rems[i])
	assert_eq(Desertion.daily_loss(repo, state, code), 1)
	assert_eq(int(state.regiments[code]["desert_rem"]), 20000)
	assert_eq(int(state.regiments[code]["deserted"]), 1)


func test_no_fit_men() -> void:
	_cond(10, 1, false)
	state.regiments[code]["wounded"] = 1000
	_law("lenient")
	assert_eq(Desertion.daily_loss(repo, state, code), 0)
	assert_eq(int(state.regiments[code]["deserted"]), 0)
	assert_eq(int(state.regiments[code]["desert_rem"]), 0)
	# many days at a huge rate never desert more than the fit men
	state.regiments[code]["wounded"] = 0
	_men(10)
	repo.balance["desert_permille_per_day"] = 1000.0
	for i in 5:
		Desertion.daily_loss(repo, state, code)
	assert_lte(int(state.regiments[code]["deserted"]), 10)
	assert_eq(ArmySystem.fit_heads(10, state.regiments[code]), 10 - int(state.regiments[code]["deserted"]))


func test_fleet_untouched() -> void:
	var fleet := ""
	for c: String in state.regiments.keys():
		if String(ArmySystem.regiment(repo, c, state).get("is_naval", "0")) == "1":
			fleet = c
			break
	if fleet == "":
		pass_test("this pack has no fleet to test")
		return
	var entry: Dictionary = state.regiments[fleet]
	entry["morale"] = 0
	entry["training"] = 0
	entry["supplies"] = 0
	entry["deserted"] = 0
	entry["desert_rem"] = 0
	assert_eq(Desertion.daily_loss(repo, state, fleet), 0)
	assert_eq(int(entry["deserted"]), 0)
	assert_eq(int(entry["desert_rem"]), 0)
