extends GutTest
## P4.4e4: a merge carries pending side warrants onto the survivor's sides and the
## presentation reads stored battle ids through BattleSystem.canonical.
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

## Battle 1: crown p1 (att) vs foe f1 (def). Battle 2: foe f2 attacks crown p2 when
## `flip`, else crown p2 attacks f2. f2 stands an 80 m footprint-edge gap from p1 (contact 100 m).
func _fixture(flip: bool) -> Dictionary:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := SuiteData.campaign(repo, 9448)
	var mine := state.regiments.keys()
	mine.sort()
	var foes := state.foes.keys()
	foes.sort()
	var p1 := String(mine[0])
	var p2 := String(mine[1])
	var f1 := String(foes[0])
	var f2 := String(foes[1])
	var at := {p1: Vector2i(10000, 10000), f1: Vector2i(10000, 20000), p2: Vector2i(30000, 30000), f2: Vector2i(11156, 10000)}
	for code: String in at:
		var e: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
		e["x_m"] = at[code].x
		e["y_m"] = at[code].y
		for arm: String in repo.world_table("military", "unit_types"):
			state.army_roster[code][arm] = "0"
		state.army_roster[code]["infantry"] = "40"
		Personnel.replace(repo, state, code, 40)
	var b1 := {"id": 1, "att": [p1], "def": [f1], "rounds": 1, "start_day": 5, "town": "",
		"place_x_m": 10000, "place_y_m": 10000, "actions": {}, "parley": {"battle_id": 1, "agreed": {}}}
	var b2 := {"id": 2, "att": [f2] if flip else [p2], "def": [p2] if flip else [f2], "rounds": 3, "start_day": 3,
		"town": "", "place_x_m": 11156, "place_y_m": 10000, "actions": {}, "parley": {"battle_id": 2, "agreed": {}}}
	state.battles = [b1, b2]
	state.tick = 1
	state.day = 7
	state.metrics.treasury = 100
	state.king_state.x_m = 100000000
	state.king_state.y_m = 100000000
	for b: Dictionary in state.battles:
		BattleFormation.ensure(b)
		BattleReport.enroll(state, b, String(b["att"][0]), "att")
		BattleReport.enroll(state, b, String(b["def"][0]), "def")
		assert_true(BattleGroups.refresh(repo, state, b), "Legal full-size merge fixture publishes groups")
	return {"repo": repo, "state": state, "p1": p1, "p2": p2, "f1": f1, "f2": f2}

func _warrant(f: Dictionary, side: String) -> void:
	var order := {"id": "w2", "battle_id": 2, "side": side, "kind": "hold",
		"issued_day": f.state.absolute_day(), "params": {"regiment": f.p2}}
	assert_eq(BattleOrders.issue(f.repo, f.state, order).status, "pending")

func test_opposite_orientation_remaps_the_side_and_delivers() -> void:
	var f := _fixture(true)
	_warrant(f, "def")
	BattleMerge.day(f.repo, f.state)
	var rec: Dictionary = f.state.battle_orders["w2"]
	assert_eq(rec.request.side, "att")
	assert_eq(rec.merge_remap.from_side, "def")
	assert_eq(rec.merge_remap.to_side, "att")
	assert_eq(int(rec.merge_remap.from_battle), 2)
	assert_ne(String(rec.merge_remap.reason), "")
	assert_eq(rec.targets, [f.p2])
	assert_eq(BattleOrders.deliver(f.repo, f.state, "w2").status, "delivered")
	assert_eq(f.state.battles[0].actions.att.order_id, "w2")
	assert_false(f.state.battles[0].actions.has("def"))

func test_same_orientation_changes_nothing() -> void:
	var f := _fixture(false)
	_warrant(f, "att")
	BattleMerge.day(f.repo, f.state)
	var rec: Dictionary = f.state.battle_orders["w2"]
	assert_eq(rec.request.side, "att")
	assert_false(rec.has("merge_remap"))
	assert_eq(BattleOrders.deliver(f.repo, f.state, "w2").status, "delivered")

func test_retry_of_a_remapped_warrant_is_still_the_same_warrant() -> void:
	var f := _fixture(true)
	_warrant(f, "def")
	BattleMerge.day(f.repo, f.state)
	var again := {"id": "w2", "battle_id": 2, "side": "def", "kind": "hold",
		"issued_day": f.state.absolute_day(), "params": {"regiment": f.p2}}
	assert_eq(BattleOrders.issue(f.repo, f.state, again).status, "pending")

func test_presentation_reads_stored_ids_canonically() -> void:
	var f := _fixture(true)
	_warrant(f, "def")
	var at := ArmySystem.pack_to_metres(f.repo, ArmySystem.position_of(f.repo, f.state, ArmySystem.regiment(f.repo, f.p2, f.state)))
	f.state.king_state.x_m = at.x
	f.state.king_state.y_m = at.y
	var quote := BattlePresentation.task_quote(f.repo, f.state, f.p2, "defend")
	assert_eq(quote.reason, "")
	assert_true(ActionSystem.new(f.repo).execute(ActionRequest.make(quote.action_code, quote.params), f.state).ok)
	assert_eq(BattlePresentation.task_view(f.repo, f.state, f.p2).current.task, "Steady defence")
	BattleMerge.day(f.repo, f.state)
	assert_eq(f.state.battles.size(), 1)
	var rows := BattlePresentation.warrants(f.state, 1)
	assert_eq(rows.size(), 1)
	assert_eq(rows[0].id, "w2")
	var view := BattlePresentation.task_view(f.repo, f.state, f.p2)
	assert_eq(int(view.battle_id), 1)
	assert_eq(view.current.task, "Steady defence")
