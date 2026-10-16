class_name RecruitmentSystem
extends RefCounted
const Quality := preload("res://scripts/engine/military_quality.gd")
## Quotes are read-only. A paid project reserves people and equipment together;
## only effective day-ends activate them, through the same personnel ledger.

static func normalize(request: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["request_id", "mode", "arm", "unit_code", "source_province", "source_population_field", "assembly_town", "commander_id"]:
		var value: Variant = request.get(key, "new" if key == "mode" else "")
		if not value is String:
			return {"error": "Recruitment field must be text: " + key}
		out[key] = value
	for key: String in ["total", "noble_permille"]:
		var value: Variant = request.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floor(float(value)):
			return {"error": "Recruitment field must be a whole number: " + key}
		out[key] = int(value)
	if String(out["request_id"]).strip_edges().is_empty() or not out["mode"] in ["new", "reinforce"]:
		return {"error": "Recruitment needs a request ID and a valid mode."}
	if int(out["total"]) <= 0:
		return {"error": "Recruitment needs a positive number of people."}
	if out["mode"] == "new" and out["unit_code"] != "":
		return {"error": "A new unit's identity is assigned by the engine."}
	return out

static func replay(state: GameState, request: Dictionary) -> Dictionary:
	var normalized := normalize(request)
	if normalized.has("error"):
		return normalized
	var project: Dictionary = state.recruitment_projects.get(normalized["request_id"], {})
	if project.is_empty():
		return {}
	if project["request"] != normalized:
		return {"error": "Recruitment request ID already belongs to another order."}
	return (project["result"] as Dictionary).duplicate(true)

static func quote(repo: DataRepository, state: GameState, request: Dictionary) -> Dictionary:
	var req := normalize(request)
	if req.has("error"):
		return req
	var previous := replay(state, req)
	if previous.has("error"):
		return previous
	if not previous.is_empty():
		return (state.recruitment_projects[req["request_id"]]["quote"] as Dictionary).duplicate(true)
	if not state.day_resolution.is_empty():
		return {"error": "Finish the pending day decision before recruiting."}
	if bool(state.military_migration.get("recruitment_blocked", false)) or bool(state.military_migration.get("organization_pending", false)):
		return {"error": "Military migration must be reconciled before recruiting."}
	var realm := repo.resolve_realm("player_realm")
	var province := String(req["source_province"])
	var town := String(req["assembly_town"])
	if not repo.provinces.has(province) or not req["source_population_field"] in MilitaryPopulation.FIELDS:
		return {"error": "Recruitment needs a known urban or rural origin."}
	if MapOwnership.owner_of(repo, state, province) != realm or not repo.burgs.has(town) \
			or String(repo.burgs[town]["province_code"]) != province or not ArmyGround.holds(repo, state, realm, town):
		return {"error": "The assembly town and origin must be held by the crown in the same province."}
	var code := "recruited:" + String(req["request_id"]) if req["mode"] == "new" else String(req["unit_code"])
	var unit: Dictionary = state.army_roster.get(code, {})
	var arm := String(req["arm"])
	var living := 0
	var existing_nobles := 0
	var needs_officer := true
	if req["mode"] == "new":
		if state.army_roster.has(code) or state.military_rosters.has(code):
			return {"error": "The new unit identity is already in use."}
	else:
		if unit.is_empty() or String(unit.get("kingdom_code", "")) != realm or not state.regiments.has(code):
			return {"error": "Reinforcements need an existing unit of the crown."}
		arm = MapObjects.regiment_arm(repo, unit)
		if String(req["arm"]) != "" and req["arm"] != arm:
			return {"error": "Reinforcements must match the unit's arm."}
		living = MilitaryRoster.living(state, code)
		existing_nobles = _nobles(state, code)
		var current := String(state.military_rosters.get(code, {}).get("commander_id", ""))
		needs_officer = current == ""
		if not needs_officer and req["commander_id"] != current:
			return {"error": "Reinforcement cannot replace the serving commander."}
	for project: Dictionary in state.recruitment_projects.values():
		if project.get("status", "") != "complete" and code in project.get("unit_codes", [project.get("unit_code", "")]):
			return {"error": "This unit already has a paid assembly in progress."}
	var types := repo.world_table("military", "unit_types")
	if not types.has(arm) or not repo.recruitment.has(arm):
		return {"error": "This arm has no recruitment contract."}
	var row: Dictionary = repo.recruitment[arm]
	var crew := int(types[arm].get("crew", 0))
	var total := int(req["total"])
	if crew <= 0 or (req["mode"] == "new" and total % crew != 0):
		return {"error": "The personnel count must fill whole equipment crews."}
	if int(row.get("requires_port", 0)) != 0 and String(repo.burgs[town].get("is_port", "0")) != "1":
		return {"error": "This arm must assemble at a held port."}
	if arm == "fleet" and _port_berth(repo, town) == ArmyGround.NONE:
		return {"error": "This port has no adjacent navigable water for assembly."}
	var pooled := false
	for split: Dictionary in repo.army_split:
		if split["arm"] == arm:
			pooled = bool(split.get("pooled", false))
	if req["mode"] == "new" and pooled:
		for other: Dictionary in state.army_roster.values():
			if String(other["kingdom_code"]) == realm and MapObjects.regiment_arm(repo, other) == arm:
				return {"error": "Reinforce the realm's existing royal train."}
	var capacity := MilitaryRoster.personnel_capacity(repo, unit)
	@warning_ignore("integer_division")
	var equipment := maxi(0, (living + total - capacity + crew - 1) / crew)
	if not pooled and arm != "fleet" and capacity + equipment * crew > int(repo.bal("army_split_cap_men")):
		return {"error": "The unit would exceed its ordinary personnel limit."}
	var composition := MilitaryRoster.composition(living + total, int(req["noble_permille"]), int(repo.bal("army_noble_cap_permille")))
	if composition.has("error"):
		return composition
	var added_nobles := int(composition["noble_troops"]) + 1 - existing_nobles
	if added_nobles < (1 if needs_officer else 0) or added_nobles > total:
		return {"error": "The requested final noble share cannot be reached by these reinforcements."}
	var officer := String(req["commander_id"])
	var refusal := MilitaryCommanders.candidate_error(repo, state, officer)
	if refusal != "" or not repo.commanders.has(officer):
		return {"error": refusal if refusal != "" else "Choose an eligible commander."}
	if (state.characters[officer] as Character).kingdom != realm or not arm in String(repo.commanders[officer]["unit_kinds"]).split("|"):
		return {"error": "The commander is not qualified for this realm and arm."}
	for cohort: Dictionary in state.military_cohorts.values():
		if cohort.get("person_id", "") == officer and int(cohort.get("released", 0)) != 1:
			if needs_officer or cohort.get("unit_code", "") != code or int(cohort.get("fit", 0)) != 1 or cohort.get("stage", "") != "active":
				return {"error": "The commander is already serving, assembling, or cannot serve."}
	var available := MilitaryPopulation.available(repo, state, province, String(req["source_population_field"]))
	for key: String in ["commoner_gold", "noble_gold", "commander_gold", "equipment_gold_per_element", "build_days"]:
		var raw := String(row.get(key, ""))
		if not raw.is_valid_int() or int(raw) < 0:
			return {"error": "Invalid recruitment contract: " + key}
	var gold := (total - added_nobles) * int(row["commoner_gold"]) + added_nobles * int(row["noble_gold"]) \
		+ (int(row["commander_gold"]) if needs_officer else 0) + equipment * int(row["equipment_gold_per_element"])
	if gold <= 0 or int(row["build_days"]) <= 0:
		return {"error": "Recruitment needs a positive price and assembly time."}
	var old_quality := Quality.profile(repo, state, code)
	var fit: Dictionary = old_quality["fit_by_identity"]
	var alive: Dictionary = old_quality["living_by_identity"]
	var quality := Quality.from_counts(repo, int(fit["commoner"]) + total - added_nobles, int(fit["noble"]) + added_nobles,
		int(alive["commoner"]) - int(fit["commoner"]), int(alive["noble"]) - int(fit["noble"]))
	var at := {"regiment_code": code, "x": repo.burgs[town]["x"], "y": repo.burgs[town]["y"], "is_naval": "1" if arm == "fleet" else "0"}
	var food_product := int(quality["supply_milli"]) * int(repo.bal("army_supply_per_head_permille")) * int(ArmySystem.height_tier(repo, at)["supply_permille"])
	@warning_ignore("integer_division")
	var food_month := maxi(1, food_product / 1_000_000_000) if food_product > 0 else 0
	var offer := {"gold": gold, "unit_code": code, "arm": arm, "equipment": {arm: equipment},
		"added_nobles": added_nobles, "needs_commander": needs_officer,
		"composition": {"commoners": total - added_nobles, "noble_troops": added_nobles - (1 if needs_officer else 0), "commander": 1 if needs_officer else 0},
		"final_composition": composition, "build_days": int(row["build_days"]),
		"earliest_completion_day": state.absolute_day() + int(row["build_days"]) - 1,
		"quality": quality, "food_per_month": food_month, "available_population": available}
	var refusals: Array[String] = []
	if available < total:
		refusals.append("There are not enough eligible civilians at this origin (%d available)." % available)
	if int(state.metrics.get("treasury", 0)) < gold:
		refusals.append("The treasury cannot pay the full recruitment price (%d gold)." % gold)
	if not refusals.is_empty():
		offer["error"] = " ".join(refusals)
	return offer

## The UI asks for legal choices, never invents a qualification rule.
static func available_commanders(repo: DataRepository, state: GameState, arm: String, code := "") -> Array[String]:
	var ids := repo.commanders.keys()
	ids.sort()
	var out: Array[String] = []
	for id: String in ids:
		if MilitaryCommanders.candidate_error(repo, state, id) != "" or (state.characters[id] as Character).kingdom != repo.resolve_realm("player_realm") \
				or not arm in String(repo.commanders[id]["unit_kinds"]).split("|"):
			continue
		var available := true
		for cohort: Dictionary in state.military_cohorts.values():
			if cohort.get("person_id", "") != id or int(cohort.get("released", 0)) == 1:
				continue
			if code == "" or cohort.get("unit_code", "") != code or cohort.get("stage", "") != "active" \
					or int(cohort.get("fit", 0)) != 1 or String(state.military_rosters.get(code, {}).get("commander_id", "")) != id:
				available = false
		if available:
			out.append(id)
	return out

static func recruit(repo: DataRepository, state: GameState, request: Dictionary) -> Dictionary:
	var previous := replay(state, request)
	if not previous.is_empty():
		return previous
	var req := normalize(request)
	var offer := quote(repo, state, req)
	if offer.has("error"):
		return offer
	var candidate := GameState.from_dict(state.to_dict(), false)
	var id := String(req["request_id"])
	var code := String(offer["unit_code"])
	var family := (state.characters[req["commander_id"]] as Character).family_name
	var rows: Array = []
	for kind: String in ["commoners", "noble_troops", "commander"]:
		var count := int(offer["composition"][kind])
		if count == 0:
			continue
		rows.append({"id": "recruit:" + id + ":" + kind, "unit_code": code, "count": count,
			"source_province": req["source_province"], "source_population_field": req["source_population_field"],
			"identity": "commoner" if kind == "commoners" else "noble", "stage": "assembling",
			"family_name": "" if kind == "commoners" else family,
			"person_id": req["commander_id"] if kind == "commander" else ""})
	var enlisted := MilitaryRoster.mobilize(repo, candidate, "recruit:" + id, rows, "paid military assembly at " + String(req["assembly_town"]))
	if enlisted.has("error"):
		return enlisted
	var paid := WorldLedger.apply(repo, candidate, "metrics.treasury", -int(offer["gold"]), "paid personnel and equipment for " + code, "recruit:" + id)
	if paid.has("error") or int(paid["delta"]) != -int(offer["gold"]):
		return {"error": "The treasury could not account for the complete price."}
	var result := {"status": "assembling", "request_id": id, "unit_code": code, "gold": int(offer["gold"]),
		"effects": [{"metric": "treasury", "delta": -int(offer["gold"]), "reason": paid["reason"]}]}
	candidate.recruitment_projects[id] = {"request": req, "unit_code": code, "cohort_ids": enlisted["cohort_ids"],
		"commander_id": req["commander_id"], "equipment": offer["equipment"], "build_days": offer["build_days"],
		"worked_days": 0, "last_processed_day": state.absolute_day() - 1, "status": "assembling", "pause_reason": "",
		"issued_day": state.absolute_day(), "quote": offer, "result": result}
	_commit(state, candidate)
	return result.duplicate(true)

static func step_day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	var ids := state.recruitment_projects.keys()
	ids.sort()
	for id: String in ids:
		var original: Dictionary = state.recruitment_projects[id]
		if original["status"] == "complete" or int(original["last_processed_day"]) >= state.absolute_day():
			continue
		var candidate := GameState.from_dict(state.to_dict(), false)
		var project: Dictionary = candidate.recruitment_projects[id]
		project["last_processed_day"] = state.absolute_day()
		var refusal := _progress_refusal(repo, candidate, project)
		if refusal == "":
			project["worked_days"] = int(project["worked_days"]) + 1
			if int(project["worked_days"]) >= int(project["build_days"]):
				refusal = _complete(repo, candidate, id)
				if refusal != "":
					# Failed completion must not publish partial units or activation.
					candidate = GameState.from_dict(state.to_dict(), false)
					project = candidate.recruitment_projects[id]
					project["last_processed_day"] = state.absolute_day()
		if refusal != "":
			project["status"] = "paused"
			project["pause_reason"] = refusal
		elif project["status"] != "complete":
			project["status"] = "assembling"
			project["pause_reason"] = ""
		_commit(state, candidate)
		events.append({"kind": "recruitment", "request_id": id, "status": project["status"],
			"reason": project.get("completion_reason", project["pause_reason"]),
			"composition": project.get("completion_composition", {}).duplicate(true)})
	return events

static func _progress_refusal(repo: DataRepository, state: GameState, project: Dictionary) -> String:
	var req: Dictionary = project["request"]
	var realm := repo.resolve_realm("player_realm")
	var town := String(req["assembly_town"])
	if not repo.burgs.has(town) or MapOwnership.owner_of(repo, state, String(req["source_province"])) != realm \
			or not ArmyGround.holds(repo, state, realm, town):
		return "The origin or assembly town is no longer held by the crown."
	var refusal := MilitaryCommanders.candidate_error(repo, state, String(project["commander_id"]))
	if refusal != "":
		return refusal
	for id: String in project["cohort_ids"]:
		var cohort: Dictionary = state.military_cohorts.get(id, {})
		if cohort.get("stage", "") != "assembling" or int(cohort.get("fit", 0)) != int(cohort.get("initial", -1)):
			return "The reserved personnel can no longer complete this assembly."
	if req["mode"] == "reinforce":
		if not bool(project["quote"]["needs_commander"]) and String(state.military_rosters.get(project["unit_code"], {}).get("commander_id", "")) != String(project["commander_id"]):
			return "The supervising commander is no longer fit or in command."
		for code: String in project.get("unit_codes", [project["unit_code"]]):
			if not state.army_roster.has(code) or not state.regiments.has(code) \
					or ArmySystem.realm_of(repo, code, state) != realm:
				return "The receiving unit is no longer available."
			var entry: Dictionary = state.regiments[code]
			if entry.get("order", "") == ArmySystem.ORDER_MARCH:
				return "The receiving unit must be physically present at the assembly town."
			if ArmySystem.is_naval(repo, state, code):
				var berth := _port_berth(repo, town)
				var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
				var reach := int(repo.bal("recruitment_port_reach_m"))
				if berth == ArmyGround.NONE or MarchClearance.dist2(here, berth) > reach * reach:
					return "The receiving fleet must be at the assembly port's water berth."
			elif ArmyGround.garrison_town(repo, state, code) != town:
				return "The receiving unit must be physically present at the assembly town."
			for battle: Dictionary in state.battles:
				if code in battle.get("att", []) or code in battle.get("def", []):
					return "The receiving unit is still in battle."
	return ""

static func _complete(repo: DataRepository, state: GameState, id: String) -> String:
	var project: Dictionary = state.recruitment_projects[id]
	var req: Dictionary = project["request"]
	var code := String(project["unit_code"])
	var town := String(req["assembly_town"])
	var arm := String(project["quote"]["arm"])
	var realm := repo.resolve_realm("player_realm")
	if req["mode"] == "new":
		if state.army_roster.has(code):
			return "The reserved unit identity is already in use."
		var row := {"regiment_code": code, "label": String(repo.burgs[town]["label"]) + " " + String(repo.world_table("military", "unit_types")[arm]["label"]),
			"kingdom_code": realm, "province_code": req["source_province"], "parent_code": code,
			"is_royal": "0", "is_naval": "1" if arm == "fleet" else "0", "camp_town": town,
			"x": String(repo.burgs[town]["x"]), "y": String(repo.burgs[town]["y"]), "source_parts": []}
		for kind: String in repo.world_table("military", "unit_types"):
			row[kind] = "0"
		if arm == "fleet":
			var berth := _port_berth(repo, town)
			if berth == ArmyGround.NONE:
				return "The port no longer has a legal water berth."
			var at := ArmySystem.metres_to_pack(repo, berth)
			row["x"] = str(at.x)
			row["y"] = str(at.y)
		state.army_roster[code] = row
		var entry := ArmySystem.starting_state(repo, row)
		entry["supplies"] = 0
		state.regiments[code] = entry
	var codes: Array = project.get("unit_codes", [code])
	for target: String in codes:
		var row: Dictionary = state.army_roster[target]
		var gear: Dictionary = project.get("equipment_by_unit", {}).get(target, project["equipment"] if codes.size() == 1 else {})
		for kind: String in gear:
			row[kind] = str(int(row.get(kind, 0)) + int(gear[kind]))
			if int(gear[kind]) > 0:
				row.get_or_add("source_parts", []).append({"regiment_code": "recruit:" + id, "province_code": req["source_province"],
					"arm": kind, "equipment_count": int(gear[kind]), "crew_per_element": int(repo.world_table("military", "unit_types")[kind]["crew"])})
	var activated := MilitaryRoster.activate(state, "recruit:complete:" + id, project["cohort_ids"], "completed paid assembly at " + town)
	if activated.has("error"):
		return String(activated["error"])
	if bool(project["quote"]["needs_commander"]):
		var appointed := MilitaryRoster.assign_commander(repo, state, code, String(project["commander_id"]), "command of the completed paid assembly")
		if appointed.has("error"):
			return String(appointed["error"])
	if req["mode"] == "new" and arm != "fleet":
		var centre := ArmyGround.town_point_m(repo, town)
		var taken := ArmyGround.held_taken(repo, state, code)
		var point := ArmyGround.free_slot(repo, centre, arm, taken, town)
		if point == ArmyGround.NONE:
			return "There is no legal camp space at the assembly town."
		ArmyGround._put(state.regiments[code], point)
		state.regiments[code]["camp_town"] = town
		LawSystem.on_settle(repo, state, code)
	project["status"] = "complete"
	project["pause_reason"] = ""
	project["completed_day"] = state.absolute_day()
	# The paid composition stays fixed. Subsequent casualties may change the
	# survivors' ratio; record the actual result rather than the old quote.
	var composition: Dictionary = {}
	for target: String in codes:
		var nobles := _nobles(state, target)
		var commander := 1 if String(state.military_rosters[target].get("commander_id", "")) != "" else 0
		composition[target] = {"commoners": MilitaryRoster.living(state, target) - nobles,
			"noble_troops": nobles - commander, "commander": commander}
	project["completion_composition"] = composition
	project["completion_reason"] = "Completed the fixed paid assembly; the recorded composition includes surviving personnel."
	return ""

## A port's adjoining sea cell, never a teleport to a distant ocean.
static func _port_berth(repo: DataRepository, town: String) -> Vector2i:
	var at := Vector2(float(repo.burgs[town]["x"]), float(repo.burgs[town]["y"]))
	var land := MapEconomy.cell_at(repo, at)
	if land < 0:
		return ArmySystem.pack_to_metres(repo, at)
	var best := ArmyGround.NONE
	var best_distance := -1
	var neighbors: PackedInt32Array = repo.cells[land].get("neighbor_ids", PackedInt32Array())
	neighbors = neighbors.duplicate()
	neighbors.sort()
	for id: int in neighbors:
		var cell: Dictionary = repo.cells.get(id, {})
		if not MapTerrain.is_sea(cell):
			continue
		var point := ArmySystem.pack_to_metres(repo, MapTerrain.cell_center(repo, cell))
		var distance := MarchClearance.dist2(point, ArmySystem.pack_to_metres(repo, at))
		if best_distance < 0 or distance < best_distance:
			best = point
			best_distance = distance
	return best

static func _nobles(state: GameState, code: String) -> int:
	var total := 0
	for id: String in state.military_rosters.get(code, {}).get("cohort_ids", []):
		var cohort: Dictionary = state.military_cohorts[id]
		if cohort["identity"] == "noble" and cohort["stage"] == "active":
			total += int(cohort["fit"]) + int(cohort["wounded"])
	return total

static func _commit(state: GameState, candidate: GameState) -> void:
	for field: String in ["military_rosters", "military_cohorts", "military_events", "recruitment_projects", "metrics", "world", "world_log", "army_roster", "regiments", "town_seat"]:
		state.set(field, candidate.get(field))
	LawSystem.commit_scopes(state, candidate)
