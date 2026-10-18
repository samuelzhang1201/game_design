class_name MilitaryRoster
extends RefCounted
## One exclusive personnel ledger. Equipment and source population stay separate.

const STATES: Array[String] = ["fit", "wounded", "captured_current", "dead", "released"]
const ACTIVE: Array[String] = ["fit", "wounded", "captured_current"]

static func composition(total: int, noble_permille: int, cap_permille: int) -> Dictionary:
	if total <= 0 or noble_permille < 0 or noble_permille > cap_permille or cap_permille < 0 or cap_permille > 1000:
		return {"error": "invalid personnel composition"}
	@warning_ignore("integer_division")
	var nobles := maxi(1, total * noble_permille / 1000)
	if nobles > total or nobles * 1000 > total * cap_permille:
		return {"error": "commander exceeds noble proportion cap"}
	return {"commoners": total - nobles, "noble_troops": nobles - 1, "commander": 1}

static func count(state: GameState, code: String, field: String) -> int:
	var total := 0
	var roster: Dictionary = state.military_rosters.get(code, {})
	for id: String in roster.get("cohort_ids", []):
		total += int(state.military_cohorts.get(id, {}).get(field, 0))
	return total

static func living(state: GameState, code: String) -> int:
	return fit(state, code) + count(state, code, "wounded") + count(state, code, "captured_current")

static func fit(state: GameState, code: String) -> int:
	return count(state, code, "fit")

## Invalid crew/count data is a data error (negative capacity), never one person per ship.
static func personnel_capacity(repo: DataRepository, equipment: Dictionary) -> int:
	var total := 0
	var types := repo.world_table("military", "unit_types")
	for arm: String in types:
		var raw: Variant = equipment.get(arm, 0)
		var crew_raw := String(types[arm].get("crew", ""))
		if not crew_raw.is_valid_int() or int(crew_raw) <= 0 or not _whole(raw):
			return -1
		total += int(raw) * int(crew_raw)
	return total

static func assign_commander(repo: DataRepository, state: GameState, code: String, character_id: String, reason: String) -> Dictionary:
	return BattleCommand.assign_unit(repo, state, code, character_id, reason)

static func mobilize(repo: DataRepository, state: GameState, event_id: String, recruits: Array, reason: String) -> Dictionary:
	return _mobilize(repo, state, event_id, recruits, reason, false)

## Existing service is preserved even when old population tables cannot account for it.
static func initialize_historical(repo: DataRepository, state: GameState, event_id: String, cohorts: Array, reason: String) -> Dictionary:
	return _mobilize(repo, state, event_id, cohorts, reason, true)

static func _mobilize(repo: DataRepository, state: GameState, event_id: String, recruits: Array, reason: String, historical: bool) -> Dictionary:
	var kind := "initialize_historical" if historical else "mobilize"
	var replay := _replay(state, event_id, kind, recruits, reason)
	if not replay.is_empty():
		return replay
	if event_id.strip_edges() == "" or reason.strip_edges() == "" or recruits.is_empty():
		return {"error": "mobilization needs an event, personnel and a reason"}
	var prepared: Dictionary = {}
	var claims: Dictionary = {}
	var persons: Dictionary = {}
	for raw: Variant in recruits:
		if not raw is Dictionary:
			return {"error": "invalid cohort"}
		var cohort: Dictionary = raw.duplicate(true)
		var invalid := _cohort_error(repo, state, cohort)
		if invalid != "":
			return {"error": invalid}
		var id := String(cohort["id"])
		if prepared.has(id) or state.military_cohorts.has(id):
			return {"error": "cohort already exists: " + id}
		var person := String(cohort.get("person_id", ""))
		if person != "":
			if persons.has(person) or _person_serving(state, person):
				return {"error": "person already serving: " + person}
			persons[person] = true
		var key := _source_key(cohort)
		claims[key] = int(claims.get(key, 0)) + _active(cohort)
		prepared[id] = cohort
	var conflicts: Array[String] = []
	for key: String in claims:
		var parts := key.split("|")
		if int(claims[key]) > MilitaryPopulation.available(repo, state, parts[0], parts[1]):
			if not historical:
				return {"error": "insufficient source population: " + key}
			if not parts[0] in conflicts:
				conflicts.append(parts[0])
	for id: String in prepared:
		var cohort: Dictionary = prepared[id]
		var code := String(cohort["unit_code"])
		if not state.military_rosters.has(code):
			state.military_rosters[code] = {"commander_id": "", "cohort_ids": [], "appointments": []}
		state.military_cohorts[id] = cohort
		state.military_rosters[code]["cohort_ids"].append(id)
	for province: String in conflicts:
		if not province in state.military_conflicts:
			state.military_conflicts.append(province)
	for cohort: Dictionary in prepared.values():
		sync_projections(state, String(cohort["unit_code"]))
	_record(state, event_id, kind, recruits, reason)
	return {"event_id": event_id, "cohort_ids": prepared.keys()}

static func transition(repo: DataRepository, state: GameState, event_id: String, changes: Array, reason: String) -> Dictionary:
	var replay := _replay(state, event_id, "transition", changes, reason)
	if not replay.is_empty():
		return replay
	if event_id.strip_edges() == "" or reason.strip_edges() == "" or changes.is_empty():
		return {"error": "transition needs an event, changes and a reason"}
	var prepared: Dictionary = {}
	var consumed: Dictionary = {}
	var deaths: Dictionary = {}
	for raw: Variant in changes:
		if not raw is Dictionary:
			return {"error": "invalid personnel change"}
		var change: Dictionary = raw
		var id := String(change.get("cohort_id", ""))
		var from := String(change.get("from", ""))
		var to := String(change.get("to", ""))
		var amount: Variant = change.get("count", -1)
		if not state.military_cohorts.has(id) or not from in ACTIVE or not to in STATES or from == to or not _whole(amount) or int(amount) <= 0:
			return {"error": "invalid personnel transition: " + id}
		var original: Dictionary = state.military_cohorts[id]
		var invalid := _cohort_error(repo, state, original.duplicate(true))
		if invalid != "":
			return {"error": invalid}
		var key := id + "|" + from
		consumed[key] = int(consumed.get(key, 0)) + int(amount)
		if int(consumed[key]) > int(original.get(from, 0)):
			return {"error": "insufficient personnel: " + id}
		if not prepared.has(id):
			prepared[id] = original.duplicate(true)
		prepared[id][from] = int(prepared[id][from]) - int(amount)
		prepared[id][to] = int(prepared[id][to]) + int(amount)
		if to == "dead":
			var source := _source_key(original)
			deaths[source] = int(deaths.get(source, 0)) + int(amount)
	# Validate every source before touching either ledger; WorldLedger commits exact province losses.
	for source: String in deaths:
		var parts := source.split("|")
		var path := "economy.provinces.%s.%s" % [parts[0], parts[1]]
		var population: Variant = WorldLedger.value_of(repo, state, path)
		var schema := WorldLedger.schema_for(repo, path)
		if population == null or schema.is_empty() or String(schema.get("type", "")) != "int" or int(population) - int(deaths[source]) < int(float(schema.get("min", 0))):
			return {"error": "invalid source population loss: " + source}
	var previous_world := state.world.duplicate(true)
	var previous_log_size := state.world_log.size()
	for source: String in deaths:
		var parts := source.split("|")
		var applied := WorldLedger.apply(repo, state, "economy.provinces.%s.%s" % [parts[0], parts[1]], -int(deaths[source]), reason, "military")
		if applied.has("error") or int(applied.get("delta", 0)) != -int(deaths[source]):
			state.world = previous_world
			state.world_log.resize(previous_log_size)
			return {"error": "source population loss was refused: " + source}
	for id: String in prepared:
		state.military_cohorts[id] = prepared[id]
		var cohort: Dictionary = prepared[id]
		var person := String(cohort.get("person_id", ""))
		var code := String(cohort["unit_code"])
		if person != "" and int(cohort["fit"]) == 0 and String(state.military_rosters[code].get("commander_id", "")) == person:
			state.military_rosters[code]["commander_id"] = ""
			state.military_rosters[code]["appointments"].append({"day": state.absolute_day(), "commander_id": "", "previous_id": person, "cohort_id": id, "reason": reason})
	for cohort: Dictionary in prepared.values():
		sync_projections(state, String(cohort["unit_code"]))
	_record(state, event_id, "transition", changes, reason)
	return {"event_id": event_id, "changes": changes.duplicate(true)}

## Legacy casualty fields are projections, never a second writable personnel ledger.
static func sync_projections(state: GameState, code: String) -> void:
	var entry: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
	if entry.is_empty():
		return
	entry["dead"] = count(state, code, "dead")
	entry["wounded"] = count(state, code, "wounded")
	entry["deserted"] = count(state, code, "released")
	entry["captured_current"] = count(state, code, "captured_current")

## Naming a counted noble changes identity only, never the unit's headcount.
static func bind_person(state: GameState, code: String, character_id: String, source_id: String, reason: String) -> String:
	if reason.strip_edges() == "" or not state.characters.has(character_id) or not state.military_rosters.has(code) or not state.military_cohorts.has(source_id) or _person_serving(state, character_id):
		return ""
	var source: Dictionary = state.military_cohorts[source_id]
	if String(source.get("unit_code", "")) != code or String(source.get("identity", "")) != "noble" or String(source.get("person_id", "")) != "" or int(source.get("fit", 0)) <= 0:
		return ""
	var named_id := "%s:person:%s:%s" % [source_id, character_id, state.military_cohorts.size()]
	var named: Dictionary = source.duplicate(true)
	named["id"] = named_id
	named["person_id"] = character_id
	named["family_name"] = (state.characters[character_id] as Character).family_name
	for field: String in STATES:
		named[field] = 1 if field == "fit" else 0
	named["initial"] = 1
	source["initial"] = int(source["initial"]) - 1
	source["fit"] = int(source["fit"]) - 1
	state.military_cohorts[named_id] = named
	state.military_rosters[code]["cohort_ids"].append(named_id)
	_record(state, "bind:" + named_id, "bind_person", [{"source_id": source_id, "cohort_id": named_id}], reason)
	return named_id

## Largest remainders spread a unit loss over sources and identities without changing the total.
static func plan_changes(state: GameState, code: String, from: String, to: String, amount: int, prior_changes: Array = []) -> Array:
	if amount < 0 or not from in ACTIVE or not to in STATES or from == to:
		return []
	var ids: Array = state.military_rosters.get(code, {}).get("cohort_ids", []).duplicate()
	ids.sort()
	var weights: Dictionary = {}
	var total := 0
	for id: String in ids:
		var n := int(state.military_cohorts[id].get(from, 0))
		for change: Dictionary in prior_changes:
			if String(change["cohort_id"]) == id and String(change["from"]) == from:
				n -= int(change["count"])
		weights[id] = maxi(0, n)
		total += maxi(0, n)
	if amount > total or amount == 0:
		return []
	var shares: Dictionary = {}
	var remainders: Array = []
	var left := amount
	for id: String in ids:
		@warning_ignore("integer_division")
		var share: int = amount * int(weights[id]) / total
		shares[id] = share
		left -= share
		remainders.append({"id": id, "remainder": amount * int(weights[id]) % total})
	remainders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["remainder"]) > int(b["remainder"]) if a["remainder"] != b["remainder"] else String(a["id"]) < String(b["id"]))
	for i in left:
		shares[remainders[i]["id"]] += 1
	var changes: Array = []
	for id: String in ids:
		if int(shares[id]) > 0:
			changes.append({"cohort_id": id, "from": from, "to": to, "count": int(shares[id])})
	return changes

static func plan_unit_changes(state: GameState, code: String, moves: Array) -> Array:
	var changes: Array = []
	for move: Dictionary in moves:
		var amount := int(move.get("count", 0))
		if amount == 0:
			continue
		var part := plan_changes(state, code, String(move.get("from", "")), String(move.get("to", "")), amount, changes)
		if part.is_empty():
			return []
		changes.append_array(part)
	return changes

static func _whole(value: Variant) -> bool:
	if value is int:
		return int(value) >= 0
	if value is String:
		return String(value).is_valid_int() and int(value) >= 0
	return false

static func _active(cohort: Dictionary) -> int:
	return int(cohort.get("fit", 0)) + int(cohort.get("wounded", 0)) + int(cohort.get("captured_current", 0))

static func _source_key(cohort: Dictionary) -> String:
	return String(cohort.get("source_province", "")) + "|" + String(cohort.get("source_population_field", ""))

static func _cohort_error(repo: DataRepository, state: GameState, cohort: Dictionary) -> String:
	for key: String in ["id", "unit_code", "source_province", "source_population_field", "identity", "stage"]:
		if String(cohort.get(key, "")).strip_edges() == "":
			return "cohort needs " + key
	if not String(cohort["source_population_field"]) in MilitaryPopulation.FIELDS:
		return "unknown population source"
	if WorldLedger.value_of(repo, state, "economy.provinces.%s.%s" % [cohort["source_province"], cohort["source_population_field"]]) == null:
		return "unknown source province"
	if not String(cohort["identity"]) in ["commoner", "noble"] or not String(cohort["stage"]) in ["mustering", "active"]:
		return "invalid identity or service stage"
	var total := 0
	for field: String in STATES:
		if not _whole(cohort.get(field, -1)):
			return "invalid personnel state: " + field
		cohort[field] = int(cohort[field])
		total += int(cohort[field])
	if not _whole(cohort.get("initial", -1)) or int(cohort["initial"]) != total or total <= 0:
		return "cohort does not conserve personnel"
	cohort["initial"] = total
	cohort["family_name"] = String(cohort.get("family_name", ""))
	var person := String(cohort.get("person_id", ""))
	if person != "" and (total != 1 or String(cohort["identity"]) != "noble" or not state.characters.has(person)):
		return "named noble must be one existing person"
	return ""

static func _person_serving(state: GameState, person: String) -> bool:
	for cohort: Dictionary in state.military_cohorts.values():
		if String(cohort.get("person_id", "")) == person and (_active(cohort) > 0 or int(cohort.get("dead", 0)) > 0):
			return true
	return false

static func _replay(state: GameState, event_id: String, kind: String, payload: Array, reason: String) -> Dictionary:
	if not state.military_events.has(event_id):
		return {}
	var event: Dictionary = state.military_events[event_id]
	if event.get("kind") != kind or event.get("payload") != payload or event.get("reason") != reason:
		return {"error": "personnel event token reused with different contents"}
	return {"event_id": event_id, "duplicate": true}

static func _record(state: GameState, event_id: String, kind: String, payload: Array, reason: String) -> void:
	state.military_events[event_id] = {"kind": kind, "payload": payload.duplicate(true), "reason": reason, "tick": state.tick}
