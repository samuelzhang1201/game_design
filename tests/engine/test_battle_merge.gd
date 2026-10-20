extends GutTest
## P4.4e1: two battles whose groups actually touch merge into one. Hand-computed with
## battle_group_contact_m 100 (data/battle/balance.csv); each unit is cut to 40 people,
## so it is ONE group standing on its anchor.
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const BattleScenario := preload("res://tests/fixtures/battle_scenario.gd")

## Battle 1: foe f1 attacks crown p1; battle 2: crown p2 attacks foe f2.
## p1 (0,0), f1 (0,3000), p2 (5000,20000), f2 (80,0): f2 stands 80 m from p1.
func _fixture(f2_at := Vector2i(80, 0), p2_at := Vector2i(5000, 20000)) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9447)
	var mine := state.regiments.keys()
	mine.sort()
	var foes := state.foes.keys()
	foes.sort()
	assert_gte(foes.size(), 2, "fixture needs two foes")
	var p1 := String(mine[0])
	var p2 := String(mine[1])
	var f1 := String(foes[0])
	var f2 := String(foes[1])
	var at := {p1: Vector2i(0, 0), f1: Vector2i(0, 3000), p2: p2_at, f2: f2_at}
	for code: String in at:
		var e: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
		e["x_m"] = at[code].x
		e["y_m"] = at[code].y
		Personnel.replace(repo, state, code, 40)
	var b1 := {"id": 1, "att": [f1], "def": [p1], "rounds": 1, "start_day": 5, "town": "",
		"place_x_m": 0, "place_y_m": 0, "actions": {}, "parley": {"battle_id": 1, "agreed": {}}}
	var b2 := {"id": 2, "att": [p2], "def": [f2], "rounds": 3, "start_day": 3, "town": "",
		"place_x_m": 80, "place_y_m": 0, "actions": {}, "parley": {"battle_id": 2, "agreed": {"marker": 1}}}
	state.battles = [b1, b2]
	state.tick = 1
	state.day = 7
	for b: Dictionary in state.battles:
		BattleFormation.ensure(b)
		BattleReport.enroll(state, b, String(b["att"][0]), "att")
		BattleReport.enroll(state, b, String(b["def"][0]), "def")
		BattleGroups.refresh(repo, state, b)
	return {"repo": repo, "state": state, "p1": p1, "p2": p2, "f1": f1, "f2": f2, "b1": b1, "b2": b2}

func test_contact_inside_reach_merges_by_allegiance() -> void:
	var f := _fixture()
	var events := BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 1)
	var s: Dictionary = f.state.battles[0]
	assert_eq(int(s.id), 1)
	assert_eq(s.def, [f.p1, f.p2])
	assert_eq(s.att, [f.f1, f.f2])
	assert_eq(f.state.battle_aliases, {"2": 1})
	assert_eq(int(s.start_day), 3)
	assert_eq(s.sources["2"].parley.agreed, {"marker": 1})
	assert_eq(events.size(), 1)
	assert_eq(events[0].kind, "merge")
	assert_eq(int(events[0].battle_id), 1)
	assert_eq(int(events[0].absorbed), 2)
	assert_ne(String(events[0].reason), "")
	assert_true(events[0] in s.report_events)

func test_reach_is_inclusive_and_only_whole_metres() -> void:
	var f := _fixture(Vector2i(100, 0))
	BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 1, "100 m is in contact")
	var g := _fixture(Vector2i(101, 0))
	BattleMerge.day(g.repo, g.state)
	assert_eq(g.state.battles.size(), 2, "101 m is not")
	var h := _fixture(Vector2i(150, 0))
	assert_eq(BattleMerge.day(h.repo, h.state), [])
	assert_eq(h.state.battle_aliases, {})

func test_same_allegiance_close_together_never_merges() -> void:
	var f := _fixture(Vector2i(50000, 50000), Vector2i(10, 0))
	BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 2)

func test_alias_resolves_and_chains() -> void:
	var f := _fixture()
	BattleMerge.day(f.repo, f.state)
	assert_eq(BattleSystem.battle_by_id(f.state, 2), f.state.battles[0])
	assert_eq(BattleSystem.canonical(f.state, 2), 1)
	assert_eq(BattleSystem.canonical(f.state, 1), 1)
	f.state.battle_aliases["7"] = 2
	assert_eq(BattleSystem.canonical(f.state, 7), 1)
	assert_eq(BattleSystem.battle_by_id(f.state, 99), {})

func test_records_migrate_without_loss_or_doubling() -> void:
	var f := _fixture()
	var n1: int = f.b1.personnel_entries.size()
	var n2: int = f.b2.personnel_entries.size()
	f.b1["event_checks"] = {"6": {"token": "a", "event_id": ""}}
	f.b2["event_checks"] = {"6": {"token": "b", "event_id": ""}, "5": {"token": "c", "event_id": ""}}
	f.b2["event_reinforcements_consumed"] = [f.p2]
	f.b1["event_reinforcements_consumed"] = [f.p2]
	f.b2["withdrawal_costs"] = [{"code": f.f2, "morale": -1}]
	f.b2["reserves"] = {f.f2: {"since_day": 3, "reason": "r"}}
	BattleMerge.day(f.repo, f.state)
	var s: Dictionary = f.state.battles[0]
	assert_eq(s.personnel_entries.size(), n1 + n2)
	assert_eq(s.unit_entries.size(), 4)
	assert_eq(s.unit_entries[f.p2].side, "def", "the absorbed crown unit sits on the crown side")
	assert_eq(s.unit_entries[f.f2].side, "att")
	for id: String in s.personnel_entries:
		assert_eq(s.personnel_entries[id].side, BattleRules.side_of(s, String(s.personnel_entries[id].unit_code)))
	assert_eq(s.event_checks["6"].token, "a", "the survivor's mark for a day stands")
	assert_eq(s.event_checks["5"].token, "c")
	assert_eq(s.event_reinforcements_consumed, [f.p2])
	assert_eq(s.withdrawal_costs.size(), 1)
	assert_true(s.reserves.has(f.f2))
	assert_eq(int(s.rounds), 3)

func test_merged_battle_does_not_fight_twice_today() -> void:
	var f := _fixture()
	var today: int = f.state.absolute_day()
	f.b2["last_resolved_day"] = today
	BattleMerge.day(f.repo, f.state)
	var s: Dictionary = f.state.battles[0]
	assert_eq(int(s.last_resolved_day), today)
	BattleSystem.step_battle(f.repo, f.state, 2)
	assert_eq(int(s.rounds), 3, "no second round")

func test_a_second_pass_changes_nothing() -> void:
	var f := _fixture()
	BattleMerge.day(f.repo, f.state)
	var before := JSON.stringify(f.state.to_dict())
	assert_eq(BattleMerge.day(f.repo, f.state), [])
	assert_eq(JSON.stringify(f.state.to_dict()), before)

func test_json_roundtrip_keeps_aliases_and_sources() -> void:
	var f := _fixture()
	BattleMerge.day(f.repo, f.state)
	var loaded := BattleScenario.roundtrip(f.state)
	assert_eq(loaded.battle_aliases, {"2": 1})
	assert_eq(loaded.battles[0].sources["2"].parley.agreed, {"marker": 1})
	assert_eq(BattleSystem.battle_by_id(loaded, 2)["id"], 1)
	var d: Dictionary = f.state.to_dict()
	d.erase("battle_aliases")
	assert_eq(GameState.from_dict(JSON.parse_string(JSON.stringify(d))).battle_aliases, {})

func test_town_battle_survives_a_field_battle() -> void:
	var f := _fixture()
	f.b2["town"] = String(f.repo.burgs.keys()[0])
	BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 1)
	assert_eq(int(f.state.battles[0].id), 2)
	assert_eq(f.state.battles[0].town, f.b2.town)
	assert_eq(f.state.battle_aliases, {"1": 2})
	assert_eq(int(f.state.battles[0].start_day), 3)

func test_two_town_battles_never_merge() -> void:
	var f := _fixture()
	f.b1["town"] = "a"
	f.b2["town"] = "b"
	BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 2)

func test_a_pending_round_blocks_the_merge() -> void:
	var f := _fixture()
	f.b2["pending_round"] = {"round": 4}
	BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 2)

func test_prepare_day_runs_the_merge() -> void:
	var f := _fixture()
	var events := BattleSystem.prepare_day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 1)
	assert_true(events.any(func(e: Dictionary) -> bool: return e.kind == "merge"))
