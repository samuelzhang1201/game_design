extends GutTest
## ACT-DRIVER part B2b2: the hosts' per-slice arrivals in the body day (`EnemyAi.arrival_substep`).
## Its own file: the driver's suite alone fills a CI runner's per-phase deadline.

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()
	ArmySystem.forget_grids()

func _helper(path: String, method: String, args: Array = []) -> Dictionary:
	var helper: GutTest = load(path).new()
	var f: Dictionary = helper.callv(method, args)
	assert_eq(helper.get_fail_count(), 0, path)
	helper.free()
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _hash(state: GameState) -> String:
	return BodyMotion._hash(state.to_dict())

## Runs the driver and checks its source is untouched and its JSON copy gives the same result.
func _day(repo: DataRepository, source: GameState, expected: String) -> GameState:
	var before := _hash(source)
	var result := BodyDayDriver.tactical_day(repo, source)
	assert_eq(_hash(source), before, "the driver never touches its source")
	assert_eq(result.status, expected, result.reason)
	if result.candidate == null: return null
	var copy := BodyDayDriver.tactical_day(repo, _json(source))
	assert_eq(_hash(copy.candidate), _hash(result.candidate), "the JSON save drives to the same candidate")
	return result.candidate

## B2b2 fixture: a host's one column (100 men, one row facing +x) marches +x on a 300 m route, 30 m
## a slice over the 10 slices, toward a town the crown holds whose point is moved onto the test
## grid 5150 m ahead of it, at (50000, `town_y`). The crown's own row stands at (50000, 50000)
## under a garrison order: on the point it garrisons the town, 30 km off it does not.
func _host_world(town_y: int) -> Dictionary:
	var f := _helper("res://tests/engine/test_body_marches.gd", "_fixture", [[100, 100]])
	var state: GameState = f.state
	f.crown = f.codes[0]
	f.foe = f.codes[1]
	var towns: Array = f.repo.burgs.keys()
	towns.sort()
	for key: String in towns:
		if ArmyGround.holds(f.repo, state, String(state.army_roster[f.crown].kingdom_code), key):
			f.town = key
			break
	var px := ArmySystem.metres_to_pack(f.repo, Vector2i(50000, town_y))
	f.repo.burgs[f.town].x = px.x
	f.repo.burgs[f.town].y = px.y
	ArmySystem.forget_grids()
	assert_eq(EnemyAi.target_point_m(f.repo, EnemyAi.KIND_TOWN, f.town), Vector2i(50000, town_y))
	var mine: Dictionary = state.regiments[f.crown]
	mine.order = ArmySystem.ORDER_GARRISON
	mine.dest_x_m = 50000
	mine.erase("route_m")
	# On the point it camps there and takes the seat, as the driver's own arrival writer settles it.
	if town_y == 50000: assert_eq(BodyDayDriver._seat_day(f.repo, state, [f.crown]), "")
	var entry: Dictionary = state.regiments[f.foe]
	state.regiments.erase(f.foe)
	state.foes[f.foe] = entry
	state.army_roster[f.foe].kingdom_code = f.repo.resolve_realm("raider_realm")
	f.host = String(f.repo.raid_hosts[0].host_code)
	entry.host = f.host
	for row: Dictionary in [entry, entry.body_groups[0]]:
		row.x_m = 44850
		row.y_m = town_y
	entry.dest_x_m = 45150
	entry.dest_y_m = town_y
	entry.route_m = [[45150, town_y]]
	state.ai_hosts = {f.host: {"mode": EnemyAi.MODE_ADVANCE, "target_kind": EnemyAi.KIND_TOWN, "target_id": f.town,
		"think_day": 0, "plunder": 0}}
	return f

func _host_events(state: GameState) -> Array:
	var out: Array = []
	for record: Dictionary in state.day_resolution.journal.get("reports", []):
		if record.kind == "host_events": out.append_array(record.events)
	return out

## B2b2: a host's column arrives in the slice that brings it up, not at the day's end. The town's
## point is 5150 m ahead and the crown garrisons it; the column walks 30 m a slice, so it touches
## the town (`battle_contact_km` 5 km, over the town's own reach) once 5150 - 30k <= 5000: after
## its 5th move (slice 4), at x = 45000. In that slice's work the host deploys, the column is
## stationed where it stands and retired from the frozen march, and the siege is laid; the body
## then holds, so the day ends at 45000, not at the route's end 45150, and the siege begins at the
## day's close. Not a body moves by the arrival.
func test_host_column_arrives_in_its_slice_and_holds_the_rest_of_the_day() -> void:
	var f := _host_world(50000)
	assert_eq([int(f.repo.bal("battle_substeps")), f.repo.bal("battle_contact_km")], [10, 5.0])
	assert_lt(float(f.repo.army_town_reach.get(String(f.repo.burgs[f.town].group), 0.0)), 5.0, "contact outreaches the town")
	assert_eq(EnemyAi.garrison_of(f.repo, f.state, f.town), [f.crown])
	assert_eq(ArmySystem.day_walk_budget(f.repo, f.state, f.foe), 300)
	var state: GameState = BodyBattle.begin_candidate(f.repo, f.state).candidate
	var today := state.absolute_day()
	# The morning's AI phase has already told an event: the arrival's join its one record, after it.
	var morning := {"type": "host_advance", "host": f.host, "day": today}
	state.day_resolution.journal.reports = [{"kind": "host_events", "events": [morning]}]
	BodyBattle._seal_private(f.repo, state)
	var begun := state
	var saved_before: GameState = null
	var told: Array = [morning,
		{"type": "host_mode", "host": f.host, "mode": EnemyAi.MODE_DEPLOYING, "why": "first column arrived; remaining columns are deploying", "day": today},
		{"type": "host_mode", "host": f.host, "mode": EnemyAi.MODE_SIEGE, "why": "leading columns deployed at the town", "day": today}]
	for slice: int in 10:
		while state.day_resolution.body_battle.stage != "contact":
			state = BodyDayDriver._slice_work(f.repo, state).candidate
			var stepped := BodyBattle.step_candidate(f.repo, state)
			assert_eq(stepped.status, "complete", stepped.reason)
			if stepped.candidate == null: return
			state = stepped.candidate
		var rows := BodyMotion._hash([BodyLifecycle.snapshot(state), state.military_cohorts])
		if slice == 4: saved_before = _json(state)
		var worked := BodyDayDriver._slice_work(f.repo, state)
		assert_eq(worked.status, "complete", worked.reason)
		if worked.candidate == null: return
		state = worked.candidate
		assert_eq(state.day_resolution.slice_work.done, "%d:move" % slice)
		assert_eq(BodyMotion._hash([BodyLifecycle.snapshot(state), state.military_cohorts]), rows, "the arrival moves no body")
		var entry: Dictionary = state.foes[f.foe]
		var saved: Dictionary = state.day_resolution.march_entries[f.foe]
		assert_eq(entry.x_m, 44850 + 30 * mini(slice + 1, 5), "slice %d" % slice)
		if slice < 4:
			assert_eq([state.ai_hosts[f.host].mode, entry.order, saved.order, _host_events(state)],
				[EnemyAi.MODE_ADVANCE, ArmySystem.ORDER_MARCH, ArmySystem.ORDER_MARCH, [morning]], "slice %d" % slice)
		else:
			assert_eq([state.ai_hosts[f.host].mode, entry.order, saved.order], [EnemyAi.MODE_SIEGE, ArmySystem.ORDER_GARRISON, ArmySystem.ORDER_GARRISON], "slice %d" % slice)
			assert_eq([entry.dest_x_m, entry.dest_y_m, entry.has("route_m"), saved.x_m, saved.has("route_m")], [45000, 50000, false, 45000, false])
			assert_eq(state.ai_hosts[f.host].deployment, {"town": f.town, "started_day": today, "complete": true, "completed_day": today})
			assert_eq(_host_events(state), told, "told once")
		assert_eq(BodyDayDriver._slice_work(f.repo, state).candidate, state, "the slice's work runs once")
		var next := BodyBattle.step_candidate(f.repo, state)
		assert_eq(next.status, "complete", next.reason)
		if next.candidate == null: return
		state = next.candidate
	# The driver alone, from the day's start and from a JSON save taken right before the arrival
	# slice's work, reaches the same day.
	var driven := _day(f.repo, begun, "complete")
	if driven == null: return
	assert_eq(_hash(driven), _hash(BodyDayDriver.tactical_day(f.repo, state).candidate))
	assert_eq(_hash(driven), _hash(BodyDayDriver.tactical_day(f.repo, saved_before).candidate), "resumed at the arrival slice")
	assert_eq([driven.foes[f.foe].x_m, UnitBodies.rows(f.repo, driven, f.foe)[0].x_m, driven.battles], [45000, 45000, []])
	assert_eq(_host_events(driven), told)
	# The day closes on it: the siege begins the same day, and the day's reports tell the host's news once.
	var closed := BodyDayDriver.day(f.repo, driven)
	assert_eq(closed.status, "complete", closed.reason)
	if closed.candidate == null: return
	assert_eq([closed.candidate.ai_hosts[f.host].mode, SiegeRecord.of_host(closed.candidate, f.host).get("days")], [EnemyAi.MODE_SIEGE, 1])
	assert_eq(closed.journal.sieges.map(func(e: Dictionary) -> String: return String(e.kind)), ["siege_begin", "siege_day"])
	assert_eq(closed.journal.reports, [{"kind": "host_events", "events": told}])
	assert_eq(closed.candidate.missives.filter(func(m: Dictionary) -> bool:
		return m.kind == "host_news" and int(m.id) >= f.state.next_missive_id).size(), 1)
	assert_eq(closed.candidate.foes[f.foe].x_m, 45000, "the close moves no one")

## Steps to the next slice's committed move (stage "contact"), each step after its owed slice work,
## and runs that move's work.
func _next_move_work(f: Dictionary, state: GameState) -> GameState:
	var first := true
	while first or state.day_resolution.body_battle.stage != "contact":
		first = false
		state = BodyDayDriver._slice_work(f.repo, state).candidate
		var stepped := BodyBattle.step_candidate(f.repo, state)
		assert_eq(stepped.status, "complete", stepped.reason)
		state = stepped.candidate
	return BodyDayDriver._slice_work(f.repo, state).candidate

## Player siege 4b: at a town the crown holds but does not garrison, the same column BESIEGES it in
## the arrival slice (5150 - 30k <= 5000: after the 5th move, at 45000; an empty town is besieged,
## not raided) and is stationed where it stands. A slice's work changes no body or personnel, so
## the town's record, and the militia it raises, opens as the day's siege settles at the close.
func test_host_at_an_undefended_town_besieges_it_and_its_militia_rises_at_the_close() -> void:
	var f := _host_world(80000)
	assert_eq(EnemyAi.garrison_of(f.repo, f.state, f.town), [])
	var manual: GameState = BodyBattle.begin_candidate(f.repo, f.state).candidate
	for slice: int in 4: manual = _next_move_work(f, manual)
	assert_eq([manual.foes[f.foe].x_m, manual.ai_hosts[f.host].mode, _host_events(manual)], [44970, EnemyAi.MODE_ADVANCE, []])
	manual = _next_move_work(f, manual)
	assert_eq([manual.foes[f.foe].x_m, manual.ai_hosts[f.host].mode, manual.foes[f.foe].order], [45000, EnemyAi.MODE_SIEGE, ArmySystem.ORDER_GARRISON])
	assert_true(SiegeRecord.of_host(manual, f.host).is_empty(), "no record in the slice's work")
	var state := _day(f.repo, f.state, "complete")
	if state == null: return
	assert_eq(_hash(state), _hash(BodyDayDriver.tactical_day(f.repo, manual).candidate))
	assert_eq(_host_events(state).map(func(e: Dictionary) -> String: return String(e.mode)), [EnemyAi.MODE_DEPLOYING, EnemyAi.MODE_SIEGE])
	assert_eq([state.foes[f.foe].x_m, state.foes[f.foe].order], [45000, ArmySystem.ORDER_GARRISON], "stationed where it arrived")
	var closed := BodyDayDriver.day(f.repo, state)
	assert_eq(closed.status, "complete", closed.reason)
	if closed.candidate == null: return
	var rec := SiegeRecord.of_host(closed.candidate, f.host)
	assert_false(rec.is_empty(), "the siege settles: the record opens")
	assert_eq((rec.militia as Array).size(), 1, "and the town's militia rises")
	assert_true(closed.candidate.regiments.has(String(rec.militia[0])), "the crown's")
	assert_eq(ArmyGround.seat_of(f.repo, closed.candidate, f.town), String(rec.militia[0]), "on the town's seat")

## B2b2: another host already deploys at the garrisoned town, so the column's host drops its target
## in the arrival slice and stands aside (no second siege): no event, the live order turns to
## garrison and it is kept out of contact today. Its frozen entry is NOT retired, so, as the
## ordinary day walks a changed order's saved route out, the body walks the day's whole 300 m and
## garrisons at its end; no battle starts.
func test_host_finding_its_town_besieged_stands_aside_and_walks_its_frozen_day() -> void:
	var f := _host_world(50000)
	var other := String(f.repo.raid_hosts[1].host_code)
	assert_ne(EnemyAi.role_of(f.repo, other), EnemyAi.ROLE_RESERVE)
	var today: int = f.state.absolute_day()
	f.state.ai_hosts[other] = {"mode": EnemyAi.MODE_DEPLOYING, "target_kind": EnemyAi.KIND_TOWN, "target_id": f.town,
		"think_day": 0, "plunder": 0, "deployment": {"town": f.town, "started_day": today, "complete": false}}
	var manual: GameState = BodyBattle.begin_candidate(f.repo, f.state).candidate
	for slice: int in 5: manual = _next_move_work(f, manual)
	var entry: Dictionary = manual.foes[f.foe]
	assert_eq([manual.ai_hosts[f.host].mode, manual.ai_hosts[f.host].target_id, _host_events(manual)], [EnemyAi.MODE_ADVANCE, "", []])
	assert_eq([entry.x_m, entry.order, entry.dest_x_m, entry.disengaged_until, manual.day_resolution.march_entries[f.foe].order],
		[45000, ArmySystem.ORDER_GARRISON, 45000, today, ArmySystem.ORDER_MARCH])
	var state := _day(f.repo, f.state, "complete")
	if state == null: return
	assert_eq(_hash(state), _hash(BodyDayDriver.tactical_day(f.repo, manual).candidate))
	entry = state.foes[f.foe]
	assert_eq([entry.x_m, entry.order, entry.dest_x_m, UnitBodies.rows(f.repo, state, f.foe)[0].x_m, state.battles], [45150, ArmySystem.ORDER_GARRISON, 45150, 45150, []])
	assert_eq([state.ai_hosts[f.host].mode, state.ai_hosts[other].mode, _host_events(state)], [EnemyAi.MODE_ADVANCE, EnemyAi.MODE_DEPLOYING, []])
