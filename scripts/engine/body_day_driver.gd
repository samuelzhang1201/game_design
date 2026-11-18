class_name BodyDayDriver
extends RefCounted
## ACT-DRIVER (part A): the inactive production driver of an admitted body world. Every writer
## (campaign creation, load, the day's march, withdrawal and lifecycle edges) shares one admission
## and ends in ONE detached candidate; the source is never touched, so the caller publishes by
## assigning that candidate. Nothing in ordinary dispatch calls it until ACT-CUTOVER.

## The one admission. `prepare(repo, detached_copy) -> {status, reason, candidate}` is the seam
## ACT-LOAD plugs into (fresh-campaign initialization, legacy save classification); without it
## only an already admitted current body world passes, and anything else fails closed.
## A frozen body day (resumable, a published round included) is admitted as it stands; an
## ordinary frozen day is not.
static func admit(repo: DataRepository, source: GameState, prepare: Callable = Callable()) -> Dictionary:
	if repo == null or source == null: return _result("error", "Admission requires data and source")
	var state := UnitBodies._copy(source)
	if prepare.is_valid():
		var prepared: Variant = prepare.call(repo, state)
		if not prepared is Dictionary or prepared.get("status") != "complete" or not prepared.get("candidate") is GameState:
			return _result("error", "Admission preparation refused: " + str(prepared.get("reason", "") if prepared is Dictionary else ""))
		state = prepared.candidate
	if not state.military_migration.has("body_version"): return _result("error", "Not an admitted body world")
	var frozen: bool = state.day_resolution.get("body_battle") is Dictionary
	var raw := UnitBodies._battle_raw_error(state)
	if not raw.is_empty(): return _result("error", raw)
	if not state.day_resolution.is_empty() and not frozen: return _result("error", "An ordinary frozen day cannot enter the body driver")
	var boundary := BodyBattleMotion._boundary(state) if frozen else BodyBattle.safe_boundary(state)
	var checked := UnitBodies.validate_battle_candidate(repo, state, boundary)
	var round_frozen: bool = frozen and checked.status == "deferred" and checked.reason == BodyBattle.FROZEN_ROUND
	if checked.status != "complete" and not round_frozen: return _result("error", checked.reason)
	if BodyBattleMotion._context(repo, state).is_empty(): return _result("error", "Unsupported locomotion policy or terrain")
	return _result("complete", "Admitted body world", state)

## The day's tactical part from the safe boundary (begin) or from a saved frozen body day,
## one `BodyBattle` control transition at a time (march and withdrawal on the ordinary budgets
## `begin` freezes; lifecycle edges through `BodyLifecycle`), until the candidate day completes
## or waits: for the player's decision, or on a transition that changes nothing (a failed round
## settlement stays on its frozen pending). Either way the result carries the one candidate to
## publish; an error carries none. Resuming the published candidate continues exactly.
static func tactical_day(repo: DataRepository, source: GameState) -> Dictionary:
	var admitted := admit(repo, source)
	if admitted.status != "complete": return admitted
	var state: GameState = admitted.candidate
	if state.day_resolution.is_empty():
		var begun := BodyBattle.begin_candidate(repo, state)
		if begun.status != "complete": return _result("error", begun.reason)
		state = begun.candidate
	# ponytail: a step ceiling per slice of move, contact, three per field (ready, plan, settle),
	# one exit per unit and advance; fields never outnumber land units.
	var limit := int(state.day_resolution.body_battle.substep_count) * (3 + 4 * state.army_roster.size())
	for i: int in limit + 1:
		if state.day_resolution.body_battle.stage == "complete": return _result("complete", "Candidate tactical day complete", state)
		if not state.day_resolution.get("pending_decision", {}).is_empty():
			return _result("blocked", "Encounter awaits the player's decision", state)
		var stepped := BodyBattle.step_candidate(repo, state)
		if stepped.status not in ["complete", "blocked"] or stepped.candidate == null:
			return _result("error", "%s step: %s" % [state.day_resolution.body_battle.stage, stepped.reason])
		# A transition that changes nothing waits (a failed settlement stays on its frozen pending).
		if stepped.status == "blocked" and BodyMotion._hash(stepped.candidate.to_dict()) == BodyMotion._hash(state.to_dict()):
			return _result("blocked", stepped.reason, stepped.candidate)
		state = stepped.candidate
	return _result("error", "Candidate tactical day did not settle within its step ceiling")

## The ordinary phases around the tactical part (`DayResolution.PHASES`): run on the frozen day.
const _OPENING: Array[String] = ["WORKS", "COURIERS", "AI_AND_SCOUT", "SIGHTING_AND_INTEL_REFRESH"]

## The whole production day of an admitted body world, the ordinary clock, supply and budgets.
## From the safe boundary it opens (the prisoner steps, reconciliation and task travel of the
## ordinary day's start, sealed; `begin` freezes the march budgets; then works, couriers, the
## enemy and sighting on the frozen day), drives the tactical part (`tactical_day`), and closes
## (sieges to the calendar, supply eaten once, the day turned, sealed at the next safe boundary).
## Works run after the march setup, which they never read. A result carries one detached
## candidate (`blocked` mid-day resumes exactly) plus, once complete, `journal`, `ticked` and
## `report` as `TickEngine.resolve_day` gives them. An ordinary phase that moves a body or
## changes personnel fails closed: its body writer is not here yet.
static func day(repo: DataRepository, source: GameState) -> Dictionary:
	var admitted := admit(repo, source)
	if admitted.status != "complete": return admitted
	var state: GameState = admitted.candidate
	var engine := TickEngine.new(repo)
	if state.day_resolution.is_empty():
		var opened := _open(repo, engine, state)
		if opened.status != "complete": return opened
		state = opened.candidate
	if state.day_resolution.body_battle.stage != "complete":
		var tactical := tactical_day(repo, state)
		if tactical.status != "complete": return tactical
		state = tactical.candidate
	return _close(repo, engine, state)

## An ordinary writer at the safe boundary between days (an order, a decree): `writer(repo,
## state)` runs on a detached copy, may move no body and change no personnel, and is sealed as
## the next outer operation (`request`, unique per act, e.g. with its order id, is its receipt;
## the same request again is an "Already published" no-op), so the next day's admission holds.
## No publisher leaves the previous result digest on a changed save.
static func publish(repo: DataRepository, source: GameState, request: Dictionary, writer: Callable) -> Dictionary:
	var admitted := admit(repo, source)
	if admitted.status != "complete": return admitted
	if not admitted.candidate.day_resolution.is_empty(): return _result("error", "A writer publishes only at a safe boundary")
	var state: GameState = admitted.candidate
	if state.military_migration.get("body_battle", {}).get("receipt") == BodyMotion._hash(request):
		return _result("complete", "Already published", state)
	writer.call(repo, state)
	return _sealed(repo, source, state, request, "Writer " + str(request.get("kind", "")))

static func _open(repo: DataRepository, engine: TickEngine, source: GameState) -> Dictionary:
	var state := UnitBodies._copy(source)
	for step: Dictionary in [PrisonerSystem.migrate_legacy(repo, state), PrisonerSystem.settle_unguarded(repo, state),
			MilitaryReorganization.reconcile(repo, state)]:
		if step.has("error") or step.get("status") == "error": return _result("error", str(step.get("error", "Day opening refused")))
	ArmySystem.ensure(repo, state)
	BattleTaskSystem.track_day(repo, state)
	ArmyTasks.step_day(repo, state)
	var opened := _sealed(repo, source, state, {"kind": "open", "abs_day": str(state.absolute_day())}, "Day opening")
	if opened.status != "complete": return opened
	var begun := BodyBattle.begin_candidate(repo, opened.candidate)
	if begun.status != "complete": return _result("error", begun.reason)
	state = begun.candidate
	var tx := state.day_resolution
	tx.journal.missive_start = state.next_missive_id
	for phase: String in _OPENING:
		var failed := _phase(engine, state, tx, phase)
		if not failed.is_empty(): return _result("error", failed)
	var moved := _body_change(begun.candidate, state, "The day's opening phases")
	if not moved.is_empty(): return _result("error", moved)
	BodyBattle._seal_private(repo, state)
	var checked := UnitBodies.validate_battle_candidate(repo, state, BodyBattleMotion._boundary(state))
	if checked.status != "complete": return _result("error", checked.reason)
	return _result("complete", "Opened the body day", state)

static func _close(repo: DataRepository, engine: TickEngine, source: GameState) -> Dictionary:
	var state := UnitBodies._copy(source)
	var tx := state.day_resolution
	# The ordinary tactical phase's day-end work: seats and laws reconciled, delivered stances settled.
	ArmyGround.reconcile(repo, state)
	LawSystem.reconcile(repo, state)
	BattleSystem.finish_day(repo, state)
	for cursor: int in range(DayResolution.PHASES.find("FIXED_TACTICAL_SUBSTEPS") + 1, DayResolution.PHASES.size()):
		var failed := _phase(engine, state, tx, DayResolution.PHASES[cursor])
		if not failed.is_empty(): return _result("error", failed)
	state.day_resolution = {}
	var organization := MilitaryReorganization.reconcile(repo, state)
	if organization.get("status", "error") == "error": return _result("error", str(organization.get("error", "Cannot reconcile military organization")))
	var closed := _sealed(repo, source, state, {"kind": "close", "abs_day": str(tx.absolute_day)}, "The day's closing phases")
	if closed.status != "complete": return closed
	closed.merge({"journal": tx.journal.duplicate(true), "ended": int(tx.absolute_day), "ticked": bool(tx.month_end),
		"report": engine.last_month_report})
	return closed

## One ordinary phase on the frozen day, its outputs restored as `resolve_day` does. "" or the error.
static func _phase(engine: TickEngine, state: GameState, tx: Dictionary, phase: String) -> String:
	engine._restore_day_outputs(tx)
	var outcome := engine._resolve_phase(state, tx, phase)
	engine._restore_day_outputs(tx)
	return "%s: %s" % [phase, outcome.get("error", "")] if outcome.get("status", "") == "error" else ""

## Seals `state` (a safe boundary) as the next outer operation after `before`, once it is shown
## to have moved no body and changed no personnel, and validates it at its new safe boundary.
static func _sealed(repo: DataRepository, before: GameState, state: GameState, request: Dictionary, what: String) -> Dictionary:
	var moved := _body_change(before, state, what)
	if not moved.is_empty(): return _result("error", moved)
	var outer: Dictionary = state.military_migration.get("body_battle", {})
	state.military_migration.body_battle = {"version": "1", "sequence": BodyBattle.safe_boundary(state).sequence,
		"receipt": BodyMotion._hash(request), "result": "", "closed_motion": outer.get("closed_motion", {}).duplicate(true)}
	BodyBattle._seal_private(repo, state)
	var checked := UnitBodies.validate_battle_candidate(repo, state, BodyBattle.safe_boundary(state))
	if checked.status != "complete": return _result("error", checked.reason)
	return _result("complete", "Sealed " + what.to_lower(), state)

## "" when every land unit's bodies, owners, anchors and position and all personnel are as they were.
# ponytail: any cohort or roster change fails closed (fleets too); narrow to land units when a fleet writer needs it.
static func _body_change(before: GameState, after: GameState, what: String) -> String:
	if BodyMotion._hash([BodyLifecycle.snapshot(before), _positions(before)]) != BodyMotion._hash([BodyLifecycle.snapshot(after), _positions(after)]):
		return what + " moved, added or removed a body; its body writer is not installed"
	if BodyMotion._hash([before.military_cohorts, before.military_rosters]) != BodyMotion._hash([after.military_cohorts, after.military_rosters]):
		return what + " changed personnel; its body loss writer is not installed"
	return ""

static func _positions(state: GameState) -> Dictionary:
	var out := {}
	for code: String in state.regiments.keys() + state.foes.keys():
		if not UnitBodies._naval(state, code): out[code] = [UnitBodies._entry(state, code).get("x_m"), UnitBodies._entry(state, code).get("y_m")]
	return out

## The player's answer to the pending encounter decision of a frozen body day.
static func acknowledge(repo: DataRepository, source: GameState, token: String, choice: String) -> Dictionary:
	var admitted := admit(repo, source)
	if admitted.status != "complete": return admitted
	if not admitted.candidate.day_resolution.get("body_battle") is Dictionary: return _result("error", "No frozen body day to acknowledge")
	var done := BodyBattle._run(repo, admitted.candidate, {"kind": "acknowledge", "token": token, "choice": choice})
	if done.status != "complete" or done.candidate == null: return _result("error", done.reason)
	return _result("complete", done.reason, done.candidate)

static func _result(status: String, reason: String, candidate: GameState = null) -> Dictionary:
	return {"status": status, "reason": reason, "candidate": candidate}
