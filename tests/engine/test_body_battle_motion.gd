extends GutTest
## B-ROUND: the resumable candidate day driver (begin, one transition per step,
## acknowledgement, round-ready, advance). No damage, round settlement or RNG.

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

## No battle and no day. The crown unit (1000 people, ten rows on y=10000) holds; the
## enemy's single 100-person cavalry row stands 1731 m east of row 0 (927 + 804): only
## row 0 touches. `other` stands 40 km away.
func _world(own_fit: int = 1000) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_contact.gd").new()
	var f: Dictionary = helper.call("_fixture", own_fit, 100)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	for code: String in f.state.army_roster:
		var entry := UnitBodies._entry(f.state, code)
		entry.body_groups = f.state.battles[0].groups[code]
		entry.x_m = int(entry.body_groups[0].x_m)
		entry.y_m = int(entry.body_groups[0].y_m)
		entry.group_anchor_m = [entry.x_m, entry.y_m]
		entry.group_facing = 37
		entry.facing_deg = 37
		entry.order = ArmySystem.ORDER_GARRISON
		entry.dest_x_m = entry.x_m
		entry.dest_y_m = entry.y_m
		for key: String in ["route_m", "departure", "camp_state", "captured", "battle_retreat"]: entry.erase(key)
		var piece := MapObjects.army_piece(f.repo, f.state.army_roster[code])
		f.repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64),
			"turn_q": 400000, "contact_um": 100, "radius_m": int(f.repo.unit_footprints[piece].radius_m),
			"clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
		f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
		f.repo.balance["body_locomotion_" + piece + "_contact_um"] = 100
	f.state.battles = []
	f.state.day_resolution = {}
	f.engine = TickEngine.new(f.repo)
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _hash(state: GameState) -> String:
	return BodyMotion._hash(state.to_dict())

## One transition; the source and its file never change.
func _step(f: Dictionary, state: GameState, expected: String) -> GameState:
	var before := _hash(state)
	var result: Dictionary = f.engine.step_body_battle_candidate(state)
	assert_eq(_hash(state), before, "a step leaves its source unchanged")
	assert_eq(result.status, expected, "%s: %s" % [state.day_resolution.body_battle.stage, result.reason])
	return result.candidate if result.candidate != null else state

func _acknowledge(f: Dictionary, state: GameState) -> GameState:
	var pending: Dictionary = state.day_resolution.pending_decision
	var request := {"kind": "acknowledge", "token": pending.token, "choice": "continue"}
	var boundary := BodyBattleMotion._boundary(state)
	var plan := BodyBattle.plan_candidate(f.repo, state, request, boundary)
	assert_eq(plan.status, "complete", plan.reason)
	var result := BodyBattle.commit_candidate(f.repo, state, plan.plan, boundary)
	assert_eq(result.status, "complete", result.reason)
	return result.candidate

## begin, move, contacts (founds the field), encounter block, acknowledge, round-ready.
func _to_ready(f: Dictionary, save_each: bool) -> Array:
	var states: Array = []
	var begun: Dictionary = f.engine.begin_body_battle_candidate(f.state)
	assert_eq(begun.status, "complete", begun.reason)
	assert_eq(begun.plan, {}, "begin's convenience result carries no plan")
	var state: GameState = begun.candidate
	for expected: String in ["complete", "complete", "blocked", "ack", "blocked"]:
		if save_each: state = _json(state)
		state = _acknowledge(f, state) if expected == "ack" else _step(f, state, expected)
		states.append(state)
	return states

func test_mid_slice_round_ready_json_retry() -> void:
	var f := _world()
	var direct := _to_ready(f, false)
	var saved := _to_ready(_world(), true)
	var ready: GameState = direct.back()
	assert_eq(_hash(saved.back()), _hash(ready), "JSON save after every transition reaches the same endpoint")
	for i: int in direct.size():
		assert_eq(_hash(_json(direct[i])), _hash(_json(saved[i])), "transition %d" % i)
	# The encounter blocked once with its decision, then acknowledgement cleared it.
	assert_eq(direct[2].day_resolution.pending_decision.kind, "encounter")
	assert_true(direct[3].day_resolution.pending_decision.is_empty())
	var tx: Dictionary = ready.day_resolution
	assert_eq(tx.body_battle.stage, "round")
	assert_eq(ready.battles.size(), 1)
	var battle: Dictionary = ready.battles[0]
	var id := int(battle.id)
	assert_eq(tx.battle_ids, [id])
	assert_eq(tx.battle_index, 0)
	var envelope: Dictionary = battle.body_round
	assert_eq(envelope.token, "bodyround:%d:%d:1" % [id, ready.absolute_day()])
	assert_eq(envelope.round, "1")
	assert_eq(envelope.motion_receipt, ready.military_migration.body_battle.closed_motion.receipt)
	assert_eq(envelope.contact_digest, BodyMotion._hash(envelope.contacts))
	# Hand count: only the crown unit's row 0 touches the enemy's one row, both directions.
	assert_eq(envelope.contacts.size(), 2)
	var engaged := 0
	for pair: Dictionary in envelope.contacts:
		assert_eq(pair.slot, 0)
		assert_eq(pair.target_slot, 0)
		assert_eq(pair.count, 100)
		assert_eq(pair.target_count, 100)
		if pair.unit == f.unit: engaged += pair.count
	assert_eq(engaged, 100)
	assert_eq(MilitaryRoster.fit(ready, f.unit), 1000)
	assert_eq(MilitaryRoster.fit(ready, f.unit) - engaged, 900, "900 stay unengaged")
	assert_eq(envelope.unit_actions.keys().size(), 2)
	# No damage, cost or draw yet.
	assert_eq(ready.rng.to_dict(), f.state.rng.to_dict())
	assert_eq(ready.military_cohorts, f.state.military_cohorts)
	assert_eq(ready.metrics, f.state.metrics)
	for code: String in [f.unit, f.enemy]:
		assert_eq(UnitBodies._entry(ready, code).supplies, UnitBodies._entry(f.state, code).supplies)
	assert_false(battle.has("pending_round"))
	# Absent CF06 the round stays blocked; repeating is an exact no-op, direct and JSON.
	for source: GameState in [ready, _json(ready)]:
		var held := _step(f, source, "blocked")
		assert_eq(_hash(held), _hash(ready))
		assert_eq(held.day_resolution.body_battle.stage, "round")
	# Changed inputs after readiness error with the input file unchanged.
	for change: String in ["row", "party", "law", "route", "budget", "policy", "diplomacy"]:
		var changed := _json(ready)
		var restore: Variant = null
		match change:
			"row": changed.battles[0].groups[f.unit][0].facing_deg += 1
			"party": changed.battles[0].parley.parties.att = []
			"law": changed.law_decree = {"battle_tactics": {"value": "restrained", "decree_id": 1, "day": 1, "sent": true}}
			"route": UnitBodies._entry(changed, f.unit).route_m = [[90000, 10000]]
			"budget": changed.day_resolution.march_budgets[f.unit] = 1
			"policy":
				restore = f.repo.balance.battle_group_contact_m
				f.repo.balance.battle_group_contact_m = 99
			"diplomacy":
				restore = f.repo.world_table("political", "diplomacy").duplicate(true)
				f.repo.world_table("political", "diplomacy")["extra"] = {"stance": "war"}
		var before := _hash(changed)
		var result: Dictionary = f.engine.step_body_battle_candidate(changed)
		assert_eq(result.status, "error", change)
		assert_null(result.candidate)
		assert_eq(_hash(changed), before)
		if change == "policy": f.repo.balance.battle_group_contact_m = restore
		if change == "diplomacy":
			var table: Dictionary = f.repo.world_table("political", "diplomacy")
			table.erase("extra")
			assert_eq(table, restore)

func test_second_slice_queue_is_admissible() -> void:
	var helper: GutTest = load("res://tests/engine/test_body_battle_merge.gd").new()
	var cases: Array = []
	for name: String in ["apart", "alias", "merge", "reverse", "unit_barrier"]:
		var f: Dictionary = helper.call("_fixture")
		var today: int = f.state.absolute_day()
		var tx: Dictionary = f.state.day_resolution
		if name != "merge" and name != "reverse":
			for code: String in [f.c, f.d]:
				for row: Dictionary in f.state.battles[1].groups[code]:
					row.y_m += 50000
					row.path_m = []
				f.state.battles[1].group_anchor_m[code][1] += 50000
				UnitBodies._entry(f.state, code).y_m += 50000
		if name == "unit_barrier":
			tx.body_battle.processed_units = [f.c]
		else:
			f.state.battles[0].last_resolved_day = today
			tx.processed_battle_ids = [8]
			var units: Array = [f.a, f.b]
			units.sort()
			tx.body_battle.processed_units = units
		if name == "alias": f.state.battle_aliases = {"12": 8}
		if name == "reverse":
			var towns: Array = f.repo.burgs.keys()
			towns.sort()
			f.state.battles[1].town = towns[0]
		BodyBattle._seal_private(f.repo, f.state)
		var boundary := BodyBattleMotion._boundary(f.state)
		var plan := BodyBattle.plan_candidate(f.repo, f.state, {"kind": "contacts"}, boundary)
		assert_eq(plan.status, "complete", "%s: %s" % [name, plan.reason])
		if plan.status != "complete": continue
		var result := BodyBattle.commit_candidate(f.repo, f.state, plan.plan, boundary)
		assert_eq(result.status, "complete", "%s: %s" % [name, result.reason])
		if result.candidate == null: continue
		var after: GameState = result.candidate
		var expected: Array = {"apart": [[9], [8]], "alias": [[9], [8]], "merge": [[], [8]],
			"reverse": [[], [9]], "unit_barrier": [[8], [9]]}[name]
		assert_eq(after.day_resolution.battle_ids, expected[0], name)
		assert_eq(after.day_resolution.body_battle.battle_ids, expected[0].map(func(id: int) -> String: return str(id)), name)
		assert_eq(after.day_resolution.battle_index, 0)
		assert_eq(after.day_resolution.processed_battle_ids, expected[1], name)
		assert_eq(after.day_resolution.body_battle.stage, "round" if not expected[0].is_empty() else "advance", name)
		for source: GameState in [after, _json(after)]:
			var checked := UnitBodies.validate_battle_candidate(f.repo, source, BodyBattleMotion._boundary(source))
			assert_eq(checked.status, "complete", "%s: %s" % [name, checked.reason])
		cases.append([name, f, after])
	helper.free()
	# Tampering the queue, index, processed membership or the daily unit barrier is rejected.
	var apart: Array = cases[0]
	var f: Dictionary = apart[1]
	for tamper: String in ["queue", "index", "processed", "barrier"]:
		var state := _json(apart[2])
		var tx: Dictionary = state.day_resolution
		match tamper:
			"queue":
				# The already processed 8 cannot re-enter slice 1's unresolved queue.
				tx.battle_ids = [8, 9]
				tx.body_battle.battle_ids = ["8", "9"]
			"index":
				tx.battle_index = 1
				tx.body_battle.battle_index = "1"
			"processed": tx.processed_battle_ids = [8, 9]
			"barrier": tx.body_battle.processed_units = [f.c]
		BodyBattle._seal_private(f.repo, state)
		var checked := UnitBodies.validate_battle_candidate(f.repo, state, BodyBattleMotion._boundary(state))
		assert_eq(checked.status, "error", tamper)

func test_begin_runs_a_quiet_day_to_complete_and_then_defers() -> void:
	var f := _world()
	for row: Dictionary in UnitBodies._entry(f.state, f.enemy).body_groups: row.y_m += 20000
	UnitBodies._entry(f.state, f.enemy).y_m += 20000
	UnitBodies._entry(f.state, f.enemy).group_anchor_m[1] += 20000
	UnitBodies._entry(f.state, f.enemy).dest_y_m += 20000
	var begun: Dictionary = f.engine.begin_body_battle_candidate(f.state)
	assert_eq(begun.status, "complete", begun.reason)
	var state: GameState = begun.candidate
	assert_eq(state.military_migration.body_battle.sequence, "0")
	assert_eq(state.day_resolution.body_battle.sequence, "1")
	assert_eq(state.day_resolution.body_battle.stage, "move")
	assert_eq(state.day_resolution.march_budgets.keys().size(), 3, "every non-naval unit has a frozen budget")
	var again: Dictionary = f.engine.begin_body_battle_candidate(state)
	assert_eq(again.status, "deferred", "begin on a frozen day defers")
	# Ten slices of move, contacts (nothing touches) and advance.
	for slice: int in 10:
		for stage: String in ["move", "contact", "advance"]:
			assert_eq(state.day_resolution.body_battle.stage, stage, "slice %d" % slice)
			assert_eq(state.day_resolution.body_battle.next_substep, str(slice))
			state = _step(f, state, "complete")
	assert_eq(state.day_resolution.body_battle.stage, "complete")
	assert_eq(state.day_resolution.body_battle.next_substep, "10")
	assert_eq(state.day_resolution.substep_index, 10)
	# One outer operation per transition: begin 0, then 30 more.
	assert_eq(state.military_migration.body_battle.sequence, "30")
	assert_eq(state.day_resolution.body_battle.sequence, "31")
	assert_eq(state.battles, [])
	assert_eq(state.rng.to_dict(), f.state.rng.to_dict())
	assert_eq(state.military_cohorts, f.state.military_cohorts)
	var done: Dictionary = f.engine.step_body_battle_candidate(state)
	assert_eq(done.status, "deferred")
	assert_eq(done.reason, "Candidate day is complete")
	assert_eq(f.engine.begin_body_battle_candidate(state).status, "deferred")
	var loaded := _json(state)
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, loaded, BodyBattleMotion._boundary(loaded)).status, "complete")

func test_advance_step_ends_an_emptied_field_before_advancing() -> void:
	var helper: GutTest = load("res://tests/engine/test_body_battle_end.gd").new()
	var f: Dictionary = helper.call("_fixture")
	helper.call("_empty_att", f)
	helper.free()
	f.engine = TickEngine.new(f.repo)
	var ended := _step(f, f.state, "complete")
	assert_eq(ended.battles, [])
	assert_eq(ended.day_resolution.journal.battles.back().why, "emptied")
	assert_eq(ended.day_resolution.body_battle.stage, "advance")
	var next := _step(f, ended, "complete")
	assert_eq(next.day_resolution.body_battle.stage, "move")
	assert_eq(next.day_resolution.body_battle.next_substep, "1")
	assert_eq(next.day_resolution.battle_ids, [])
	assert_eq(next.day_resolution.processed_battle_ids, [8])

func test_closed_requests_and_wrong_stage() -> void:
	var f := _world()
	var begun: Dictionary = f.engine.begin_body_battle_candidate(f.state)
	var state: GameState = begun.candidate
	var boundary := BodyBattleMotion._boundary(state)
	var before := _hash(state)
	for request: Dictionary in [{"kind": "begin", "extra": 1}, {"kind": "advance", "x": 1}, {"kind": "round_ready", "battle_id": 8},
		{"kind": "round_ready", "battle_id": "0"}, {"kind": "acknowledge", "token": "", "choice": "continue"}]:
		assert_eq(BodyBattle.plan_candidate(f.repo, state, request, boundary).status, "error", str(request))
	for request: Dictionary in [{"kind": "advance"}, {"kind": "round_ready", "battle_id": "8"}]:
		var waited := BodyBattle.plan_candidate(f.repo, state, request, boundary)
		assert_eq(waited.status, "deferred", str(request))
		assert_eq(waited.reason, "Operation waits for its lifecycle stage")
	assert_eq(_hash(state), before)
	assert_eq(BodyBattle.step_candidate(null, state).status, "error")
	assert_eq(f.engine.step_body_battle_candidate(f.state).status, "error", "no candidate day to step")
