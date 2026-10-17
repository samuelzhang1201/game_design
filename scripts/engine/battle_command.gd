class_name BattleCommand
extends RefCounted
## Commanders name people already counted in the personnel ledger.

static func available(state: GameState, id: String) -> bool:
	if not state.characters.has(id):
		return false
	var person: Character = state.characters[id]
	if person.category == "player" or person.traits.has("crowned_head") or int(person.attributes.get("health", 1)) <= 0:
		return false
	for flag: String in ["dead", "captured", "unavailable", "wounded"]:
		if person.flags.has(flag):
			return false
	for cohort: Dictionary in state.military_cohorts.values():
		if String(cohort.get("person_id", "")) == id and int(cohort.get("released", 0)) == 0 and int(cohort.get("fit", 0)) != 1:
			return false
	return true

static func select(state: GameState, ids: Array[String], nominee: String) -> String:
	if nominee != "":
		return nominee if ids.has(nominee) and available(state, nominee) else ""
	var candidates: Array[String] = []
	for id: String in ids:
		if available(state, id):
			candidates.append(id)
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var left: Character = state.characters[a]
		var right: Character = state.characters[b]
		var lm := int(left.skills.get("sk_martial", 0))
		var rm := int(right.skills.get("sk_martial", 0))
		if lm != rm:
			return lm > rm
		var lp := int(left.attributes.get("prestige", 0))
		var rp := int(right.attributes.get("prestige", 0))
		return lp > rp if lp != rp else a < b)
	return "" if candidates.is_empty() else candidates[0]

static func retain_or_select(state: GameState, ids: Array[String], incumbent: String) -> String:
	return incumbent if ids.has(incumbent) and available(state, incumbent) else select(state, ids, "")

static func eligible_for_unit(repo: DataRepository, state: GameState, code: String, id: String) -> bool:
	if not state.characters.has(id) or not repo.commanders.has(id):
		return false
	var definition: Dictionary = repo.commanders[id]
	var unit: Dictionary = ArmySystem.regiment(repo, code, state)
	if unit.is_empty() or int(definition.get("eligible", 0)) != 1:
		return false
	var person: Character = state.characters[id]
	if person.kingdom != String(unit.get("kingdom_code", "")) or person.kingdom != repo.resolve_realm(String(definition.get("realm_slot", ""))):
		return false
	var kind := "fleet" if String(unit.get("is_naval", "0")) == "1" else MapObjects.regiment_arm(repo, unit)
	if not String(definition.get("unit_kinds", "")).split("|").has(kind):
		return false
	for other: String in state.military_rosters:
		if other != code and String(state.military_rosters[other].get("commander_id", "")) == id:
			return false
	if not available(state, id):
		return false
	for cohort: Dictionary in state.military_cohorts.values():
		if String(cohort.get("person_id", "")) == id and int(cohort.get("released", 0)) == 0 and String(cohort.get("unit_code", "")) != code:
			return false
	return true

static func assign_unit(repo: DataRepository, state: GameState, code: String, character_id: String, reason: String) -> Dictionary:
	if reason.strip_edges().is_empty() or not state.military_rosters.has(code) or not eligible_for_unit(repo, state, code, character_id):
		return {"error": "Commander is unavailable, ineligible or already assigned; an appointment needs a reason"}
	var roster: Dictionary = state.military_rosters[code]
	if String(roster.get("commander_id", "")) == character_id:
		return {"commander_id": character_id}
	var person: Character = state.characters[character_id]
	var source_id := ""
	var named_id := ""
	for id: String in roster.get("cohort_ids", []):
		var cohort: Dictionary = state.military_cohorts[id]
		if String(cohort.get("identity", "")) != "noble" or int(cohort.get("fit", 0)) <= 0:
			continue
		if String(cohort.get("person_id", "")) == character_id:
			named_id = id
			break
		if String(cohort.get("person_id", "")) == "" and String(cohort.get("family_name", "")) in ["", person.family_name] and source_id == "":
			source_id = id
	if named_id == "" and source_id == "":
		return {"error": "No fit noble of the commander's family is counted in this unit"}
	if named_id == "":
		named_id = MilitaryRoster.bind_person(state, code, character_id, source_id, reason)
		if named_id == "":
			return {"error": "Commander personnel binding was refused"}
	var appointment := {"day": state.absolute_day(), "commander_id": character_id, "previous_id": String(roster.get("commander_id", "")), "cohort_id": named_id, "reason": reason}
	roster["commander_id"] = character_id
	if not roster.has("appointments"):
		roster["appointments"] = []
	roster["appointments"].append(appointment)
	return {"commander_id": character_id, "cohort_id": named_id}

## Stable reserve order, preserving valid appointments. Return every refusal.
static func ensure_assignments(repo: DataRepository, state: GameState, reason: String) -> Array:
	if reason.strip_edges().is_empty():
		return [{"reason": "Military appointments need a reason"}]
	var errors: Array = []
	var authored := CharacterFactory.build_roster(repo)
	for id: String in authored:
		if not state.characters.has(id):
			state.characters[id] = authored[id]
	var candidates: Array = repo.commanders.keys()
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var left := int(repo.commanders[a].get("reserve_priority", 0))
		var right := int(repo.commanders[b].get("reserve_priority", 0))
		return left < right if left != right else a < b)
	var codes: Array = state.military_rosters.keys()
	codes.sort()
	for code: String in codes:
		var unit: Dictionary = ArmySystem.regiment(repo, code, state)
		if String(unit.get("kingdom_code", "")) not in [repo.resolve_realm("player_realm"), repo.resolve_realm("raider_realm")]:
			continue
		var roster: Dictionary = state.military_rosters[code]
		var incumbent := String(roster.get("commander_id", ""))
		if incumbent != "" and eligible_for_unit(repo, state, code, incumbent):
			continue
		if incumbent != "":
			roster["commander_id"] = ""
			roster.get("appointments", []).append({"day": state.absolute_day(), "commander_id": "", "previous_id": incumbent, "reason": reason})
		var assigned := false
		for id: String in candidates:
			if eligible_for_unit(repo, state, code, id):
				var result := assign_unit(repo, state, code, id, reason)
				if not result.has("error"):
					assigned = true
					break
		if not assigned:
			errors.append({"code": code, "reason": "No eligible commander with a fit noble place"})
	return errors

## Ordinary reinforcements cannot displace a valid battlefield commander.
static func update_battle(repo: DataRepository, state: GameState, battle: Dictionary) -> Dictionary:
	var selected: Dictionary = battle.get("commanders", {}).duplicate()
	for side: String in ["att", "def"]:
		var ids: Array[String] = []
		for code: String in battle.get(side, []):
			var id := String(state.military_rosters.get(code, {}).get("commander_id", ""))
			if id != "" and eligible_for_unit(repo, state, code, id):
				ids.append(id)
		var nominee := String(battle.get("commander_nominees", {}).get(side, ""))
		var id := select(state, ids, nominee) if nominee != "" else retain_or_select(state, ids, String(selected.get(side, "")))
		if nominee != "" and id == "":
			return {"error": "The nominated battlefield commander is unavailable or absent"}
		selected[side] = id
	battle["commanders"] = selected
	return selected
