extends GutTest
## ACT-LIFECYCLE: every lifecycle edge on an admitted body world is a zero-delta ownership
## transfer. Fixtures are the accepted B-ENTER/B-MERGE/B-WITHDRAW/B-END ones; group size 100.
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

## Hand-computed rows of 100: 1000 -> ten full; 901 -> nine full and a one-person tail;
## 900 -> nine full; 1 -> one; 0 -> an empty store.
const FITS := {1000: [100, 100, 100, 100, 100, 100, 100, 100, 100, 100],
	901: [100, 100, 100, 100, 100, 100, 100, 100, 100, 1],
	900: [100, 100, 100, 100, 100, 100, 100, 100, 100], 1: [1], 0: []}

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _helper(path: String, method: String, args: Array = []) -> Dictionary:
	var helper: GutTest = load(path).new()
	var f: Dictionary = helper.callv(method, args)
	assert_eq(helper.get_fail_count(), 0, path)
	helper.free()
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

## Plans one edge, commits it through the adapter on the source and its JSON copy (same
## published state, source untouched), then replays the committed plan as a proved no-op.
func _edge(repo: DataRepository, source: GameState, request: Dictionary) -> GameState:
	var boundary := BodyBattleMotion._boundary(source)
	var file := BodyMotion._hash(source.to_dict())
	var planned := BodyBattle.plan_candidate(repo, source, request, boundary)
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return null
	var result := BodyLifecycle.commit_candidate(repo, source, planned.plan, boundary)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(BodyMotion._hash(source.to_dict()), file, "the source is never touched")
	if result.candidate == null: return null
	var copy := BodyLifecycle.commit_candidate(repo, _json(source), planned.plan, boundary)
	assert_eq(copy.status, "complete", copy.reason)
	if copy.candidate != null: assert_eq(BodyMotion._hash(copy.candidate.to_dict()), BodyMotion._hash(result.candidate.to_dict()))
	for again: GameState in [result.candidate, _json(result.candidate)]:
		var retry := BodyLifecycle.commit_candidate(repo, again, planned.plan, boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), BodyMotion._hash(result.candidate.to_dict()))
	assert_eq(BodyLifecycle.continuity_error(source, result.candidate, request), "")
	assert_eq(BodyLifecycle.continuity_error(result.candidate, result.candidate, {"kind": "replay"}), "")
	return result.candidate

func _rows(state: GameState, code: String) -> Dictionary:
	return BodyLifecycle.snapshot(state)[code].rows

func _counts(state: GameState, code: String) -> Array:
	return _rows(state, code).values().map(func(row: Dictionary) -> int: return row.count)

## B-ENTER's nonbattle world with the crown unit at `fit` (the enemy keeps 100).
func _contact_world(fit: int) -> Dictionary:
	var f := _helper("res://tests/engine/test_body_battle_contact.gd", "_fixture", [fit, 100])
	for code: String in f.state.army_roster:
		var entry := UnitBodies._entry(f.state, code)
		entry.body_groups = f.state.battles[0].groups[code]
		entry.group_anchor_m = [int(entry.x_m), int(entry.y_m)]
		entry.group_facing = 37
		entry.facing_deg = 37
		for row: Dictionary in entry.body_groups:
			row.path_m = [[row.x_m - 2, row.y_m], [row.x_m, row.y_m]]
		var piece := MapObjects.army_piece(f.repo, f.state.army_roster[code])
		f.repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64),
			"turn_q": 400000, "contact_um": 100, "radius_m": int(f.repo.unit_footprints[piece].radius_m),
			"clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
		f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
		f.repo.balance["body_locomotion_" + piece + "_contact_um"] = 100
	f.state.battles = []
	var tx := DayResolution.begin(f.state.day, false, f.state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = 5
	tx.march_entries = {}
	tx.march_budgets = {}
	tx.marching_codes = []
	tx.body_battle = {"version": "1", "abs_day": str(f.state.absolute_day()), "sequence": "0",
		"next_substep": "0", "substep_count": "10", "stage": "contact",
		"battle_ids": [], "battle_index": "0", "processed_units": []}
	f.state.day_resolution = tx
	return f

func test_start_founders_keep_every_body_at_each_fit() -> void:
	for fit: int in FITS:
		var f := _contact_world(fit)
		var before := BodyLifecycle.snapshot(f.state)
		assert_eq(_counts(f.state, f.unit), FITS[fit], "fit %d before contact" % fit)
		var state := _edge(f.repo, f.state, {"kind": "contacts"})
		if state == null: continue
		var after := BodyLifecycle.snapshot(state)
		if fit == 0:
			# A zero-fit unit cannot fight: it keeps its empty nonbattle store and no field starts.
			assert_eq(state.battles, [], "fit 0")
			assert_eq(after, before)
			continue
		assert_eq(state.battles.size(), 1, "fit %d" % fit)
		for code: String in [f.unit, f.enemy]:
			assert_eq(after[code].owner, int(state.battles[0].id), "fit %d %s enrolled" % [fit, code])
			for field: String in ["rows", "anchor", "facing", "unit_facing", "next_slot"]:
				assert_eq(after[code][field], before[code][field], "fit %d %s %s" % [fit, code, field])
		assert_eq(_counts(state, f.unit), FITS[fit], "fit %d after contact" % fit)
		var entry := UnitBodies._entry(f.state, f.unit)
		assert_eq(after[f.unit].anchor, [int(entry.x_m), int(entry.y_m)])
		assert_eq(after[f.unit].facing, 37)
		assert_eq(after[f.unit].next_slot, 20)

func test_join_moves_only_the_joiner() -> void:
	var path := "res://tests/engine/test_body_battle_enter.gd"
	var helper: GutTest = load(path).new()
	var f: Dictionary = helper.call("_fixture")
	helper.call("_field", f)
	helper.call("_joiner", f)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var before := BodyLifecycle.snapshot(f.state)
	var state := _edge(f.repo, f.state, {"kind": "enter", "unit": f.other, "battle_id": "8", "side": "att"})
	if state == null: return
	var after := BodyLifecycle.snapshot(state)
	assert_eq(before[f.other].owner, 0)
	assert_eq(after[f.other].owner, 8)
	assert_eq(_counts(state, f.other), FITS[901])
	assert_eq(_rows(state, f.other)["9"], {"slot": 9, "home_slot": 9, "count": 1, "x_m": 100000, "y_m": 11731,
		"facing_deg": 37, "role": "reserve", "path_m": [[100000, 11730], [100000, 11731]]})
	for code: String in [f.unit, f.enemy]: assert_eq(after[code], before[code], code)

func test_merge_moves_the_absorbed_field_whole() -> void:
	var f := _helper("res://tests/engine/test_body_battle_merge.gd", "_fixture")
	var before := BodyLifecycle.snapshot(f.state)
	var state := _edge(f.repo, f.state, {"kind": "merge", "first_id": "8", "second_id": "9"})
	if state == null: return
	var after := BodyLifecycle.snapshot(state)
	assert_eq(state.battles.size(), 1)
	assert_eq(BattleSystem.canonical(state, 9), 8, "the absorbed id names its survivor")
	for code: String in after:
		assert_eq(after[code].owner, 8, code)
		assert_eq(after[code].rows, before[code].rows, code)
		assert_eq(after[code].anchor, before[code].anchor, code)
		assert_eq(after[code].facing, before[code].facing, code)
		assert_eq(_counts(state, code), FITS[901], code)

func test_exit_returns_the_exact_store_to_owner_zero() -> void:
	var path := "res://tests/engine/test_body_battle_withdraw.gd"
	var helper: GutTest = load(path).new()
	var f: Dictionary = helper.call("_fixture", 901)
	helper.call("_put", f, f.enemy, [30000, 60000])
	var source: GameState = helper.call("_advance", f, f.state)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var before := BodyLifecycle.snapshot(source)
	var state := _edge(f.repo, source, {"kind": "withdraw", "unit": f.code, "battle_id": "8", "reason": "Actual separated withdrawal"})
	if state == null: return
	var after := BodyLifecycle.snapshot(state)
	assert_eq(before[f.code].owner, 8)
	assert_eq(after[f.code].owner, 0)
	assert_eq(after[f.code].rows, before[f.code].rows)
	assert_eq(after[f.code].anchor, [50000, 60000])
	assert_eq(_counts(state, f.code), FITS[901])
	for code: String in [f.enemy, f.other]: assert_eq(after[code], before[code], code)

## B-END's advance-stage field 8 with the crown unit at `fit`; `other` holds an empty store.
func _end_world(fit: int) -> Dictionary:
	var f := _helper("res://tests/engine/test_body_battle_deploy.gd", "_field", [fit])
	var state: GameState = f.state
	assert_false(Personnel.replace(f.repo, state, f.other, 0).has("error"))
	var battle: Dictionary = state.battles[0]
	battle.groups[f.other] = []
	battle.rounds = 2
	battle.town = ""
	for side: String in BattleSystem.SIDES:
		for code: String in battle[side]:
			BattleReport.enroll(state, battle, code, side)
	var tx := state.day_resolution
	tx.body_battle.stage = "advance"
	tx.battle_step = "fighting"
	tx.battle_ids = [8]
	tx.battle_index = 1
	tx.processed_battle_ids = [8]
	tx.body_battle.battle_ids = ["8"]
	tx.body_battle.battle_index = "1"
	BodyBattle._seal_private(f.repo, state)
	return f

func test_end_releases_every_member_exactly_at_each_fit() -> void:
	for fit: int in FITS:
		var f := _end_world(fit)
		var before := BodyLifecycle.snapshot(f.state)
		assert_eq(_counts(f.state, f.unit), FITS[fit], "fit %d in battle" % fit)
		var state := _edge(f.repo, f.state, {"kind": "cancel", "battle_id": "8", "reason": "Received terminal release"})
		if state == null: continue
		assert_eq(state.battles, [], "fit %d: the field is deleted after every store left" % fit)
		var after := BodyLifecycle.snapshot(state)
		for code: String in f.codes:
			assert_eq(before[code].owner, 8)
			assert_eq(after[code].owner, 0, "fit %d %s released" % [fit, code])
			assert_eq(after[code].rows, before[code].rows, "fit %d %s" % [fit, code])
			assert_eq(after[code].next_slot, 20)
		assert_eq(after[f.unit].anchor, [40000, 60000])
		assert_eq(after[f.unit].facing, 0)
		assert_eq(after[f.enemy].facing, 180)
		assert_eq(_counts(state, f.unit), FITS[fit], "fit %d released" % fit)
		assert_eq(after[f.other].rows, {}, "an empty store stays an initialized empty set")

func test_any_displacement_or_owner_slip_is_refused() -> void:
	var f := _end_world(901)
	var request := {"kind": "cancel", "battle_id": "8", "reason": "Received terminal release"}
	var state := _edge(f.repo, f.state, request)
	if state == null: return
	var unit: String = f.unit
	var cases := {
		"Lifecycle moved body %s:9" % unit: func(s: GameState) -> void: UnitBodies._entry(s, unit).body_groups[9].x_m += 1,
		"Lifecycle moved body %s:0" % unit: func(s: GameState) -> void: UnitBodies._entry(s, unit).body_groups[0].path_m = [[1, 1]],
		"Lifecycle renumbered, added or retired a body of " + unit: func(s: GameState) -> void: UnitBodies._entry(s, unit).body_groups[9].slot = 19,
		"Lifecycle changed the anchor of " + unit: func(s: GameState) -> void: UnitBodies._entry(s, unit).group_anchor_m = [40001, 60000],
		"Lifecycle changed the facing of " + unit: func(s: GameState) -> void: UnitBodies._entry(s, unit).group_facing = 1,
		"Lifecycle changed the next_slot of " + unit: func(s: GameState) -> void: UnitBodies._entry(s, unit).group_next_slot = 21,
		"Lifecycle changed personnel or RNG": func(s: GameState) -> void: s.rng.randi_range(0, 999),
	}
	for expected: String in cases:
		var forged := UnitBodies._copy(state)
		cases[expected].call(forged)
		assert_eq(BodyLifecycle.continuity_error(f.state, forged, request), expected)
	# Owner bookkeeping: an end must release every member; a join may not enroll a bystander.
	assert_string_starts_with(BodyLifecycle.continuity_error(f.state, f.state, request), "Lifecycle did not move the owner of ")
	var join := {"kind": "enter", "unit": f.unit, "battle_id": "8", "side": "att"}
	assert_string_starts_with(BodyLifecycle.continuity_error(state, f.state, join), "Unlawful body owner change: ")
	var wrong := {"kind": "enter", "unit": f.unit, "battle_id": "9", "side": "att"}
	assert_eq(BodyLifecycle._owner_error(state, wrong, {f.unit: {"owner": 0}}, {f.unit: {"owner": 8}}),
		"Lifecycle did not move the owner of " + f.unit, "joined the wrong field")
	var faced := UnitBodies._copy(state)
	UnitBodies._entry(faced, f.unit).facing_deg = 91
	assert_eq(BodyLifecycle.continuity_error(f.state, faced, request), "Lifecycle changed the unit_facing of " + f.unit)
	var cursor := UnitBodies._copy(state)
	cursor.military_migration.body_motion = {"version": "1"}
	assert_eq(BodyLifecycle.continuity_error(f.state, cursor, request), "Lifecycle invented a motion cursor")

func test_non_edges_pending_decisions_and_failures_publish_nothing() -> void:
	var f := _end_world(901)
	var boundary := BodyBattleMotion._boundary(f.state)
	var file := BodyMotion._hash(f.state.to_dict())
	var planned := BodyBattle.plan_candidate(f.repo, f.state, {"kind": "cancel", "battle_id": "8", "reason": "Released"}, boundary)
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return
	for kind: Variant in ["advance", "round_ready", "begin", null]:
		var forged: Dictionary = planned.plan.duplicate(true)
		forged.request.kind = kind
		var refused := BodyLifecycle.commit_candidate(f.repo, f.state, forged, boundary)
		assert_eq(refused.status, "error", str(kind))
		assert_null(refused.candidate)
	assert_eq(BodyLifecycle.commit_candidate(f.repo, f.state, {}, boundary).status, "error")
	var ongoing := BodyBattle.plan_candidate(f.repo, f.state, {"kind": "end", "battle_id": "8", "reason": "Ended"}, boundary)
	assert_eq(ongoing.status, "deferred", "both sides still stand")
	assert_eq(BodyMotion._hash(f.state.to_dict()), file)
	# A decision is lawfully pending only at the round stage (contact and advance need an idle
	# cursor), so every lifecycle edge waits for its own stage; a clean contact plan cannot slip past.
	var helper: GutTest = load("res://tests/engine/test_body_battle_enter.gd").new()
	var g: Dictionary = helper.call("_fixture")
	helper.call("_field", g)
	helper.call("_joiner", g)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var join := {"kind": "enter", "unit": g.other, "battle_id": "8", "side": "att"}
	var contact := BodyBattleMotion._boundary(g.state)
	var clean := BodyBattle.plan_candidate(g.repo, g.state, join, contact)
	assert_eq(clean.status, "complete", clean.reason)
	var tx: Dictionary = g.state.day_resolution
	tx.battle_step = "fighting"
	tx.battle_ids = [8]
	tx.substep_battle_ids = [8]
	tx.body_battle.battle_ids = ["8"]
	tx.body_battle.stage = "round"
	DayResolution.block_on_encounter(tx, 8)
	var round := BodyBattleMotion._boundary(g.state)
	file = BodyMotion._hash(g.state.to_dict())
	for request: Dictionary in [join, {"kind": "contacts"}, {"kind": "merge", "first_id": "8", "second_id": "9"},
			{"kind": "withdraw", "unit": g.unit, "battle_id": "8", "reason": "Leaves"},
			{"kind": "cancel", "battle_id": "8", "reason": "Called off"}, {"kind": "end", "battle_id": "8", "reason": "Ended"}]:
		var waiting := BodyBattle.plan_candidate(g.repo, g.state, request, round)
		assert_eq(waiting.status, "deferred", request.kind)
		assert_eq(waiting.reason, "Operation waits for its lifecycle stage", request.kind)
	var refusals := ["Battle boundary disagrees with saved control", "Invalid enrollment plan/boundary"]
	for i: int in 2:
		var at: Dictionary = [contact, round][i]
		var held := BodyLifecycle.commit_candidate(g.repo, g.state, clean.plan, at)
		assert_eq([held.status, held.reason], ["error", refusals[i]])
		assert_null(held.candidate)
	assert_eq(BodyMotion._hash(g.state.to_dict()), file)
