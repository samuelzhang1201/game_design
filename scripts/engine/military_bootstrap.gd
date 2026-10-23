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
		var integrity := _integrity_error(repo, state)
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
	# Build a disposable personnel plan, partition with the saved-unit allocator,
	# then enlist only the capped leaves through the ordinary ledger boundary.
	for raw: Dictionary in plan["recruits"]:
		var cohort := raw.duplicate(true)
		cohort.initial = int(cohort.count)
		cohort.fit = int(cohort.count)
		cohort.erase("count")
		for status: String in ["wounded", "captured_current", "dead", "released"]: cohort[status] = 0
		candidate.military_cohorts[cohort.id] = cohort
		var code := String(cohort.unit_code)
		if not candidate.military_rosters.has(code):
			candidate.military_rosters[code] = {"commander_id": "", "cohort_ids": []}
		candidate.military_rosters[code].cohort_ids.append(cohort.id)
	for code: String in plan["appointments"]:
		candidate.military_rosters[code].commander_cohort_id = "initial:" + code + ":commander"
	var partition := MilitaryReorganization.reconcile(repo, candidate)
	if partition.has("error") or partition.get("status") != "complete":
		return partition
	var recruits: Array = []
	for cohort: Dictionary in candidate.military_cohorts.values():
		if int(cohort.initial) == 0: continue
		var row := cohort.duplicate(true)
		row.count = int(cohort.initial)
		recruits.append(row)
	candidate.military_cohorts.clear()
	candidate.military_rosters.clear()
	var result := Roster.mobilize(repo, candidate, INITIAL_EVENT, recruits, "Opening military service")
	if result.has("error"):
		return result
	for code: String in plan["appointments"]:
		result = Roster.assign_commander(repo, candidate, code, plan["appointments"][code], "Opening military command")
		if result.has("error"):
			return result
	candidate.military_migration.merge({"version": VERSION, "status": "initialized",
		"origin_rule": "opening_province_recruitment_weights", "organization_version": 1, "event_id": INITIAL_EVENT}, true)
	for field: String in ["army_roster", "military_rosters", "military_cohorts", "military_events", "military_migration"]:
		state.set(field, candidate.get(field))
	return {"status": "initialized", "units": state.military_rosters.size()}

static func _integrity_error(repo: DataRepository, state: GameState) -> String:
	var pending := RecruitmentSystem.pending_new_units(repo, state)
	if pending.has("error"): return String(pending.error)
	for code: String in state.army_roster:
		if not state.military_rosters.has(code):
			return "Initialized unit has no personnel roster: " + code
	var referenced: Dictionary = {}
	for code: String in state.military_rosters:
		if not state.army_roster.has(code) and not pending.units.has(code):
			return "Personnel roster has no saved equipment unit: " + code
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
	if not state.day_resolution.is_empty():
		var incompatibility := DayResolution.incompatibility_reason(state.day_resolution)
		if not incompatibility.is_empty():
			return {"error": incompatibility}
	if state.military_migration.has("import_main_v7"):
		return _import_main_v7(repo, state)
	if int(state.military_migration.get("version", 0)) == VERSION:
		var error := _migration_integrity_error(repo, state)
		if not error.is_empty():
			return {"error": error}
		_mark_living_pending(repo, state)
		return {"status": "unchanged"}
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
	var origin_estimates: Array[String] = []
	for code: String in codes:
		var unit: Dictionary = candidate.army_roster[code]
		var sources := ArmySplit.saved_sources(repo, unit)
		if sources.has("error"):
			return sources
		if bool(sources["reconstructed"]):
			unit["source_parts"] = sources["parts"]
			reconstructed.append(code)
		for part: Dictionary in sources["parts"]:
			if part.has("origin_reason") and not String(part["origin_reason"]) in origin_estimates:
				origin_estimates.append(String(part["origin_reason"]))
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
			"released": entry.get("deserted", 0), "captured_current": entry.get("captured_current", 0)}
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
		"reason": "Preserve saved personnel without replaying historical population losses" + ("; " + "; ".join(origin_estimates) if not origin_estimates.is_empty() else "")},
		"result": {"status": "personnel_migrated", "units": codes.size()}}
	candidate.military_migration = {"version": VERSION, "status": "personnel_migrated",
		"organization_pending": true, "event_id": event_id,
		"origin_rule": "saved_equipment_provenance_current_population_weights_with_opening_fallback",
		"reconstructed_provenance": reconstructed, "opening_population_fallback": fallback_sources,
		"origin_estimates": origin_estimates, "organization_reason": "; ".join(origin_estimates),
		"historical_identity_rule": "unrecorded_anonymous_losses_not_family_facts;surviving_fit_use_configured_noble_share",
		"historical_population_rule": "not_replayed", "recruitment_blocked": not conflicts.is_empty(), "conflicts": conflicts}
	state.characters = candidate.characters
	state.army_roster = candidate.army_roster
	state.military_rosters = candidate.military_rosters
	state.military_cohorts = candidate.military_cohorts
	state.military_events = candidate.military_events
	state.military_migration = candidate.military_migration
	return {"status": "personnel_migrated", "units": codes.size(), "organization_pending": true, "conflicts": conflicts}

## Completed historical organization does not establish the assigned-living cap.
static func _mark_living_pending(repo: DataRepository, state: GameState) -> void:
	for roster: Dictionary in state.military_rosters.values():
		var assigned := 0
		for id: String in roster.get("cohort_ids", []):
			assigned += int(state.military_cohorts[id].get("fit", 0)) + int(state.military_cohorts[id].get("wounded", 0))
		if assigned > int(repo.bal("army_living_cap_men")):
			state.military_migration.organization_pending = true

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
	var integrity := _integrity_error(repo, state)
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
		if not ArmySplit.is_whole_count(cohort.get("initial", -1)) or total != int(cohort["initial"]) or total < 0:
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

## Main's version-seven ledger is translated privately, never re-enlisted or charged.
static func _import_main_v7(repo: DataRepository, state: GameState) -> Dictionary:
	var candidate := GameState.from_dict(state.to_dict(), false)
	var imported: Dictionary = candidate.military_migration["import_main_v7"]
	if not ArmySplit.is_whole_count(imported.get("organization_version", -1)) \
			or int(imported["organization_version"]) > 1:
		return {"error": "Unsupported saved military organization version."}
	var version := int(imported["organization_version"])
	if candidate.military_cohorts.is_empty() and candidate.military_rosters.is_empty() and candidate.military_events.is_empty():
		if version > 0:
			return {"error": "Completed main military organization has no personnel ledger."}
		candidate.military_migration = {}
		var legacy := migrate(repo, candidate)
		if legacy.has("error"):
			return legacy
	else:
		for id: String in candidate.military_cohorts:
			var cohort: Dictionary = candidate.military_cohorts[id]
			if cohort.get("stage", "") == "mustering":
				cohort["stage"] = "assembling"
			var error := Roster.cohort_error(repo, cohort)
			if not error.is_empty():
				return {"error": error + " " + id}
		for code: String in candidate.military_rosters:
			var roster: Dictionary = candidate.military_rosters[code]
			var person := String(roster.get("commander_id", ""))
			if person.is_empty():
				continue
			var matches: Array = []
			for id: String in roster.get("cohort_ids", []):
				var cohort: Dictionary = candidate.military_cohorts.get(id, {})
				if cohort.get("person_id", "") == person and int(cohort.get("fit", 0)) == 1 and cohort.get("stage", "") == "active":
					matches.append(id)
			if matches.size() != 1:
				return {"error": "Saved commander needs one existing fit noble cohort: " + code}
			roster["commander_cohort_id"] = matches[0]
		for id: String in candidate.military_events:
			var converted := _main_receipt(id, candidate.military_events[id])
			if converted.has("error"):
				return converted
			candidate.military_events[id] = converted
		candidate.military_migration = {"version": VERSION, "status": "main_v7_imported"}
	for code: String in candidate.army_roster:
		var source := ArmySplit.saved_sources(repo, candidate.army_roster[code])
		if source.has("error"):
			return source
		candidate.army_roster[code]["source_parts"] = source["parts"]
	var integrity := _migration_integrity_error(repo, candidate)
	if not integrity.is_empty():
		return {"error": integrity}
	var conflicts: Array = imported.get("conflicts", []).duplicate(true)
	for conflict: Dictionary in _migration_conflicts(repo, candidate):
		if not conflict in conflicts:
			conflicts.append(conflict)
	candidate.military_migration.merge({"version": VERSION, "organization_version": version,
		"organization_pending": version == 0 or bool(imported.get("organization_pending", false)),
		"unit_mapping": imported.get("unit_mapping", {}).duplicate(true),
		"conflicts": conflicts, "recruitment_blocked": not conflicts.is_empty(),
		"import_evidence": imported.duplicate(true), "historical_population_rule": "not_replayed"}, true)
	for battle: Dictionary in candidate.battles:
		if bool(battle.get("ended", false)) or bool(battle.get("finished", false)):
			continue
		if not battle.has("id") or not battle.get("att", null) is Array or not battle.get("def", null) is Array:
			return {"error": "Malformed saved active battlefield."}
		BattleRules.freeze(repo, candidate, battle)
		BattleFormation.ensure(battle)
		if not battle.has("actions"):
			battle["actions"] = {"att": {"kind": "attack", "reason": "Resume saved active engagement"},
				"def": {"kind": "hold", "reason": "Defend saved active engagement"}}
	# Completed main organization IDs are authoritative even if today's cap differs.
	if version == 1:
		candidate.military_migration["organization_pending"] = false
	_mark_living_pending(repo, candidate)
	for field: String in ["army_roster", "military_rosters", "military_cohorts", "military_events", "military_migration"]:
		candidate.set(field, GameState._whole(candidate.get(field)))
	for field: String in ["characters", "army_roster", "military_rosters", "military_cohorts", "military_events", "military_migration", "battles"]:
		state.set(field, candidate.get(field))
	return {"status": "main_v7_imported", "organization_pending": candidate.military_migration["organization_pending"]}


static func _main_receipt(id: String, receipt: Variant) -> Dictionary:
	if id.strip_edges().is_empty():
		return {"error": "Military receipt needs an event ID."}
	if not receipt is Dictionary:
		return {"error": "Military receipt must be a record: " + id}
	if receipt.has("request") or receipt.has("result"):
		var error := _receipt_error(receipt)
		return {"error": error + ": " + id} if error != "" else receipt.duplicate(true)
	if not receipt.get("kind", null) is String or not receipt.get("reason", null) is String:
		return {"error": "Military receipt needs a kind and reason: " + id}
	var kind := String(receipt.get("kind", ""))
	var reason := String(receipt.get("reason", ""))
	if id.is_empty() or kind.is_empty() or reason.strip_edges().is_empty():
		return {"error": "Malformed historical military receipt: " + id}
	if not kind in ["transition", "mobilize", "initialize_historical", "bind_person", "organization"]:
		return {"error": "Unknown historical military receipt: " + id}
	if kind != "organization" and not receipt.get("payload", null) is Array:
		return {"error": "Historical military payload must be an array: " + id}
	var request := {"kind": kind, "reason": reason}
	var result := {"status": "applied", "event_id": id}
	if kind == "transition":
		var normalized := Roster._normalize_rows(receipt.get("payload", []), ["cohort_id", "from", "to"])
		if normalized.has("error") or normalized.get("rows", []).is_empty():
			return {"error": "Malformed historical personnel transition receipt: " + id}
		request["changes"] = normalized["rows"]
		result["changes"] = normalized["rows"].duplicate(true)
	elif kind == "mobilize":
		var recruits: Array = []
		for old: Variant in receipt.get("payload", []):
			if not old is Dictionary:
				return {"error": "Historical recruit must be a record: " + id}
			var row: Dictionary = old.duplicate(true)
			row["count"] = old.get("initial", 0)
			if row.get("stage", "") == "mustering":
				row["stage"] = "assembling"
			recruits.append(row)
		var normalized := Roster._normalize_rows(recruits, ["id", "unit_code", "source_province", "source_population_field", "identity", "family_name", "stage", "person_id"])
		if normalized.has("error") or normalized.get("rows", []).is_empty():
			return {"error": "Malformed historical personnel mobilization receipt: " + id}
		request["recruits"] = normalized["rows"]
		result["cohort_ids"] = recruits.map(func(row: Dictionary) -> String: return String(row["id"]))
	else:
		request["legacy_payload"] = receipt.duplicate(true)
	var converted := {"request": request, "result": result, "legacy_evidence": receipt.duplicate(true)}
	var error := _receipt_error(converted)
	return {"error": error + ": " + id} if error != "" else converted


## Validate saved replay data structurally, without replaying historical losses or
## requiring historical units to remain live. Every supported kind has a schema.
static func _receipt_error(receipt: Dictionary) -> String:
	if not receipt.get("request", null) is Dictionary or not receipt.get("result", null) is Dictionary:
		return "Military receipt request and result must be records"
	var request: Dictionary = receipt["request"]
	var result: Dictionary = receipt["result"]
	if not request.get("kind", null) is String:
		return "Military receipt kind must be text"
	var kind: String = request["kind"]
	if kind != "military_wages" and not _receipt_text(request.get("reason")):
		return "Military receipt needs a reason"
	match kind:
		"transition", "transfer_units", "mobilize":
			var field := "changes" if kind == "transition" else ("orders" if kind == "transfer_units" else "recruits")
			var error := _receipt_rows_error(request.get(field), kind)
			if error != "":
				return error
			if result.get("status") != "applied":
				return "Personnel receipt result must be applied"
			if kind == "mobilize":
				if not _receipt_ids(result.get("cohort_ids"), false) or result["cohort_ids"] != request["recruits"].map(func(row: Dictionary) -> String: return row["id"]):
					return "Recruitment receipt needs its original cohort IDs"
			elif result.has("changes"):
				if _receipt_rows_error(result["changes"], "transition") != "" or (kind == "transition" and result["changes"] != request["changes"]):
					return "Personnel receipt has invalid result changes"
			elif not _receipt_lines(result.get("population")):
				return "Personnel receipt needs population results"
		"activate":
			if not _receipt_ids(request.get("cohort_ids"), false) or result.get("status") != "active" or result.get("cohort_ids") != request["cohort_ids"]:
				return "Invalid activation receipt"
		"legacy_personnel_import":
			if result.get("status") != "personnel_migrated" or not _receipt_count(result.get("units", -1)):
				return "Invalid personnel import receipt"
		"military_wages":
			if not _receipt_count(request.get("tick", -1)) or result.get("status") != "applied" or not _receipt_count(result.get("monthly_wages", -1)) or not result.get("breakdown", null) is Array or not _receipt_lines(result.get("lines")) or not _receipt_text(result.get("reason")):
				return "Invalid wage receipt"
		"battle_round":
			if not _receipt_ids(request.get("att"), true) or not _receipt_ids(request.get("def"), true) or not request.get("tier", null) is Dictionary:
				return "Invalid battle round request"
			for code: Variant in result:
				var loss: Variant = result[code]
				if not code is String or not loss is Dictionary or not code in request["att"] + request["def"]:
					return "Invalid battle round result"
				if not _receipt_count(loss.get("dead", -1)) or not _receipt_count(loss.get("wounded", -1)) or not _receipt_integer(loss.get("morale")) or not _receipt_text(loss.get("reason")):
					return "Invalid battle casualty result"
		"initialize_historical", "bind_person", "organization":
			var legacy: Variant = request.get("legacy_payload")
			if not legacy is Dictionary or legacy.get("kind") != kind or legacy.get("reason") != request["reason"] or result.get("status") != "applied":
				return "Invalid historical military receipt"
			if kind == "organization":
				if not legacy.get("aliases", null) is Dictionary:
					return "Invalid historical organization aliases"
				for code: Variant in legacy["aliases"]:
					if not _receipt_text(code) or not _receipt_ids(legacy["aliases"][code], false):
						return "Invalid historical organization alias"
			else:
				if not legacy.get("payload", null) is Array or legacy["payload"].is_empty():
					return "Invalid historical personnel payload"
				for row: Variant in legacy["payload"]:
					if not row is Dictionary:
						return "Historical personnel entry must be a record"
					if kind == "bind_person":
						if not _receipt_text(row.get("source_id")) or not _receipt_text(row.get("cohort_id")):
							return "Invalid historical named-person binding"
					elif not _receipt_count(row.get("initial", -1)) or not _receipt_text(row.get("id")) or not _receipt_text(row.get("unit_code")):
						return "Invalid historical personnel initialization"
		_:
			return "Unknown military receipt kind"
	return ""

static func _receipt_rows_error(rows: Variant, kind: String) -> String:
	if not rows is Array or rows.is_empty():
		return "Personnel receipt needs entries"
	for row: Variant in rows:
		if not row is Dictionary or not _receipt_count(row.get("count", -1)) or int(row["count"]) <= 0:
			return "Personnel receipt needs positive whole counts"
		if kind == "mobilize":
			for field: String in ["id", "unit_code", "source_province", "source_population_field", "identity", "family_name", "stage", "person_id"]:
				if not row.get(field, null) is String:
					return "Invalid recruitment receipt text"
			if not _receipt_text(row["id"]) or not _receipt_text(row["unit_code"]) or not _receipt_text(row["source_province"]) or not row["source_population_field"] in Population.FIELDS or not row["identity"] in ["commoner", "noble"] or not row["stage"] in ["active", "assembling"]:
				return "Invalid recruitment receipt origin or identity"
		else:
			var id_field := "cohort_id" if kind == "transition" else "unit_code"
			if not _receipt_text(row.get(id_field)) or not row.get("from", null) is String or not row.get("to", null) is String or not row["to"] in Roster.TRANSITIONS.get(row["from"], []):
				return "Invalid personnel receipt transition"
	return ""

static func _receipt_text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

static func _receipt_ids(value: Variant, allow_empty: bool) -> bool:
	if not value is Array or (not allow_empty and value.is_empty()):
		return false
	var seen: Dictionary = {}
	for id: Variant in value:
		if not _receipt_text(id) or seen.has(id):
			return false
		seen[id] = true
	return true

static func _receipt_integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))

static func _receipt_count(value: Variant) -> bool:
	return _receipt_integer(value) and float(value) >= 0

static func _receipt_lines(value: Variant) -> bool:
	if not value is Array:
		return false
	for line: Variant in value:
		if not line is Dictionary or not _receipt_text(line.get("path")) or not _receipt_text(line.get("reason")) or not _receipt_integer(line.get("delta")) or not _receipt_integer(line.get("value")):
			return false
	return true
