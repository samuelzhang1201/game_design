extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Play := preload("res://tests/invasion_play.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")

var _old_data: DataRepository
var _old_maker: Callable

func before_each() -> void:
	_old_data = Game.data
	_old_maker = Game.campaign_maker

func after_each() -> void:
	Game.campaign_maker = _old_maker
	Game.restart()
	Game.data = _old_data

func test_rejected_campaign_preserves_the_existing_reign() -> void:
	Game.restart()
	Game.data = SuiteData.repo()
	Game.state = SuiteData.campaign(Game.data, 42)
	var previous: GameState = Game.state
	Game.campaign_maker = GameState.new_campaign
	Game.data.balance["army_split_cap_men"] = 0
	ArmySplit.forget()
	assert_eq(Game.call("start_campaign", 44), false)
	assert_same(Game.state, previous, "an invalid army configuration must not replace the current campaign")
	assert_false(Game.load_error.is_empty(), "player can see why creation failed")

func test_loading_legacy_siege_checks_actual_deployment_without_replaying_day() -> void:
	Game.restart()
	Game.data = SuiteData.repo()
	var state := SuiteData.campaign(Game.data, 42)
	var host := Play.host(Game.data, "main")
	var town := TownStores.depot(Game.data, state)
	var at := Play.town_m(Game.data, town)
	var units := EnemyAi.live_regiments(Game.data, state, host)
	for i: int in units.size():
		Play.place(Game.data, state, units[i], at + Vector2i(100000 + i * 5000, 0), ArmySystem.ORDER_STANDBY)
	var mind: Dictionary = state.ai_hosts[host]
	mind["mode"] = "SIEGE"
	mind["target_kind"] = "town"
	mind["target_id"] = town
	mind["siege_progress"] = 250
	mind["siege_days"] = 4
	mind["assault"] = 1
	mind.erase("deployment")
	state.day_resolution = DayResolution.begin(state.day, false)
	state.day_resolution.erase("protocol_version")
	state.day_resolution.erase("substep_protocol_version")
	state.day_resolution["phase"] = "battles"
	state.day_resolution["journal"]["battles"] = [{"kind": "round", "battle_id": 99}]
	var journal := state.day_resolution.duplicate(true)
	var before_foes := state.foes.duplicate(true)
	var path := "user://battle_deployment_load_test.json"
	assert_true(SaveLoad.save_game(state, path))
	var loaded := Game.load_campaign(path)
	assert_true(loaded, Game.load_error)
	if not loaded:
		return
	assert_eq(Game.state.ai_hosts[host]["mode"], "DEPLOYING")
	assert_eq(int(Game.state.ai_hosts[host]["siege_progress"]), 250)
	assert_eq(int(Game.state.ai_hosts[host]["siege_days"]), 4)
	assert_eq(int(Game.state.ai_hosts[host]["assault"]), 0)
	assert_eq(Game.state.foes, before_foes, "loading does not move or feed columns")
	assert_eq(Game.state.day_resolution, journal, "completed daily work is not replayed")
	assert_eq(Game.state.day, state.day)
	assert_true(Game.save_campaign(path))
	var normalized := SaveLoad.state_hash(Game.state)
	assert_true(Game.load_campaign(path))
	assert_eq(SaveLoad.state_hash(Game.state), normalized, "migration applies once")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_unknown_day_protocol_refuses_before_ui_journal_write() -> void:
	Game.restart()
	Game.data = SuiteData.repo()
	Game.state = SuiteData.campaign(Game.data, 42)
	Game.engine = TickEngine.new(Game.data)
	Game.state.day_resolution = DayResolution.begin(Game.state.day, false)
	Game.state.day_resolution["protocol_version"] = 999
	Game.set_clock_speed(4)
	var before := SaveLoad.state_hash(Game.state)
	var result := Game.advance_day()
	assert_eq(result.get("status", ""), "error")
	assert_eq(Game.clock_speed, 0)
	assert_eq(SaveLoad.state_hash(Game.state), before, "the UI cannot annotate an unsupported transaction")

func test_failed_personnel_round_pauses_clock_and_preserves_transaction() -> void:
	Game.restart()
	Game.data = SuiteData.no_clearance(SuiteData.open_country(SuiteData.repo()))
	Game.state = Scenario.contact(Game.data, 10)
	Game.engine = TickEngine.new(Game.data)
	Game.data.battle_events.clear()
	BattleSystem.detect_contacts(Game.data, Game.state)
	var battle: Dictionary = Game.state.battles[0]
	battle["actions"] = {"att": {"kind": "attack"}, "def": {"kind": "hold"}}
	for entry: Dictionary in Game.state.regiments.values() + Game.state.foes.values():
		entry["morale"] = 80
		entry["supplies"] = 10000
	var defender := String(battle["def"][0])
	var cohort := String(Game.state.military_rosters[defender]["cohort_ids"][0])
	Game.state.military_cohorts[cohort]["source_population_field"] = "invalid"
	var attacker := String(battle["att"][0])
	# This injected write failure needs melee damage, independent of ranged reach.
	var fit := ArmySystem.fit_count(Game.data, Game.state, attacker)
	for arm: String in Game.data.world_table("military", "unit_types"):
		Game.state.army_roster[attacker][arm] = "0"
	Game.state.army_roster[attacker]["infantry"] = str(fit)
	var food := int(BattleSystem._stored(Game.state, attacker)["supplies"])
	Game.state.day_resolution = DayResolution.begin(Game.state.absolute_day(), false)
	Game.state.day_resolution["phase"] = "FIXED_TACTICAL_SUBSTEPS"
	Game.state.day_resolution["phase_cursor"] = DayResolution.PHASES.find("FIXED_TACTICAL_SUBSTEPS")
	Game.state.day_resolution["battle_step"] = "fighting"
	Game.state.day_resolution["battle_ids"] = [int(battle["id"])]
	Game.state.day_resolution["acknowledged_encounters"] = [int(battle["id"])]
	assert_true(DayResolution.incompatibility_reason(Game.state.day_resolution).is_empty(), "the fixture must reach personnel validation")
	Game.set_clock_speed(4)
	var day := Game.state.absolute_day()
	var out := Game.advance_day()
	assert_eq(out.get("status", ""), "error")
	assert_eq(Game.clock_speed, 0)
	assert_eq(Game.state.absolute_day(), day)
	assert_eq(int(Game.state.day_resolution.get("battle_index", -1)), 0)
	assert_eq(int(battle["rounds"]), 0)
	assert_eq(int(BattleSystem._stored(Game.state, attacker)["supplies"]), food)
	assert_false(String(out.get("error", "")).is_empty())

func test_failed_legacy_personnel_import_does_not_replace_current_reign() -> void:
	Game.restart()
	Game.data = SuiteData.repo()
	Game.state = SuiteData.campaign(Game.data, 42)
	var previous: GameState = Game.state
	var old_save := SuiteData.campaign(Game.data, 43)
	old_save.military_rosters.clear()
	old_save.military_cohorts.clear()
	old_save.military_events.clear()
	old_save.military_migration.clear()
	var code := old_save.army_roster.keys()[0] as String
	old_save.army_roster[code]["source_parts"] = [{"province_code": "missing-origin", "arm": "infantry", "equipment_count": 1, "crew_per_element": 1}]
	var path := "user://invalid_personnel_import.json"
	assert_true(SaveLoad.save_game(old_save, path))
	assert_false(Game.load_campaign(path))
	assert_same(Game.state, previous)
	assert_false(Game.load_error.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
