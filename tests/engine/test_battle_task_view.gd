extends GutTest
## BattlePresentation.task_view / task_quote: the WAR ROOM task block's facts.
const SuiteData := preload("res://tests/suite_data.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 944)
	var codes := state.regiments.keys()
	codes.sort()
	var enemy := String(state.foes.keys()[0])
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, String(codes[0]), state)))
	state.battles = [{"id": 944, "att": [codes[0], codes[1]], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": at.x, "place_y_m": at.y}]
	state.king_state.x_m = 100000000
	state.king_state.y_m = 100000000
	state.metrics.treasury = 100
	repo.courier_kinds.ordinary.gold = 2
	return {"repo": repo, "state": state, "a": String(codes[0]), "b": String(codes[1]),
		"spare": String(codes[2]), "enemy": enemy}

func _send(f: Dictionary, quote: Dictionary) -> Dictionary:
	return ActionSystem.new(f.repo).execute(ActionRequest.make(quote.action_code, quote.params), f.state)

func test_view_is_empty_off_the_field_and_for_a_foe() -> void:
	var f := _fixture()
	assert_eq(BattlePresentation.task_view(f.repo, f.state, f.spare), {})
	assert_eq(BattlePresentation.task_view(f.repo, f.state, f.enemy), {})
	assert_eq(BattlePresentation.task_quote(f.repo, f.state, f.spare, "defend").params, {})

func test_view_lists_tasks_opponents_and_formations() -> void:
	var f := _fixture()
	var view := BattlePresentation.task_view(f.repo, f.state, f.a)
	assert_eq(int(view.battle_id), 944)
	assert_eq(view.tasks.size(), f.repo.battle_behaviors.size())
	assert_eq(view.tasks[0], {"id": "charge", "label": "Frontal charge"})
	assert_eq(view.formations.size(), f.repo.battle_formations.size())
	assert_eq(view.targets.size(), 1)
	assert_eq(view.targets[0].code, f.enemy)
	assert_eq(view.current, {})
	assert_eq(view.pending, [])

func test_remote_quote_is_what_executing_it_spends_and_status_turns_received() -> void:
	var f := _fixture()
	var quote := BattlePresentation.task_quote(f.repo, f.state, f.a, "flank", f.enemy)
	assert_eq(quote.reason, "")
	assert_eq([quote.filing_gold, quote.courier_gold, quote.local], [1, 2, false])
	assert_true(_send(f, quote).ok)
	assert_eq(int(f.state.metrics.treasury), 100 - 1 - 2, "the quote is the real spend")
	var view := BattlePresentation.task_view(f.repo, f.state, f.a)
	assert_eq(view.pending.size(), 1)
	assert_eq([view.pending[0].task, view.pending[0].target, view.pending[0].status],
		["Flank attack", String(ArmySystem.regiment(f.repo, f.enemy, f.state).label), "pending"])
	# a second task the same day joins the waiting courier: filing only, a fresh request id
	var again := BattlePresentation.task_quote(f.repo, f.state, f.a, "defend")
	assert_ne(again.params.request_id, quote.params.request_id)
	assert_eq([again.filing_gold, again.courier_gold], [1, 0])
	assert_true(_send(f, again).ok)
	assert_eq(int(f.state.metrics.treasury), 96)
	assert_eq(CourierSystem._deliver(f.repo, f.state, f.state.couriers[0]).type, "delivered")
	view = BattlePresentation.task_view(f.repo, f.state, f.a)
	assert_eq([view.current.task, view.current.status], ["Steady defence", "received"])
	assert_eq(view.pending, [])

func test_local_quote_costs_filing_only_and_cancel_quotes_its_own_action() -> void:
	var f := _fixture()
	var at := ArmySystem.pack_to_metres(f.repo, ArmySystem.position_of(f.repo, f.state, ArmySystem.regiment(f.repo, f.a, f.state)))
	f.state.king_state.x_m = at.x
	f.state.king_state.y_m = at.y
	var quote := BattlePresentation.task_quote(f.repo, f.state, f.a, "defend")
	assert_eq([quote.filing_gold, quote.courier_gold, quote.local], [1, 0, true])
	assert_true(_send(f, quote).ok)
	assert_eq(BattlePresentation.task_view(f.repo, f.state, f.a).current.task, "Steady defence")
	var cancel := BattlePresentation.task_quote(f.repo, f.state, f.a, "cancel")
	assert_eq(cancel.action_code, "BATTLE_TASK_CANCEL")
	assert_false(cancel.params.has("task"))
	assert_eq(cancel.reason, "")
	assert_true(_send(f, cancel).ok)
	assert_eq(BattlePresentation.task_view(f.repo, f.state, f.a).current, {})
	assert_eq(int(f.state.metrics.treasury), 98)

func test_quote_reason_is_action_system_validate_for_every_formation() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	for shape: String in f.repo.battle_formations:
		var quote := BattlePresentation.task_quote(f.repo, f.state, f.a, "defend", "", shape)
		assert_eq(quote.params.formation, shape)
		assert_eq(quote.reason, actions.validate(ActionRequest.make("BATTLE_TASK", quote.params), f.state))
	f.state.metrics.treasury = 2
	assert_eq(BattlePresentation.task_quote(f.repo, f.state, f.a, "defend").reason,
		"The chancery cannot pay for this unit task.")

func test_lapsed_task_shows_its_reason() -> void:
	var f := _fixture()
	assert_true(_send(f, BattlePresentation.task_quote(f.repo, f.state, f.a, "flank", f.enemy)).ok)
	f.state.battles[0]["parley"] = {"agreed": {"ceasefire": {"policy": "protect"}}}
	assert_eq(CourierSystem._deliver(f.repo, f.state, f.state.couriers[0]).type, "lapsed")
	var view := BattlePresentation.task_view(f.repo, f.state, f.a)
	assert_eq(view.refused.status, "invalid")
	assert_ne(view.refused.reason, "")
