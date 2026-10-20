extends GutTest

const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")

func _fixture(protected_source: int, reverse := false) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9447)
	state.tick = 1
	state.day = 7
	var mine := state.regiments.keys()
	mine.sort()
	var foes := state.foes.keys()
	foes.sort()
	var protected := String(mine[1])
	for i: int in range(2):
		var own := String(mine[1 - i])
		var enemy := String(foes[i])
		for code: String in [own, enemy]:
			var entry: Dictionary = state.regiments.get(code, state.foes.get(code, {}))
			entry["x_m"] = 0
			entry["y_m"] = 0
			Personnel.replace(repo, state, code, 40)
		var att: Array = [own] if reverse == (i == 0) else [enemy]
		var def: Array = [enemy] if reverse == (i == 0) else [own]
		var agreed := {}
		if i == 0:
			agreed["herald_safety"] = {"policy": "protect", "until_day": state.absolute_day()}
		var battle := {"id": protected_source if i == 0 else 3 - protected_source,
			"att": att, "def": def, "rounds": 0, "start_day": 5, "town": "",
			"place_x_m": 0, "place_y_m": 0, "actions": {},
			"parley": {"agreed": agreed, "parties": {"att": att.duplicate(), "def": def.duplicate()}}}
		BattleFormation.ensure(battle)
		BattleGroups.refresh(repo, state, battle)
		state.battles.append(battle)
	BattleMerge.day(repo, state)
	for side: String in BattleSystem.SIDES:
		(state.battles[0][side] as Array).sort()
	return {"repo": repo, "state": state, "protected": protected}

func _heralds(f: Dictionary) -> Array:
	var view := BattlePresentation.map_snapshot(f.repo, f.state, f.repo.resolve_realm("player_realm"))
	return view.battle_signals.filter(func(signal_row: Dictionary) -> bool: return signal_row.kind == "herald")

func test_merged_herald_uses_original_party_from_either_source_and_orientation() -> void:
	for source: int in [1, 2]:
		for reverse: bool in [false, true]:
			var f := _fixture(source, reverse)
			assert_eq(f.state.battles.size(), 1)
			var rows := _heralds(f)
			assert_eq(rows.size(), 1, "An active carried agreement retains its herald")
			if not rows.is_empty():
				assert_eq(rows[0].unit_code, f.protected, "An unrelated ally cannot carry the herald")
			var before := SaveLoad.state_hash(f.state)
			assert_eq(_heralds(f), rows)
			assert_eq(SaveLoad.state_hash(f.state), before)
			f.state = Scenario.roundtrip(f.state)
			assert_eq(_heralds(f), rows, "JSON preserves original source parties and signal")

func test_expired_or_fighting_agreement_has_no_herald() -> void:
	var f := _fixture(2)
	f.state.day += 1
	assert_eq(_heralds(f), [])
	f.state.day -= 1
	f.state.battles[0].rounds = 1
	assert_eq(_heralds(f), [])

func test_departed_party_does_not_protect_an_unrelated_ally_or_disclose_to_foreign_realm() -> void:
	var f := _fixture(1)
	var battle: Dictionary = f.state.battles[0]
	for side: String in BattleSystem.SIDES:
		(battle[side] as Array).erase(f.protected)
	assert_eq(_heralds(f), [])
	assert_eq(BattlePresentation.map_snapshot(f.repo, f.state, f.repo.resolve_realm("raider_realm")),
		{"map_units": {}, "battle_signals": []})

func test_departed_counterparty_cannot_be_replaced_by_an_unrelated_opponent() -> void:
	var f := _fixture(2)
	var battle: Dictionary = f.state.battles[0]
	var parties: Dictionary = battle.sources["2"].parley.parties
	for side: String in BattleSystem.SIDES:
		for code: String in parties[side]:
			if code != f.protected:
				for live_side: String in BattleSystem.SIDES:
					(battle[live_side] as Array).erase(code)
	assert_eq(_heralds(f), [])
