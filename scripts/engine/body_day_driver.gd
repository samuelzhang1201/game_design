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
