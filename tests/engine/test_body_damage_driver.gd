extends GutTest
## D-DRIVER (CF06): the candidate day's round stage drives a frozen round through planning
## (one draw) and settlement, one control transition each, then the queue moves on. No second
## round the same day; every stage retries exactly, direct and through JSON.
## World: D-PENDING's — the crown unit (1000 people, ten rows) holds; the enemy's single
## 100-person cavalry row attacks.

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _ready_world() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_round_pending.gd").new()
	var f: Dictionary = helper.call("_ready_world")
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _hash(state: GameState) -> String:
	return BodyMotion._hash(state.to_dict())

func _step(f: Dictionary, state: GameState, expected: String) -> GameState:
	var before := _hash(state)
	var result: Dictionary = f.engine.step_body_battle_candidate(state)
	assert_eq(_hash(state), before, "a step leaves its source unchanged")
	assert_eq(result.status, expected, "%s: %s" % [state.day_resolution.body_battle.stage, result.reason])
	return result.candidate if result.candidate != null else state

func test_round_stage_plans_then_settles_then_advances() -> void:
	var f := _ready_world()
	var ready: GameState = f.ready
	var draw := Rng.from_dict(ready.rng.to_dict())
	draw.randi_range(0, 999)
	# Transition 1: planning freezes the pending and the one draw; the stage stays round.
	var planned := _step(f, ready, "complete")
	assert_true(planned.battles[0].has("pending_round"))
	assert_eq(planned.rng.to_dict(), draw.to_dict(), "exactly one draw")
	assert_eq(planned.day_resolution.body_battle.stage, "round")
	assert_eq(int(planned.military_migration.body_battle.sequence), int(ready.military_migration.body_battle.sequence) + 1)
	assert_eq(planned.military_cohorts, ready.military_cohorts, "no personnel before settlement")
	var plan: Dictionary = planned.battles[0].body_round_plan.plan
	# Transition 2: settlement applies exactly the frozen effects and exhausts the one-field queue.
	var settled := _step(f, planned, "complete")
	var battle: Dictionary = settled.battles[0]
	assert_false(battle.has("body_round"))
	assert_eq(int(battle.rounds), 1)
	assert_eq(settled.rng.to_dict(), draw.to_dict(), "settlement draws nothing")
	var receipt: Dictionary = settled.military_events["bodyround:%d:%d:1:settlement" % [f.id, ready.absolute_day()]]
	assert_eq(settled.day_resolution.journal.battles.back(), receipt.result.round_event, "the day's round event")
	assert_eq(settled.day_resolution.journal.battles.size(), planned.day_resolution.journal.battles.size() + 1)
	for code: String in [f.unit, f.enemy]:
		var lost := int(plan.effects.unit_results[code].dead) + int(plan.effects.unit_results[code].wounded)
		assert_eq(MilitaryRoster.fit(settled, code), MilitaryRoster.fit(ready, code) - lost, code)
	assert_eq(settled.day_resolution.body_battle.stage, "advance")
	assert_eq(settled.day_resolution.body_battle.next_substep, ready.day_resolution.body_battle.next_substep)
	assert_eq(int(settled.military_migration.body_battle.sequence), int(planned.military_migration.body_battle.sequence) + 1)
	# Transition 3: the slice advances.
	var advanced := _step(f, settled, "complete")
	assert_eq(advanced.day_resolution.body_battle.stage, "move")
	assert_eq(int(advanced.day_resolution.body_battle.next_substep), int(ready.day_resolution.body_battle.next_substep) + 1)

func test_no_second_round_the_same_day() -> void:
	var f := _ready_world()
	var state := _step(f, _step(f, f.ready, "complete"), "complete")
	var draws := state.rng.to_dict()
	var fits := {f.unit: MilitaryRoster.fit(state, f.unit), f.enemy: MilitaryRoster.fit(state, f.enemy)}
	# The rest of the day: every later slice the field stays in contact but is already processed,
	# so each slice is move, contacts (nothing queued) and advance; the day completes.
	var guard := 0
	while state.day_resolution.body_battle.stage != "complete" and guard < 100:
		guard += 1
		var stage: String = state.day_resolution.body_battle.stage
		assert_ne(stage, "round", "no field is queued for a second round")
		state = _step(f, state, "complete")
	assert_eq(state.day_resolution.body_battle.stage, "complete")
	assert_eq(int(state.battles[0].rounds), 1)
	assert_eq(state.rng.to_dict(), draws, "no second draw")
	assert_eq({f.unit: MilitaryRoster.fit(state, f.unit), f.enemy: MilitaryRoster.fit(state, f.enemy)}, fits)
	assert_eq(f.engine.step_body_battle_candidate(state).reason, "Candidate day is complete")

func test_each_round_transition_retries_exactly_direct_and_json() -> void:
	var f := _ready_world()
	var planned := _step(f, f.ready, "complete")
	var settled := _step(f, planned, "complete")
	# The same input file gives the same transition, direct and through a JSON save.
	for pair: Array in [[f.ready, planned], [planned, settled]]:
		for source: GameState in [pair[0], _json(pair[0])]:
			assert_eq(_hash(_step(f, source, "complete")), _hash(pair[1]))
	# A failed settlement (a stale family-loss receipt outside the basis) stays blocked on the
	# frozen pending; repairing that receipt settles the same draw.
	var broken := _json(planned)
	var n := int(planned.battles[0].pending_round.round)
	var stale := "family:battle:%d:round:%d:%s" % [f.id, n, f.unit]
	broken.military_events[stale] = {"request": {"kind": "stale"}, "result": {}}
	BodyBattle._seal_private(f.repo, broken)
	var held := _step(f, broken, "blocked")
	assert_eq(_hash(held), _hash(broken))
	assert_eq(_hash(_step(f, _json(held), "blocked")), _hash(broken))
	held.military_events.erase(stale)
	BodyBattle._seal_private(f.repo, held)
	assert_eq(_hash(_step(f, held, "complete")), _hash(settled))
	# Malformed frozen state through the driver fails closed: never a second planning draw.
	for broken_kind: String in ["pending_only", "wrapper_only", "wrapper_not_dict"]:
		var bad := _json(planned)
		var live: Dictionary = bad.battles[0]
		match broken_kind:
			"pending_only": live.erase("body_round_plan")
			"wrapper_only": live.erase("pending_round")
			"wrapper_not_dict": live.body_round_plan = "forged"
		BodyBattle._seal_private(f.repo, bad)
		var result: Dictionary = f.engine.step_body_battle_candidate(bad)
		assert_eq(result.status, "error", broken_kind)
		assert_null(result.candidate, broken_kind)
	# A changed basis after readiness errors, with no candidate.
	var moved := _json(f.ready)
	moved.battles[0].groups[f.unit][5].y_m += 1
	BodyBattle._seal_private(f.repo, moved)
	var refused: Dictionary = f.engine.step_body_battle_candidate(moved)
	assert_eq(refused.status, "error")
	assert_null(refused.candidate)

## B-MERGE's two separate fields (8: A–B, 9: C–D, 50 km apart) from a real begin.
func _two_fields() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_merge.gd").new()
	var f: Dictionary = helper.call("_fixture")
	helper.free()
	_shift(f, f.state, 50000)
	f.state.day_resolution = {}
	for code: String in [f.a, f.b, f.c, f.d]:
		var entry := UnitBodies._entry(f.state, code)
		entry.order = ArmySystem.ORDER_GARRISON
		entry.dest_x_m = entry.x_m
		entry.dest_y_m = entry.y_m
		for key: String in ["route_m", "departure", "camp_state"]: entry.erase(key)
	f.engine = TickEngine.new(f.repo)
	return f

## Field 9's rows and units, moved north by `dy` metres.
func _shift(f: Dictionary, state: GameState, dy: int) -> void:
	var field: Dictionary = state.battles[1]
	for code: String in [f.c, f.d]:
		for row: Dictionary in field.groups[code]:
			row.y_m += dy
			row.path_m = []
		field.group_anchor_m[code][1] += dy
		UnitBodies._entry(state, code).y_m += dy

func test_two_field_queue_prefix_then_merge_fights_no_second_round() -> void:
	var f := _two_fields()
	var begun: Dictionary = f.engine.begin_body_battle_candidate(f.state)
	assert_eq(begun.status, "complete", begun.reason)
	var state: GameState = begun.candidate
	var start := Rng.from_dict(state.rng.to_dict())
	# The exact first slice: move, contacts queue [8, 9], then each field ready → planned →
	# settled in queue order, then the slice advances.
	var expected := [["move", 0, "complete"], ["contact", 0, "complete"],
		["round", 0, "blocked"], ["round", 0, "complete"], ["round", 0, "complete"],
		["round", 1, "blocked"], ["round", 1, "complete"], ["round", 1, "complete"], ["advance", 2, "complete"]]
	for want: Array in expected:
		assert_eq([state.day_resolution.body_battle.stage, int(state.day_resolution.battle_index)], [want[0], want[1]])
		state = _step(f, state, want[2])
		if want[0] == "contact": assert_eq(state.day_resolution.battle_ids, [8, 9])
	assert_eq(state.day_resolution.processed_battle_ids, [8, 9])
	var units: Array = [f.a, f.b, f.c, f.d]
	units.sort()
	assert_eq(state.day_resolution.body_battle.processed_units, units)
	for battle: Dictionary in state.battles: assert_eq(int(battle.rounds), 1, str(battle.id))
	start.randi_range(0, 999)
	start.randi_range(0, 999)
	assert_eq(state.rng.to_dict(), start.to_dict(), "one draw per field")
	# Slice 1: field 9 comes back beside field 8; contacts merge them, and the merged field —
	# both halves already fought today — queues nothing.
	_shift(f, state, -50000)
	BodyBattle._seal_private(f.repo, state)
	state = _step(f, state, "complete")   # move
	state = _step(f, state, "complete")   # contacts merge
	assert_eq(state.battles.size(), 1)
	assert_eq(state.battle_aliases, {"9": 8})
	assert_eq(state.day_resolution.battle_ids, [])
	assert_eq(state.day_resolution.body_battle.stage, "advance")
	assert_eq(int(state.battles[0].rounds), 1)
	assert_eq(state.rng.to_dict(), start.to_dict(), "no second round after the merge")
	for source: GameState in [state, _json(state)]:
		assert_eq(UnitBodies.validate_battle_candidate(f.repo, source, BodyBattleMotion._boundary(source)).status, "complete")
