extends GutTest

func test_clause_agreements_are_independent() -> void:
	var rules: GDScript = load("res://scripts/engine/battle_rules.gd")
	assert_not_null(rules, "battle rules exist")
	if rules == null:
		return
	var result: Dictionary = rules.negotiate(
		{"herald_safety": "protect", "noble_ransom": "allow", "surrender": "accept"},
		{"herald_safety": "protect", "noble_ransom": "deny", "surrender": "accept"})
	assert_eq(result["agreed"], {"herald_safety": "protect", "surrender": "accept"})
	assert_true(result["rejected"].has("noble_ransom"))

func test_conditions_must_match_in_full() -> void:
	var rules: GDScript = load("res://scripts/engine/battle_rules.gd")
	if rules == null:
		return
	var ours := {"wounded": {"policy": "protect", "until_day": 6, "scope": "wounded"}}
	var theirs := {"wounded": {"policy": "protect", "until_day": 7, "scope": "wounded"}}
	var result: Dictionary = rules.negotiate(ours, theirs)
	assert_true(result["agreed"].is_empty())
	assert_eq(result["rejected"]["wounded"]["ours"], ours["wounded"])
	assert_eq(result["rejected"]["wounded"]["theirs"], theirs["wounded"])
	assert_ne(result["rejected"]["wounded"]["reason"], "")

const SuiteData := preload("res://tests/suite_data.gd")

func _battle(repo: DataRepository, state: GameState) -> Dictionary:
	var mine := state.regiments.keys()
	mine.sort()
	var enemies := state.foes.keys()
	enemies.sort()
	var battle := {"id": 999, "att": [mine[0]], "def": [enemies[0]], "rounds": 0,
		"place_x_m": 0, "place_y_m": 0, "town": ""}
	state.battles.append(battle)
	return battle

func test_agreement_snapshot_survives_changes() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 88)
	var battle := _battle(repo, state)
	var code := String(battle["att"][0])
	state.law_in_force["unit:" + code] = {"quarter": {"value": "give", "decree_id": 4}}
	BattleRules.freeze(repo, state, battle)
	var frozen: Dictionary = battle["parley"].duplicate(true)
	assert_eq(frozen["battle_id"], 999)
	assert_eq(frozen["received"]["att"]["surrender"]["decree_id"], 4)
	state.law_in_force["unit:" + code]["quarter"] = {"value": "refuse", "decree_id": 5}
	state.military_rosters[code]["commander_id"] = ""
	BattleRules.freeze(repo, state, battle)
	assert_eq(battle["parley"], frozen, "new law and commander cannot renegotiate")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(restored.battles.back()["parley"], frozen)
	assert_false("red_flag" in BattleRules.legal_actions(repo, restored, 999, "att"))
	assert_true("surrender" in BattleRules.legal_actions(repo, restored, 999, "att"))
	assert_false("renegotiate" in BattleRules.legal_actions(repo, restored, 999, "att"))

func test_new_law_may_strengthen_but_cannot_break_battle_obligations() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 89)
	var battle := _battle(repo, state)
	BattleRules.freeze(repo, state, battle)
	var code := String(battle["att"][0])
	state.law_in_force["unit:" + code] = {"quarter": {"value": "refuse", "decree_id": 3}}
	assert_false("red_flag" in BattleRules.legal_actions(repo, state, 999, "att"))
	battle["parley"]["agreed"].erase("surrender")
	assert_true("red_flag" in BattleRules.legal_actions(repo, state, 999, "att"))
	assert_true("surrender" in BattleRules.legal_actions(repo, state, 999, "att"), "refusing new prisoners does not forbid our surrender")
	battle["parley"]["agreed"]["safe_withdrawal"] = {"policy": "protect", "scope": "withdrawing", "until_day": state.absolute_day(), "end_condition": "departure", "conditions": {}}
	assert_false("pursue" in BattleRules.legal_actions(repo, state, 999, "att"))
	state.day += 1
	assert_true("pursue" in BattleRules.legal_actions(repo, state, 999, "att"))

func test_reinforcements_inherit_existing_agreements() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 90)
	var battle := _battle(repo, state)
	BattleRules.freeze(repo, state, battle)
	var frozen: Dictionary = battle["parley"].duplicate(true)
	var codes := state.regiments.keys()
	codes.sort()
	var joiner := String(codes[1])
	state.law_in_force["unit:" + joiner] = {"quarter": {"value": "refuse", "decree_id": 10}}
	assert_true(BattleSystem.join(repo, state, 999, joiner, "att"))
	assert_true(joiner in battle["parley"]["parties"]["att"], "P4.4e3: the reinforcement becomes a party")
	frozen["parties"]["att"].append(joiner)   # the only change the join makes to the frozen terms
	assert_eq(battle["parley"], frozen)
	assert_false("red_flag" in BattleRules.legal_actions(repo, state, 999, "att"))

func test_received_version_ignores_undelivered_decree_and_uses_newer_camp_version() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 93)
	var battle := _battle(repo, state)
	var code := String(battle["att"][0])
	state.law_decree["quarter"] = {"value": "refuse", "decree_id": 10}
	assert_eq(LawSystem.received(repo, state, "quarter", code)["value"], "give")
	var town := ArmyGround.camped_by(repo, state, code)
	assert_ne(town, "", "opening unit has a real camp")
	state.law_in_force["unit:" + code] = {"quarter": {"value": "refuse", "decree_id": 2}}
	state.law_in_force["town:" + town] = {"quarter": {"value": "give", "decree_id": 3}}
	assert_eq(LawSystem.received(repo, state, "quarter", code)["decree_id"], 3)
	BattleRules.freeze(repo, state, battle)
	assert_eq(battle["parley"]["received"]["att"]["surrender"]["decree_id"], 3)
