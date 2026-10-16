extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
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
	row["infantry"] = "600"
	repo.world_table("military", "unit_types")["infantry"]["crew"] = "1"
	province = MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm"))[0]
	state.world["economy.provinces.%s.rural_population" % province] = 10000
	repo.balance["recruitment_eligible_permille"] = 1000
	repo.balance["army_supply_per_head_permille"] = 30000
	repo.balance["army_training_base_permille"] = 1000
	repo.balance["army_training_step_permille"] = 0
	repo.balance["army_morale_base_permille"] = 1000
	repo.balance["army_morale_step_permille"] = 0
	repo.army_matchups.clear()
	repo.army_terrain.clear()
	repo.army_town_defence.clear()
	_add(code, "common", "commoner", 570)
	_add(code, "noble", "noble", 30)

func _add(unit: String, id: String, identity: String, count: int, stage := "active") -> void:
	var result := MilitaryRoster.mobilize(repo, state, "raise:" + id, [{"id": id, "unit_code": unit,
		"source_province": province, "source_population_field": "rural_population", "identity": identity,
		"family_name": "", "stage": stage, "count": count}], "Quality test enlistment")
	assert_false(result.has("error"), str(result))

func _move(id: String, cohort: String, from: String, to: String, count: int) -> void:
	var result := MilitaryRoster.transition(repo, state, id, [{"cohort_id": cohort,
		"from": from, "to": to, "count": count}], "Quality test casualty")
	assert_false(result.has("error"), str(result))

func test_full_fit_quality_and_food_are_applied_to_the_real_army() -> void:
	assert_eq(ArmySystem.power_on(repo, state, code, "attack", "", ""), 630)
	var use := ArmySystem.supply_use(repo, state.army_roster[code], state)
	assert_eq(use, 19800, "570 commoners + 30 nobles at three rations = 660 food-equivalent people")
	assert_eq(ArmySystem.day_bite(use, 1), 660)
	assert_eq(ArmySystem.supply_use(repo, state.army_roster[code]), 18000, "explicit null-state preview retains commoner capacity")

func test_living_wounded_eat_but_only_fit_nobles_grant_quality() -> void:
	_move("common_deaths", "common", "fit", "dead", 38)
	_move("noble_deaths", "noble", "fit", "dead", 2)
	_move("common_wounds", "common", "fit", "wounded", 42)
	_move("noble_wounds", "noble", "fit", "wounded", 28)
	assert_eq(ArmySystem.fit_count(repo, state, code), 490)
	assert_eq(ArmySystem.power_on(repo, state, code, "attack", "", ""), 490)
	assert_eq(ArmySystem.day_bite(ArmySystem.supply_use(repo, state.army_roster[code], state), 1), 616)

func test_monthly_wages_pay_actual_active_living_player_people_once_after_json() -> void:
	_move("noble_wounds", "noble", "fit", "wounded", 10)
	_move("common_captured", "common", "fit", "captured_current", 10)
	_move("common_released", "common", "fit", "released", 10)
	_add(code, "assembling", "noble", 100, "assembling")
	var idle := "idle_home"
	state.army_roster[idle] = state.army_roster[code].duplicate(true)
	state.army_roster[idle]["regiment_code"] = idle
	_add(idle, "idle", "commoner", 100)
	var foreign := "idle_foreign"
	state.army_roster[foreign] = state.army_roster[code].duplicate(true)
	state.army_roster[foreign]["regiment_code"] = foreign
	state.army_roster[foreign]["kingdom_code"] = repo.resolve_realm("raider_realm")
	_add(foreign, "foreign", "noble", 100)
	state.metrics["treasury"] = 1000.0
	ArmySystem.settle_month(repo, state)
	assert_eq(state.metrics["treasury"], 992.0, "(650 commoners * 10 + 30 nobles * 50) / 1000 = 8 gold")
	var found := false
	for line: Dictionary in state.world_log:
		if String(line.get("source", "")) == "military_wages:2":
			found = true
			assert_ne(String(line.get("reason", "")), "")
	assert_true(found, "wages retain a reasoned WorldLedger output")
	var before := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	ArmySystem.settle_month(repo, state)
	assert_eq(SaveLoad.state_hash(state), before)

func test_profile_counts_fit_and_living_by_identity_with_reasoned_factors() -> void:
	var quality := ArmySystem.Quality.profile(repo, state, code)
	assert_eq(quality["fit_by_identity"], {"commoner": 570, "noble": 30})
	assert_eq(quality["living_by_identity"], {"commoner": 570, "noble": 30})
	assert_eq(int(quality["power_permille"]), 1050)
	assert_eq(int(quality["discipline_permille"]), 1050)
	assert_eq(int(quality["supply_milli"]), 660000)
	assert_eq(int(quality["monthly_wages"]), 7)
	for line: Dictionary in quality["breakdown"]:
		assert_ne(String(line["reason"]), "")
	assert_eq(ArmySystem.Quality.from_counts(repo, 570, 30), quality)
	_move("noble_wounds", "noble", "fit", "wounded", 30)
	quality = ArmySystem.Quality.profile(repo, state, code)
	assert_eq(int(quality["discipline_permille"]), 1000)
	assert_eq(int(quality["power_permille"]), 1000)
	assert_eq(int(quality["supply_milli"]), 660000)
	assert_eq(int(quality["monthly_wages"]), 7)

func test_supply_rounds_only_after_identity_per_head_and_terrain_factors() -> void:
	_move("release_common", "common", "fit", "released", 569)
	_move("release_nobles", "noble", "fit", "released", 29)
	repo.noble_quality["noble"]["supply_permille"] = "1500"
	repo.balance["army_supply_per_head_permille"] = 1500
	assert_eq(ArmySystem.supply_use(repo, state.army_roster[code], state), 3, "(1000 + 1500) * 1500 * 1000 / 1e9 = 3.75, floor once")
	repo.balance["army_supply_per_head_permille"] = 100
	assert_eq(ArmySystem.supply_use(repo, state.army_roster[code], state), 1)
	repo.balance["army_supply_per_head_permille"] = 0
	assert_eq(ArmySystem.supply_use(repo, state.army_roster[code], state), 0)

func test_identity_power_does_not_multiply_ship_crews_or_artillery_crews() -> void:
	var row: Dictionary = state.army_roster[code]
	row["infantry"] = "0"
	row["fleet"] = "20"
	repo.world_table("military", "unit_types")["fleet"]["crew"] = "30"
	assert_eq(ArmySystem.power_on(repo, state, code, "attack", "", ""), 21, "20 equipment power * 1050 / 1000, never 630 crew power")
	row["fleet"] = "0"
	row["artillery"] = "20"
	repo.world_table("military", "unit_types")["artillery"]["crew"] = "30"
	assert_eq(ArmySystem.power_on(repo, state, code, "attack", "", ""), 21)

func test_zero_personnel_month_is_consumed_before_new_recruits_join() -> void:
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.metrics["treasury"] = 1000.0
	ArmySystem.settle_month(repo, state)
	_add(code, "later", "noble", 100)
	ArmySystem.settle_month(repo, state)
	assert_eq(state.metrics["treasury"], 1000.0)
	state.tick += 1
	ArmySystem.settle_month(repo, state)
	assert_eq(state.metrics["treasury"], 995.0)

func test_new_campaign_load_contains_its_live_identity_weighted_start_days() -> void:
	var opening := SuiteData.campaign(repo, 19)
	var start_days := int(repo.bal("army_start_supply_days"))
	for unit: String in opening.regiments:
		var reg := ArmySystem.regiment(repo, unit, opening)
		var use := ArmySystem.supply_use(repo, reg, opening)
		if use < Calendar.DAYS_PER_TICK:
			continue
		assert_eq(ArmySystem.days_in_hand(int(opening.regiments[unit]["supplies"]), use), start_days, unit)
		if start_days == ArmySystem.carry_of(repo, opening.regiments[unit]):
			assert_eq(ArmySystem.bars_of(repo, opening, unit).y, 1000, "opening carry load is full: " + unit)

func test_foe_spawn_load_contains_its_live_identity_weighted_start_days() -> void:
	assert_false(repo.raid_hosts.is_empty())
	var host: Dictionary = repo.raid_hosts[0]
	var opening := SuiteData.campaign(repo, 19)
	EnemyAi.spawn(repo, opening, host)
	for unit: String in EnemyAi.host_units(repo, opening, host):
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, unit, opening), opening)
		if use < Calendar.DAYS_PER_TICK:
			continue
		assert_eq(ArmySystem.days_in_hand(int(opening.foes[unit]["supplies"]), use), int(repo.bal("army_start_supply_days")), unit)
