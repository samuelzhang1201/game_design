extends GutTest
## ACT-DRIVER part A: one admission for every writer (ACT-LOAD's preparation seam), the day's
## tactical part driven to one detached candidate, exact resume and an untouched source.

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

func test_march_day_moves_the_row_by_the_ordinary_budget() -> void:
	var f := _march_world()
	# Hand-computed: the 300 m route fits in one day's pace, so day_walk_budget = ceil(300) = 300,
	# shared over the 10 slices as 30 each; a straight +x leg along the row's facing needs no
	# pivot, so every slice translates its whole share: the row ends at x = 50000 + 300.
	assert_eq(ArmySystem.day_walk_budget(f.repo, f.state, f.code), 300)
	var cohorts := BodyMotion._hash(f.state.military_cohorts)
	var rng := BodyMotion._hash(f.state.rng.to_dict())
	var state := _day(f.repo, f.state, "complete")
	if state == null: return
	assert_eq(state.day_resolution.body_battle.stage, "complete")
	assert_eq(state.day_resolution.march_budgets[f.code], 300)
	var row: Dictionary = UnitBodies.rows(f.repo, state, f.code)[0]
	assert_eq([row.x_m, row.y_m, row.facing_deg, row.count], [50300, 50000, 0, 100])
	assert_eq([state.regiments[f.code].x_m, state.regiments[f.code].y_m], [50300, 50000], "the anchor follows the row")
	assert_eq(BodyMotion._hash(state.military_cohorts), cohorts, "a march changes no personnel")
	assert_eq(BodyMotion._hash(state.rng.to_dict()), rng, "a march draws nothing")
	# Resuming the completed candidate (direct or saved) is an exact no-op.
	for again: GameState in [state, _json(state)]:
		var retry := BodyDayDriver.tactical_day(f.repo, again)
		assert_eq(retry.status, "complete", retry.reason)
		assert_eq(_hash(retry.candidate), _hash(state))

func test_admission_fails_closed_and_takes_the_load_seam() -> void:
	var f := _march_world()
	var legacy := UnitBodies._copy(f.state)
	legacy.military_migration.erase("body_version")
	var file := _hash(legacy)
	var refused := BodyDayDriver.admit(f.repo, legacy)
	assert_eq([refused.status, refused.reason, refused.candidate], ["error", "Not an admitted body world", null])
	assert_eq(_hash(legacy), file, "a refused load keeps the source save")
	# ACT-LOAD's classifier plugs in on a detached copy; its refusal fails closed.
	var classify := func(_repo: DataRepository, state: GameState) -> Dictionary:
		state.military_migration.body_version = 1
		return {"status": "complete", "reason": "", "candidate": state}
	var classified := BodyDayDriver.admit(f.repo, legacy, classify)
	assert_eq(classified.status, "complete", classified.reason)
	assert_eq(_hash(legacy), file, "the seam works on a copy")
	if classified.candidate != null: assert_eq(_hash(classified.candidate), _hash(f.state))
	var reject := func(_repo: DataRepository, _state: GameState) -> Dictionary:
		return {"status": "error", "reason": "overlapping legacy rows", "candidate": null}
	var rejected := BodyDayDriver.admit(f.repo, f.state, reject)
	assert_eq([rejected.status, rejected.reason], ["error", "Admission preparation refused: overlapping legacy rows"])
	# An ordinary frozen day, or an arm without its installed policy, never enters the driver.
	var ordinary := UnitBodies._copy(f.state)
	ordinary.day_resolution = DayResolution.begin(ordinary.day, false, ordinary.absolute_day())
	assert_eq(BodyDayDriver.admit(f.repo, ordinary).reason, "An ordinary frozen day cannot enter the body driver")
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	f.repo.unit_footprints[piece].erase("locomotion_certificate")
	var day := BodyDayDriver.tactical_day(f.repo, f.state)
	assert_eq([day.status, day.candidate], ["error", null])
	assert_eq(BodyDayDriver.admit(f.repo, f.state).reason, "Unsupported locomotion policy or terrain")

## The contact world: begin, move, contacts found the field, the encounter waits for the player;
## the answer, then round ready, plan, settle and the rest of the day. The driver's candidates
## equal the stepwise control transitions, and a saved blocked day resumes exactly.
## The manual reference: one engine transition, then the slice work it makes due
## (`_slice_work`), as the driver runs it.
func _manual_step(f: Dictionary, state: GameState) -> Dictionary:
	var step: Dictionary = f.engine.step_body_battle_candidate(state)
	if step.candidate != null:
		var due := BodyDayDriver._slice_work(f.repo, step.candidate)
		assert_eq(due.status, "complete", due.reason)
		step.candidate = due.candidate
	return step

func test_encounter_blocks_then_resumes_to_the_stepped_day() -> void:
	var path := "res://tests/engine/test_body_battle_motion.gd"
	var f := _helper(path, "_world", [1000])
	var helper: GutTest = load(path).new()
	# Begin, move, contact, the encounter block, acknowledgement, round-ready (the motion suite's
	# `_to_ready`), each move and contact followed by the slice's work.
	var stepped: Array = []
	var manual: GameState = f.engine.begin_body_battle_candidate(f.state).candidate
	for expected: String in ["complete", "complete", "blocked", "ack", "blocked"]:
		if expected == "ack":
			manual = helper.call("_acknowledge", f, manual)
		else:
			var step := _manual_step(f, manual)
			assert_eq(step.status, expected, step.reason)
			manual = step.candidate
		stepped.append(manual)
	var guard := 0
	while manual.day_resolution.body_battle.stage != "complete" and guard < 200:
		guard += 1
		var step := _manual_step(f, manual)
		assert_true(step.status in ["complete", "blocked"] and step.candidate != null, step.reason)
		if step.candidate == null: break
		manual = step.candidate
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var blocked := _day(f.repo, f.state, "blocked")
	if blocked == null: return
	assert_eq(_hash(blocked), _hash(stepped[2]), "stops at the encounter decision")
	var pending: Dictionary = blocked.day_resolution.pending_decision
	var again := BodyDayDriver.tactical_day(f.repo, _json(blocked))
	assert_eq([again.status, _hash(again.candidate)], ["blocked", _hash(blocked)], "a saved blocked day waits")
	var answered := BodyDayDriver.acknowledge(f.repo, blocked, pending.token, "continue")
	assert_eq(answered.status, "complete", answered.reason)
	if answered.candidate == null: return
	assert_eq(_hash(answered.candidate), _hash(stepped[3]))
	var done := _day(f.repo, answered.candidate, "complete")
	if done == null: return
	assert_eq(_hash(done), _hash(manual), "the driver's day equals the stepped day")
	var published := _day(f.repo, stepped[4], "complete")
	if published != null: assert_eq(_hash(published), _hash(manual), "a published frozen round resumes as it stands")
	assert_eq(int(done.battles[0].rounds), 1, "one round the same day")

## D-DRIVER's failed settlement (a stale family-loss receipt): the driver waits on the frozen
## pending with the unchanged candidate instead of retrying; repaired, the same day completes.
func test_failed_settlement_waits_on_its_frozen_pending() -> void:
	var path := "res://tests/engine/test_body_damage_driver.gd"
	var f := _helper(path, "_ready_world")
	var planned: GameState = BodyBattle.step_candidate(f.repo, f.ready).candidate
	var broken := _json(planned)
	var stale := "family:battle:%d:round:%d:%s" % [f.id, int(planned.battles[0].pending_round.round), f.unit]
	broken.military_events[stale] = {"request": {"kind": "stale"}, "result": {}}
	BodyBattle._seal_private(f.repo, broken)
	var held := _day(f.repo, broken, "blocked")
	if held == null: return
	# The fixture is stepped raw, so the slice's owed work (B2b) runs once; nothing else changes.
	var owed := BodyDayDriver._slice_work(f.repo, broken)
	assert_eq(owed.status, "complete", owed.reason)
	assert_eq(_hash(held), _hash(owed.candidate), "nothing changes while the settlement fails")
	held.military_events.erase(stale)
	BodyBattle._seal_private(f.repo, held)
	var done := _day(f.repo, held, "complete")
	var clean := _day(f.repo, planned, "complete")
	if done != null and clean != null: assert_eq(_hash(done), _hash(clean), "the same frozen draw settles")

func test_malformed_saved_day_is_refused_not_crashed() -> void:
	var path := "res://tests/engine/test_body_battle_motion.gd"
	var f := _helper(path, "_world", [1000])
	var begun := BodyBattle.begin_candidate(f.repo, f.state)
	assert_eq(begun.status, "complete", begun.reason)
	if begun.candidate == null: return
	var bad: GameState = _json(begun.candidate)
	bad.day_resolution.body_battle.erase("next_substep")
	var refused := BodyDayDriver.admit(f.repo, bad)
	assert_eq([refused.status, refused.candidate], ["error", null])
	assert_ne(refused.reason, "")

## A fleet-only world has no body to keep: the day still drives (the contact edge's empty snapshot).
func test_world_without_land_units_drives_its_day() -> void:
	var f := _march_world()
	for code: String in f.state.army_roster: f.state.army_roster[code].is_naval = "1"
	_day(f.repo, f.state, "complete")

## ACT-DRIVER part B1: the whole sealed day, the writer between days and the ordinary guard.

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

## The thirtieth day settles the month once (`ticked`, a report, the tick turned to day 1); a
## month-end wound recovery changes personnel, so with wounded men the day fails closed.
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
	assert_string_contains(refused.reason, "personnel")
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
		"think_day": 0, "plunder": 0, "siege_progress": 0}}
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
	assert_eq([closed.candidate.ai_hosts[f.host].mode, closed.candidate.ai_hosts[f.host].siege_days], [EnemyAi.MODE_SIEGE, 1])
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

## B2b2: at a town the crown holds but does not garrison, the same column turns its host to the
## raid in the same slice (5150 - 30k <= 5000: after the 5th move, not the 4th at 5030 m) and is
## NOT stationed: it walks its whole 300 m, and the frozen march keeps it.
func test_host_at_an_undefended_town_raids_and_marches_on() -> void:
	var f := _host_world(80000)
	assert_eq(EnemyAi.garrison_of(f.repo, f.state, f.town), [])
	var manual: GameState = BodyBattle.begin_candidate(f.repo, f.state).candidate
	for slice: int in 4: manual = _next_move_work(f, manual)
	assert_eq([manual.foes[f.foe].x_m, manual.ai_hosts[f.host].mode, _host_events(manual)], [44970, EnemyAi.MODE_ADVANCE, []])
	manual = _next_move_work(f, manual)
	assert_eq([manual.foes[f.foe].x_m, manual.ai_hosts[f.host].mode, manual.foes[f.foe].order], [45000, EnemyAi.MODE_RAID, ArmySystem.ORDER_MARCH])
	var state := _day(f.repo, f.state, "complete")
	if state == null: return
	assert_eq(_hash(state), _hash(BodyDayDriver.tactical_day(f.repo, manual).candidate))
	var today := state.absolute_day()
	assert_eq(state.ai_hosts[f.host].mode, EnemyAi.MODE_RAID)
	assert_eq(_host_events(state), [{"type": "host_mode", "host": f.host, "mode": EnemyAi.MODE_RAID, "why": "reached an undefended target", "day": today}])
	assert_eq([state.foes[f.foe].x_m, state.foes[f.foe].order, state.day_resolution.march_entries[f.foe].order],
		[45150, ArmySystem.ORDER_GARRISON, ArmySystem.ORDER_GARRISON], "arrived at its route's end")
	assert_true(state.ai_hosts[f.host].get("deployment", {}).is_empty())

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
		"think_day": 0, "plunder": 0, "siege_progress": 0, "deployment": {"town": f.town, "started_day": today, "complete": false}}
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

## B2c: the garrisoned crown unit of 100 on the point of a town it holds, a
## treasury, 1000 eligible civilians and a two-day infantry contract at 2 gold a commoner, 10 a noble.
func _recruit_world() -> Dictionary:
	var f := _helper("res://tests/engine/test_body_marches.gd", "_fixture", [[100]])
	var state: GameState = f.state
	var realm: String = f.repo.resolve_realm("player_realm")
	assert_eq(String(state.army_roster[f.code].kingdom_code), realm)
	var towns: Array = f.repo.burgs.keys()
	towns.sort()
	for key: String in towns:
		if ArmyGround.holds(f.repo, state, realm, key) and MapOwnership.owner_of(f.repo, state, String(f.repo.burgs[key].province_code)) == realm:
			f.town = key
			break
	f.province = String(f.repo.burgs[f.town].province_code)
	# The town stands where the pack has it (a new unit camps on real ground), so the open test
	# grid is stretched over the whole map (10 km cells) and the unit stands on the town's point.
	var size := Vector2i(ceili(float(f.repo.map_info.width) / 10.0), ceili(float(f.repo.map_info.height) / 10.0))
	var slopes := PackedByteArray()
	slopes.resize(size.x * size.y)
	MarchPath.use(f.repo, MarchPath.build(f.repo, size.x, size.y, 10000, slopes))
	f.at = ArmyGround.town_point_m(f.repo, f.town)
	var entry: Dictionary = state.regiments[f.code]
	for row: Dictionary in [entry, entry.body_groups[0]]:
		row.x_m = f.at.x
		row.y_m = f.at.y
	entry.order = ArmySystem.ORDER_GARRISON
	entry.dest_x_m = f.at.x
	entry.dest_y_m = f.at.y
	entry.erase("route_m")
	assert_eq(BodyDayDriver._seat_day(f.repo, state, [f.code]), "")
	assert_eq(ArmyGround.garrison_town(f.repo, state, f.code), f.town)
	state.metrics.treasury = 5000
	f.repo.balance.recruitment_eligible_permille = 1000
	state.world[MilitaryPopulation.path(f.province, "rural_population")] = 1000
	for arm: String in ["infantry", MapObjects.regiment_arm(f.repo, state.army_roster[f.code])]: f.repo.recruitment[arm] = {"arm": arm, "commoner_gold": "2", "noble_gold": "10",
		"commander_gold": "0", "equipment_gold_per_element": "0", "build_days": "2", "requires_port": "0"}
	var ids: Array = f.repo.commanders.keys()
	ids.sort()
	f.officers = ids.filter(func(id: String) -> bool:
		return (state.characters[id] as Character).kingdom == realm and MilitaryCommanders.candidate_error(f.repo, state, id) == "" \
			and "infantry" in String(f.repo.commanders[id].unit_kinds).split("|"))
	return f

func _recruit_order(f: Dictionary, mode: String, id: String, total: int, officer: String) -> Dictionary:
	return {"request_id": id, "mode": mode, "arm": "infantry" if mode == "new" else "", "unit_code": f.code if mode == "reinforce" else "",
		"total": total, "source_province": f.province, "source_population_field": "rural_population", "assembly_town": f.town,
		"noble_permille": 0, "commander_id": officer}

func _row_facts(repo: DataRepository, state: GameState, code: String) -> Array:
	return UnitBodies.rows(repo, state, code).map(func(row: Dictionary) -> Array: return [row.slot, row.count])

## B2c: two paid assemblies ordered between days (150 reinforcements for the unit of 100, and a new
## unit of 200) are sealed as ordinary writers: people reserved, no body. Both complete at the
## second day's end, and the close gives them bodies through the placement protocol.
## Hand-computed: neither unit has a commander, so each order is its commoners at 2 gold and one
## noble officer at 10: 149 * 2 + 10 = 308 and 199 * 2 + 10 = 408. Rows hold 100 men: 250 fit is
## [100, 100, 50], the survivor keeping slot 0 and its point, growth taking slots 10 and 11 (the
## counter stood at 10); the new unit's 200 are slots 0 and 1, camped one slot spacing off the town.
func test_recruit_orders_reserve_people_and_completion_places_their_bodies() -> void:
	var f := _recruit_world()
	var repo: DataRepository = f.repo
	var state: GameState = f.state
	var raised := "recruited:raise"
	var before_rows := UnitBodies.rows(repo, state, f.code)
	assert_eq([state.military_rosters[f.code].commander_id, _row_facts(repo, state, f.code), state.regiments[f.code].group_next_slot], ["", [[0, 100]], 10])
	var gold := [308, 408]
	var orders := [_recruit_order(f, "reinforce", "grow", 150, f.officers[0]), _recruit_order(f, "new", "raise", 200, f.officers[1])]
	for i: int in orders.size():
		var sequence := int(state.military_migration.get("body_battle", {}).get("sequence", -1))
		var order := func(r: DataRepository, s: GameState) -> void: assert_eq(RecruitmentSystem.recruit(r, s, orders[i]).get("gold"), gold[i])
		var published := BodyDayDriver.publish(repo, state, {"kind": "recruit", "id": orders[i].request_id}, order)
		assert_eq(published.status, "complete", published.reason)
		if published.candidate == null: return
		state = published.candidate
		assert_eq(int(state.military_migration.body_battle.sequence), sequence + 1, "each order is one outer operation")
	assert_eq(int(state.metrics.treasury), 5000 - 308 - 408)
	assert_eq([MilitaryRoster.fit(state, f.code), MilitaryRoster.fit(state, raised), UnitBodies.rows(repo, state, f.code)], [100, 0, before_rows], "reserved people have no body")
	assert_eq(state.recruitment_projects.grow.cohort_ids.map(func(id: String) -> Array: return [state.military_cohorts[id].stage, state.military_cohorts[id].fit]),
		[["assembling", 149], ["assembling", 1]])
	assert_false(state.regiments.has(raised))
	# People cannot become soldiers but through a completion: a writer that activates them is refused.
	var enlist := func(_r: DataRepository, s: GameState) -> void: s.military_cohorts["recruit:grow:commoners"].stage = "active"
	assert_string_contains(BodyDayDriver.publish(repo, state, {"kind": "enlist"}, enlist).reason, "personnel")
	# Day one: a day's work each, still assembling; the body world carries them through its whole day.
	var first := BodyDayDriver.day(repo, state)
	assert_eq(first.status, "complete", first.reason)
	if first.candidate == null: return
	state = first.candidate
	assert_eq(state.recruitment_projects.values().map(func(p: Dictionary) -> Array: return [p.status, p.worked_days]), [["assembling", 1], ["assembling", 1]])
	assert_eq([_row_facts(repo, state, f.code), state.regiments.has(raised), state.military_migration.has("body_placement")], [[[0, 100]], false, false])
	# The held row now carries its own point as its path; the point itself has not moved.
	assert_eq([before_rows[0].x_m, before_rows[0].y_m], [f.at.x, f.at.y])
	before_rows = UnitBodies.rows(repo, state, f.code)
	assert_eq([before_rows[0].x_m, before_rows[0].y_m], [f.at.x, f.at.y])
	# Day two: both complete in the close, and each gets its bodies as one placement operation.
	var source_hash := _hash(state)
	var second := BodyDayDriver.day(repo, state)
	assert_eq(_hash(state), source_hash, "the driver never touches its source")
	assert_eq(second.status, "complete", second.reason)
	if second.candidate == null: return
	assert_eq(_hash(BodyDayDriver.day(repo, _json(state)).candidate), _hash(second.candidate), "the JSON save drives to the same day")
	var done: GameState = second.candidate
	assert_eq(done.recruitment_projects.values().map(func(p: Dictionary) -> Array: return [p.status, p.completed_day]),
		[["complete", state.absolute_day()], ["complete", state.absolute_day()]])
	assert_eq([MilitaryRoster.fit(done, f.code), _row_facts(repo, done, f.code), done.regiments[f.code].group_next_slot], [250, [[0, 100], [10, 100], [11, 50]], 12])
	assert_eq(UnitBodies.rows(repo, done, f.code)[0], before_rows[0], "the survivor keeps its row")
	assert_eq([done.military_rosters[f.code].commander_id, done.military_rosters[raised].commander_id], [f.officers[0], f.officers[1]])
	assert_eq([MilitaryRoster.fit(done, raised), _row_facts(repo, done, raised), done.regiments[raised].group_next_slot], [200, [[0, 100], [1, 100]], 2])
	var camp := Vector2i(done.regiments[raised].x_m, done.regiments[raised].y_m)
	assert_eq([done.regiments[raised].camp_town, MarchClearance.dist2(camp, f.at)], [f.town, 4400 * 4400], "camped on the town's first ring")
	assert_eq(int(repo.bal("army_slot_spacing_m")), 4400)
	assert_eq([done.military_migration.body_placement.sequence, done.military_migration.body_placement.operation_id], ["1", "placement:recruit:raise:" + raised],
		"two placement operations, in project order")
	assert_eq(UnitBodies.validate_battle_candidate(repo, done, BodyBattle.safe_boundary(done)).status, "complete")
	# The close's guard lets through exactly the recruits: nothing else may gain a body or change.
	var cohorts: Array = done.recruitment_projects.grow.cohort_ids + done.recruitment_projects.raise.cohort_ids
	assert_eq(BodyDayDriver._body_change(state, done, "X", [f.code, raised], cohorts), "")
	assert_string_contains(BodyDayDriver._body_change(state, done, "X"), "X moved, added or removed a body")
	assert_string_contains(BodyDayDriver._body_change(state, done, "X", [f.code, raised]), "X changed personnel")
	var hungry := UnitBodies._copy(done)
	var veteran: String = hungry.military_rosters[f.code].cohort_ids.filter(func(id: String) -> bool: return id not in cohorts and int(hungry.military_cohorts[id].fit) > 0)[0]
	hungry.military_cohorts[veteran].fit -= 1
	assert_string_contains(BodyDayDriver._body_change(state, hungry, "X", [f.code, raised], cohorts), "X changed personnel", "a recruited unit's veterans stay guarded")
	# Day three is admitted and leaves both units' bodies where they stand.
	var third := BodyDayDriver.day(repo, done)
	assert_eq(third.status, "complete", third.reason)
	if third.candidate == null: return
	for code: String in [f.code, raised]: assert_eq(UnitBodies.rows(repo, third.candidate, code), UnitBodies.rows(repo, done, code))
