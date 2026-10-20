extends GutTest
## P4.4e3: an agreement binds and protects only its own parties, wherever they later
## fight. Battle 1 (f1 attacks p1) agreed a ceasefire; battle 2 (p2 attacks f2) none.
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture(merge := true) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9447)
	var mine := state.regiments.keys()
	mine.sort()
	var foes := state.foes.keys()
	foes.sort()
	var p1 := String(mine[0])
	var p2 := String(mine[1])
	var p3 := String(mine[2])
	var f1 := String(foes[0])
	var f2 := String(foes[1])
	var at := {p1: Vector2i(0, 0), f1: Vector2i(0, 3000), p2: Vector2i(5000, 20000), f2: Vector2i(80, 0), p3: Vector2i(40000, 40000)}
	for code: String in at:
		var e: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
		e["x_m"] = at[code].x
		e["y_m"] = at[code].y
		Personnel.replace(repo, state, code, 40)
	var term := {"policy": "protect", "scope": "battle", "until_day": 0, "end_condition": "battle_end", "conditions": {}}
	var b1 := {"id": 1, "att": [f1], "def": [p1], "rounds": 1, "start_day": 5, "town": "",
		"place_x_m": 0, "place_y_m": 0, "actions": {},
		"parley": {"battle_id": 1, "agreed": {"ceasefire": term}, "parties": {"att": [f1], "def": [p1]}}}
	var b2 := {"id": 2, "att": [p2], "def": [f2], "rounds": 3, "start_day": 3, "town": "",
		"place_x_m": 80, "place_y_m": 0, "actions": {}, "parley": {"battle_id": 2, "agreed": {}, "parties": {"att": [p2], "def": [f2]}}}
	state.battles = [b1, b2]
	state.tick = 1
	state.day = 7
	for b: Dictionary in state.battles:
		BattleFormation.ensure(b)
		BattleReport.enroll(state, b, String(b["att"][0]), "att")
		BattleReport.enroll(state, b, String(b["def"][0]), "def")
		BattleGroups.refresh(repo, state, b)
	if merge:
		BattleMerge.day(repo, state)
	return {"repo": repo, "state": state, "p1": p1, "p2": p2, "p3": p3, "f1": f1, "f2": f2}

func _legal(f: Dictionary, unit: String, target := "") -> Array[String]:
	var b := BattleSystem.battle_of(f.state, unit)
	return BattleRules.legal_actions(f.repo, f.state, int(b["id"]), BattleRules.side_of(b, unit), unit, target)

func test_ceasefire_binds_only_its_parties_after_the_merge() -> void:
	var f := _fixture()
	assert_eq(f.state.battles.size(), 1)
	assert_false("attack" in _legal(f, f.p1, f.f1), "p1 toward f1 is protected")
	assert_true("attack" in _legal(f, f.p1, f.f2), "f2 never agreed with p1")
	assert_true("attack" in _legal(f, f.p2, f.f2), "battle 2 agreed nothing")
	assert_true("attack" in _legal(f, f.p2, f.f1), "p2 was never a party of the ceasefire")
	assert_false("attack" in _legal(f, f.f1, f.p1), "the other party is bound too")

func test_no_target_cannot_confirm_the_object_so_the_agreement_applies() -> void:
	var f := _fixture()
	assert_false("attack" in _legal(f, f.p1), "possibly breaching action held")
	assert_true("attack" in _legal(f, f.p2), "p2 is no party of any agreement")

func test_protection_survives_the_other_battle_being_the_survivor() -> void:
	var f := _fixture(false)
	f.state.battles[1]["town"] = "T"   # survivor = 2, battle 1 is absorbed
	BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 1)
	assert_eq(int(f.state.battles[0].id), 2)
	assert_false("attack" in _legal(f, f.p1, f.f1), "still binds p1 toward f1 under the new record")
	assert_true("attack" in _legal(f, f.p2, f.f1))

func test_freeze_records_parties_and_join_appends() -> void:
	var f := _fixture(false)
	var b := {"id": 3, "att": [f.f1], "def": [f.p1]}
	f.state.battles = [b]
	BattleRules.freeze(f.repo, f.state, b)
	assert_eq(b.parley.parties, {"att": [f.f1], "def": [f.p1]})
	var e: Dictionary = f.state.regiments[f.p3]
	e["x_m"] = 0
	e["y_m"] = 100
	assert_true(BattleSystem.join(f.repo, f.state, 3, f.p3, "def"))
	assert_eq(b.parley.parties.def, [f.p1, f.p3])

func test_old_parley_without_parties_defaults_to_current_members_and_roundtrips() -> void:
	var f := _fixture(false)
	f.state.battles[0].parley.erase("parties")
	assert_false("attack" in _legal(f, f.p1, f.f1), "old save: members default to parties")
	var copy: Dictionary = JSON.parse_string(JSON.stringify(f.state.battles[1].parley))
	assert_eq(copy.parties.att, [f.p2])
