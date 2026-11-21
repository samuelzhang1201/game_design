extends GutTest
## ACT-DRIVER part A: one admission for every writer (ACT-LOAD's preparation seam), the day's
## tactical part driven to one detached candidate, exact resume and an untouched source. The whole days
## are test_body_day_driver_days.gd (together the suite filled a CI runner's per-phase deadline).

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
