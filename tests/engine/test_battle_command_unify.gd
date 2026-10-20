extends GutTest
## P4.4e2: a merge picks ONE commander per surviving side. Fixture as test_battle_merge:
## battle 1 (survivor) foe f1 att / crown p1 def; battle 2 crown p2 att / foe f2 def; so the
## absorbed battle's att commander (p2's officer, B) joins survivor def (p1's officer, A).
const SuiteData := preload("res://tests/suite_data.gd")

func _fixture(a_skill := 5, b_skill := 7) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9447)
	var mine := state.regiments.keys()
	mine.sort()
	var foes := state.foes.keys()
	foes.sort()
	var p1 := String(mine[0])
	var p2 := String(mine[1])
	var f1 := String(foes[0])
	var f2 := String(foes[1])
	var at := {p1: Vector2i(0, 0), f1: Vector2i(0, 3000), p2: Vector2i(5000, 20000), f2: Vector2i(80, 0)}
	for code: String in at:
		var e: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
		e["x_m"] = at[code].x
		e["y_m"] = at[code].y
	var b1 := {"id": 1, "att": [f1], "def": [p1], "rounds": 1, "start_day": 5, "town": "",
		"place_x_m": 0, "place_y_m": 0, "actions": {}, "parley": {"battle_id": 1, "agreed": {}}}
	var b2 := {"id": 2, "att": [p2], "def": [f2], "rounds": 3, "start_day": 3, "town": "",
		"place_x_m": 80, "place_y_m": 0, "actions": {}, "parley": {"battle_id": 2, "agreed": {}}}
	state.battles = [b1, b2]
	state.tick = 1
	state.day = 7
	for b: Dictionary in state.battles:
		BattleFormation.ensure(b)
		BattleReport.enroll(state, b, String(b["att"][0]), "att")
		BattleReport.enroll(state, b, String(b["def"][0]), "def")
		BattleGroups.refresh(repo, state, b)
		BattleCommand.update_battle(repo, state, b)
	var a := String(state.military_rosters[p1].commander_id)
	var b_id := String(state.military_rosters[p2].commander_id)
	assert_ne(a, b_id)
	state.characters[a].skills["sk_martial"] = a_skill
	state.characters[b_id].skills["sk_martial"] = b_skill
	return {"repo": repo, "state": state, "p1": p1, "p2": p2, "a": a, "b": b_id, "b1": b1, "b2": b2}

func _merge(f: Dictionary) -> Dictionary:
	BattleMerge._merge(f.repo, f.state, f.b1, f.b2)   # the commander rule, not the contact test, is under test
	assert_eq(f.state.battles.size(), 1)
	return f.state.battles[0]

func test_better_martial_commander_wins_and_union_row_names_both() -> void:
	var f := _fixture(5, 7)
	assert_eq(f.b1.commanders.def, f.a)
	var s := _merge(f)
	assert_eq(s.commanders.def, f.b)
	var row: Dictionary = s.command_unions[0]
	assert_eq(row.side, "def")
	assert_eq(row.chosen, f.b)
	assert_eq(row.from, [f.a, f.b])
	assert_ne(String(row.reason), "")

func test_prestige_then_smaller_id_break_ties() -> void:
	var f := _fixture(6, 6)
	f.state.characters[f.a].attributes["prestige"] = 3
	f.state.characters[f.b].attributes["prestige"] = 4
	assert_eq(_merge(f).commanders.def, f.b)
	var g := _fixture(6, 6)
	g.state.characters[g.a].attributes["prestige"] = 4
	g.state.characters[g.b].attributes["prestige"] = 4
	var want: String = g.a if g.a < g.b else g.b
	assert_eq(_merge(g).commanders.def, want)

func test_nominee_sequence_decides_between_two_nominees() -> void:
	var f := _fixture(5, 7)
	f.b1["commander_nominees"] = {"def": f.a}
	f.b1["commander_nominee_seq"] = {"def": 1}
	f.b2["commander_nominees"] = {"att": f.b}
	f.b2["commander_nominee_seq"] = {"att": 2}
	var s := _merge(f)
	assert_eq(s.commanders.def, f.b)
	assert_eq(s.commander_nominees.def, f.b)
	assert_eq(int(s.commander_nominee_seq.def), 2)

func test_single_nominee_beats_better_martial() -> void:
	var f := _fixture(5, 9)
	f.b1["commander_nominees"] = {"def": f.a}
	assert_eq(_merge(f).commanders.def, f.a)

func test_reinforcement_after_merge_keeps_the_unified_commander() -> void:
	var f := _fixture(5, 7)
	var s := _merge(f)
	var spare: Array = f.state.regiments.keys().filter(func(c: String) -> bool: return not c in [f.p1, f.p2])
	spare.sort()
	s.def.append(spare[0])
	BattleCommand.update_battle(f.repo, f.state, s)
	assert_eq(s.commanders.def, f.b)

func test_pending_warrant_of_the_losing_commander_is_refused() -> void:
	var f := _fixture(5, 7)
	var order := {"id": "w1", "unit": f.p1, "battle_id": 1, "task": "defend", "formation": "", "target_unit": "",
		"source": "general", "issuer": f.a, "max_route_m": 0, "region": ""}
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, order).status, "pending")
	_merge(f)
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "w1").status, "invalid")
