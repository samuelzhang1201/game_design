class_name MilitaryBootstrap
extends RefCounted
## Build the complete opening personnel ledger before deploying any army.
## Opening station is an explicit origin policy, not invented ancestry.
const Roster := preload("res://scripts/engine/military_roster.gd")
const Commanders := preload("res://scripts/engine/military_commanders.gd")
const Population := preload("res://scripts/engine/military_population.gd")
const VERSION := 1
const RATE_SCALE := 1_000_000
const INITIAL_EVENT := "military:initial"

static func initialize(repo: DataRepository, state: GameState) -> Dictionary:
	if int(state.military_migration.get("version", 0)) == VERSION:
		if state.military_rosters.is_empty() or state.military_cohorts.is_empty():
			return {"error": "Military initialization marker has no personnel ledger."}
		var integrity := _integrity_error(state)
		if integrity != "":
			return {"error": integrity}
		return {"status": "unchanged"}
	if not state.military_migration.is_empty() or not state.military_rosters.is_empty() \
			or not state.military_cohorts.is_empty() or not state.military_events.is_empty():
		return {"error": "Cannot initialize a partial or unsupported military ledger."}
	if state.army_roster.is_empty():
		return {"error": "Military initialization needs the actual army roster."}
	var plan := _plan(repo, state)
	if plan.has("error"):
		return plan
	# Mobilization and every appointment succeed on a private candidate first.
	# No failed late appointment leaves an earlier origin reserved in live state.
	var candidate := GameState.from_dict(state.to_dict(), false)
	var result := Roster.mobilize(repo, candidate, INITIAL_EVENT, plan["recruits"], "Opening military service")
	if result.has("error"):
		return result
	for code: String in plan["appointments"]:
		result = Roster.assign_commander(repo, candidate, code, plan["appointments"][code], "Opening military command")
		if result.has("error"):
			return result
	state.military_rosters = candidate.military_rosters
	state.military_cohorts = candidate.military_cohorts
	state.military_events = candidate.military_events
	state.military_migration = {"version": VERSION, "status": "initialized",
		"origin_rule": "opening_province_recruitment_weights", "event_id": INITIAL_EVENT}
	return {"status": "initialized", "units": state.military_rosters.size()}

static func _integrity_error(state: GameState) -> String:
	for code: String in state.army_roster:
		if not state.military_rosters.has(code):
			return "Initialized unit has no personnel roster: " + code
	var referenced: Dictionary = {}
	for code: String in state.military_rosters:
		var ids: Array = state.military_rosters[code].get("cohort_ids", [])
		if ids.is_empty():
			return "Initialized unit has no personnel cohorts: " + code
		for id: String in ids:
			if referenced.has(id) or not state.military_cohorts.has(id):
				return "Missing or duplicated initialized cohort: " + id
			if state.military_cohorts[id].get("unit_code", "") != code:
				return "Initialized cohort belongs to a different unit: " + id
			referenced[id] = true
	if referenced.size() != state.military_cohorts.size():
		return "Initialized personnel contains an unassigned cohort."
	return ""

static func _plan(repo: DataRepository, state: GameState) -> Dictionary:
	var recruits: Array = []
	var appointments: Dictionary = {}
	var assigned: Dictionary = {}
	var codes := state.army_roster.keys()
	codes.sort()
	for code: String in codes:
		var unit: Dictionary = state.army_roster[code]
		var origins := _origins(repo, state, unit)
		if origins.has("error"):
			return origins
		var rows: Array = origins["rows"]
		var weights: Array = []
		var total := 0
		for row: Dictionary in rows:
			weights.append(row["count"])
			total += int(row["count"])
		if total != Roster.personnel_capacity(repo, unit):
			return {"error": "Equipment and source personnel disagree for " + code}
		var composition := Roster.composition(total, int(repo.bal("army_noble_start_permille")), int(repo.bal("army_noble_cap_permille")))
		if composition.has("error"):
			return {"error": code + ": " + String(composition["error"])}
		var person := _commander(repo, state, unit, assigned)
		if person.is_empty():
			return {"error": "No eligible unassigned commander for " + code}
		assigned[person] = true
		appointments[code] = person
		var family := (state.characters[person] as Character).family_name
		var nobles := BattleSystem.apportion(weights, int(composition["noble_troops"]) + 1)
		var officer_placed := false
		for i: int in rows.size():
			var origin: Dictionary = rows[i]
			var noble_count := int(nobles[i])
			var commoners := int(origin["count"]) - noble_count
			if commoners > 0:
				recruits.append(_cohort(code, origin, "commoner", commoners, ""))
			if noble_count > 0 and not officer_placed:
				var officer := _cohort(code, origin, "noble", 1, family)
				officer["id"] = "initial:" + code + ":commander"
				officer["person_id"] = person
				recruits.append(officer)
				officer_placed = true
				noble_count -= 1
			if noble_count > 0:
				recruits.append(_cohort(code, origin, "noble", noble_count, family))
	return {"recruits": recruits, "appointments": appointments}

static func _origins(repo: DataRepository, state: GameState, unit: Dictionary) -> Dictionary:
	var parts: Array = unit.get("source_parts", [])
	if parts.is_empty():
		return {"error": "Opening personnel need equipment provenance."}
	var types := repo.world_table("military", "unit_types")
	var totals: Dictionary = {}
	for part: Dictionary in parts:
		var province := String(part.get("province_code", ""))
		var arm := String(part.get("arm", ""))
		var count := int(part.get("equipment_count", 0))
		var crew := int(part.get("crew_per_element", 0))
		if not repo.provinces.has(province) or not types.has(arm) or count <= 0 or crew <= 0:
			return {"error": "Invalid opening equipment origin."}
		var weights: Array = []
		for field: String in Population.FIELDS:
			var people: Variant = WorldLedger.value_of(repo, state, Population.path(province, field))
			var key := "rural_rate" if field == "rural_population" else "urban_rate"
			var rate := float(types[arm].get(key, 0))
			if people == null or int(people) < 0 or not is_finite(rate) or rate < 0:
				return {"error": "Invalid opening population or recruitment rate."}
			weights.append(int(people) * roundi(rate * RATE_SCALE))
		if int(weights[0]) + int(weights[1]) == 0:
			return {"error": "No supported population origin for " + arm + " in " + province}
		var shares := BattleSystem.apportion(weights, count * crew)
		for i: int in Population.FIELDS.size():
			if int(shares[i]) <= 0:
				continue
			var field := Population.FIELDS[i]
			var key := Population.path(province, field)
			if not totals.has(key):
				totals[key] = {"source_province": province, "source_population_field": field, "count": 0}
			totals[key]["count"] = int(totals[key]["count"]) + int(shares[i])
	var keys := totals.keys()
	keys.sort()
	var rows: Array = []
	for key: String in keys:
		rows.append(totals[key])
	return {"rows": rows}

static func _commander(repo: DataRepository, state: GameState, unit: Dictionary, assigned: Dictionary) -> String:
	var candidates: Array[String] = []
	var arm := MapObjects.regiment_arm(repo, unit)
	var realm := String(unit.get("kingdom_code", ""))
	for id: String in repo.commanders:
		if assigned.has(id) or Commanders.candidate_error(repo, state, id) != "":
			continue
		var definition: Dictionary = repo.commanders[id]
		if repo.resolve_realm(String(definition["realm_slot"])) == realm \
				and arm in String(definition["unit_kinds"]).split("|"):
			candidates.append(id)
	# Preserve officers with broad qualifications for units lacking specialists.
	candidates.sort_custom(func(a: String, b: String) -> bool:
		var ad: Dictionary = repo.commanders[a]
		var bd: Dictionary = repo.commanders[b]
		var ar := 1 if ad.get("pool_role", "active") == "reserve" else 0
		var br := 1 if bd.get("pool_role", "active") == "reserve" else 0
		if ar != br:
			return ar < br
		var ac := String(ad["unit_kinds"]).split("|").size()
		var bc := String(bd["unit_kinds"]).split("|").size()
		if ac != bc:
			return ac < bc
		var ap := int(ad.get("reserve_priority", 0))
		var bp := int(bd.get("reserve_priority", 0))
		return a < b if ap == bp else ap < bp)
	return "" if candidates.is_empty() else candidates[0]

static func _cohort(code: String, origin: Dictionary, identity: String, count: int, family: String) -> Dictionary:
	return {"id": "initial:%s:%s:%s:%s" % [code, origin["source_province"], origin["source_population_field"], identity],
		"unit_code": code, "source_province": origin["source_province"],
		"source_population_field": origin["source_population_field"], "count": count,
		"identity": identity, "family_name": family, "stage": "active"}

## One-time import of saved personnel facts. Organization is deliberately left
## on its saved IDs until a later safe boundary can remap every reference.
## Historical deaths are imported, never replayed against today's population.
static func migrate(repo: DataRepository, state: GameState) -> Dictionary:
	if int(state.military_migration.get("version", 0)) == VERSION:
		var error := _migration_integrity_error(repo, state)
		return {"status": "unchanged"} if error.is_empty() else {"error": error}
	if not state.military_migration.is_empty() or not state.military_rosters.is_empty() \
			or not state.military_cohorts.is_empty() or not state.military_events.is_empty():
		return {"error": "Cannot migrate a partial or unsupported military ledger."}
	if state.army_roster.is_empty():
		return {"error": "Personnel migration needs the saved army roster."}
	var candidate := GameState.from_dict(state.to_dict(), false)
	var authored := CharacterFactory.build_roster(repo)
	for id: String in repo.commanders:
		if not candidate.characters.has(id) and authored.has(id):
			candidate.characters[id] = authored[id]
	var codes: Array = candidate.army_roster.keys()
	codes.sort()
	var assigned: Dictionary = {}
	var reconstructed: Array[String] = []
	var fallback_sources: Array[String] = []
	for code: String in codes:
		var unit: Dictionary = candidate.army_roster[code]
		var sources := ArmySplit.saved_sources(repo, unit)
		if sources.has("error"):
			return sources
		if bool(sources["reconstructed"]):
			unit["source_parts"] = sources["parts"]
			reconstructed.append(code)
		var origin_state := GameState.new()
		origin_state.world = candidate.world.duplicate(true)
		# Origin weights are not historical facts. Where today's source has no
		# residents, use the same province's authored opening population only.
		for part: Dictionary in sources["parts"]:
			var province := String(part["province_code"])
			var weighted_total := 0
			var arm_type := repo.world_row("military", "unit_types", String(part["arm"]))
			for field: String in Population.FIELDS:
				var residents: Variant = WorldLedger.value_of(repo, candidate, Population.path(province, field))
				var rate := float(arm_type.get("rural_rate" if field == "rural_population" else "urban_rate", 0))
				if residents == null or not ArmySplit.is_whole_count(residents) or not is_finite(rate) or rate < 0:
					return {"error": "Invalid saved population or recruitment weight: " + province}
				weighted_total += int(residents) * roundi(rate * RATE_SCALE)
			if weighted_total != 0:
				continue
			var opening := repo.world_row("economy", "provinces", province)
			for field: String in Population.FIELDS:
				if not ArmySplit.is_whole_count(opening.get(field, -1)):
					return {"error": "No valid opening population fallback for " + province}
				origin_state.world[Population.path(province, field)] = int(opening[field])
			if not province in fallback_sources:
				fallback_sources.append(province)
		var origins := _origins(repo, origin_state, unit)
		if origins.has("error"):
			return origins
		var total := Roster.personnel_capacity(repo, unit)
		var entry: Dictionary = candidate.regiments.get(code, candidate.foes.get(code, {}))
		if candidate.regiments.has(code) and candidate.foes.has(code):
			return {"error": "Saved unit has conflicting live records: " + code}
		var statuses := {"dead": entry.get("dead", 0), "wounded": entry.get("wounded", 0),
			"released": entry.get("deserted", 0)}
		var lost := 0
		for status: String in statuses:
			if not ArmySplit.is_whole_count(statuses[status]):
				return {"error": "Saved personnel loss must be a whole nonnegative count: " + code}
			statuses[status] = int(statuses[status])
			lost += int(statuses[status])
		if total <= 0 or lost > total:
			return {"error": "Saved losses exceed equipment personnel capacity: " + code}
		var fit := total - lost
		var person := ""
		if fit > 0:
			person = _commander(repo, candidate, unit, assigned)
			if person.is_empty():
				return {"error": "No eligible commander for saved survivors: " + code}
			assigned[person] = true
		candidate.military_rosters[code] = {"commander_id": "", "cohort_ids": []}
		var remaining: Array = []
		var rows: Array = origins["rows"]
		for origin: Dictionary in rows:
			remaining.append(int(origin["count"]))
		for status: String in statuses:
			var allocation := BattleSystem.apportion(remaining, int(statuses[status]))
			for i: int in rows.size():
				var count := int(allocation[i])
				if count > 0:
					_migration_cohort(candidate, code, rows[i], "commoner", status, count, "", "")
					remaining[i] = int(remaining[i]) - count
		if fit > 0:
			var share := int(repo.bal("army_noble_start_permille"))
			var cap := int(repo.bal("army_noble_cap_permille"))
			if share < 0 or share > cap or cap <= 0 or cap > 1000:
				return {"error": "Invalid noble share for saved survivors."}
			@warning_ignore("integer_division")
			var nobles := BattleSystem.apportion(remaining, maxi(1, fit * share / 1000))
			var family := (candidate.characters[person] as Character).family_name
			var placed := false
			for i: int in rows.size():
				var noble_count := int(nobles[i])
				var commoners := int(remaining[i]) - noble_count
				if commoners > 0:
					_migration_cohort(candidate, code, rows[i], "commoner", "fit", commoners, "", "")
				if noble_count > 0 and not placed:
					_migration_cohort(candidate, code, rows[i], "noble", "fit", 1, family, person)
					placed = true
					noble_count -= 1
				if noble_count > 0:
					_migration_cohort(candidate, code, rows[i], "noble", "fit", noble_count, family, "")
			var appointment := Roster.assign_commander(repo, candidate, code, person, "Appointed to surviving saved personnel during migration")
			if appointment.has("error"):
				return appointment
	var integrity := _migration_integrity_error(repo, candidate)
	if not integrity.is_empty():
		return {"error": integrity}
	var conflicts := _migration_conflicts(repo, candidate)
	var event_id := "military:migration:personnel:v1"
	candidate.military_events[event_id] = {"request": {"kind": "legacy_personnel_import",
		"reason": "Preserve saved personnel without replaying historical population losses"},
		"result": {"status": "personnel_migrated", "units": codes.size()}}
	candidate.military_migration = {"version": VERSION, "status": "personnel_migrated",
		"organization_pending": true, "event_id": event_id,
		"origin_rule": "saved_equipment_provenance_current_population_weights_with_opening_fallback",
		"reconstructed_provenance": reconstructed, "opening_population_fallback": fallback_sources,
		"historical_identity_rule": "unrecorded_anonymous_losses_not_family_facts;surviving_fit_use_configured_noble_share",
		"historical_population_rule": "not_replayed", "recruitment_blocked": not conflicts.is_empty(), "conflicts": conflicts}
	state.characters = candidate.characters
	state.army_roster = candidate.army_roster
	state.military_rosters = candidate.military_rosters
	state.military_cohorts = candidate.military_cohorts
	state.military_events = candidate.military_events
	state.military_migration = candidate.military_migration
	return {"status": "personnel_migrated", "units": codes.size(), "organization_pending": true, "conflicts": conflicts}

static func _migration_cohort(state: GameState, code: String, origin: Dictionary, identity: String,
		status: String, count: int, family: String, person: String) -> void:
	var id := "legacy:%s:%s:%s:%s:%s" % [code, origin["source_province"], origin["source_population_field"], identity, status]
	if person != "":
		id += ":commander"
	var cohort := {"id": id, "unit_code": code, "source_province": origin["source_province"],
		"source_population_field": origin["source_population_field"], "identity": identity,
		"family_name": family, "stage": "active", "initial": count,
		"fit": 0, "wounded": 0, "captured_current": 0, "dead": 0, "released": 0}
	cohort[status] = count
	if status != "fit":
		cohort["historical_identity"] = "unrecorded"
	if person != "":
		cohort["person_id"] = person
	state.military_cohorts[id] = cohort
	state.military_rosters[code]["cohort_ids"].append(id)

static func _migration_integrity_error(repo: DataRepository, state: GameState) -> String:
	var integrity := _integrity_error(state)
	if integrity != "":
		return integrity
	if state.military_cohorts.is_empty():
		return "Military marker has no personnel ledger."
	var named: Dictionary = {}
	for id: String in state.military_cohorts:
		var cohort: Dictionary = state.military_cohorts[id]
		if cohort.get("id", "") != id or not repo.provinces.has(String(cohort.get("source_province", ""))) \
				or not String(cohort.get("source_population_field", "")) in Population.FIELDS \
				or not String(cohort.get("identity", "")) in ["commoner", "noble"] \
				or not String(cohort.get("stage", "")) in ["active", "assembling"]:
			return "Invalid personnel identity or origin: " + id
		var total := 0
		for status: String in Roster.PERSONNEL_STATES:
			if not ArmySplit.is_whole_count(cohort.get(status, -1)):
				return "Invalid personnel status count: " + id
			total += int(cohort[status])
		if not ArmySplit.is_whole_count(cohort.get("initial", -1)) or total != int(cohort["initial"]) or total <= 0:
			return "Personnel conservation failed: " + id
		var person := String(cohort.get("person_id", ""))
		if person != "":
			if total != 1 or not state.characters.has(person) or cohort.get("identity", "") != "noble":
				return "Invalid named personnel record: " + id
			if int(cohort.get("released", 0)) != 1:
				if named.has(person):
					return "Duplicate serving named person: " + person
				named[person] = true
	var commanders: Dictionary = {}
	for code: String in state.military_rosters:
		var roster: Dictionary = state.military_rosters[code]
		var person := String(roster.get("commander_id", ""))
		if person.is_empty():
			continue
		var cohort_id := String(roster.get("commander_cohort_id", ""))
		var cohort: Dictionary = state.military_cohorts.get(cohort_id, {})
		var unit: Dictionary = state.army_roster.get(code, {})
		var character: Character = state.characters.get(person) as Character
		var definition: Dictionary = repo.commanders.get(person, {})
		if commanders.has(person) or cohort.get("person_id", "") != person \
				or cohort.get("unit_code", "") != code or int(cohort.get("fit", 0)) != 1 \
				or cohort.get("stage", "") != "active" or character == null \
				or Commanders.candidate_error(repo, state, person) != "" \
				or character.kingdom != unit.get("kingdom_code", "") \
				or not MapObjects.regiment_arm(repo, unit) in String(definition.get("unit_kinds", "")).split("|"):
			return "Invalid saved commander appointment: " + code
		commanders[person] = true
	return ""

static func _migration_conflicts(repo: DataRepository, state: GameState) -> Array:
	var origins: Dictionary = {}
	for cohort: Dictionary in state.military_cohorts.values():
		var source := Population.path(String(cohort["source_province"]), String(cohort["source_population_field"]))
		origins[source] = int(origins.get(source, 0)) + int(cohort["fit"]) + int(cohort["wounded"]) + int(cohort["captured_current"])
	var keys := origins.keys()
	keys.sort()
	var conflicts: Array = []
	for source: String in keys:
		var population := int(WorldLedger.value_of(repo, state, source))
		@warning_ignore("integer_division")
		var eligible := population * clampi(int(repo.bal("recruitment_eligible_permille")), 0, 1000) / 1000
		if int(origins[source]) > eligible:
			conflicts.append({"source": source, "occupied": int(origins[source]), "eligible": eligible,
				"reason": "Saved military residents exceed current eligible population; preserve personnel and block further recruitment"})
	return conflicts
