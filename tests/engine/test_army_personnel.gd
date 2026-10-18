extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")
var repo: DataRepository
var state: GameState
var code: String
var province: String

func before_each() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
	state = SuiteData.campaign(repo, 7)
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_events.clear()
	state.military_migration.clear()
	state.conduct_marks.clear()
	state.tick = 2
	state.day = 1
	var codes := state.regiments.keys()
	codes.sort()
	for c: String in codes:
		if String(ArmySystem.regiment(repo, c, state).get("is_naval", "0")) != "1":
			code = c
			break
	var row: Dictionary = state.army_roster[code]
	for arm: String in repo.world_table("military", "unit_types"):
		row[arm] = "0"
	row["infantry"] = "100"
	repo.world_table("military", "unit_types")["infantry"]["crew"] = "1"
	province = MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm"))[0]
	state.world["economy.provinces.%s.rural_population" % province] = 10000
	repo.balance["recruitment_eligible_permille"] = 1000
	repo.balance["army_supply_per_head_permille"] = 1000
	repo.balance["army_training_base_permille"] = 1000
	repo.balance["army_training_step_permille"] = 0
	repo.balance["army_morale_base_permille"] = 1000
	repo.balance["army_morale_step_permille"] = 0
	repo.army_matchups.clear()
	repo.army_terrain.clear()
	repo.army_town_defence.clear()
	_mobilize(code, 100)

func _mobilize(unit: String, count: int) -> void:
	var result := Roster.mobilize(repo, state, "raise:" + unit, [{"id": "cohort:" + unit, "unit_code": unit,
		"source_province": province, "source_population_field": "rural_population", "identity": "commoner",
		"family_name": "", "stage": "active", "count": count}], "Test enlistment")
	assert_false(result.has("error"), str(result))

func _move(id: String, from_status: String, to_status: String, count: int, unit := "") -> void:
	var result := Roster.transfer_units(repo, state, id, [{"unit_code": code if unit == "" else unit,
		"from": from_status, "to": to_status, "count": count}], "Test personnel transfer")
	assert_false(result.has("error"), str(result))

func test_crew_capacity_does_not_multiply_full_strength_equipment_power() -> void:
	var types := repo.world_table("military", "unit_types")
	types["fleet"]["crew"] = "100"
	types["artillery"]["crew"] = "8"
	assert_eq(ArmySystem.headcount(repo, {"fleet": 1}), 100)
	assert_eq(ArmySystem.headcount(repo, {"artillery": 2}), 16)
	assert_eq(ArmySystem.power_of_arms(repo, {"fleet": 10}, 1000, 0, 0, "attack", "", ""), 10)
	assert_eq(ArmySystem.power_of_arms(repo, {"fleet": 10}, 500, 0, 0, "attack", "", ""), 5)
	assert_eq(ArmySystem.power_of_arms(repo, {"artillery": 2}, 16, 0, 0, "attack", "", ""), 2)
	assert_eq(ArmySystem.power_of_arms(repo, {"artillery": 2}, 8, 0, 0, "attack", "", ""), 1)

func test_personnel_losses_change_power_and_food_without_changing_equipment() -> void:
	var equipment: Dictionary = state.army_roster[code].duplicate(true)
	_move("wound", "fit", "wounded", 20)
	_move("death", "fit", "dead", 10)
	_move("capture", "fit", "captured_current", 10)
	_move("release", "fit", "released", 10)
	assert_eq(ArmySystem.power_on(repo, state, code, "attack", "", ""), 50)
	assert_eq(ArmySystem.fit_permille(repo, state, code), 500)
	assert_eq(ArmySystem.supply_use(repo, state.army_roster[code], state), 70, "50 fit and 20 wounded still eat monthly supplies")
	assert_eq(state.army_roster[code], equipment)
	state.regiments[code]["dead"] = 99
	state.regiments[code]["wounded"] = 99
	state.regiments[code]["deserted"] = 99
	assert_eq(ArmySystem.power_on(repo, state, code, "attack", "", ""), 50, "legacy counters cannot override the ledger")

func test_a_live_state_missing_personnel_fails_closed() -> void:
	state.military_rosters.erase(code)
	assert_eq(ArmySystem.power_on(repo, state, code, "attack", "", ""), 0)
	assert_eq(ArmySystem.supply_use(repo, state.army_roster[code], state), 0)
	assert_eq(ArmySystem.supply_use(repo, state.army_roster[code]), 100, "null state is an explicit full-capacity preview")

func test_monthly_recovery_includes_undeployed_units_and_is_once_after_json() -> void:
	var idle := "idle_reserve"
	state.army_roster[idle] = state.army_roster[code].duplicate(true)
	state.army_roster[idle]["regiment_code"] = idle
	state.army_roster[idle]["kingdom_code"] = repo.resolve_realm("raider_realm")
	_mobilize(idle, 100)
	_move("wounds_home", "fit", "wounded", 40)
	_move("wounds_idle", "fit", "wounded", 20, idle)
	repo.balance["army_wound_recovery_permille"] = 250
	ArmySystem.settle_month(repo, state)
	assert_eq(ArmySystem.wounded_count(repo, state, code), 30)
	assert_eq(ArmySystem.wounded_count(repo, state, idle), 15)
	assert_eq(ArmySystem.fit_count(repo, state, idle), 85)
	assert_false(state.regiments.has(idle))
	assert_false(state.foes.has(idle))
	var before := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	ArmySystem.settle_month(repo, state)
	assert_eq(SaveLoad.state_hash(state), before)
	state.tick += 1
	ArmySystem.settle_month(repo, state)
	assert_eq(ArmySystem.wounded_count(repo, state, code), 23)
	assert_eq(ArmySystem.wounded_count(repo, state, idle), 12)

func test_zero_recovery_still_consumes_this_month_for_an_idle_unit() -> void:
	var idle := "idle_reserve"
	_mobilize(idle, 100)
	ArmySystem.settle_month(repo, state)
	_move("later_wounds", "fit", "wounded", 20, idle)
	var before := SaveLoad.state_hash(state)
	ArmySystem.settle_month(repo, state)
	assert_eq(ArmySystem.wounded_count(repo, state, idle), 20)
	assert_eq(SaveLoad.state_hash(state), before)

func test_hazards_transfer_fit_people_once_and_preserve_legacy_counters() -> void:
	state.hazards.clear()
	var reg := ArmySystem.regiment(repo, code, state)
	var cell := MapEconomy.cell_at(repo, ArmySystem.position_of(repo, state, reg))
	assert_gte(cell, 0)
	repo.hazard_kinds["personnel_hazard"] = {"wounds_permille": 100, "morale": -5, "public": true}
	Hazards.add(state, "personnel_hazard", "personnel_hazard", "Test hazard", [cell], state.tick, -1, "fixture")
	state.regiments[code]["morale"] = 60
	state.regiments[code]["wounded"] = 777
	Hazards.settle_regiments(repo, state)
	assert_eq(ArmySystem.fit_count(repo, state, code), 90)
	assert_eq(ArmySystem.wounded_count(repo, state, code), 10)
	assert_eq(int(state.regiments[code]["morale"]), 55)
	assert_eq(int(state.regiments[code]["wounded"]), 777, "legacy personnel counters are not written")
	var before := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	assert_true(Hazards.settle_regiments(repo, state).is_empty())
	assert_eq(SaveLoad.state_hash(state), before)

func test_foraging_wounds_use_the_same_ledger_without_changing_population() -> void:
	repo.balance["forage_harass_permille"] = 200
	state.regiments[code]["forage_days"] = 15
	state.regiments[code]["wounded"] = 777
	var people: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.rural_population" % province)
	ArmyConduct.settle_units(repo, state)
	assert_eq(ArmySystem.fit_count(repo, state, code), 90)
	assert_eq(ArmySystem.wounded_count(repo, state, code), 10, "100 * 200/1000 * 15/30")
	assert_eq(ArmySystem.living_count(repo, state, code), 100)
	assert_eq(int(state.regiments[code]["wounded"]), 777)
	assert_eq(WorldLedger.value_of(repo, state, "economy.provinces.%s.rural_population" % province), people)
	var before := SaveLoad.state_hash(state)
	ArmyConduct.settle_units(repo, state)
	assert_eq(SaveLoad.state_hash(state), before)

func test_desertion_fraction_and_releases_are_consumed_once_per_day() -> void:
	repo.balance["desert_permille_per_day"] = 1
	repo.balance["desert_morale"] = 101
	repo.balance["desert_training"] = 101
	repo.balance["desert_supply_days"] = 100
	for law: String in ["fine", "lenient", "hanging"]:
		repo.balance["desert_mult_" + law] = 1000
	state.regiments[code]["supplies"] = 0
	state.regiments[code]["deserted"] = 777
	var available := MilitaryPopulation.available(repo, state, province, "rural_population")
	assert_eq(Desertion.daily_loss(repo, state, code), 0)
	assert_eq(int(state.regiments[code].get("desert_rem", 0)), 30000)
	var before := SaveLoad.state_hash(state)
	assert_eq(Desertion.daily_loss(repo, state, code), 0)
	assert_eq(SaveLoad.state_hash(state), before, "zero-loss retries must not accumulate the fraction again")
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	for d in [2, 3]:
		state.day = d
		assert_eq(Desertion.daily_loss(repo, state, code), 0)
	state.day = 4
	assert_eq(Desertion.daily_loss(repo, state, code), 1)
	assert_eq(ArmySystem.fit_count(repo, state, code), 99)
	assert_eq(MilitaryPopulation.available(repo, state, province, "rural_population"), available + 1)
	assert_eq(int(state.regiments[code]["deserted"]), 777)
	before = SaveLoad.state_hash(state)
	assert_eq(Desertion.daily_loss(repo, state, code), 0)
	assert_eq(SaveLoad.state_hash(state), before)

func test_clearance_preview_stops_blocking_when_the_ledger_has_no_living_people() -> void:
	assert_true((ArmySystem._ahead_blockers(repo, state)["codes"] as Array).has(code))
	_move("destroyed", "fit", "dead", 100)
	assert_false((ArmySystem.clearance_blockers(repo, state)["codes"] as Array).has(code))
	assert_false((ArmySystem._ahead_blockers(repo, state)["codes"] as Array).has(code), "same-day preview cache must observe ledger losses")

func test_released_prisoners_do_not_count_as_desertion() -> void:
	_move("taken", "fit", "captured_current", 10)
	_move("freed", "captured_current", "released", 10)
	assert_eq(Desertion.total(state, code), 0)
	repo.balance["desert_permille_per_day"] = 100
	repo.balance["desert_morale"] = 101
	repo.balance["desert_training"] = 0
	repo.balance["desert_supply_days"] = -1
	for law: String in ["fine", "lenient", "hanging"]:
		repo.balance["desert_mult_" + law] = 1000
	assert_eq(Desertion.daily_loss(repo, state, code), 9)
	assert_eq(Desertion.total(state, code), 9)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	assert_eq(Desertion.total(state, code), 9)

func test_positive_fractional_monthly_food_keeps_the_minimum_resource_unit() -> void:
	_move("leave_nine", "fit", "released", 91)
	repo.balance["army_supply_per_head_permille"] = 100
	var reg: Dictionary = state.army_roster[code]
	assert_eq(int(ArmySystem.height_tier(repo, reg, state)["supply_permille"]), 1000)
	assert_eq(ArmySystem.supply_use(repo, reg, state), 1, "9 people x 100/1000 x 1000/1000 = 0.9: at least one monthly grain unit")
	repo.balance["army_supply_per_head_permille"] = 0
	assert_eq(ArmySystem.supply_use(repo, reg, state), 0, "explicit zero consumption stays zero")
	repo.balance["army_supply_per_head_permille"] = 100
	_move("last_nine", "fit", "released", 9)
	assert_eq(ArmySystem.supply_use(repo, reg, state), 0, "no living personnel consumes nothing")
