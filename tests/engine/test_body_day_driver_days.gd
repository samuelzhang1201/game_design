extends GutTest
## ACT-DRIVER part A, its whole days: the full day, the sealed writer, the encounter and arrival days,
## the month, the seat, the king and contact. Its own file: the driver's suite alone filled a CI runner's per-phase deadline.

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

## The marches fixture on the INSTALLED policy: one row of 100 at (50000, 50000), facing 0 (+x).
func _march_world() -> Dictionary:
	var f := _helper("res://tests/engine/test_body_marches.gd", "_fixture", [[100]])
	var entry: Dictionary = f.state.regiments[f.code]
	entry.dest_x_m = 50300
	entry.dest_y_m = 50000
	entry.route_m = [[50300, 50000]]
	return f


## A 40 km +x march, longer than a day's pace, so no day of the test ends in an arrival
## (the legacy arrival/garrison snap is a body writer part B2 replaces; it fails closed here).
func _long_world() -> Dictionary:
	var f := _march_world()
	var entry: Dictionary = f.state.regiments[f.code]
	entry.dest_x_m = 90000
	entry.route_m = [[90000, 50000]]
	return f

func _supplies(state: GameState, code: String) -> int:
	return int(state.regiments[code].supplies)


func test_full_day_marches_eats_once_turns_the_day_and_seals() -> void:
	var f := _long_world()
	var source: GameState = f.state
	# Day 3: 100 men use `use` (10..29) a month, and use*3/30 - use*2/30 >= 1, so a double meal shows.
	source.day = 3
	# Even pacing (ArmySystem.day_walk_budget): ceil(40000 / days) for days = ceil(40000 / pace) > 1.
	var budget := ArmySystem.day_walk_budget(f.repo, source, f.code)
	assert_between(budget, 1, 39999, "the march does not arrive today")
	var before := _hash(source)
	var d := source.day
	var result := BodyDayDriver.day(f.repo, source)
	assert_eq(_hash(source), before, "the driver never touches its source")
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var state: GameState = result.candidate
	var copy := BodyDayDriver.day(f.repo, _json(source))
	assert_eq(_hash(copy.candidate), _hash(state), "the JSON save drives to the same day")
	# The straight +x leg needs no pivot, so the row walks its whole budget; the calendar turns once
	# and the closed day leaves no frozen transaction.
	assert_eq(state.day, d + 1)
	assert_true(state.day_resolution.is_empty())
	var row: Dictionary = UnitBodies.rows(f.repo, state, f.code)[0]
	assert_eq([row.x_m, row.y_m, row.facing_deg, row.count], [50000 + budget, 50000, 0, 100])
	# Supply is eaten once, at the day's end position: one day_bite of the month's use.
	var use := ArmySystem.supply_use(f.repo, ArmySystem.regiment(f.repo, f.code, state), state)
	# Hand-computed meal: use*d/30 - use*(d-1)/30, at least 1 when use >= 30, so a double meal shows.
	@warning_ignore("integer_division")
	var meal := use * d / 30 - use * (d - 1) / 30
	assert_between(use, 10, 29, "the fixture's month of supply for 100 men")
	assert_eq(meal, 1)
	assert_eq(_supplies(source, f.code) - _supplies(state, f.code), meal, "eaten exactly once")
	assert_eq([result.ticked, result.ended], [false, source.absolute_day()])
	# Sealed at its next safe boundary: admitted, and the next day walks its own budget and eats
	# one more meal.
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, state, BodyBattle.safe_boundary(state)).status, "complete")
	var budget2 := ArmySystem.day_walk_budget(f.repo, state, f.code)
	assert_between(budget2, 1, 39999 - budget)
	var next := BodyDayDriver.day(f.repo, state)
	assert_eq(next.status, "complete", next.reason)
	if next.candidate == null: return
	assert_eq(next.candidate.day, d + 2)
	assert_eq(UnitBodies.rows(f.repo, next.candidate, f.code)[0].x_m, 50000 + budget + budget2)

func test_writer_between_days_is_sealed_or_refused() -> void:
	var f := _long_world()
	var first := BodyDayDriver.day(f.repo, f.state)
	assert_eq(first.status, "complete", first.reason)
	if first.candidate == null: return
	var state: GameState = first.candidate
	var order := func(_repo: DataRepository, s: GameState) -> void:
		var entry: Dictionary = s.regiments[f.code]
		entry.order = ArmySystem.ORDER_MARCH
		entry.dest_x_m = 130000
		entry.route_m = [[130000, 50000]]
	# An unsealed write breaks the endpoint proof: the next day refuses it, the save kept.
	var raw := UnitBodies._copy(state)
	order.call(f.repo, raw)
	var kept := _hash(raw)
	var refused := BodyDayDriver.day(f.repo, raw)
	assert_eq([refused.status, refused.candidate], ["error", null])
	assert_eq(_hash(raw), kept)
	# Through publish it is the next outer operation; the next day walks the new route's budget.
	var published := BodyDayDriver.publish(f.repo, state, {"kind": "order", "unit": f.code}, order)
	assert_eq(published.status, "complete", published.reason)
	if published.candidate == null: return
	assert_eq(int(published.candidate.military_migration.body_battle.sequence), int(state.military_migration.body_battle.sequence) + 1)
	var again := BodyDayDriver.publish(f.repo, published.candidate, {"kind": "order", "unit": f.code}, order)
	assert_eq([again.status, again.reason, _hash(again.candidate)], ["complete", "Already published", _hash(published.candidate)], "a repeat is a no-op")
	var x: int = UnitBodies.rows(f.repo, state, f.code)[0].x_m
	var budget := ArmySystem.day_walk_budget(f.repo, published.candidate, f.code)
	assert_between(budget, 1, 130000 - x - 1)
	var marched := BodyDayDriver.day(f.repo, published.candidate)
	assert_eq(marched.status, "complete", marched.reason)
	if marched.candidate != null: assert_eq(UnitBodies.rows(f.repo, marched.candidate, f.code)[0].x_m, x + budget)
	# A writer that moves a body or changes personnel is not a lawful ordinary writer.
	var shove := func(_repo: DataRepository, s: GameState) -> void: s.regiments[f.code].body_groups[0].x_m += 1
	assert_string_contains(BodyDayDriver.publish(f.repo, state, {"kind": "shove"}, shove).reason, "moved")
	var lose := func(_repo: DataRepository, s: GameState) -> void: s.military_cohorts.clear()
	assert_string_contains(BodyDayDriver.publish(f.repo, state, {"kind": "lose"}, lose).reason, "personnel")
	var frozen := BodyDayDriver.tactical_day(f.repo, state)
	assert_eq(BodyDayDriver.publish(f.repo, frozen.candidate, {"kind": "order"}, order).reason, "A writer publishes only at a safe boundary")

## The encounter day opens and blocks at the decision (a saved blocked day waits), drives its round
## after the answer, then closes: the fighting garrisons keep their actual anchors and rows (no seat
## snap), the seats move only as `_seat_day` allows, and the next safe boundary is sealed.
func test_encounter_day_completes_with_garrisons_where_they_stand() -> void:
	var path := "res://tests/engine/test_body_battle_motion.gd"
	var f := _helper(path, "_world", [1000])
	var blocked := BodyDayDriver.day(f.repo, f.state)
	assert_eq(blocked.status, "blocked", blocked.reason)
	if blocked.candidate == null: return
	assert_eq(blocked.candidate.day_resolution.body_battle.stage, "round")
	var pending: Dictionary = blocked.candidate.day_resolution.pending_decision
	var answered := BodyDayDriver.acknowledge(f.repo, blocked.candidate, pending.token, "continue")
	assert_eq(answered.status, "complete", answered.reason)
	if answered.candidate == null: return
	var tactical := BodyDayDriver.tactical_day(f.repo, answered.candidate)
	assert_eq(tactical.status, "complete", tactical.reason)
	if tactical.candidate == null: return
	assert_eq(int(tactical.candidate.battles[0].rounds), 1)
	var kept := _hash(answered.candidate)
	var closed := BodyDayDriver.day(f.repo, answered.candidate)
	assert_eq(closed.status, "complete", closed.reason)
	assert_eq(_hash(answered.candidate), kept, "the driver never touches its source")
	if closed.candidate == null: return
	for code: String in f.state.army_roster:
		var end := UnitBodies._entry(tactical.candidate, code)
		var now := UnitBodies._entry(closed.candidate, code)
		assert_eq([now.x_m, now.y_m], [end.x_m, end.y_m], code + " keeps its actual anchor")
		assert_eq(UnitBodies.rows(f.repo, closed.candidate, code), UnitBodies.rows(f.repo, tactical.candidate, code), code + " keeps its rows")
	for town: String in tactical.candidate.town_seat:
		var holder: String = tactical.candidate.town_seat[town]
		if f.state.army_roster.has(holder): assert_eq(closed.candidate.town_seat.get(town), holder, "a fighting garrison keeps its seat")
	assert_eq(closed.ended, int(answered.candidate.day_resolution.absolute_day))
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, closed.candidate, BodyBattle.safe_boundary(closed.candidate)).status, "complete")

func test_ordinary_day_refuses_an_admitted_body_world() -> void:
	var f := _march_world()
	var engine := TickEngine.new(f.repo)
	var before := _hash(f.state)
	assert_eq(engine.resolve_day(f.state), {"status": "error", "error": TickEngine.BODY_WORLD})
	assert_eq(engine.resolve_decision(f.state, "t", "continue"), {"status": "error", "error": TickEngine.BODY_WORLD})
	assert_eq(engine.advance_day(f.state), [])
	assert_eq(_hash(f.state), before, "no ordinary writer touches it")

## The thirtieth day settles the month once (`ticked`, a report, the tick turned to day 1). Its
## wound recovery is the close's personnel (B2d, `test_body_day_losses.gd`); a saved world whose
## rows disagree with its fit people is refused at admission, the save kept.
func test_thirtieth_day_settles_the_month_once() -> void:
	var f := _long_world()
	# Tick 1: the reign's opening tick 0 settles through `advance`, and its day 30 is absolute day 30
	# while tick 1's first day is absolute day 1.
	f.state.tick = 1
	f.state.day = 30
	var tick: int = f.state.tick
	var result := BodyDayDriver.day(f.repo, f.state)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	assert_eq([result.ticked, result.report != null], [true, true])
	assert_eq([result.candidate.tick, result.candidate.day], [tick + 1, 1])
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, result.candidate, BodyBattle.safe_boundary(result.candidate)).status, "complete")
	var wounded := _long_world()
	wounded.state.tick = 1
	wounded.state.day = 30
	var hurt := MilitaryRoster.transfer_units(wounded.repo, wounded.state, "test:wound",
		[{"unit_code": wounded.code, "from": "fit", "to": "wounded", "count": 10}], "Test wounds")
	assert_false(hurt.has("error"), str(hurt.get("error", "")))
	var before := _hash(wounded.state)
	var refused := BodyDayDriver.day(wounded.repo, wounded.state)
	assert_eq([refused.status, refused.candidate], ["error", null])
	assert_string_contains(refused.reason, "Bodies disagree with fit personnel")
	assert_eq(_hash(wounded.state), before)

## Hand-computed arrival: the 300 m route fits one day (budget 300), so the row ends ON its
## destination (50300, 50000), facing 0; the march turns to GARRISON there and settles its camp at
## that actual anchor, with no seat snap: the anchor equals the row and the day closes sealed. In
## the field it takes no seat; with a held town's point moved under (50300, 50000) that town's
## seat goes to the arrival, and its camp is that town.
## The 300 m route fits the day's budget of 300, so the row ends on its destination (50300, 50000)
## facing 0 and garrisons THERE, off every town point: no snap, and in the field no seat. The
## fixture keeps the whole campaign's seats for the units it dropped; a seat whose holder is gone
## is cleared, as `ArmyGround.reconcile` clears it. (Seating on a town's point: the seat test.)
func test_arrival_day_garrisons_where_the_column_stands() -> void:
	var f := _march_world()
	var before := _hash(f.state)
	for key: String in f.state.town_seat:
		assert_false(f.state.army_roster.has(f.state.town_seat[key]), "only dropped units' seats")
	var result := BodyDayDriver.day(f.repo, f.state)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(_hash(f.state), before, "the driver never touches its source")
	if result.candidate == null: return
	var state: GameState = result.candidate
	var entry: Dictionary = state.regiments[f.code]
	var row: Dictionary = UnitBodies.rows(f.repo, state, f.code)[0]
	assert_eq([row.x_m, row.y_m, row.facing_deg, row.count], [50300, 50000, 0, 100])
	assert_eq([entry.x_m, entry.y_m, entry.order], [50300, 50000, ArmySystem.ORDER_GARRISON], "garrisoned where it stands")
	assert_true(f.code in result.journal.arrivals)
	assert_eq(state.town_seat, {}, "in the field it takes no seat")
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, state, BodyBattle.safe_boundary(state)).status, "complete")
	var copy := BodyDayDriver.day(f.repo, _json(f.state))
	assert_eq(_hash(copy.candidate), _hash(state), "the JSON save gives the same day")

## The seat rules, hand-built on one crown unit standing at (50000, 50000), off every town point
## (a garrison whose rows moved in battle): it KEEPS a seat it holds; it loses it on the march
## (`ArmyGround.leave`'s rule) or once its town is lost; a seat whose holder is gone is cleared;
## an arrival standing on a held town's point camps there and takes its empty seat.
func test_seat_day_clears_a_seat_only_as_the_legacy_day_does() -> void:
	var f := _march_world()
	var realm: String = f.state.army_roster[f.code].kingdom_code
	var towns: Array = f.repo.burgs.keys()
	towns.sort()
	var town := ""
	for key: String in towns:
		if ArmyGround.holds(f.repo, f.state, realm, key):
			town = key
			break
	assert_ne(town, "", "a held town")
	var other := ""
	for key: String in f.repo.kingdoms:
		if key != realm:
			other = key
			break
	for case: String in ["garrison", "march", "lost", "gone"]:
		var state := UnitBodies._copy(f.state)
		state.town_seat = {town: f.code if case != "gone" else "no_such_unit"}
		var entry: Dictionary = state.regiments[f.code]
		entry.order = ArmySystem.ORDER_MARCH if case == "march" else ArmySystem.ORDER_GARRISON
		if case == "lost":
			assert_true(MapOwnership.set_owner(f.repo, state, String(f.repo.burgs[town].province_code), other, "test: town lost"))
		assert_eq(BodyDayDriver._seat_day(f.repo, state, []), "", case)
		assert_eq(state.town_seat, {town: f.code} if case == "garrison" else {}, case)
		assert_eq([entry.x_m, entry.y_m], [50000, 50000], case + ": no anchor moves")
	var state := UnitBodies._copy(f.state)
	state.town_seat = {}
	state.regiments[f.code].order = ArmySystem.ORDER_GARRISON
	var px := ArmySystem.metres_to_pack(f.repo, Vector2i(50000, 50000))
	f.repo.burgs[town].x = px.x
	f.repo.burgs[town].y = px.y
	ArmySystem.forget_grids()
	assert_eq(BodyDayDriver._seat_day(f.repo, state, [f.code]), "", "arrive")
	assert_eq(state.town_seat, {town: f.code}, "an arrival on the point takes the seat")
	assert_eq(String(state.regiments[f.code].get("camp_town", "")), town, "its camp is the town under its anchor")
	assert_eq([state.regiments[f.code].x_m, state.regiments[f.code].y_m], [50000, 50000], "arrive: no anchor moves")

## B2b: the king walks his daily budget in slice shares, once each. 100000 m left at
## 30 km a day is ceil(100000 / 30000) = 4 days, so ceil(100000 / 4) = 25000 m today, from
## (10000, 20000) east: 2500 m a slice over the 10 slices, (12500, 20000) after the first, and
## (35000, 20000) at the day's end. His route is set through `publish` (an ordinary writer).
func test_king_walks_his_daily_budget_in_slice_shares() -> void:
	var f := _march_world()
	f.repo.balance["king_travel_km_per_day"] = 30.0
	assert_eq(int(f.repo.bal("battle_substeps")), 10, "the hand case's slice count")
	var route := func(_repo: DataRepository, s: GameState) -> void:
		s.king_state = {"x_m": 10000, "y_m": 20000, "route": [[110000, 20000]], "follow_code": "",
			"travel_state": "travelling", "last_advanced_day": 0}
	var routed := BodyDayDriver.publish(f.repo, f.state, {"kind": "king_route"}, route)
	assert_eq(routed.status, "complete", routed.reason)
	if routed.candidate == null: return
	var opened := BodyDayDriver._open(f.repo, TickEngine.new(f.repo), routed.candidate)
	assert_eq(opened.status, "complete", opened.reason)
	if opened.candidate == null: return
	var moved := BodyBattle.step_candidate(f.repo, opened.candidate)
	assert_eq(moved.status, "complete", moved.reason)
	var first := BodyDayDriver._slice_work(f.repo, moved.candidate)
	assert_eq(first.status, "complete", first.reason)
	if first.candidate == null: return
	assert_eq([first.candidate.king_state.x_m, first.candidate.king_state.y_m, first.candidate.day_resolution.king_substep_index],
		[12500, 20000, 0], "the first slice's share")
	assert_eq(BodyDayDriver._slice_work(f.repo, first.candidate).candidate, first.candidate, "done once")
	var result := BodyDayDriver.day(f.repo, routed.candidate)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var king: Dictionary = result.candidate.king_state
	assert_eq([king.x_m, king.y_m, king.route, king.travel_state, king.last_advanced_day],
		[35000, 20000, [[110000, 20000]], "travelling", result.ended])
	assert_eq(result.journal.king_state, king, "the day's journal keeps the king")
	var copy := BodyDayDriver.day(f.repo, _json(routed.candidate))
	assert_eq(_hash(copy.candidate), _hash(result.candidate), "the JSON save gives the same day")

## B2b: after a slice's contacts, a unit on search travel caught in a battle leaves the frozen
## march (entry and membership) and its task pauses, as `ArmyTasks.pause_battles` does in the
## ordinary day; nothing moves. Saved before that work ran (the cursor at the slice's move), the
## driver runs it before waiting on the encounter, and the answered day then completes on the
## edited march. A candidate stepped past a slice without its work is refused.
func test_contact_slice_pauses_search_travel_out_of_the_frozen_march() -> void:
	var f := _helper("res://tests/engine/test_body_battle_motion.gd", "_world", [1000])
	var blocked := BodyDayDriver.day(f.repo, f.state)
	assert_eq(blocked.status, "blocked", blocked.reason)
	if blocked.candidate == null: return
	var state := UnitBodies._copy(blocked.candidate)
	var code := ""
	for key: String in state.regiments:
		if not BattleSystem.battle_of(state, key).is_empty():
			code = key
			break
	assert_ne(code, "", "a crown unit in the battle")
	var entry: Dictionary = state.regiments[code]
	var issued := ArmyTasks.issue(f.repo, state, {"id": "", "kind": "search", "unit_codes": [code],
		"center_x_m": int(entry.x_m) + 40000, "center_y_m": int(entry.y_m), "radius_m": 2000})
	assert_true(issued.ok, str(issued))
	var id := String(issued.get("id", ""))
	assert_eq(ArmyTasks.receive(f.repo, state, id, 1, code).status, "received")
	entry.travel_task_id = id
	var tx := state.day_resolution
	var saved: Dictionary = entry.duplicate(true)
	saved.order = ArmySystem.ORDER_MARCH
	tx.march_entries[code] = saved
	tx.marching_codes.append(code)
	tx.marching_codes.sort()
	tx.slice_work.done = "0:move"
	BodyBattle._seal_private(f.repo, state)
	var at := [entry.x_m, entry.y_m]
	var before := _hash(state)
	var waited := BodyDayDriver.tactical_day(f.repo, state)
	assert_eq(waited.status, "blocked", waited.reason)
	assert_eq(_hash(state), before, "the driver never touches its source")
	if waited.candidate == null: return
	var out: GameState = waited.candidate
	assert_false(out.day_resolution.march_entries.has(code), "out of the frozen march")
	assert_false(code in out.day_resolution.marching_codes, "and out of its membership")
	assert_eq(out.army_tasks[id].units[code].phase, "paused_battle")
	assert_false(out.regiments[code].has("travel_task_id"))
	assert_eq([out.regiments[code].x_m, out.regiments[code].y_m], at, "nothing moves")
	assert_eq(out.day_resolution.slice_work.done, "0:contact")
	var answered := BodyDayDriver.acknowledge(f.repo, out, out.day_resolution.pending_decision.token, "continue")
	assert_eq(answered.status, "complete", answered.reason)
	if answered.candidate == null: return
	var done := BodyDayDriver.tactical_day(f.repo, answered.candidate)
	assert_eq(done.status, "complete", done.reason)
	# Stepped past slice 0 with its work undone, the next slice is refused.
	var skipped := UnitBodies._copy(answered.candidate)
	skipped.day_resolution.slice_work.done = "0:move"
	skipped.day_resolution.body_battle.stage = "move"
	skipped.day_resolution.body_battle.next_substep = "1"
	skipped.day_resolution.substep_index = 1
	BodyBattle._seal_private(f.repo, skipped)
	assert_eq(BodyDayDriver._slice_work(f.repo, skipped).reason, "Slice 0's tactical work was skipped")
