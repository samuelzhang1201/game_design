extends GutTest
## B-MERGE: candidate field union. Field 8 is A (crown, att) vs B (foe, def) under an
## A<->B ceasefire; field 9 is C (foe, att) vs D (crown, def). Merging swaps 9's sides.
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

const FIT := 901 # ten rows: nine of 100 and a final one-person row

func after_each() -> void:
	MarchPath.forget()

## Rows of `slot` at x = 10000 + slot * 10000 on line `y`. Infantry radius 927, cavalry 804:
## A(y10000) touches B (x + 1731) and C (y11731) at their surfaces; D(y13462) touches C.
func _fixture(layout: String = "touch", ranged: bool = false) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var mine: Array = state.regiments.keys()
	mine.sort()
	var foes: Array = state.foes.keys()
	foes.sort()
	var a: String = mine[0]
	var b: String = foes[0]
	var c: String = foes[1]
	var d: String = mine[1]
	var y := {a: 10000, b: 10000, c: 11731, d: 13462}
	if layout == "friendly": y = {a: 10000, b: 10000, c: 2000, d: 8096} # D's surface 50 m from A; no enemy pair touches
	var cohorts := {}
	var rosters := {}
	var army := {}
	var rows := {}
	for code: String in [a, b, c, d]:
		assert_false(Personnel.replace(repo, state, code, FIT).has("error"))
		army[code] = state.army_roster[code]
		for arm: String in repo.world_table("military", "unit_types"):
			army[code][arm] = "0"
		army[code]["archers" if ranged and code == c else ("cavalry" if code in [b, c] else "infantry")] = "100"
		rosters[code] = state.military_rosters[code]
		for id: String in rosters[code].cohort_ids:
			cohorts[id] = state.military_cohorts[id]
		var entry: Dictionary = state.regiments[code] if code in [a, d] else state.foes[code]
		entry.erase("body_groups")
		entry.erase("body_reconciliation")
		entry.group_next_slot = 20
		entry.facing_deg = 37
		rows[code] = []
		for slot: int in BattleGroups.counts(FIT, 100).size():
			var x := 10000 + slot * 10000 + (1731 if code == b else 0)
			rows[code].append({"slot": slot, "home_slot": slot, "count": mini(100, FIT - slot * 100),
				"x_m": x, "y_m": y[code], "facing_deg": 37, "role": "reserve", "path_m": [[x - 2, y[code]], [x, y[code]]]})
		entry.x_m = 10000 + (1731 if code == b else 0)
		entry.y_m = y[code]
	state.regiments = {a: state.regiments[a], d: state.regiments[d]}
	state.foes = {b: state.foes[b], c: state.foes[c]}
	state.army_roster = army
	state.military_rosters = rosters
	state.military_cohorts = cohorts
	state.military_migration.body_version = 1
	state.tick = 1
	state.day = 7
	state.foe_next_id = 9
	for code: String in army:
		var piece := MapObjects.army_piece(repo, army[code])
		repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64),
			"turn_q": 400000, "contact_um": 100, "radius_m": int(repo.unit_footprints[piece].radius_m),
			"clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
		repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
		repo.balance["body_locomotion_" + piece + "_contact_um"] = 100
	state.battles = [_battle(repo, state, 8, a, b, rows), _battle(repo, state, 9, c, d, rows)]
	var term := {"policy": "protect", "scope": "battle", "until_day": 0, "end_condition": "battle_end", "conditions": {}}
	state.battles[0].parley.agreed = {"ceasefire": term}
	state.battles[0].parley.parties = {"att": [a], "def": [b]}
	var tx := DayResolution.begin(state.day, false, state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = 5
	tx.march_entries = {}
	tx.march_budgets = {}
	tx.marching_codes = []
	tx.body_battle = {"version": "1", "abs_day": str(state.absolute_day()), "sequence": "0",
		"next_substep": "0", "substep_count": "10", "stage": "contact",
		"battle_ids": [], "battle_index": "0", "processed_units": []}
	state.day_resolution = tx
	var grid := MarchPath.new()
	grid.cols = 20
	grid.rows = 20
	grid.cell_m = 10000
	grid.closed.resize(400)
	grid.water.resize(400)
	MarchPath.use(repo, grid)
	return {"repo": repo, "state": state, "a": a, "b": b, "c": c, "d": d, "rows": rows}

func _battle(repo: DataRepository, state: GameState, id: int, att: String, def: String, rows: Dictionary) -> Dictionary:
	var battle := BattleSystem.contact_skeleton_candidate(repo, state, att, def)
	battle.id = id
	battle.att = [att]
	battle.def = [def]
	battle.actions = {"att": {"kind": "hold", "reason": "Hold"}, "def": {"kind": "hold", "reason": "Hold"}}
	battle.erase("parley")
	BattleRules.freeze(repo, state, battle)
	battle.groups = {}
	battle.group_anchor_m = {}
	battle.group_facing = {}
	battle.body_version = 1
	battle.group_size_version = 2
	battle.group_size_men = 100
	for code: String in [att, def]:
		battle.groups[code] = rows[code].duplicate(true)
		battle.group_anchor_m[code] = [rows[code][0].x_m, rows[code][0].y_m]
		battle.group_facing[code] = 37
	return battle

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _run(f: Dictionary, request: Dictionary, state: GameState = null) -> Dictionary:
	if state == null: state = f.state
	var boundary := BodyBattleMotion._boundary(state)
	var before := BodyMotion._hash(state.to_dict())
	var plan := BodyBattle.plan_candidate(f.repo, state, request, boundary)
	assert_eq(BodyMotion._hash(state.to_dict()), before, "planning leaves the source unchanged")
	if plan.status != "complete": return plan
	var result := BodyBattle.commit_candidate(f.repo, state, plan.plan, boundary)
	assert_eq(BodyMotion._hash(state.to_dict()), before, "commit publishes a detached state")
	result.plan = plan.plan
	return result

func _merge_request() -> Dictionary:
	return {"kind": "merge", "first_id": "8", "second_id": "9"}

func test_bilateral_parties_and_side_swap() -> void:
	var f := _fixture()
	var a: String = f.a
	var b: String = f.b
	var c: String = f.c
	var d: String = f.d
	var today: int = f.state.absolute_day()
	f.state.battles[1].last_resolved_day = today - 1
	var charge := {"phase": "approach", "target": a, "origin_x_m": 10000, "origin_y_m": 11731,
		"x_m": 10000, "y_m": 11731, "runup_m": 300, "impact_day": -1, "heading_deg": 180}
	f.state.foes[c].charge = charge.duplicate(true)
	f.state.unit_tasks = {c: {"current_id": "hold9", "received_sequence": 1, "orders": {"hold9": {
		"sequence": 1, "status": "active", "reason": "Received", "history": [],
		"request": {"id": "hold9", "unit": c, "battle_id": 9, "task": "hold", "formation": "",
			"target_unit": "", "source": "player", "issuer": "", "max_route_m": 0, "region": ""}}}}}
	var tasks: Dictionary = f.state.unit_tasks.duplicate(true)
	var result := _run(f, _merge_request())
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var state: GameState = result.candidate
	assert_eq(state.battles.size(), 1, "the absorbed field is deleted after its stores transfer")
	var field: Dictionary = state.battles[0]
	assert_eq(int(field.id), 8, "the lower id survives")
	# 9's attacker C is a foe -> 8's def; 9's defender D is crown -> 8's att.
	assert_eq(field.att, [a, d])
	assert_eq(field.def, [b, c])
	assert_eq(BattleSystem.canonical(state, 9), 8)
	assert_eq(int(state.battle_aliases["9"]), 8)
	# Immutable source parties: the survivor's own, the absorbed field's under sources.
	assert_eq(field.parley.parties, {"att": [a], "def": [b]})
	assert_eq(field.sources["9"].parley.parties, {"att": [c], "def": [d]})
	assert_false("attack" in BattleRules.legal_actions(f.repo, state, 8, "def", b, a), "A<->B ceasefire still binds B")
	assert_true("attack" in BattleRules.legal_actions(f.repo, state, 8, "def", c, a), "unrelated C is no party to it")
	# Exact stores: ten-row slots, counts, paths, facing and anchors transfer verbatim.
	for code: String in [a, b, c, d]:
		assert_eq(field.groups[code], f.rows[code], code)
		assert_eq(field.group_facing[code], 37)
		assert_eq(field.group_anchor_m[code], [f.rows[code][0].x_m, f.rows[code][0].y_m])
		assert_eq(UnitBodies._entry(state, code).group_next_slot, 20)
	assert_eq(field.groups[c].map(func(row: Dictionary) -> int: return row.count), [100, 100, 100, 100, 100, 100, 100, 100, 100, 1])
	assert_eq(state.foes[c].charge, charge)
	assert_eq(state.unit_tasks, tasks)
	assert_eq(int(field.last_resolved_day), today - 1, "max already-resolved day")
	# Hand count: A slot i touches C slot i only (1731 m apart, the 10000 m pitch is out of reach),
	# both directions, so 2 x 10 pairs; each direction's counts sum to 9 x 100 + 1 = 901.
	assert_eq(result.plan.contacts.size(), 20)
	for pair: Array in [[a, c], [c, a]]:
		var own: Array = result.plan.contacts.filter(func(p: Dictionary) -> bool: return p.unit == pair[0])
		assert_eq(own.size(), 10)
		var total := 0
		for p: Dictionary in own:
			assert_eq(p.target_unit, pair[1])
			assert_eq(p.slot, p.target_slot)
			total += p.count
		assert_eq(total, 901)
	assert_eq(state.day_resolution.journal.battles.back(), {"kind": "merge", "battle_id": 8, "absorbed": 9,
		"reason": "Fronts touched: battle 9 joined battle 8 on the same field."})
	assert_eq(state.day_resolution.body_battle.stage, "contact")
	assert_eq(state.day_resolution.body_battle.sequence, "1")
	assert_eq(state.military_migration.body_battle.sequence, "0")
	assert_eq(state.rng.to_dict(), f.state.rng.to_dict())
	assert_eq(state.metrics, f.state.metrics)
	assert_eq(state.military_cohorts, f.state.military_cohorts)
	var boundary := BodyBattleMotion._boundary(f.state)
	for source: GameState in [state, _json(state)]:
		var retry := BodyBattle.commit_candidate(f.repo, source, result.plan, boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), BodyMotion._hash(state.to_dict()))

func test_contacts_discovery_merges_then_freezes_one_queue() -> void:
	var f := _fixture()
	var result := _run(f, {"kind": "contacts"})
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var state: GameState = result.candidate
	assert_eq(state.battles.size(), 1)
	assert_eq(state.battles[0].att, [f.a, f.d])
	assert_eq(state.battles[0].def, [f.b, f.c])
	assert_eq(state.day_resolution.battle_ids, [8])
	assert_eq(state.day_resolution.body_battle.battle_ids, ["8"])
	assert_eq(state.day_resolution.body_battle.stage, "round")

func _assert_unmerged(f: Dictionary, request: Dictionary, why: String) -> void:
	var before := BodyMotion._hash(f.state.to_dict())
	var result := _run(f, request)
	assert_eq(result.status, "deferred", why)
	assert_true(result.reason.contains(why), result.reason)
	assert_null(result.candidate)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	assert_eq(f.state.battles.size(), 2, why)

func test_pending_round_two_towns_friendly_contact_and_incompatible_union_do_not_merge() -> void:
	var f := _fixture()
	var b: Dictionary = f.state.battles[1]
	var ready := {"version": "1", "token": "bodyround:9:%d:1" % f.state.absolute_day(),
		"abs_day": str(f.state.absolute_day()), "round": "1", "motion_receipt": "a".repeat(64),
		"contact_digest": BodyMotion._hash([]), "basis": "b".repeat(64), "contacts": [], "unit_actions": {}}
	b.body_round = ready
	b.pending_round = {"day": f.state.absolute_day(), "round": 1, "att": b.att.duplicate(), "def": b.def.duplicate(),
		"tier": BattleSystem.tier_of(f.repo, 500).duplicate(true), "att_power": 1, "def_power": 1,
		"odds": 500, "roll": 500, "eff": 500, "contexts": {
			"att": {"kind": "melee", "loss_permille": 1000, "reason": "Frozen contact"},
			"def": {"kind": "melee", "loss_permille": 1000, "reason": "Frozen contact"}},
		"reason": "Frozen round", "costs": [], "unit_actions": {}, "body_round_receipt": BodyMotion._hash(ready)}
	_assert_unmerged(f, _merge_request(), "Frozen round")
	f = _fixture()
	var towns: Array = f.repo.burgs.keys()
	towns.sort()
	f.state.battles[0].town = towns[0]
	f.state.battles[1].town = towns[1]
	_assert_unmerged(f, _merge_request(), "Two town battles never merge")
	_assert_unmerged(_fixture("friendly"), _merge_request(), "No lawful physical cross-field contact")
	f = _fixture("friendly")
	var apart := _run(f, {"kind": "contacts"})
	assert_eq(apart.status, "complete", apart.reason)
	if apart.candidate != null:
		assert_eq(apart.candidate.battles.size(), 2, "no enemy cross contact leaves the fields apart")
		assert_true(apart.candidate.battle_aliases.is_empty())
		assert_false(apart.candidate.day_resolution.journal.battles.any(func(e: Dictionary) -> bool: return e.kind == "merge"))
	f = _fixture()
	f.state.army_roster[f.c].kingdom_code = f.repo.resolve_realm("player_realm")
	_assert_unmerged(f, _merge_request(), "Incompatible allegiance union")

## D-FIRE replaced the explicit dependency with the real fire query: an attacking archer C
## 6141 m (surface gap) from A, far beyond reach 400, neither merges nor blocks discovery.
func _assert_out_of_reach_stays_apart(f: Dictionary) -> void:
	var before := BodyMotion._hash(f.state.to_dict())
	var merge := _run(f, _merge_request())
	assert_eq(merge.status, "deferred", merge.reason)
	assert_null(merge.candidate)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	assert_eq(merge.reason, "No lawful physical cross-field contact or direct fire")
	var discovery := _run(f, {"kind": "contacts"})
	assert_eq(discovery.status, "complete", discovery.reason)
	if discovery.candidate != null: assert_eq(discovery.candidate.battles.size(), 2)

func test_ranged_unit_out_of_reach_does_not_merge() -> void:
	var f := _fixture("friendly", true)
	f.state.battles[1].actions.att = {"kind": "attack", "reason": "Received advance plan"}
	assert_gt(BattleRanged.share(f.repo, f.state, f.c), 0)
	_assert_out_of_reach_stays_apart(f)

func test_received_unit_task_attack_alone_is_evaluated_by_the_fire_query() -> void:
	var f := _fixture("friendly", true)
	assert_eq(f.state.battles[1].actions.att.kind, "hold", "the side action holds")
	f.state.foes[f.c].supplies = 1000000
	f.state.unit_tasks = {f.c: {"current_id": "adv9", "received_sequence": 1, "orders": {"adv9": {
		"sequence": 1, "status": "received", "reason": "Received", "history": [],
		"request": {"id": "adv9", "unit": f.c, "battle_id": 9, "task": "advance", "formation": "",
			"target_unit": "", "source": "ai", "issuer": "", "max_route_m": 0, "region": ""}}}}}
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.state.battles[1], f.c).kind, "attack")
	_assert_out_of_reach_stays_apart(f)

func test_merge_requests_are_closed_and_forged_plans_reject() -> void:
	var f := _fixture()
	var boundary := BodyBattleMotion._boundary(f.state)
	for request: Dictionary in [{"kind": "merge", "first_id": "9", "second_id": "8"},
		{"kind": "merge", "first_id": "8", "second_id": "8"}, {"kind": "merge", "first_id": "i8", "second_id": "9"},
		{"kind": "merge", "first_id": 8, "second_id": "9"}, {"kind": "merge", "first_id": "0", "second_id": "9"},
		{"kind": "merge", "first_id": "8", "second_id": "9", "extra": true}, {"kind": "merge", "first_id": "8", "second_id": "12"}]:
		var before := BodyMotion._hash(f.state.to_dict())
		assert_eq(BodyBattle.plan_candidate(f.repo, f.state, request, boundary).status, "error", str(request))
		assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	var p := BodyBattle.plan_candidate(f.repo, f.state, _merge_request(), boundary)
	assert_eq(p.status, "complete", p.reason)
	if p.plan.is_empty(): return
	var forged: Dictionary = p.plan.duplicate(true)
	forged.contacts[0].count += 1
	var before := BodyMotion._hash(f.state.to_dict())
	assert_eq(BodyBattle.commit_candidate(f.repo, f.state, forged, boundary).status, "error")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	# A row changed after planning is a stale plan, not a merge.
	var changed := UnitBodies._copy(f.state)
	changed.battles[1].groups[f.c][0].facing_deg += 1
	assert_eq(BodyBattle.commit_candidate(f.repo, changed, p.plan, boundary).status, "error")
