class_name MilitaryCommanders
extends RefCounted
## A named officer has a one-person noble cohort. Appointment references it;
## changing the appointment never creates, transfers or revives personnel.

static func eligible_for_unit(repo: DataRepository, state: GameState, code: String, person: String) -> bool:
	return not _eligibility(repo, state, code, person).has("error")

static func assign(repo: DataRepository, state: GameState, code: String, person: String, reason: String) -> Dictionary:
	if reason.strip_edges().is_empty():
		return {"error": "An appointment needs a reason."}
	var eligibility := _eligibility(repo, state, code, person)
	if eligibility.has("error"):
		return eligibility
	var roster: Dictionary = state.military_rosters[code]
	var cohort_id := String(eligibility["cohort_id"])
	if roster.get("commander_id", "") == person and roster.get("commander_cohort_id", "") == cohort_id:
		return {"status": "unchanged", "commander_id": person}
	_record(state, roster, person, cohort_id, reason)
	return {"status": "appointed", "commander_id": person}

static func _eligibility(repo: DataRepository, state: GameState, code: String, person: String) -> Dictionary:
	var unit := ArmySystem.regiment(repo, code, state)
	var character: Character = state.characters.get(person) as Character
	var definition: Dictionary = repo.commanders.get(person, {})
	if unit.is_empty() or not state.military_rosters.has(code) or character == null:
		return {"error": "Appointment needs an existing unit and person."}
	var refusal := candidate_error(repo, state, person)
	if refusal != "":
		return {"error": refusal}
	var realm := String(unit.get("kingdom_code", ""))
	if character.kingdom != realm or repo.resolve_realm(String(definition.get("realm_slot", ""))) != realm:
		return {"error": "Commander and unit must belong to the same realm."}
	if not MapObjects.regiment_arm(repo, unit) in String(definition.get("unit_kinds", "")).split("|"):
		return {"error": "This commander is not qualified for the unit's arm."}
	for other: String in state.military_rosters:
		if other != code and state.military_rosters[other].get("commander_id", "") == person:
			return {"error": "This person already commands another unit."}
	var roster: Dictionary = state.military_rosters[code]
	var cohort_id := ""
	for id: String in roster.get("cohort_ids", []):
		var cohort: Dictionary = state.military_cohorts.get(id, {})
		if cohort.get("person_id", "") == person and cohort.get("unit_code", "") == code \
				and cohort.get("identity", "") == "noble" and cohort.get("stage", "") == "active" \
				and int(cohort.get("initial", 0)) == 1 and int(cohort.get("fit", 0)) == 1:
			cohort_id = id
			break
	if cohort_id.is_empty():
		return {"error": "Commander must be a fit, enlisted noble in this unit."}
	return {"cohort_id": cohort_id}

## Recruitment and appointment share the same eligibility gate. In particular,
## the king must never enter a cohort that ordinary surrender can capture.
static func candidate_error(repo: DataRepository, state: GameState, person: String) -> String:
	var character: Character = state.characters.get(person) as Character
	var definition: Dictionary = repo.commanders.get(person, {})
	if character == null or definition.get("eligible", "0") != "1":
		return "This person is not an eligible noble commander."
	if character.category == "player" or character.family_name.is_empty():
		return "This person cannot enlist as military personnel."
	if character.kingdom != repo.resolve_realm(String(definition.get("realm_slot", ""))):
		return "Commander eligibility belongs to another realm."
	if person in state.council.values() or not character.seat.is_empty() or int(character.attributes.get("health", 0)) <= 0:
		return "This person has a conflicting office or cannot serve."
	return MilitaryPopulation.service_refusal(state, person)

## A casualty cannot remain in command. Recovery or release never silently
## restores the appointment; selection is a separate legal decision.
static func clear_unfit(state: GameState, reason: String) -> void:
	var codes := state.military_rosters.keys()
	codes.sort()
	for code: String in codes:
		var roster: Dictionary = state.military_rosters[code]
		var person := String(roster.get("commander_id", ""))
		if person.is_empty():
			continue
		var cohort: Dictionary = state.military_cohorts.get(roster.get("commander_cohort_id", ""), {})
		if int(cohort.get("fit", 0)) != 1 or cohort.get("stage", "") != "active":
			_record(state, roster, "", "", reason)

static func _record(state: GameState, roster: Dictionary, person: String, cohort_id: String, reason: String) -> void:
	if not roster.has("appointments"):
		roster["appointments"] = []
	roster["appointments"].append({"day": state.absolute_day(),
		"from": String(roster.get("commander_id", "")), "to": person, "reason": reason})
	roster["commander_id"] = person
	roster["commander_cohort_id"] = cohort_id
