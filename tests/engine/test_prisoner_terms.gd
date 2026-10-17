extends GutTest

const SuiteData := preload("res://tests/suite_data.gd")

func _holder(state: GameState) -> String:
	var codes := state.regiments.keys()
	codes.sort()
	var holder := String(codes[0])
	state.law_in_force["unit:" + holder] = {}
	return holder

func test_terms_load_with_integer_opinion_and_reasons() -> void:
	var repo := SuiteData.repo()
	assert_true("prisoner_terms" in repo, "repository loads disposition terms")
	if not "prisoner_terms" in repo:
		return
	var terms: Dictionary = repo.get("prisoner_terms")
	assert_eq(terms.keys(), ["ransom", "exchange", "release"])
	for kind: String in terms:
		assert_typeof(terms[kind].family_opinion, TYPE_INT)
		assert_eq(terms[kind].family_opinion, 2 if kind == "release" else 1)
		assert_ne(String(terms[kind].reason), "")
		assert_ne(String(terms[kind].label), "")

func test_share_reads_received_default_then_delivery_not_decree() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 521)
	var holder := _holder(state)
	state.law_decree["ransom_captor_share"] = {"value": "900", "decree_id": 12}
	assert_eq(LawSystem.prisoner_share(repo, state, holder),
		{"permille": 300, "received": {"value": "300", "decree_id": 0}})
	state.law_in_force["unit:" + holder]["ransom_captor_share"] = {"value": "400", "decree_id": 13}
	assert_eq(LawSystem.prisoner_share(repo, state, holder),
		{"permille": 400, "received": {"value": "400", "decree_id": 13}})

func test_foreign_share_uses_foreign_received_law() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 522)
	var holder := String(state.foes.keys()[0])
	state.foes[holder]["received_laws"]["ransom_captor_share"] = {"value": "600", "decree_id": 3}
	assert_eq(LawSystem.prisoner_share(repo, state, holder),
		{"permille": 600, "received": {"value": "600", "decree_id": 3}})

func test_invalid_share_row_and_received_value_refuse() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 523)
	var holder := _holder(state)
	for value: String in ["-1", "1001", "abc", "30.5"]:
		state.law_in_force["unit:" + holder]["ransom_captor_share"] = {"value": value, "decree_id": 99}
		assert_true((LawSystem.prisoner_share(repo, state, holder) as Dictionary).has("error"))
	repo.laws["ransom_captor_share"]["kind"] = "choice"
	assert_true((LawSystem.prisoner_share(repo, state, holder) as Dictionary).has("error"))
	repo.laws.erase("ransom_captor_share")
	assert_true((LawSystem.prisoner_share(repo, state, holder) as Dictionary).has("error"))

func test_ransom_requires_nobles_and_received_permission() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 524)
	var holder := _holder(state)
	var batch := {"holder_code": holder, "battle_id": 525, "commoners": 0, "nobles": 10}
	state.law_decree["ransom"] = {"value": "execute", "decree_id": 8}
	assert_eq(LawSystem.prisoner_refusal(repo, state, batch, "ransom"), "")
	state.law_in_force["unit:" + holder]["ransom"] = {"value": "execute", "decree_id": 9}
	assert_ne(LawSystem.prisoner_refusal(repo, state, batch, "ransom"), "")
	for kind: String in ["release", "exchange"]:
		assert_eq(LawSystem.prisoner_refusal(repo, state, batch, kind), "")
	batch.commoners = 1
	state.law_in_force["unit:" + holder]["ransom"]["value"] = "ransom"
	assert_ne(LawSystem.prisoner_refusal(repo, state, batch, "ransom"), "")
	assert_ne(LawSystem.prisoner_refusal(repo, state, batch, "execute"), "")

func test_agreed_ransom_survives_policy_change_and_respects_deadline() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 525)
	var holder := _holder(state)
	var batch := {"holder_code": holder, "battle_id": 525, "commoners": 0, "nobles": 10}
	state.law_in_force["unit:" + holder]["ransom"] = {"value": "execute", "decree_id": 9}
	var term := {"policy": "allow", "scope": "noble_prisoners", "until_day": state.absolute_day(), "conditions": {}}
	state.battles.append({"id": 525, "parley": {"agreed": {"noble_ransom": term}}})
	assert_eq(LawSystem.prisoner_refusal(repo, state, batch, "ransom"), "")
	state.day += 1
	assert_ne(LawSystem.prisoner_refusal(repo, state, batch, "ransom"), "")

func test_captured_ransom_protection_survives_battle_removal() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 526)
	var holder := _holder(state)
	state.law_in_force["unit:" + holder]["ransom"] = {"value": "execute", "decree_id": 9}
	var batch := {"holder_code": holder, "battle_id": 526, "commoners": 0, "nobles": 10, "ransom_protected": true}
	assert_eq(LawSystem.prisoner_refusal(repo, state, batch, "ransom"), "")
	batch.commoners = 1
	assert_ne(LawSystem.prisoner_refusal(repo, state, batch, "ransom"), "")

func test_foreign_received_ransom_policy_is_independent() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 527)
	var holder := String(state.foes.keys()[0])
	var batch := {"holder_code": holder, "commoners": 0, "nobles": 1}
	state.foes[holder]["received_laws"]["ransom"] = {"value": "execute", "decree_id": 2}
	assert_ne(LawSystem.prisoner_refusal(repo, state, batch, "ransom"), "")
	state.foes[holder]["received_laws"]["ransom"] = {"value": "ransom", "decree_id": 3}
	assert_eq(LawSystem.prisoner_refusal(repo, state, batch, "ransom"), "")
