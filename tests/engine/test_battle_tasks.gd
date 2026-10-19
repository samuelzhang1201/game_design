extends GutTest

const SuiteData := preload("res://tests/suite_data.gd")
const PATH := "res://scripts/engine/battle_task_system.gd"
var tasks: GDScript

func before_each() -> void:
	tasks = load(PATH) if FileAccess.file_exists(PATH) else null

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 944)
	var codes := state.regiments.keys()
	codes.sort()
	var enemy := String(state.foes.keys()[0])
	var battle := {"id": 944, "att": [codes[0], codes[1]], "def": [enemy], "rounds": 0,
		"place_x_m": 0, "place_y_m": 0}
	state.battles = [battle]
	return {"repo": repo, "state": state, "a": String(codes[0]), "b": String(codes[1]),
		"enemy": enemy, "battle": battle}

func _order(f: Dictionary, id: String, kind := "flank", unit := "") -> Dictionary:
	return {"id": id, "unit": f.a if unit == "" else unit, "battle_id": 944,
		"task": kind, "formation": "line", "target_unit": f.enemy, "source": "player", "issuer": ""}

func test_task_ledger_is_available() -> void:
	assert_not_null(tasks, "P4.4 needs a canonical unit task ledger")

func test_pending_warrants_replace_only_on_delivery_and_ignore_late_orders() -> void:
	if tasks == null: return
	var f := _fixture()
	var first_order := _order(f, "first")
	first_order.formation = "diamond"
	var first: Dictionary = tasks.issue_task(f.repo, f.state, first_order)
	var second: Dictionary = tasks.issue_task(f.repo, f.state, _order(f, "second", "defend"))
	assert_eq(first.sequence, 1)
	assert_eq(second.sequence, 2)
	assert_true(tasks.current(f.state, f.a).is_empty())
	assert_eq(tasks.deliver_task(f.repo, f.state, "second").status, "received")
	assert_eq(tasks.deliver_task(f.repo, f.state, "first").status, "superseded")
	assert_eq(tasks.current(f.state, f.a).request.task, "defend")
	assert_eq(tasks.current(f.state, f.a).sequence, 2)
	assert_eq(f.battle.get("unit_formations", {}).get(f.a, {}).get("target", ""), "line", "late task cannot reform the recipient")

func test_json_retry_preserves_original_request_receipt_and_sequence() -> void:
	if tasks == null: return
	var f := _fixture()
	var order := _order(f, "same")
	var pending: Dictionary = tasks.issue_task(f.repo, f.state, order)
	assert_eq(tasks.issue_task(f.repo, f.state, order), pending)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var received: Dictionary = tasks.deliver_task(f.repo, restored, "same")
	assert_eq(received.status, "received")
	var before: Dictionary = restored.to_dict()
	assert_eq(tasks.deliver_task(f.repo, restored, "same"), received)
	assert_eq(tasks.issue_task(f.repo, restored, order), received)
	assert_eq(restored.to_dict(), before)
	order.task = "defend"
	assert_eq(tasks.issue_task(f.repo, restored, order).status, "invalid")
	assert_eq(restored.to_dict(), before)
	var other := _order(f, "same", "defend", f.b)
	assert_eq(tasks.issue_task(f.repo, restored, other).status, "invalid")
	var legacy: Dictionary = f.state.to_dict()
	legacy.erase("unit_tasks")
	assert_eq(GameState.from_dict(legacy).get("unit_tasks"), {})

func test_general_can_assign_b_but_cannot_replace_player_task_a() -> void:
	if tasks == null: return
	var f := _fixture()
	var person := String(f.state.military_rosters[f.a].commander_id)
	f.battle["commanders"] = {"att": person}
	f.state.regiments[f.a].morale = 1
	tasks.issue_task(f.repo, f.state, _order(f, "royal"))
	assert_eq(tasks.deliver_task(f.repo, f.state, "royal").status, "received", "risk does not veto receipt")
	var general := _order(f, "general-a", "defend")
	general.source = "general"
	general.issuer = person
	assert_eq(tasks.issue_task(f.repo, f.state, general).status, "invalid")
	general.unit = f.b
	general.id = "general-b"
	assert_eq(tasks.issue_task(f.repo, f.state, general).status, "pending")
	assert_eq(tasks.deliver_task(f.repo, f.state, "general-b").status, "received")
	assert_eq(tasks.current(f.state, f.a).request.task, "flank")
	assert_eq(tasks.current(f.state, f.b).request.task, "defend")

func test_law_membership_and_authority_are_rechecked_at_delivery() -> void:
	if tasks == null: return
	var f := _fixture()
	f.battle["parley"] = {"agreed": {"ceasefire": {"policy": "protect"}}}
	assert_eq(tasks.issue_task(f.repo, f.state, _order(f, "blocked")).status, "invalid")
	f.battle.erase("parley")
	tasks.issue_task(f.repo, f.state, _order(f, "later-law"))
	f.battle["parley"] = {"agreed": {"ceasefire": {"policy": "protect"}}}
	assert_eq(tasks.deliver_task(f.repo, f.state, "later-law").status, "invalid")
	assert_true(tasks.current(f.state, f.a).is_empty())
	f.battle.erase("parley")
	tasks.issue_task(f.repo, f.state, _order(f, "left"))
	f.battle.att.erase(f.a)
	assert_eq(tasks.deliver_task(f.repo, f.state, "left").status, "invalid")
	f.battle.att.append(f.a)
	var person := String(f.state.military_rosters[f.a].commander_id)
	f.battle["commanders"] = {"att": person}
	var order := _order(f, "general", "defend", f.b)
	order.source = "general"
	order.issuer = person
	tasks.issue_task(f.repo, f.state, order)
	f.battle.commanders.att = ""
	assert_eq(tasks.deliver_task(f.repo, f.state, "general").status, "invalid")

func test_new_royal_delivery_invalidates_pending_general_without_affecting_current() -> void:
	if tasks == null: return
	var f := _fixture()
	var person := String(f.state.military_rosters[f.a].commander_id)
	f.battle["commanders"] = {"att": person}
	var general := _order(f, "general", "defend")
	general.source = "general"
	general.issuer = person
	tasks.issue_task(f.repo, f.state, general)
	tasks.issue_task(f.repo, f.state, _order(f, "royal"))
	tasks.deliver_task(f.repo, f.state, "royal")
	assert_eq(tasks.deliver_task(f.repo, f.state, "general").status, "superseded")
	assert_eq(tasks.current(f.state, f.a).request.id, "royal")

func _ready_for_wedge(f: Dictionary) -> void:
	f.state.regiments[f.a].morale = 100
	f.state.regiments[f.a].training = 100
	for arm: String in f.repo.world_table("military", "unit_types"):
		f.state.army_roster[f.a][arm] = "0"
	f.state.army_roster[f.a].infantry = "600"

func test_seven_tasks_combine_with_each_existing_formation() -> void:
	if tasks == null: return
	var f := _fixture()
	_ready_for_wedge(f)
	var kinds: Array = f.repo.get("battle_behaviors").keys()
	kinds.sort()
	assert_eq(kinds, ["advance", "charge", "defend", "flank", "guard_flank", "pursue", "retreat"])
	for kind: String in kinds:
		for formation: String in f.repo.battle_formations:
			var order := _order(f, kind + ":" + formation, kind)
			order.formation = formation
			assert_eq(tasks.issue_task(f.repo, f.state, order).status, "pending")
			assert_eq(tasks.deliver_task(f.repo, f.state, order.id).status, "received")
			assert_eq(tasks.current(f.state, f.a).request.formation, formation)
			assert_eq(tasks.current(f.state, f.a).request.task, kind)

func test_replacement_is_single_and_every_transition_has_causality() -> void:
	if tasks == null: return
	var f := _fixture()
	tasks.issue_task(f.repo, f.state, _order(f, "one"))
	tasks.deliver_task(f.repo, f.state, "one")
	tasks.issue_task(f.repo, f.state, _order(f, "two", "advance"))
	var replacement: Dictionary = tasks.deliver_task(f.repo, f.state, "two")
	assert_eq(replacement.status, "received")
	var ledger: Dictionary = f.state.get("unit_tasks")[f.a]
	assert_eq(ledger.current_id, "two")
	assert_eq(ledger.orders.one.status, "replaced")
	assert_eq(ledger.orders.two.status, "received")
	for record: Dictionary in ledger.orders.values():
		for entry: Dictionary in record.history:
			assert_ne(entry.reason, "")
			assert_eq(entry.day, f.state.absolute_day())
			assert_eq(entry.source, "player")
	var copy: Dictionary = tasks.current(f.state, f.a)
	copy.request.task = "defend"
	assert_eq(tasks.current(f.state, f.a).request.task, "advance", "read access cannot mutate the ledger")

func test_unit_law_does_not_inherit_another_units_stricter_policy() -> void:
	if tasks == null: return
	var f := _fixture()
	f.state.law_in_force["unit:" + f.b] = {"battle_tactics": {"value": "restrained", "decree_id": 100}}
	assert_eq(tasks.issue_task(f.repo, f.state, _order(f, "free-a", "charge")).status, "pending")
	assert_eq(tasks.deliver_task(f.repo, f.state, "free-a").status, "received")
	assert_eq(tasks.issue_task(f.repo, f.state, _order(f, "restricted-b", "charge", f.b)).status, "invalid")
	assert_false("charge" in BattleRules.legal_actions(f.repo, f.state, 944, "att"), "army-wide warrant retains its stricter intersection")
	assert_eq(BattleRules.legal_actions(f.repo, f.state, 944, "att", f.enemy), [])

func test_invalid_input_and_removed_targets_do_not_mutate_current_task() -> void:
	if tasks == null: return
	var f := _fixture()
	tasks.issue_task(f.repo, f.state, _order(f, "keep", "defend"))
	tasks.deliver_task(f.repo, f.state, "keep")
	var saved: Dictionary = f.state.to_dict()
	for patch: Dictionary in [{"id": ""}, {"unit": f.enemy}, {"battle_id": 944.5},
			{"task": "unknown"}, {"formation": "circle"}, {"target_unit": f.a},
			{"source": "commander"}, {"source": "general", "issuer": "unknown"},
			{"sequence": 500}, {"issuer": []}, {3: "bad-key"}]:
		var invalid := _order(f, "bad")
		invalid.merge(patch, true)
		assert_eq(tasks.issue_task(f.repo, f.state, invalid).status, "invalid")
		assert_eq(f.state.to_dict(), saved, "refusal is atomic")
	assert_eq(tasks.deliver_task(f.repo, f.state, "missing").status, "invalid")
	var sent := _order(f, "lost-target")
	tasks.issue_task(f.repo, f.state, sent)
	sent.task = "retreat"
	f.state.foes[f.enemy]["captured"] = true
	assert_eq(tasks.deliver_task(f.repo, f.state, "lost-target").status, "invalid")
	assert_eq(tasks.current(f.state, f.a).request.id, "keep")
	var ledger: Dictionary = f.state.get("unit_tasks")[f.a]
	assert_eq(ledger.orders["lost-target"].request.task, "flank", "issued request is frozen")
	assert_eq(ledger.received_sequence, 1)

func test_general_dispatched_after_royal_order_cannot_replace_it_on_arrival() -> void:
	if tasks == null: return
	var f := _fixture()
	var person := String(f.state.military_rosters[f.a].commander_id)
	f.battle["commanders"] = {"att": person}
	tasks.issue_task(f.repo, f.state, _order(f, "royal"))
	var general := _order(f, "general", "defend")
	general.source = "general"
	general.issuer = person
	assert_eq(tasks.issue_task(f.repo, f.state, general).sequence, 2)
	tasks.deliver_task(f.repo, f.state, "royal")
	assert_eq(tasks.deliver_task(f.repo, f.state, "general").status, "invalid")
	assert_eq(tasks.current(f.state, f.a).request.id, "royal")

func test_stale_battle_membership_does_not_keep_missing_target_or_general_alive() -> void:
	if tasks == null: return
	var f := _fixture()
	tasks.issue_task(f.repo, f.state, _order(f, "missing-target"))
	f.state.foes.erase(f.enemy)
	assert_eq(tasks.deliver_task(f.repo, f.state, "missing-target").status, "invalid")
	assert_true(tasks.current(f.state, f.a).is_empty())
	f = _fixture()
	var general := _order(f, "missing-general", "defend", f.b)
	general.source = "general"
	general.issuer = String(f.state.military_rosters[f.a].commander_id)
	f.battle["commanders"] = {"att": general.issuer}
	tasks.issue_task(f.repo, f.state, general)
	f.state.regiments.erase(f.a)
	assert_eq(tasks.deliver_task(f.repo, f.state, "missing-general").status, "invalid")
	assert_true(tasks.current(f.state, f.b).is_empty())

func test_generals_later_deployment_cannot_supersede_the_only_royal_warrant() -> void:
	if tasks == null: return
	var f := _fixture()
	tasks.issue_task(f.repo, f.state, _order(f, "royal-first"))
	var general := _order(f, "general-second", "defend")
	general.source = "general"
	general.issuer = String(f.state.military_rosters[f.a].commander_id)
	f.battle["commanders"] = {"att": general.issuer}
	tasks.issue_task(f.repo, f.state, general)
	assert_eq(tasks.deliver_task(f.repo, f.state, "general-second").status, "received")
	assert_eq(tasks.deliver_task(f.repo, f.state, "royal-first").status, "received")
	assert_eq(tasks.current(f.state, f.a).request.id, "royal-first")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(tasks.current(restored, f.a), tasks.current(f.state, f.a))

func test_general_cannot_authorize_pursuit_without_a_players_contact_plan() -> void:
	if tasks == null: return
	var f := _fixture()
	var order := _order(f, "general-pursuit", "pursue")
	order.source = "general"
	order.issuer = String(f.state.military_rosters[f.a].commander_id)
	f.battle["commanders"] = {"att": order.issuer}
	assert_eq(tasks.issue_task(f.repo, f.state, order).status, "invalid")
	order.source = "player"
	order.issuer = ""
	order.id = "royal-pursuit"
	assert_eq(tasks.issue_task(f.repo, f.state, order).status, "pending")
	assert_eq(tasks.deliver_task(f.repo, f.state, "royal-pursuit").status, "received")

func test_task_formation_starts_only_at_receipt_for_the_recipient() -> void:
	var f := _fixture()
	BattleFormation.ensure(f.battle)
	var side: Dictionary = f.battle.formations.duplicate(true)
	assert_eq(tasks.issue_task(f.repo, f.state, _order(f, "deploy")).status, "pending")
	assert_false(f.battle.has("unit_formations"))
	assert_eq(tasks.deliver_task(f.repo, f.state, "deploy").status, "received")
	assert_eq(f.battle.get("unit_formations", {}).get(f.a, {}).get("target", ""), "line")
	assert_false(f.battle.get("unit_formations", {}).has(f.b))
	assert_eq(f.battle.formations, side)
	assert_eq(BattleFormation.of_unit(f.state, f.a), "double_rank", "preparation is real, not instant")

func test_unsuitable_formation_refuses_atomically_at_issue_and_receipt() -> void:
	var f := _fixture()
	tasks.issue_task(f.repo, f.state, _order(f, "keep"))
	tasks.deliver_task(f.repo, f.state, "keep")
	_ready_for_wedge(f)
	f.state.regiments[f.a].morale = 0
	var next := _order(f, "wedge")
	next.formation = "wedge"
	var before: Dictionary = f.state.to_dict()
	assert_eq(tasks.issue_task(f.repo, f.state, next).status, "invalid")
	assert_eq(f.state.to_dict(), before)
	_ready_for_wedge(f)
	assert_eq(tasks.issue_task(f.repo, f.state, next).status, "pending")
	f.state.regiments[f.a].morale = 0
	var deployment: Dictionary = f.battle.get("unit_formations", {}).duplicate(true)
	assert_eq(tasks.deliver_task(f.repo, f.state, "wedge").status, "invalid")
	assert_eq(tasks.current(f.state, f.a).request.id, "keep")
	assert_eq(f.battle.get("unit_formations", {}), deployment)
	assert_eq(f.state.unit_tasks[f.a].received_sequence, 1)

func test_replacement_and_cancel_do_not_erase_received_formation_costs() -> void:
	var f := _fixture()
	tasks.issue_task(f.repo, f.state, _order(f, "line"))
	tasks.deliver_task(f.repo, f.state, "line")
	assert_true(f.battle.get("unit_formations", {}).has(f.a))
	if not f.battle.get("unit_formations", {}).has(f.a): return
	BattleFormation.advance(f.repo, f.state, f.battle)
	var deployment: Dictionary = f.battle.unit_formations[f.a].duplicate(true)
	var same := _order(f, "same-shape", "defend")
	tasks.issue_task(f.repo, f.state, same)
	tasks.deliver_task(f.repo, f.state, "same-shape")
	assert_eq(f.battle.unit_formations[f.a], deployment, "a new task with the same shape does not reset progress")
	var next := _order(f, "empty", "defend")
	next.formation = ""
	tasks.issue_task(f.repo, f.state, next)
	tasks.deliver_task(f.repo, f.state, "empty")
	assert_eq(f.battle.unit_formations[f.a], deployment)
	var cancel := {"id": "cancel", "unit": f.a, "battle_id": 944, "task": "cancel"}
	tasks.issue_task(f.repo, f.state, cancel)
	assert_eq(f.battle.unit_formations[f.a], deployment)
	tasks.deliver_task(f.repo, f.state, "cancel")
	assert_true(tasks.current(f.state, f.a).is_empty())
	assert_eq(f.battle.unit_formations[f.a], deployment, "cancellation cannot refund physical disorder")
	tasks.deliver_task(f.repo, f.state, "line")
	assert_eq(f.battle.unit_formations[f.a], deployment)

func test_formation_receipt_json_replay_and_retarget_preserve_progress_and_disorder() -> void:
	var f := _fixture()
	tasks.issue_task(f.repo, f.state, _order(f, "first"))
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	for state: GameState in [f.state, saved]:
		assert_eq(tasks.deliver_task(f.repo, state, "first").status, "received")
		BattleFormation.advance(f.repo, state, state.battles[0])
	assert_eq(saved.to_dict(), f.state.to_dict())
	assert_true(f.battle.get("unit_formations", {}).has(f.a))
	if not f.battle.get("unit_formations", {}).has(f.a): return
	var before: Dictionary = saved.to_dict()
	tasks.deliver_task(f.repo, saved, "first")
	BattleFormation.advance(f.repo, saved, saved.battles[0])
	assert_eq(saved.to_dict(), before)
	var deadline := int(f.battle.unit_formations[f.a].disorder_until)
	f.repo.battle_formations.diamond.disorder_days = 0
	var next := _order(f, "retarget")
	next.formation = "diamond"
	tasks.issue_task(f.repo, f.state, next)
	tasks.deliver_task(f.repo, f.state, "retarget")
	assert_eq(f.battle.unit_formations[f.a].target, "diamond")
	assert_eq(int(f.battle.unit_formations[f.a].progress), 0)
	assert_eq(int(f.battle.unit_formations[f.a].disorder_until), deadline)

func test_task_formation_uses_the_existing_local_and_courier_delivery_adapter() -> void:
	for local: bool in [false, true]:
		var f := _fixture()
		tasks.issue_task(f.repo, f.state, _order(f, "transport"))
		var courier := {"id": 1, "target": f.a}
		var order := {"action_code": "BATTLE_TASK", "unit_task_id": "transport"}
		assert_eq(CourierSystem._deliver_one(f.repo, f.state, courier, order, local).type, "delivered")
		assert_eq(f.battle.get("unit_formations", {}).get(f.a, {}).get("target", ""), "line")
		assert_false(f.battle.get("unit_formations", {}).has(f.b))
