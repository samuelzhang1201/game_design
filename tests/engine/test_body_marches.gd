extends GutTest

func test_candidate_march_api_exists() -> void:
	var army: GDScript = load("res://scripts/engine/army_system.gd")
	var tick: GDScript = load("res://scripts/engine/tick_engine.gd")
	var day: GDScript = load("res://scripts/engine/day_resolution.gd")
	var bodies: GDScript = load("res://scripts/engine/unit_bodies.gd")
	for method: String in ["plan_body_march_candidate", "commit_body_march_candidate"]:
		assert_true(army.has_method(method), method)
	for method: String in ["begin_body_march_candidate", "step_body_march_candidate"]:
		assert_true(tick.get_script_method_list().any(func(item: Dictionary) -> bool: return item.name == method), method)
	assert_true(day.has_method("body_march_incompatibility_reason"))
	assert_true(bodies.has_method("validate_march_candidate"))

const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _ready_api() -> bool:
	return (load("res://scripts/engine/army_system.gd") as GDScript).has_method("plan_body_march_candidate")

func _fixture(counts: Array = [1000]) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var codes: Array = state.regiments.keys()
	codes.sort()
	codes = codes.slice(0, counts.size())
	var entries := {}
	var definitions := {}
	var rosters := {}
	var cohorts := {}
	for i: int in codes.size():
		var code: String = codes[i]
		assert_false(Personnel.replace(repo, state, code, counts[i]).has("error"))
		entries[code] = state.regiments[code]
		definitions[code] = state.army_roster[code]
		definitions[code].is_naval = "0"
		rosters[code] = state.military_rosters[code]
		for id: String in rosters[code].cohort_ids: cohorts[id] = state.military_cohorts[id]
		var entry: Dictionary = entries[code]
		entry.x_m = 50000
		entry.y_m = 50000 + i * 30000
		entry.dest_x_m = entry.x_m + 10000
		entry.dest_y_m = entry.y_m
		entry.order = ArmySystem.ORDER_MARCH
		entry.order_id = 10
		entry.erase("departure")
		entry.erase("camp_state")
		entry.supplies = 100000
		entry.group_next_slot = 10
		entry.body_groups = []
		var piece := MapObjects.army_piece(repo, definitions[code])
		var radius := int(repo.unit_footprints[piece].radius_m)
		for j: int in BattleGroups.counts(counts[i], 100).size():
			entry.body_groups.append({"slot": j, "home_slot": j, "count": mini(100, int(counts[i]) - j * 100),
				"x_m": entry.x_m + j * (2 * radius + 100), "y_m": entry.y_m,
				"role": "front", "facing_deg": 0, "path_m": []})
	state.regiments = entries
	state.foes = {}
	state.army_roster = definitions
	state.military_rosters = rosters
	state.military_cohorts = cohorts
	state.battles = []
	state.day_resolution = {}
	state.military_migration.erase("body_motion")
	state.military_migration.body_version = 1
	repo.balance.army_march_grid_px = 1
	var slopes := PackedByteArray()
	slopes.resize(200 * 200)
	var grid := MarchPath.build(repo, 200, 200, 1000, slopes)
	MarchPath.use(repo, grid)
	assert_eq(UnitBodies.migrate_candidate(repo, state).status, "complete")
	return {"repo": repo, "state": state, "codes": codes, "code": codes[0], "grid": grid}

func _begin(f: Dictionary, budget: int = 1000) -> GameState:
	var before: Dictionary = f.state.to_dict()
	var result: Dictionary = TickEngine.new(f.repo).call("begin_body_march_candidate", f.state)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(f.state.to_dict(), before)
	if result.candidate == null: return null
	var state: GameState = result.candidate
	for code: String in state.day_resolution.march_budgets: state.day_resolution.march_budgets[code] = budget
	return state

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _plan(f: Dictionary, state: GameState) -> Dictionary:
	var before := state.to_dict()
	var result: Dictionary = ArmySystem.plan_body_march_candidate(f.repo, state)
	assert_eq(state.to_dict(), before, "planning never mutates source or RNG")
	assert_eq(result.keys().size(), 4)
	assert_eq(result.status, "complete", result.reason)
	return result.plan

func _commit(f: Dictionary, state: GameState, plan: Dictionary, status: String = "complete") -> Dictionary:
	var before := state.to_dict()
	var result: Dictionary = ArmySystem.commit_body_march_candidate(f.repo, state, plan)
	assert_eq(result.status, status, result.reason)
	assert_eq(state.to_dict(), before, "commit only publishes detached output")
	if status == "error":
		assert_null(result.candidate)
		assert_eq(result.plan, {})
	return result

func test_real_boundary_not_wrapper() -> void:
	if not _ready_api(): return
	var f := _fixture()
	var state := _begin(f)
	if state == null: return
	assert_eq(UnitBodies.migrate_candidate(f.repo, state).status, "deferred")
	assert_false(DayResolution.incompatibility_reason(state.day_resolution).is_empty())
	var before := state.to_dict()
	var engine := TickEngine.new(f.repo)
	assert_eq(engine.resolve_day(state).status, "error")
	assert_eq(state.to_dict(), before)
	assert_eq(engine.call("begin_body_march_candidate", state).status, "deferred")
	var p := _plan(f, state)
	assert_false(p.motion.cursor.is_empty(), "real frozen planner executes")
	var result := _commit(f, state, p)
	assert_eq(result.candidate.day_resolution.body_march.next_substep, "1")
	assert_eq(result.candidate.day_resolution.march_entries.size(), 1)
	for mutation: String in ["phase", "version", "decision", "rows"]:
		var bad := UnitBodies._copy(state)
		match mutation:
			"phase": bad.day_resolution.phase = "SIEGES"
			"version": bad.day_resolution.protocol_version = 3
			"decision": bad.day_resolution.pending_decision = {"token": "pending"}
			"rows": bad.regiments[f.code].erase("body_groups")
		var saved := bad.to_dict()
		assert_eq(engine.call("step_body_march_candidate", bad).status, "error")
		assert_eq(bad.to_dict(), saved)

func test_budget_and_supply_once() -> void:
	if not _ready_api(): return
	for path: Array in [[[50003, 50000], [50003, 50004]], [[50001, 50001]]]:
		var f := _fixture([901])
		var entry: Dictionary = f.state.regiments[f.code]
		entry.route_m = path
		entry.dest_x_m = path.back()[0]
		entry.dest_y_m = path.back()[1]
		var state := _begin(f, 70)
		if state == null: return
		var p := _plan(f, state)
		assert_eq(p.units[0].used_m, 7 if path.size() == 2 else 2, "sum rounded segment lengths, unit maximum not sum of ten")
		assert_eq(p.units[0].anchor_path_m, [[50000, 50000]] + path)
		var result := _commit(f, state, p)
		assert_eq(result.candidate.regiments[f.code].supplies, entry.supplies, "no base meal in march")
		var replay := _commit(f, result.candidate, p)
		assert_eq(replay.candidate.to_dict(), result.candidate.to_dict())
		assert_eq(_commit(f, _json(result.candidate), JSON.parse_string(JSON.stringify(p))).candidate.to_dict(), result.candidate.to_dict())

func test_atomic_stale_and_json() -> void:
	if not _ready_api(): return
	var f := _fixture([1000, 900, 1, 0])
	var state := _begin(f, 997)
	if state == null: return
	for i: int in f.codes.size(): state.day_resolution.march_budgets[f.codes[i]] += i * 17
	for slice: int in 10:
		var restored := _json(state)
		var p := _plan(f, state)
		assert_eq(p, _plan(f, restored), "before-slice JSON resumes exact frozen input")
		var forged := p.duplicate(true)
		forged.units[0].anchor_path_m.back()[0] += 1
		_commit(f, state, forged, "error")
		var result := _commit(f, state, p)
		var roundtrip := _commit(f, restored, JSON.parse_string(JSON.stringify(p)))
		assert_eq(result.candidate.to_dict(), roundtrip.candidate.to_dict())
		assert_eq(result.candidate.rng.to_dict(), state.rng.to_dict())
		assert_eq(result.candidate.military_cohorts, state.military_cohorts)
		state = result.candidate
		assert_eq(_json(state).to_dict(), state.to_dict(), "after-slice JSON preserves control strings and paths")
		assert_eq(_commit(f, _json(state), p).candidate.to_dict(), state.to_dict())
	var complete: Dictionary = TickEngine.new(f.repo).call("step_body_march_candidate", state)
	assert_eq(complete.status, "complete")
	assert_eq(complete.plan, {})
	assert_eq(complete.candidate.to_dict(), state.to_dict())
	assert_eq(state.day, f.state.day)
	var query := ArmySystem.plan_body_march_candidate(f.repo, state)
	assert_null(query.candidate, "planning never publishes a candidate, including exhausted days")
	assert_eq(query.plan, {})

func test_raw_controls_stale_basis_and_detached_outputs() -> void:
	if not _ready_api(): return
	var f := _fixture([1])
	var state := _begin(f)
	if state == null: return
	var p := _plan(f, state)
	for value: Variant in [0, 0.1, true, null, "01", "-1", "9223372036854775808"]:
		var bad := UnitBodies._copy(state)
		bad.day_resolution.body_march.next_substep = value
		bad = _json(bad)
		var before := bad.to_dict()
		assert_eq(TickEngine.new(f.repo).call("step_body_march_candidate", bad).status, "error")
		assert_eq(TickEngine.new(f.repo).begin_body_march_candidate(bad).status, "error")
		assert_eq(bad.to_dict(), before)
	for change: String in ["supplies", "command", "grid", "config"]:
		var bad := UnitBodies._copy(state)
		match change:
			"supplies": bad.regiments[f.code].supplies -= 1
			"command": bad.regiments[f.code].order_id += 1
			"grid": f.grid.closed[0] = 1
			"config": f.repo.balance.army_run_speed_permille += 1
		_commit(f, bad, p, "error")
		f.grid.closed[0] = 0
	var before := state.to_dict()
	p.units[0].entry_after.supplies = -50
	p.units[0].saved_entry_after.route_m.append([1, 1])
	assert_eq(state.to_dict(), before)

func test_polyline_terrain_and_bounds() -> void:
	if not _ready_api(): return
	for point: Array in [[0, 50000], [2147483648, 50000], [199999, 50000]]:
		var f := _fixture([1])
		f.state.regiments[f.code].body_groups[0].x_m = point[0]
		var result: Dictionary = TickEngine.new(f.repo).call("begin_body_march_candidate", f.state)
		if result.status == "complete":
			result = TickEngine.new(f.repo).call("step_body_march_candidate", result.candidate)
		assert_eq(result.status, "error", "whole swept disc must remain inside terrain bounds")
	var f := _fixture([1])
	var state := _begin(f)
	if state == null: return
	f.grid.closed[50 * f.grid.cols + 50] = 1
	var before := state.to_dict()
	assert_eq(TickEngine.new(f.repo).call("step_body_march_candidate", state).status, "error")
	assert_eq(state.to_dict(), before)
	MarchPath.use(f.repo, null)
	assert_eq(TickEngine.new(f.repo).call("step_body_march_candidate", state).status, "error", "missing terrain never takes straight fallback")

func test_received_orders_and_prediction() -> void:
	if not _ready_api(): return
	var f := _fixture([100])
	var state := _begin(f)
	if state == null: return
	state.regiments[f.code].order_id += 1
	state.regiments[f.code].dest_x_m += 1000
	var p := _plan(f, state)
	var result := _commit(f, state, p)
	assert_eq(result.candidate.regiments[f.code].order_id, state.regiments[f.code].order_id)
	assert_eq(result.candidate.regiments[f.code].dest_x_m, state.regiments[f.code].dest_x_m)
	var predicted: Dictionary = TickEngine.new(f.repo).call("step_body_march_candidate", state)
	assert_eq(predicted.plan, p)
	assert_eq(predicted.candidate.to_dict(), result.candidate.to_dict())
	var cancelled := UnitBodies._copy(state)
	cancelled.regiments[f.code].order = ArmySystem.ORDER_GARRISON
	cancelled.regiments[f.code].order_id += 1
	var cancel_result := TickEngine.new(f.repo).step_body_march_candidate(cancelled)
	assert_eq(cancel_result.status, "complete", cancel_result.reason)
	assert_eq(cancel_result.candidate.regiments[f.code].order, ArmySystem.ORDER_GARRISON)
	assert_eq(cancel_result.candidate.regiments[f.code].dest_x_m, cancel_result.candidate.regiments[f.code].x_m)
	state.regiments[f.code].captured = true
	p = _plan(f, state)
	for move: Dictionary in p.motion.moves: assert_eq(move.used_m, 0)

func _set_route(f: Dictionary, index: int, start: Array, end: Array) -> void:
	var entry: Dictionary = f.state.regiments[f.codes[index]]
	var dx: int = int(start[0]) - int(entry.x_m)
	var dy: int = int(start[1]) - int(entry.y_m)
	entry.x_m = start[0]
	entry.y_m = start[1]
	entry.dest_x_m = end[0]
	entry.dest_y_m = end[1]
	entry.route_m = [end]
	for body: Dictionary in entry.body_groups:
		body.x_m += dx
		body.y_m += dy

func _continuous_clear(f: Dictionary, state: GameState, p: Dictionary) -> void:
	# Independently minimize each relative linear interval using time knots from both polylines.
	var moves: Array = p.motion.moves.duplicate(true)
	for code: String in state.regiments.keys() + state.foes.keys():
		for body: Dictionary in UnitBodies.rows(f.repo, state, code):
			if moves.any(func(m: Dictionary) -> bool: return m.unit == code and int(m.slot) == int(body.slot)): continue
			moves.append({"unit": code, "slot": body.slot, "budget_m": 0, "path_m": [[body.x_m, body.y_m]], "used_m": 0})
	for i: int in moves.size():
		var a: Dictionary = moves[i]
		assert_true(int(a.used_m) <= int(a.budget_m))
		for j: int in range(i):
			var b: Dictionary = moves[j]
			var ar := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, state.army_roster[a.unit])].radius_m)
			var br := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, state.army_roster[b.unit])].radius_m)
			var knots: Array[float] = [0.0, 1.0]
			for move: Dictionary in [a, b]:
				var cost := 0.0
				for k: int in range(1, move.path_m.size()):
					var x: int = int(move.path_m[k][0]) - int(move.path_m[k - 1][0])
					var y: int = int(move.path_m[k][1]) - int(move.path_m[k - 1][1])
					cost += ceil(sqrt(float(x * x + y * y)))
					if move.budget_m > 0: knots.append(cost / float(move.budget_m))
			knots.sort()
			for k: int in range(1, knots.size()):
				var t0 := knots[k - 1]
				var t1 := knots[k]
				if t1 <= t0: continue
				var ax := _coordinate(a, t0, 0) - _coordinate(b, t0, 0)
				var ay := _coordinate(a, t0, 1) - _coordinate(b, t0, 1)
				var dx := _coordinate(a, t1, 0) - _coordinate(b, t1, 0) - ax
				var dy := _coordinate(a, t1, 1) - _coordinate(b, t1, 1) - ay
				var speed := dx * dx + dy * dy
				var u := clampf(-(ax * dx + ay * dy) / speed, 0.0, 1.0) if speed > 0 else 0.0
				assert_true(pow(ax + u * dx, 2) + pow(ay + u * dy, 2) >= pow(ar + br, 2) - 0.001, "continuous measured-circle separation")

func _coordinate(move: Dictionary, time: float, axis: int) -> float:
	var left: float = time * int(move.budget_m)
	for i: int in range(1, move.path_m.size()):
		var a: Array = move.path_m[i - 1]
		var b: Array = move.path_m[i]
		var dx: int = int(b[0]) - int(a[0])
		var dy: int = int(b[1]) - int(a[1])
		var cost := ceilf(sqrt(float(dx * dx + dy * dy)))
		if cost > 0 and left <= cost: return float(a[axis]) + (int(b[axis]) - int(a[axis])) * left / cost
		left -= cost
	return float(move.path_m.back()[axis])

func test_opposed_and_three_way() -> void:
	if not _ready_api(): return
	for counts: Array in [[1000, 1000], [901, 900, 1], [1, 1, 0]]:
		var f := _fixture(counts)
		_set_route(f, 0, [40000, 60000], [70000, 60000])
		_set_route(f, 1, [100000, 60000], [70000, 60000])
		if counts.size() == 3: _set_route(f, 2, [70000, 100000], [70000, 40000])
		var state := _begin(f, 60000)
		if state == null: return
		var p := _plan(f, state)
		_continuous_clear(f, state, p)
		assert_true(p.units[0].used_m > 0)
		var permuted := UnitBodies._copy(state)
		var codes: Array = permuted.regiments.keys()
		codes.reverse()
		var entries := {}
		var frozen := {}
		var budgets := {}
		for code: String in codes:
			entries[code] = permuted.regiments[code]
			frozen[code] = permuted.day_resolution.march_entries[code]
			budgets[code] = permuted.day_resolution.march_budgets[code]
		permuted.regiments = entries
		permuted.day_resolution.march_entries = frozen
		permuted.day_resolution.march_budgets = budgets
		assert_eq(_plan(f, permuted), p)
		var result := _commit(f, state, p)
		assert_eq(result.candidate.military_cohorts, state.military_cohorts)

func test_hostile_and_withdrawal() -> void:
	if not _ready_api(): return
	var f := _fixture([100, 100])
	_set_route(f, 0, [45000, 60000], [55000, 60000])
	_set_route(f, 1, [55000, 60000], [45000, 60000])
	var foreign: String = f.codes[1]
	f.state.foes[foreign] = f.state.regiments[foreign]
	f.state.regiments.erase(foreign)
	f.state.army_roster[foreign].kingdom_code = f.repo.resolve_realm("raider_realm")
	var state := _begin(f, 200000)
	if state == null: return
	var p := _plan(f, state)
	_continuous_clear(f, state, p)
	for move: Dictionary in p.motion.moves:
		for point: Array in move.path_m: assert_eq(point[1], 60000, "hostile passage has no friendly side bypass")
	var battle := {"id": 1, "att": [f.code], "def": [foreign], "body_version": 1,
		"group_size_version": 2, "group_size_men": 100, "groups": {}, "group_facing": {}, "group_anchor_m": {}}
	for code: String in f.codes:
		var entry := UnitBodies._entry(f.state, code)
		battle.groups[code] = entry.body_groups
		entry.erase("body_groups")
	f.state.battles = [battle]
	state = _begin(f, 1000)
	if state == null: return
	p = _plan(f, state)
	for move: Dictionary in p.motion.moves: assert_eq(move.used_m, 0, "combatant without withdrawal authorization remains an obstacle")
	f.state.regiments[f.code].battle_retreat = true
	_set_battle_retreat(f)
	state = _begin(f, 1000)
	p = _plan(f, state)
	assert_true(p.units[0].used_m > 0, "authorized withdrawal uses the same swept planner")
	_continuous_clear(f, state, p)

func _set_battle_retreat(f: Dictionary) -> void:
	var entry: Dictionary = f.state.regiments[f.code]
	entry.dest_x_m = 35000
	entry.dest_y_m = 60000
	entry.route_m = [[35000, 60000]]

func _runner(f: Dictionary, supplies: int = 1000) -> void:
	var state: GameState = f.state
	var repo: DataRepository = f.repo
	var roster: Dictionary = state.military_rosters[f.code]
	var officer := {}
	for id: String in roster.cohort_ids:
		if not str(state.military_cohorts[id].get("person_id", "")).is_empty(): officer = state.military_cohorts[id]
	assert_false(officer.is_empty())
	var person := str(officer.person_id)
	assert_false(Personnel.move(repo, state, f.code, "fit", "released", 1).has("error"))
	assert_false(MilitaryRoster.mobilize(repo, state, "body:runner", [{"id": "body:runner", "unit_code": f.code,
		"source_province": officer.source_province, "source_population_field": officer.source_population_field,
		"identity": "noble", "family_name": officer.family_name, "person_id": person, "stage": "active", "count": 1}], "Candidate runner fixture").has("error"))
	assert_false(MilitaryCommanders.assign(repo, state, f.code, person, "Candidate runner fixture").has("error"))
	state.characters[person].skills.sk_martial = 100
	state.characters[person].attributes.boldness = 100
	state.day = 10
	repo.balance.army_supply_per_head_permille = 2995
	repo.balance.army_run_supply_permille = 2000
	state.regiments[f.code].disengaging = 1
	state.regiments[f.code].supplies = supplies
	state.regiments[f.code].run_supply_rem = 0
	assert_eq(ArmySystem.day_bite(ArmySystem.supply_use(repo, state.army_roster[f.code], state), state.day), 100)

func test_running_charge_reserves_base_food_and_rejection_restores_supply() -> void:
	if not _ready_api(): return
	for supplies: int in [1000, 100]:
		var f := _fixture([1000])
		_runner(f, supplies)
		var radius := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.code])].radius_m)
		var bodies: Array = f.state.regiments[f.code].body_groups
		var offset: int = 80000 - radius - 50 - int(bodies.back().x_m)
		for body: Dictionary in bodies: body.x_m += offset
		var state := _begin(f, 1000)
		if state == null: return
		var p := _plan(f, state)
		var result := _commit(f, state, p)
		assert_eq(result.candidate.regiments[f.code].supplies, supplies - (10 if supplies == 1000 else 0))
		assert_eq(p.units[0].step_budget_m, UnitGait.run_step_m(f.repo, 100) if supplies == 1000 else 100)
		assert_eq(_commit(f, result.candidate, p).candidate.regiments[f.code].supplies, result.candidate.regiments[f.code].supplies)
		f.grid.closed[50 * f.grid.cols + 80] = 1
		assert_eq(ArmySystem._body_terrain_error(f.repo, state, []), "", "source discs are legal before the staged run")
		var before := state.to_dict()
		assert_eq(TickEngine.new(f.repo).step_body_march_candidate(state).status, "error")
		assert_eq(state.to_dict(), before, "terrain rejection rolls back the staged run charge and carry")

func test_friendly_foreign_bodies_yield_and_actual_sidestep_terrain_is_atomic() -> void:
	if not _ready_api(): return
	var f := _fixture([100, 100])
	_set_route(f, 0, [45000, 60000], [55000, 60000])
	_set_route(f, 1, [55000, 60000], [45000, 60000])
	# Different friendly realms do not turn a body into a unit-wide enemy wall.
	f.state.army_roster[f.codes[1]].kingdom_code = f.repo.resolve_realm("neighbor_realm")
	var state := _begin(f, 500000)
	if state == null: return
	var p := _plan(f, state)
	_continuous_clear(f, state, p)
	assert_true(p.motion.moves.any(func(m: Dictionary) -> bool: return m.path_m.size() > 2), "actual planner supplies friendly side legs")
	var blocked_cell := -1
	for move: Dictionary in p.motion.moves:
		for point: Array in move.path_m:
			if int(point[1]) == 60000: continue
			var cell: Vector2i = f.grid.cell_of(Vector2i(point[0], point[1]))
			blocked_cell = cell.y * f.grid.cols + cell.x
	if blocked_cell < 0: return
	f.grid.closed[blocked_cell] = 1
	var before := state.to_dict()
	var rejected := TickEngine.new(f.repo).step_body_march_candidate(state)
	assert_eq(rejected.status, "error", "side leg terrain rejection applies to whole simultaneous transaction")
	assert_true("terrain" in rejected.reason)
	assert_eq(state.to_dict(), before)

func test_sealed_pocket_waits_without_retreat_and_exact_tangency() -> void:
	if not _ready_api(): return
	var f := _fixture([100, 400])
	var first: Dictionary = f.state.regiments[f.code]
	var wall: Dictionary = f.state.regiments[f.codes[1]]
	var ra := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.code])].radius_m)
	var rb := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.codes[1]])].radius_m)
	var distance := ra + rb
	wall.order = ArmySystem.ORDER_GARRISON
	for i: int in 4:
		var delta: Array = [[distance, 0], [-distance, 0], [0, distance], [0, -distance]][i]
		wall.body_groups[i].x_m = first.x_m + delta[0]
		wall.body_groups[i].y_m = first.y_m + delta[1]
	var state := _begin(f, 1000)
	if state == null: return
	for slice: int in 2:
		var p := _plan(f, state)
		assert_eq(p.units[0].used_m, 0, "sealed real-radius pocket waits")
		assert_false(p.motion.reasons.is_empty())
		_continuous_clear(f, state, p)
		var result := _commit(f, state, p)
		assert_eq(result.candidate.regiments[f.code].x_m, first.x_m)
		assert_eq(result.candidate.regiments[f.code].order, ArmySystem.ORDER_MARCH)
		state = result.candidate

func test_outer_inner_receipts_and_completed_controls_fail_closed() -> void:
	if not _ready_api(): return
	var f := _fixture([1])
	var state := _begin(f)
	if state == null: return
	var p := _plan(f, state)
	var committed: GameState = _commit(f, state, p).candidate
	for change: String in ["outer", "inner", "skip", "future", "unknown", "raw"]:
		var bad := UnitBodies._copy(committed)
		match change:
			"outer":
				bad.day_resolution.body_march.next_substep = "0"
				bad.day_resolution.substep_index = 0
				bad.day_resolution.body_march.last = {}
			"inner": bad.military_migration.erase("body_motion")
			"skip": bad.day_resolution.body_march.next_substep = "2"
			"future": bad.day_resolution.body_march.version = "2"
			"unknown": bad.day_resolution.body_march.extra = 0
			"raw": bad.day_resolution.body_march.last.substep = 0.1
		var before := bad.to_dict()
		assert_eq(TickEngine.new(f.repo).step_body_march_candidate(bad).status, "error")
		assert_eq(bad.to_dict(), before)
	var wrong := p.duplicate(true)
	wrong.substep = true
	_commit(f, state, wrong, "error")
	wrong = p.duplicate(true)
	wrong.abs_day += 1
	_commit(f, state, wrong, "error")
	wrong = p.duplicate(true)
	wrong.extra = true
	_commit(f, state, wrong, "error")

func test_packing_gate_and_production_entries_remain_unbound() -> void:
	if not _ready_api(): return
	var f := _fixture([1])
	f.state.regiments[f.code].camp_state = {"phase": CampSystem.PACKING, "move_not_before_day": f.state.absolute_day() + 2}
	var state := _begin(f)
	if state == null: return
	var p := _plan(f, state)
	assert_eq(p.units[0].used_m, 0)
	for path: String in ["res://scripts/engine/army_system.gd", "res://scripts/engine/tick_engine.gd"]:
		var text := FileAccess.get_file_as_string(path)
		var start := text.find("## Explicit candidate march transaction" if "army_system" in path else "## Opt-in march-only harness")
		assert_true(start > 0)
		assert_false("body_march_candidate(" in text.substr(0, start), "ordinary movement/prediction/resolve_day never calls candidate APIs")

func test_disc_grazing_corner_gap_and_out_of_map_side_leg() -> void:
	if not _ready_api(): return
	var f := _fixture([100, 200])
	var moving: Dictionary = f.state.regiments[f.code]
	var wall: Dictionary = f.state.regiments[f.codes[1]]
	var ra := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.code])].radius_m)
	var rb := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.codes[1]])].radius_m)
	wall.order = ArmySystem.ORDER_GARRISON
	for i: int in 2:
		wall.body_groups[i].x_m = moving.x_m + 5000
		wall.body_groups[i].y_m = moving.y_m + (ra + rb) * (1 if i == 0 else -1)
	var state := _begin(f, 100000)
	if state == null: return
	var p := _plan(f, state)
	assert_eq(p.units[0].used_m, 10000, "constructed real-body gap admits progress at exact legal tangency")
	_continuous_clear(f, state, p)
	f = _fixture([1])
	var radius := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.code])].radius_m)
	f.state.regiments[f.code].body_groups[0].x_m = 51000 - radius
	f.grid.closed[50 * f.grid.cols + 51] = 1
	var rejected := TickEngine.new(f.repo).begin_body_march_candidate(f.state)
	assert_eq(rejected.status, "error", "circle grazing forbidden rectangle is rejected even with legal center cell")
	assert_true("terrain" in rejected.reason)
	# The same real planner's negative-y avoidance leg must be checked against the map edge.
	f = _fixture([100, 100])
	var y := 1000
	_set_route(f, 0, [45000, y], [55000, y])
	_set_route(f, 1, [55000, y], [45000, y])
	state = _begin(f, 500000)
	if state == null: return
	var before := state.to_dict()
	rejected = TickEngine.new(f.repo).step_body_march_candidate(state)
	assert_eq(rejected.status, "error", "returned avoidance side leg extends beyond map bounds")
	assert_true("bounds" in rejected.reason)
	assert_eq(state.to_dict(), before)

func test_crown_royal_and_foreign_units_share_one_slice_and_run_wait_still_pays() -> void:
	if not _ready_api(): return
	var f := _fixture([100, 100, 100])
	f.state.army_roster[f.codes[1]].is_royal = "1"
	var foreign: String = f.codes[2]
	f.state.army_roster[foreign].kingdom_code = f.repo.resolve_realm("neighbor_realm")
	f.state.foes[foreign] = f.state.regiments[foreign]
	f.state.regiments.erase(foreign)
	var state := _begin(f, 1000)
	if state == null: return
	var p := _plan(f, state)
	assert_eq(p.units.size(), 3)
	assert_eq(p.motion.moves.size(), 3)
	for row: Dictionary in p.units: assert_true(row.used_m > 0)
	_continuous_clear(f, state, p)
	_commit(f, state, p)
	f = _fixture([1000, 1000])
	_runner(f)
	var entry: Dictionary = f.state.regiments[f.code]
	entry.x_m = 30000
	entry.dest_x_m = 40000
	var wall: Dictionary = f.state.regiments[f.codes[1]]
	wall.order = ArmySystem.ORDER_GARRISON
	var ra := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.code])].radius_m)
	var rb := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.codes[1]])].radius_m)
	for i: int in 10:
		entry.body_groups[i].x_m = 30000 + i * (4 * maxi(ra, rb) + 100)
		wall.body_groups[i].x_m = entry.body_groups[i].x_m + ra + rb
		wall.body_groups[i].y_m = entry.body_groups[i].y_m
	state = _begin(f, 1000)
	p = _plan(f, state)
	assert_eq(p.units[0].used_m, 0)
	assert_eq(p.motion.blocked.size(), 10)
	_continuous_clear(f, state, p)
	var result := _commit(f, state, p)
	assert_eq(result.candidate.regiments[f.code].supplies, 990, "successful paid run retains charge even when it waits")
	assert_eq(result.candidate.regiments[f.code].run_supply_rem, 0)

func test_pursuit_bounds_credit_actual_distance_once_and_received_law_budget() -> void:
	if not _ready_api(): return
	var f := _fixture([100])
	f.state.unit_tasks[f.code] = {"current_id": "body:pursuit", "orders": {"body:pursuit": {
		"status": "received", "history": [], "request": {"task": "pursue", "target_unit": "observed:unit", "source": "king",
			"max_route_m": 30, "region": ""}, "pursuit": {"route_m": 0}, "track": {"phase": "follow"}}}}
	var state := _begin(f, 1000)
	if state == null: return
	var p := _plan(f, state)
	assert_eq(p.units[0].used_m, 30, "desired path and allowance stop at remaining received pursuit range")
	var result := _commit(f, state, p)
	var record := BattleTaskSystem.current(result.candidate, f.code)
	assert_eq(record.pursuit.route_m, 30)
	assert_eq(record.status, "bounded")
	assert_eq(result.candidate.regiments[f.code].x_m, 50030)
	assert_eq(_commit(f, result.candidate, p).candidate.to_dict(), result.candidate.to_dict())
	var next := _plan(f, result.candidate)
	assert_eq(next.units[0].used_m, 0)
	f = _fixture([100])
	f.state.law_in_force[LawSystem.UNIT_PREFIX + f.code] = {"truce_days": {"value": "on", "decree_id": 7}}
	var expected := ArmySystem.day_walk_budget(f.repo, f.state, f.code)
	var begun := TickEngine.new(f.repo).begin_body_march_candidate(f.state)
	assert_eq(begun.status, "complete", begun.reason)
	assert_eq(begun.candidate.day_resolution.march_budgets[f.code], expected)
	assert_eq(LawEffects.unit_pace_permille(f.repo, f.state, f.code), 950)

func test_raw_entry_readers_reject_before_helpers_can_normalize_or_crash() -> void:
	if not _ready_api(): return
	var f := _fixture([1])
	var state := _begin(f)
	if state == null: return
	for field: String in ["x_m", "supplies", "order", "gait", "camp_state", "departure", "disengaging", "captured", "morale", "training", "carry_days"]:
		var bad := UnitBodies._copy(state)
		bad.regiments[f.code][field] = 1.5 if field in ["x_m", "supplies", "disengaging", "morale", "training", "carry_days"] else null
		var before := bad.to_dict()
		var result := TickEngine.new(f.repo).step_body_march_candidate(bad)
		assert_eq(result.status, "error", field)
		assert_eq(bad.to_dict(), before)

func test_repeated_route_points_do_not_grant_untravelled_loop_progress() -> void:
	if not _ready_api(): return
	var f := _fixture([1])
	var entry: Dictionary = f.state.regiments[f.code]
	entry.route_m = [[50010, 50000], [50010, 50010], [50000, 50010], [50000, 50000]]
	entry.dest_x_m = 50000
	entry.dest_y_m = 50000
	var state := _begin(f, 0)
	if state == null: return
	var p := _plan(f, state)
	assert_eq(p.units[0].used_m, 0)
	assert_eq(p.units[0].anchor_path_m, [[50000, 50000]], "already standing at a later route point cannot spend free route metres")
	assert_eq(p.units[0].saved_entry_after.route_m, entry.route_m)

func _pursuit(f: Dictionary, limit: int) -> void:
	f.state.unit_tasks[f.code] = {"current_id": "review:pursuit", "orders": {"review:pursuit": {
		"status": "received", "history": [], "request": {"task": "pursue", "target_unit": "observed:unit", "source": "king",
			"max_route_m": limit, "region": ""}, "pursuit": {"route_m": 0}, "track": {"phase": "follow"}}}}

func _assert_candidate_error(result: Dictionary) -> void:
	assert_eq(result.keys().size(), 4, "all public failures retain the closed wire shape")
	assert_true(result.has("status"))
	if not result.has("status"): return
	assert_eq(result.status, "error", str(result))
	assert_false(result.reason.is_empty())
	assert_null(result.candidate)
	assert_eq(result.plan, {})

func test_review_pursuit_preserves_full_route_through_slices_corners_and_blocking() -> void:
	var f := _fixture([100])
	_pursuit(f, 10000)
	var state := _begin(f, 1000)
	for slice: int in 3:
		var result := _commit(f, state, _plan(f, state))
		state = _json(result.candidate)
		assert_eq(state.regiments[f.code].x_m, 50100 + slice * 100)
		assert_eq(state.regiments[f.code].order, ArmySystem.ORDER_MARCH)
		assert_eq(state.day_resolution.march_entries[f.code].route_m, [[60000, 50000]])
		assert_eq(result.plan.arrivals, [])
		assert_eq(BattleTaskSystem.current(state, f.code).pursuit.route_m, (slice + 1) * 100)
	f = _fixture([100])
	f.state.regiments[f.code].route_m = [[50300, 50000], [50300, 50400]]
	f.state.regiments[f.code].dest_x_m = 50300
	f.state.regiments[f.code].dest_y_m = 50400
	_pursuit(f, 10000)
	state = _begin(f, 1000)
	for slice: int in 7:
		var result := _commit(f, state, _plan(f, state))
		state = _json(result.candidate)
		assert_eq(result.plan.arrivals, [f.code] if slice == 6 else [])
		assert_eq(BattleTaskSystem.current(state, f.code).pursuit.route_m, (slice + 1) * 100)
		assert_eq(state.regiments[f.code].order, ArmySystem.ORDER_GARRISON if slice == 6 else ArmySystem.ORDER_MARCH)
	assert_eq([state.regiments[f.code].x_m, state.regiments[f.code].y_m], [50300, 50400])
	f = _fixture([100, 100])
	var wall: Dictionary = f.state.regiments[f.codes[1]]
	wall.order = ArmySystem.ORDER_GARRISON
	var ra := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.code])].radius_m)
	var rb := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.codes[1]])].radius_m)
	wall.body_groups[0].x_m = 50000 + ra + rb + 50
	wall.body_groups[0].y_m = 50000
	_pursuit(f, 10000)
	state = _begin(f, 1000)
	var total := 0
	for slice: int in 2:
		var result := _commit(f, state, _plan(f, state))
		total += int(result.plan.units[0].used_m)
		state = result.candidate
		assert_eq(result.plan.arrivals, [])
		assert_eq(state.regiments[f.code].order, ArmySystem.ORDER_MARCH)
		assert_eq(state.day_resolution.march_entries[f.code].route_m, [[60000, 50000]])
		assert_eq(BattleTaskSystem.current(state, f.code).pursuit.route_m, total)
	assert_true(total <= 50)

func test_review_duplicate_adjacent_points_never_credit_off_route_side_legs() -> void:
	var prefix := ArmySystem._body_route_prefix([[0, 0], [0, 0], [10, 0]], [[0, 0], [0, 5], [10, 5], [10, 0]])
	assert_eq(prefix.back(), [10, 0])
	assert_eq(ArmySystem._body_remaining([[0, 0], [0, 0], [10, 0]], [[0, 0]]), [[10, 0]], "already-reached zero legs are not remaining travel")
	for point: Array in prefix: assert_eq(point[1], 0)
	var f := _fixture([100, 100])
	_set_route(f, 0, [45000, 60000], [55000, 60000])
	_set_route(f, 1, [55000, 60000], [45000, 60000])
	for code: String in f.codes:
		var entry: Dictionary = f.state.regiments[code]
		entry.route_m.push_front([entry.x_m, entry.y_m])
	var state := _begin(f, 500000)
	var p := _plan(f, state)
	assert_true(p.motion.moves.any(func(m: Dictionary) -> bool: return m.path_m.size() > 2), "use a real planner avoidance route")
	for row: Dictionary in p.units:
		for point: Array in row.anchor_path_m: assert_eq(point[1], 60000, "anchor must rejoin the requested route")
		var entry: Dictionary = state.day_resolution.march_entries[row.unit]
		var original: Array = [[entry.x_m, entry.y_m]] + entry.route_m
		assert_eq(row.saved_entry_after.get("route_m", []), ArmySystem._body_remaining(original, row.anchor_path_m))
	_commit(f, state, p)

func test_review_inner_receipt_day_matches_noninitial_and_completed_outer_cursor() -> void:
	var f := _fixture([1])
	var state := _begin(f)
	var first := _commit(f, state, _plan(f, state))
	state = first.candidate
	var previous_day := UnitBodies._copy(state)
	previous_day.day_resolution = {}
	previous_day.day += 1
	var engine := TickEngine.new(f.repo)
	var resumed := engine.begin_body_march_candidate(_json(previous_day))
	assert_eq(resumed.status, "complete", resumed.reason)
	assert_eq(engine.step_body_march_candidate(resumed.candidate).status, "complete", "initial cursor accepts a legitimate prior-day receipt")
	for boundary: int in [1, 10]:
		while int(state.day_resolution.body_march.next_substep) < boundary:
			state = _commit(f, state, _plan(f, state)).candidate
		for roundtrip: bool in [false, true]:
			var bad := UnitBodies._copy(state)
			bad.military_migration.body_motion.abs_day = str(bad.absolute_day() - 1)
			if roundtrip: bad = _json(bad)
			var before := bad.to_dict()
			_assert_candidate_error(engine.step_body_march_candidate(bad))
			_assert_candidate_error(ArmySystem.commit_body_march_candidate(f.repo, bad, first.plan))
			assert_eq(bad.to_dict(), before)

func test_review_missing_or_malformed_arrival_journal_rejects_all_entries() -> void:
	var f := _fixture([1])
	var state := _begin(f)
	var plan := _plan(f, state)
	for journal: Dictionary in [{}, {"arrivals": null}, {"arrivals": 1}, {"arrivals": {}}, {"arrivals": false}]:
		for roundtrip: bool in [false, true]:
			var bad := UnitBodies._copy(state)
			bad.day_resolution.journal = journal.duplicate(true)
			if roundtrip: bad = _json(bad)
			var before := bad.to_dict()
			assert_false(DayResolution.body_march_incompatibility_reason(bad.day_resolution).is_empty())
			_assert_candidate_error(TickEngine.new(f.repo).begin_body_march_candidate(bad))
			_assert_candidate_error(ArmySystem.plan_body_march_candidate(f.repo, bad))
			_assert_candidate_error(ArmySystem.commit_body_march_candidate(f.repo, bad, plan))
			_assert_candidate_error(TickEngine.new(f.repo).step_body_march_candidate(bad))
			assert_eq(bad.to_dict(), before, "invalid frozen journal is neither repaired nor partially committed")

func test_review_region_limit_is_a_bound_not_a_destination_arrival() -> void:
	var f := _fixture([1])
	var provinces: Array = f.repo.province_borders.keys()
	provinces.sort()
	var province: String = provinces[0]
	var scale := float(ArmySystem.metres_per_pack_px(f.repo))
	f.repo.province_borders[province] = [PackedVector2Array([
		Vector2(49000 / scale, 49000 / scale), Vector2(51000 / scale, 49000 / scale),
		Vector2(51000 / scale, 51000 / scale), Vector2(49000 / scale, 51000 / scale)])]
	f.state.manor_province = {}
	_pursuit(f, 10000)
	f.state.unit_tasks[f.code].orders["review:pursuit"].request.region = province
	var state := _begin(f, 20000)
	var result := _commit(f, state, _plan(f, state))
	assert_eq(result.candidate.regiments[f.code].x_m, 51000)
	assert_eq(result.plan.arrivals, [], "reaching a pursuit bound is not arrival at the received destination")
	var record := BattleTaskSystem.current(result.candidate, f.code)
	assert_eq(record.status, "bounded")
	assert_eq(record.reason, "Pursuit reached its region's edge")

func test_pursuit_full_route_keeps_motion_numerical_range_guard() -> void:
	var f := _fixture([1])
	_pursuit(f, 10000)
	f.state.regiments[f.code].dest_x_m = -2147483648
	f.state.regiments[f.code].dest_y_m = -2147483648
	f.state.regiments[f.code].route_m = [[-2147483648, -2147483648]]
	var state := _begin(f, 1000)
	var before := state.to_dict()
	_assert_candidate_error(TickEngine.new(f.repo).step_body_march_candidate(state))
	assert_eq(state.to_dict(), before, "clipping a pursuit intent cannot hide an unsafe full-route projection")
