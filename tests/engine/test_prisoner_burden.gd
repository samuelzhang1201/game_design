extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var repo: DataRepository
var state: GameState
var code: String

func before_each() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	state = SuiteData.campaign(repo, 7)
	var codes := state.regiments.keys()
	codes.sort()
	for candidate: String in codes:
		if not ArmySystem.is_naval(repo, state, candidate):
			code = candidate
			break
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_rosters[code] = {"cohort_ids": ["burden_commoner", "burden_noble"]}
	state.military_cohorts["burden_commoner"] = {"identity": "commoner", "unit_code": code,
		"stage": "active", "fit": 90, "wounded": 0}
	state.military_cohorts["burden_noble"] = {"identity": "noble", "unit_code": code,
		"stage": "active", "fit": 10, "wounded": 0}
	repo.balance["army_supply_per_head_permille"] = 100
	repo.balance["prisoner_guard_permille"] = 100
	repo.balance["prisoner_load_permille"] = 250
	state.regiments[code]["supplies"] = 100000
	state.regiments[code].erase("camp_state")

func _hold(commoners: int = 50, nobles: int = 10, wounded: int = 20) -> void:
	state.set("prisoner_batches", {"burden": {"id": "burden", "holder_code": code,
		"commoners": commoners, "nobles": nobles, "wounded_subset": wounded, "disposition": "held"}})

func test_food_weights_count_captive_wounds_once_and_follow_current_holder() -> void:
	var reg := ArmySystem.regiment(repo, code, state)
	assert_eq(ArmySystem.supply_use(repo, reg, state), 12)
	_hold()
	assert_eq(ArmySystem.supply_use(repo, reg, state), 20, "120 own + 80 captive weighted heads")
	var batches: Dictionary = state.get("prisoner_batches")
	batches["burden"]["wounded_subset"] = 0
	assert_eq(ArmySystem.supply_use(repo, reg, state), 20)
	batches["burden"]["holder_code"] = "successor"
	assert_eq(ArmySystem.supply_use(repo, reg, state), 12)
	assert_eq(PrisonerBurden.supply_milli(repo, state, "successor"), 80000)

func test_guards_reduce_both_combat_reads_without_changing_personnel_or_wages() -> void:
	var before := state.military_cohorts.duplicate(true)
	var wages := int(MilitaryQuality.profile(repo, state, code)["monthly_wages"])
	var strength := int(BattleStrength.unit(repo, state, code, true)["power"])
	var old_power := ArmySystem.power(repo, state, code, "attack")
	_hold()
	assert_lt(int(BattleStrength.unit(repo, state, code, true)["power"]), strength)
	assert_lt(ArmySystem.power(repo, state, code, "attack"), old_power)
	assert_eq(state.military_cohorts, before)
	assert_eq(ArmySystem.fit_count(repo, state, code), 100)
	assert_eq(int(MilitaryQuality.profile(repo, state, code)["monthly_wages"]), wages)

func test_prisoner_load_slows_actual_step_speed_and_forecast() -> void:
	var step := ArmySystem.day_step_m(repo, state, code)
	var speed := ArmySystem.speed_km_per_day(repo, state, code)
	var from := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code, state))
	var to := from + ArmySystem.metres_to_pack(repo, Vector2i(300000, 0))
	var days := ArmySystem.march_days_between(repo, state, code, from, to)
	_hold(1000, 0, 0)
	assert_lt(ArmySystem.day_step_m(repo, state, code), step)
	assert_lt(ArmySystem.speed_km_per_day(repo, state, code), speed)
	assert_gt(ArmySystem.march_days_between(repo, state, code, from, to), days)

func test_hand_computed_guard_ceiling_cap_and_pace() -> void:
	state.military_cohorts["burden_commoner"]["wounded"] = 20
	_hold()
	assert_eq(PrisonerBurden.supply_milli(repo, state, code), 80000)
	assert_eq(PrisonerBurden.guard_count(repo, state, code), 6)
	assert_eq(PrisonerBurden.pace_permille(repo, state, code), 888)
	_hold(51, 10, 20)
	assert_eq(PrisonerBurden.guard_count(repo, state, code), 7, "61 prisoners need seven guards")
	state.military_cohorts["burden_commoner"]["fit"] = 3
	state.military_cohorts["burden_noble"]["fit"] = 0
	assert_eq(PrisonerBurden.guard_count(repo, state, code), 3)
	var bonus: Array[Dictionary] = [{"category": "action", "source": "guard_test:bonus",
		"permille": 3000, "reason": "An action bonus cannot create combatants from guards"}]
	assert_eq(int(BattleStrength.unit(repo, state, code, true, bonus)["power"]), 0)
	assert_eq(ArmySystem.power(repo, state, code, "attack"), 0)
	assert_eq(ArmySystem.fit_count(repo, state, code), 3)

func test_empty_or_released_custody_has_no_burden() -> void:
	assert_eq(PrisonerBurden.pace_permille(repo, state, code), 1000)
	_hold()
	var batches: Dictionary = state.get("prisoner_batches")
	batches["burden"]["disposition"] = "released"
	assert_eq(PrisonerBurden.supply_milli(repo, state, code), 0)
	assert_eq(PrisonerBurden.guard_count(repo, state, code), 0)
	assert_eq(PrisonerBurden.pace_permille(repo, state, code), 1000)
	state.military_cohorts.clear()
	state.military_rosters.clear()
	assert_eq(PrisonerBurden.pace_permille(repo, state, code), 0)

func test_own_and_captive_food_round_once_together() -> void:
	state.military_cohorts["burden_commoner"]["fit"] = 1
	state.military_cohorts["burden_commoner"]["dead"] = 900
	state.military_cohorts["burden_noble"]["fit"] = 0
	repo.balance["army_supply_per_head_permille"] = 500
	_hold(1, 0, 1)
	assert_eq(ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code, state), state), 1,
		"Two half-unit rations become one; dead personnel eat nothing")

func test_null_state_previews_have_no_custody_burden() -> void:
	assert_eq(PrisonerBurden.supply_milli(repo, null, code), 0)
	assert_eq(PrisonerBurden.guard_count(repo, null, code), 0)
	assert_eq(PrisonerBurden.pace_permille(repo, null, code), 1000)
