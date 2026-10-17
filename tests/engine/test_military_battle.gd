extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")
var repo: DataRepository
var state: GameState
var origins: Array[String] = []
var tier: Dictionary

func before_each() -> void:
	repo = SuiteData.repo()
	repo.balance["recruitment_eligible_permille"] = 1000
	state = GameState.new()
	state.rng = Rng.new(42)
	state.metrics = GameState.default_metrics(repo)
	origins.assign(repo.provinces.keys().slice(0, 2))
	var realms := [repo.resolve_realm("player_realm"), repo.resolve_realm("raider_realm")]
	for i: int in 2:
		var code := "a" if i == 0 else "b"
		var count := 600 if i == 0 else 400
		var unit := {"regiment_code": code, "label": code, "kingdom_code": realms[i],
			"infantry": count, "is_naval": "0", "x": "0", "y": "0", "province_code": origins[i]}
		state.army_roster[code] = unit
		var entry := ArmySystem.starting_state(repo, unit)
		entry["morale"] = 70
		if i == 0:
			state.regiments[code] = entry
		else:
			state.foes[code] = entry
		state.world[_path(i)] = 2000
		assert_false(Roster.mobilize(repo, state, "raise:" + code, [{"id": code, "unit_code": code,
			"source_province": origins[i], "source_population_field": "rural_population", "identity": "commoner",
			"family_name": "", "stage": "active", "count": count}], "test enlistment").has("error"))
	tier = {"attacker_loss_permille": 100, "defender_loss_permille": 250,
		"wounded_share_permille": 600, "attacker_morale": -8, "defender_morale": -12}

func _path(i: int) -> String:
	return "economy.provinces.%s.rural_population" % origins[i]

func _round(id: String = "battle:1:round:1") -> Dictionary:
	var service := BattleSystem.new()
	var arguments := 0
	for method: Dictionary in service.get_method_list():
		if method["name"] == "apply_round":
			arguments = method["args"].size()
	assert_eq(arguments, 8, "battle rounds must accept a stable transaction ID")
	if arguments != 8:
		return {"error": "missing atomic round interface"}
	return service.call("apply_round", repo, state, ["a"], ["b"], tier, "battle at the ford", Callable(), id)

func test_both_sides_commit_personnel_and_origin_deaths_together() -> void:
	assert_false(_round().has("error"))
	assert_eq(Roster.fit(state, "a"), 540)
	assert_eq(Roster.fit(state, "b"), 300)
	assert_eq(int(state.military_cohorts["a"]["wounded"]), 36)
	assert_eq(int(state.military_cohorts["a"]["dead"]), 24)
	assert_eq(int(state.military_cohorts["b"]["wounded"]), 60)
	assert_eq(int(state.military_cohorts["b"]["dead"]), 40)
	assert_eq(int(WorldLedger.value_of(repo, state, _path(0))), 1976)
	assert_eq(int(WorldLedger.value_of(repo, state, _path(1))), 1960)
	assert_eq(int(state.regiments["a"]["morale"]), 62)
	assert_eq(int(state.foes["b"]["morale"]), 58)
	assert_eq(int(state.regiments["a"].get("dead", 0)), 0, "legacy state is not a second writable casualty ledger")

func test_defender_population_failure_changes_neither_side() -> void:
	state.world[_path(1)] = 399
	var before := SaveLoad.state_hash(state)
	assert_true(_round().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_same_round_after_json_does_not_replan_losses_or_repeat_morale() -> void:
	var first := _round()
	assert_false(first.has("error"))
	var before := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(_round(), first)
	assert_eq(SaveLoad.state_hash(state), before)
	tier["attacker_loss_permille"] = 200
	assert_true(_round().has("error"), "a consumed round cannot be reused for a different outcome")
	assert_eq(SaveLoad.state_hash(state), before)

func test_zero_loss_round_records_morale_once() -> void:
	tier["attacker_loss_permille"] = 0
	tier["defender_loss_permille"] = 0
	assert_false(_round().has("error"))
	assert_eq(int(state.regiments["a"]["morale"]), 62)
	assert_eq(Roster.fit(state, "a"), 600)
	var before := SaveLoad.state_hash(state)
	assert_false(_round().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_failed_round_keeps_day_transaction_at_same_battle() -> void:
	state.world[_path(1)] = 399
	tier["tier"] = "draw"
	tier["eff_min"] = 0
	tier["eff_max"] = 1000
	tier["rout"] = "none"
	repo.battle_outcomes = [tier]
	state.battles = [{"id": 1, "att": ["a"], "def": ["b"], "rounds": 0,
		"town": "", "place_x_m": 0, "place_y_m": 0, "start_day": state.absolute_day(),
		"actions": {"att": {"kind": "attack"}, "def": {"kind": "hold"}}}]
	state.day_resolution = DayResolution.begin(state.absolute_day(), false)
	state.day_resolution["phase"] = "battles"
	state.day_resolution["battle_ids"] = [1]
	state.day_resolution["journal"]["missive_start"] = state.next_missive_id
	var before := GameState.from_dict(state.to_dict())
	var result := TickEngine.new(repo).resolve_day(state)
	assert_eq(result["status"], "error")
	assert_eq(int(state.battles[0]["rounds"]), 0)
	assert_eq(state.day_resolution, before.day_resolution, "failed commit cannot advance the day cursor")
	assert_eq(state.day, int(before.day))
	assert_eq(state.military_cohorts, before.military_cohorts)
	assert_eq(state.metrics, before.metrics)
	assert_eq(state.world, before.world)
	assert_true(state.battles[0].has("pending_round"), "the failed round retains its one saved RNG draw")
	var held := SaveLoad.state_hash(state)
	assert_eq(TickEngine.new(repo).resolve_day(state)["status"], "error")
	assert_eq(SaveLoad.state_hash(state), held, "retry draws and charges nothing")

func test_visible_unit_readers_use_survivors_and_wounds_from_cohorts() -> void:
	assert_false(_round().has("error"))
	var card := MapObjects.army_card(repo, "a", state)
	var card_count := ""
	for row: Array in card["fields"]:
		if row[0] == "Under arms":
			card_count = row[1]
	assert_eq(card_count, "576")
	var brief := WarFolio.brief(repo, state, "a")
	var brief_count := ""
	for row: Dictionary in brief["rows"]:
		if row["label"] == "Under arms":
			brief_count = row["text"]
	assert_eq(brief_count, "576 · 540 fit")
	var slip := WarPieceSlip.reading(repo, state, ["a"])
	assert_eq(int(slip[0]["heads"]), 576)
	assert_eq(int(slip[0]["fit"]), 540)

func test_defeated_foreign_column_cannot_fight_from_legacy_full_strength() -> void:
	state.foes["b"]["host"] = "test_host"
	assert_false(Roster.transfer_units(repo, state, "all-wounded", [{"unit_code": "b", "from": "fit", "to": "wounded", "count": 400}], "incapacitated").has("error"))
	assert_false(BattleSystem._can_fight(repo, state, "b"))
	assert_eq(EnemyAi.live_regiments(repo, state, "test_host"), [])
