class_name MilitaryRoster
extends RefCounted

## A commander occupies one noble place, never an additional person.
## The caller supplies the recruitment cap from data; survivors are not capped.
static func composition(total: int, noble_permille: int, cap_permille: int) -> Dictionary:
	if total <= 0:
		return {"error": "Personnel total must be positive."}
	if cap_permille <= 0 or cap_permille > 1000:
		return {"error": "Noble cap must be within the whole unit."}
	if noble_permille < 0 or noble_permille > cap_permille:
		return {"error": "Requested noble share exceeds recruitment limits."}
	@warning_ignore("integer_division")
	var nobles := maxi(1, total * noble_permille / 1000)
	if nobles * 1000 > total * cap_permille:
		return {"error": "Unit is too small for a commander within the noble cap."}
	return {"commoners": total - nobles, "noble_troops": nobles - 1, "commander": 1}

## Equipment quantities remain equipment: a ship's crew is not another ship.
static func personnel_capacity(repo: DataRepository, equipment: Dictionary) -> int:
	var total := 0
	var types := repo.world_table("military", "unit_types")
	for code: String in types:
		var row: Dictionary = types[code]
		if not ArmySplit.is_whole_count(equipment.get(code, 0)) or not ArmySplit.is_whole_count(row.get("crew", 0)) or int(row.get("crew", 0)) <= 0:
			return -1
		total += int(equipment.get(code, 0)) * int(row["crew"])
	return total

const Population := preload("res://scripts/engine/military_population.gd")
const Commanders := preload("res://scripts/engine/military_commanders.gd")
const PERSONNEL_STATES: Array[String] = ["fit", "wounded", "captured_current", "dead", "released"]
const TRANSITIONS := {
	"fit": ["wounded", "captured_current", "dead", "released"],
	"wounded": ["fit", "captured_current", "dead", "released"],
	"captured_current": ["dead", "released"],
}

## The caller pays and reserves equipment in the same synchronous order transaction.
## No mutation occurs on a refused enlistment, including a partially valid batch.
static func mobilize(repo: DataRepository, state: GameState, event_id: String, recruits: Array, reason: String) -> Dictionary:
	var normalized := _normalize_rows(recruits, ["id", "unit_code", "source_province", "source_population_field", "identity", "family_name", "stage", "person_id"])
	if normalized.has("error"):
		return normalized
	recruits = normalized["rows"]
	var request := {"kind": "mobilize", "recruits": recruits, "reason": reason}
	var replay := _replay(state, event_id, request, reason)
	if not replay.is_empty():
		return replay
	if recruits.is_empty():
		return {"error": "Enlistment needs people."}
	var additions: Dictionary = {}
	var reserved: Dictionary = {}
	var unit_additions: Dictionary = {}
	var people: Dictionary = {}
	for cohort: Dictionary in state.military_cohorts.values():
		var person := String(cohort.get("person_id", ""))
		if person != "" and int(cohort.get("released", 0)) != 1:
			people[person] = true
	for raw: Dictionary in recruits:
		var id := String(raw.get("id", ""))
		var province := String(raw.get("source_province", ""))
		var field := String(raw.get("source_population_field", ""))
		var code := String(raw.get("unit_code", ""))
		var count := int(raw.get("count", 0))
		var stage := String(raw.get("stage", ""))
		var identity := String(raw.get("identity", ""))
		var person := String(raw.get("person_id", ""))
		if id.is_empty() or code.is_empty() or count <= 0 or additions.has(id) or state.military_cohorts.has(id):
			return {"error": "Enlistment needs a unique cohort, a unit and positive personnel."}
		if not field in Population.FIELDS or not repo.provinces.has(province):
			return {"error": "Enlistment needs a known rural or urban origin."}
		if not stage in ["assembling", "active"] or not identity in ["commoner", "noble"]:
			return {"error": "Enlistment has an invalid stage or identity."}
		if person != "":
			var character: Character = state.characters.get(person) as Character
			if count != 1 or identity != "noble" or character == null or people.has(person):
				return {"error": "A named officer needs one unique noble personnel place."}
			var refusal := Commanders.candidate_error(repo, state, person)
			if refusal != "":
				return {"error": refusal}
			if character.family_name != String(raw["family_name"]) or int(character.attributes.get("health", 0)) <= 0:
				return {"error": "Named personnel must retain their family and be alive."}
			people[person] = true
		var source := Population.path(province, field)
		reserved[source] = int(reserved.get(source, 0)) + count
		if int(reserved[source]) > Population.available(repo, state, province, field):
			return {"error": "Not enough eligible civilians at " + source}
		additions[id] = {"id": id, "unit_code": code, "source_province": province,
			"source_population_field": field, "identity": identity,
			"family_name": String(raw.get("family_name", "")), "stage": stage,
			"initial": count, "fit": count, "wounded": 0, "captured_current": 0,
			"dead": 0, "released": 0}
		if person != "":
			additions[id]["person_id"] = person
	for cohort: Dictionary in additions.values():
		var code := String(cohort.unit_code)
		unit_additions[code] = int(unit_additions.get(code, 0)) + int(cohort.fit)
	for code: String in unit_additions:
		var refusal := capacity_error(repo, state, code, int(unit_additions[code]))
		if refusal != "": return {"error": refusal}
	for id: String in additions:
		var cohort: Dictionary = additions[id]
		state.military_cohorts[id] = cohort
		var code := String(cohort["unit_code"])
		if not state.military_rosters.has(code):
			state.military_rosters[code] = {"commander_id": "", "cohort_ids": []}
		state.military_rosters[code]["cohort_ids"].append(id)
		state.military_rosters[code]["living_cap_men"] = int(repo.bal("army_living_cap_men"))
	return _record(state, event_id, request, {"status": "applied", "cohort_ids": additions.keys()})

## Apply every cohort change and every originating population loss, or none.
## released and dead are terminal: re-enlistment creates a new paid cohort.
static func transition(repo: DataRepository, state: GameState, event_id: String, changes: Array, reason: String) -> Dictionary:
	var normalized := _normalize_rows(changes, ["cohort_id", "from", "to"])
	if normalized.has("error"):
		return normalized
	changes = normalized["rows"]
	var request := {"kind": "transition", "changes": changes, "reason": reason}
	var replay := _replay(state, event_id, request, reason)
	if not replay.is_empty():
		return replay
	return _apply_transition(repo, state, event_id, changes, reason, request)

## Combat, recovery and desertion submit whole-unit counts together. Resolve
## their original sources before any write, including both sides of a battle.
static func transfer_units(repo: DataRepository, state: GameState, event_id: String, orders: Array, reason: String) -> Dictionary:
	var normalized := _normalize_rows(orders, ["unit_code", "from", "to"])
	if normalized.has("error"):
		return normalized
	orders = normalized["rows"]
	var request := {"kind": "transfer_units", "orders": orders, "reason": reason}
	var replay := _replay(state, event_id, request, reason)
	if not replay.is_empty():
		return replay
	var groups: Dictionary = {}
	for order: Dictionary in orders:
		var code := String(order["unit_code"])
		var from := String(order["from"])
		var to := String(order["to"])
		if not state.military_rosters.has(code) or int(order["count"]) <= 0 or not to in TRANSITIONS.get(from, []):
			return {"error": "Invalid unit personnel transfer."}
		if not groups.has(code):
			groups[code] = {}
		if not groups[code].has(from):
			groups[code][from] = {}
		groups[code][from][to] = int(groups[code][from].get(to, 0)) + int(order["count"])
	var changes: Array = []
	var codes := groups.keys()
	codes.sort()
	for code: String in codes:
		var ids: Array = state.military_rosters[code].get("cohort_ids", []).duplicate()
		ids.sort()
		var seen: Dictionary = {}
		for id: String in ids:
			if seen.has(id) or not state.military_cohorts.has(id) or state.military_cohorts[id].get("unit_code", "") != code:
				return {"error": "Unit has an inconsistent personnel roster."}
			seen[id] = true
		var origins: Array = groups[code].keys()
		origins.sort()
		for from: String in origins:
			var weights: Array = []
			var available := 0
			for id: String in ids:
				var cohort: Dictionary = state.military_cohorts[id]
				var count := int(cohort.get(from, 0)) if cohort.get("stage", "") == "active" else 0
				weights.append(count)
				available += count
			var destinations: Array = groups[code][from].keys()
			destinations.sort()
			var total := 0
			for to: String in destinations:
				total += int(groups[code][from][to])
			if total > available:
				return {"error": "Not enough personnel in " + code + ":" + from}
			# Apportion the combined loss first, then split its destinations.
			# This prevents independent wound/death rounding claiming one head twice.
			var remaining := BattleSystem.apportion(weights, total)
			for to: String in destinations:
				var shares := BattleSystem.apportion(remaining, int(groups[code][from][to]))
				for i: int in ids.size():
					var count := int(shares[i])
					if count > 0:
						changes.append({"cohort_id": ids[i], "from": from, "to": to, "count": count})
						remaining[i] = int(remaining[i]) - count
	return _apply_transition(repo, state, event_id, changes, reason, request)

static func _apply_transition(repo: DataRepository, state: GameState, event_id: String, changes: Array, reason: String, request: Dictionary) -> Dictionary:
	if changes.is_empty():
		return {"error": "A personnel transition needs changes."}
	var updated: Dictionary = {}
	var consumed: Dictionary = {}
	var deaths: Dictionary = {}
	for change: Dictionary in changes:
		var id := String(change.get("cohort_id", ""))
		var from := String(change.get("from", ""))
		var to := String(change.get("to", ""))
		var count := int(change.get("count", 0))
		if not state.military_cohorts.has(id) or count <= 0 or not to in TRANSITIONS.get(from, []):
			return {"error": "Invalid personnel transition."}
		var original: Dictionary = state.military_cohorts[id]
		var code := String(original.get("unit_code", ""))
		if original.get("id", "") != id or not id in state.military_rosters.get(code, {}).get("cohort_ids", []):
			return {"error": "Original cohort has an inconsistent roster reference."}
		var integrity := cohort_error(repo, original)
		if not integrity.is_empty():
			return {"error": integrity}
		var source_key := id + ":" + from
		consumed[source_key] = int(consumed.get(source_key, 0)) + count
		if not updated.has(id):
			updated[id] = original.duplicate(true)
		var cohort: Dictionary = updated[id]
		if int(original.get(from, 0)) < int(consumed[source_key]):
			return {"error": "Not enough personnel in " + id + ":" + from}
		cohort[from] = int(cohort[from]) - count
		cohort[to] = int(cohort[to]) + count
		if to == "dead":
			var source := Population.path(String(cohort["source_province"]), String(cohort["source_population_field"]))
			deaths[source] = int(deaths.get(source, 0)) + count
	# Preflight the exact ledger writes: never accept clamping a death away.
	var sources := deaths.keys()
	sources.sort()
	for source: String in sources:
		var current: Variant = WorldLedger.value_of(repo, state, source)
		var schema := WorldLedger.schema_for(repo, source)
		if current == null or String(schema.get("type", "")) != "int":
			return {"error": "No population ledger for " + source}
		var target := int(current) - int(deaths[source])
		if target < int(schema.get("min", 0)) or target > int(schema.get("max", 0)):
			return {"error": "Population cannot account for these deaths at " + source}
		var parts := source.split(".")
		var occupied_after := Population.occupied(state, parts[2], parts[3])
		for id: String in updated:
			var after: Dictionary = updated[id]
			if String(after["source_province"]) != parts[2] or String(after["source_population_field"]) != parts[3]:
				continue
			var before: Dictionary = state.military_cohorts[id]
			for status: String in ["fit", "wounded", "captured_current"]:
				occupied_after += int(after[status]) - int(before[status])
		if target < occupied_after:
			return {"error": "Origin population conflicts with surviving reserved personnel at " + source}
	for id: String in updated:
		state.military_cohorts[id] = updated[id]
	Commanders.clear_unfit(state, reason)
	var lines: Array = []
	for source: String in sources:
		var line := WorldLedger.apply(repo, state, source, -int(deaths[source]), reason, event_id)
		line["delta"] = int(line["delta"])
		line["value"] = int(line["value"])
		lines.append(line)
	return _record(state, event_id, request, {"status": "applied", "population": lines, "changes": changes.duplicate(true)})

static func assign_commander(repo: DataRepository, state: GameState, code: String, character_id: String, reason: String) -> Dictionary:
	return Commanders.assign(repo, state, code, character_id, reason)

## Complete a paid assembly without creating people or reversing casualties.
static func activate(state: GameState, event_id: String, ids: Array, reason: String, repo: DataRepository = null) -> Dictionary:
	var request := {"kind": "activate", "cohort_ids": ids.duplicate(), "reason": reason}
	var replay := _replay(state, event_id, request, reason)
	if not replay.is_empty():
		return replay
	if ids.is_empty():
		return {"error": "Activation needs assembling personnel."}
	var seen: Dictionary = {}
	for id: Variant in ids:
		if not id is String or seen.has(id) or not state.military_cohorts.has(id) \
				or state.military_cohorts[id].get("stage", "") != "assembling":
			return {"error": "Activation needs unique assembling cohorts."}
		seen[id] = true
	for id: String in ids:
		var code := String(state.military_cohorts[id].unit_code)
		var cap := int(repo.bal("army_living_cap_men")) if repo != null else int(state.military_rosters.get(code, {}).get("living_cap_men", 0))
		if cap <= 0 or assigned_living(state, code) > cap:
			return {"error": "Activation requires reconciled assigned living personnel within its cap."}
	for id: String in ids:
		state.military_cohorts[id]["stage"] = "active"
	return _record(state, event_id, request, {"status": "active", "cohort_ids": ids.duplicate()})

## Active and paid assembling people share one reservation budget; custody does not.
static func assigned_living(state: GameState, code: String) -> int:
	var total := 0
	for id: String in state.military_rosters.get(code, {}).get("cohort_ids", []):
		var cohort: Dictionary = state.military_cohorts[id]
		if cohort.get("stage", "") in ["active", "assembling"]:
			total += int(cohort.get("fit", 0)) + int(cohort.get("wounded", 0))
	return total

static func capacity_error(repo: DataRepository, state: GameState, code: String, added := 0) -> String:
	var cap := int(repo.bal("army_living_cap_men"))
	if cap <= 0: return "Living personnel capacity must be positive."
	var remaining := maxi(0, cap - assigned_living(state, code))
	if added > remaining or assigned_living(state, code) > cap:
		return "Unit limit is %d fit plus wounded including assembling personnel; %d places remain." % [cap, remaining]
	return ""

## Captives and released civilians never remain in their original fighting unit.
static func living(state: GameState, code: String) -> int:
	return _count(state, code, true)

static func fit(state: GameState, code: String) -> int:
	return _count(state, code, false)

static func _count(state: GameState, code: String, include_wounded: bool) -> int:
	var total := 0
	for id: String in state.military_rosters.get(code, {}).get("cohort_ids", []):
		var cohort: Dictionary = state.military_cohorts[id]
		if String(cohort["stage"]) != "active":
			continue
		total += int(cohort["fit"])
		if include_wounded:
			total += int(cohort["wounded"])
	return total

static func _replay(state: GameState, event_id: String, request: Dictionary, reason: String) -> Dictionary:
	if event_id.strip_edges().is_empty() or reason.strip_edges().is_empty():
		return {"error": "Personnel changes need an event ID and a reason."}
	if not state.military_events.has(event_id):
		return {}
	var previous: Variant = state.military_events[event_id]
	if not previous is Dictionary or not previous.get("request", null) is Dictionary or not previous.get("result", null) is Dictionary:
		return {"error": "Saved personnel receipt is malformed."}
	if previous["request"] != request:
		return {"error": "Personnel event ID was already used for a different request."}
	return (previous["result"] as Dictionary).duplicate(true)

static func _record(state: GameState, event_id: String, request: Dictionary, result: Dictionary) -> Dictionary:
	state.military_events[event_id] = {"request": request.duplicate(true), "result": result.duplicate(true)}
	return result

## Keep only validated request fields; UI metadata never becomes save state.
static func _normalize_rows(rows: Array, string_fields: Array[String]) -> Dictionary:
	var normalized: Array = []
	for raw: Variant in rows:
		if not raw is Dictionary:
			return {"error": "Personnel entries must be records."}
		var count: Variant = raw.get("count", 0)
		if not (count is int or count is float):
			return {"error": "Personnel count must be a whole number."}
		if count is float and (not is_finite(count) or count != floor(count)):
			return {"error": "Personnel count must be a whole number."}
		var row := {"count": int(count)}
		for field: String in string_fields:
			var value: Variant = raw.get(field, "")
			if not value is String:
				return {"error": "Personnel field must be text: " + field}
			row[field] = value
		normalized.append(row)
	return {"rows": normalized}

## Validate original balances before any source is consumed by an atomic batch.
static func cohort_error(repo: DataRepository, cohort: Dictionary) -> String:
	if not repo.provinces.has(String(cohort.get("source_province", ""))) \
			or not String(cohort.get("source_population_field", "")) in Population.FIELDS \
			or not String(cohort.get("identity", "")) in ["commoner", "noble"] \
			or not String(cohort.get("stage", "")) in ["active", "assembling"]:
		return "Invalid personnel identity or origin."
	var total := 0
	for status: String in PERSONNEL_STATES:
		if not ArmySplit.is_whole_count(cohort.get(status, -1)):
			return "Invalid original personnel count."
		total += int(cohort[status])
	if not ArmySplit.is_whole_count(cohort.get("initial", -1)) or total != int(cohort["initial"]):
		return "Original personnel does not conserve people."
	return ""
