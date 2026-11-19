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
func test_encounter_blocks_then_resumes_to_the_stepped_day() -> void:
	var path := "res://tests/engine/test_body_battle_motion.gd"
	var f := _helper(path, "_world", [1000])
	var helper: GutTest = load(path).new()
	var stepped: Array = helper.call("_to_ready", f, false)
	var manual: GameState = stepped[4]
	var guard := 0
	while manual.day_resolution.body_battle.stage != "complete" and guard < 200:
		guard += 1
		var step: Dictionary = f.engine.step_body_battle_candidate(manual)
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
	assert_eq(_hash(held), _hash(broken), "nothing changes while the settlement fails")
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
	var saved := BodyDayDriver.day(f.repo, _json(blocked.candidate))
	assert_eq([saved.status, _hash(saved.candidate)], ["blocked", _hash(blocked.candidate)], "a saved blocked day waits")
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
func test_arrival_day_garrisons_where_the_column_stands() -> void:
	for on_point: bool in [false, true]:
		var f := _march_world()
		var town := ""
		if on_point:
			var realm: String = f.state.army_roster[f.code].kingdom_code
			var towns: Array = f.repo.burgs.keys()
			towns.sort()
			for key: String in towns:
				if ArmyGround.holds(f.repo, f.state, realm, key):
					town = key
					break
			assert_ne(town, "", "a held town")
			var px := ArmySystem.metres_to_pack(f.repo, Vector2i(50300, 50000))
			f.repo.burgs[town].x = px.x
			f.repo.burgs[town].y = px.y
			ArmySystem.forget_grids()
		var before := _hash(f.state)
		# The fixture keeps the whole campaign's seats for the units it dropped; a seat whose holder
		# is gone is cleared, as `ArmyGround.reconcile` clears it. No other unit holds one.
		var seats := {}
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
		if on_point:
			seats[town] = f.code
			assert_eq(String(entry.get("camp_town", "")), town, "its camp is the town under its anchor")
		assert_eq(state.town_seat, seats, "a seat goes only to the unit on the town's point")
		assert_eq(UnitBodies.validate_battle_candidate(f.repo, state, BodyBattle.safe_boundary(state)).status, "complete")
		var copy := BodyDayDriver.day(f.repo, _json(f.state))
		assert_eq(_hash(copy.candidate), _hash(state), "the JSON save gives the same day")

## The seat rules, hand-built on one crown unit standing at (50000, 50000), off every town point
## (a garrison whose rows moved in battle): it KEEPS a seat it holds; it loses it on the march
## (`ArmyGround.leave`'s rule) or once its town is lost; a seat whose holder is gone is cleared.
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
