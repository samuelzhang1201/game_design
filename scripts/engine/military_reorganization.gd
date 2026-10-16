class_name MilitaryReorganization
extends RefCounted
## Upgrade saved organizations on a private candidate; personnel history stays intact.
const Roster := preload("res://scripts/engine/military_roster.gd")
const Commanders := preload("res://scripts/engine/military_commanders.gd")
const REASON := "Saved military organization brought within personnel capacity"
const COUNTS := ["fit", "wounded", "captured_current", "dead", "released"]

static func reconcile(repo: DataRepository, state: GameState) -> Dictionary:
	if not bool(state.military_migration.get("organization_pending", false)):
		return {"status": "complete"}
	if not state.day_resolution.is_empty():
		return {"status": "deferred", "reason": "A day transaction is still running"}
	var candidate := GameState.from_dict(state.to_dict(), false)
	var result := _reconcile(repo, candidate)
	if result.get("status", "error") == "error":
		return result
	if candidate.military_migration == state.military_migration and result["status"] == "deferred":
		return result
	for field: String in ["army_roster", "military_rosters", "military_cohorts", "military_migration",
			"regiments", "foes", "supply_lines", "war_drafts", "scout_log", "couriers", "recruitment_projects"]:
		state.set(field, candidate.get(field))
	LawSystem.commit_scopes(state, candidate)
	return result

static func _reconcile(repo: DataRepository, state: GameState) -> Dictionary:
	var mapping: Dictionary = state.military_migration.get("unit_mapping", {}).duplicate(true)
	var cohorts: Dictionary = state.military_migration.get("cohort_mapping", {}).duplicate(true)
	var codes := state.army_roster.keys()
	codes.sort()
	var deferred: Array = []
	var changed := false
	for code: String in codes:
		if mapping.has(code):
			continue
		var plan := _plan(repo, state, code)
		if plan.has("error"):
			return {"status": "error", "error": plan["error"]}
		if (plan["units"] as Array).size() <= 1:
			continue
		if _in_battle(state, code):
			deferred.append(code)
			continue
		var error := _split(repo, state, code, plan, mapping, cohorts)
		if error != "":
			return {"status": "error", "error": error}
		changed = true
	if changed:
		state.military_migration["unit_mapping"] = mapping
		state.military_migration["cohort_mapping"] = cohorts
		state.military_migration["organization_reason"] = REASON
	if deferred.is_empty():
		state.military_migration["organization_pending"] = false
		state.military_migration["organization_version"] = 1
	return {"status": "complete" if deferred.is_empty() else "deferred", "deferred": deferred}

static func _in_battle(state: GameState, code: String) -> bool:
	for battle: Dictionary in state.battles:
		if bool(battle.get("ended", false)) or bool(battle.get("finished", false)):
			continue
		if code in battle.get("att", []) or code in battle.get("def", []):
			return true
	return false

static func _plan(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var unit: Dictionary = state.army_roster[code]
	var provenance := ArmySplit.saved_sources(repo, unit)
	if provenance.has("error"):
		return provenance
	if not state.military_rosters.has(code):
		return {"error": "Saved unit has no personnel roster: " + code}
	for id: String in state.military_rosters[code].get("cohort_ids", []):
		var cohort: Dictionary = state.military_cohorts.get(id, {})
		if cohort.is_empty() or cohort.get("unit_code", "") != code \
				or not repo.provinces.has(String(cohort.get("source_province", ""))) \
				or not String(cohort.get("source_population_field", "")) in ["rural_population", "urban_population"]:
			return {"error": "Invalid saved personnel origin or reference: " + id}
		var total := 0
		for count: String in COUNTS:
			if not ArmySplit.is_whole_count(cohort.get(count, -1)):
				return {"error": "Invalid saved personnel count: " + id}
			total += int(cohort[count])
		if total != int(cohort.get("initial", -1)) or (cohort.has("person_id") and total != 1):
			return {"error": "Invalid saved personnel identity: " + id}
	var pending := _pending_gear(state, code)
	var final := unit.duplicate(true)
	for gear: Dictionary in pending.values():
		for arm: String in gear:
			if not repo.world_table("military", "unit_types").has(arm) or not ArmySplit.is_whole_count(gear[arm]):
				return {"error": "Invalid pending paid equipment: " + code}
			final[arm] = str(int(final.get(arm, 0)) + int(gear[arm]))
	var capacity := Roster.personnel_capacity(repo, final)
	var cap := int(repo.bal("army_split_cap_men"))
	if cap <= 0:
		return {"error": "Personnel split capacity must be positive"}
	if capacity <= cap or String(unit.get("is_naval", "0")) == "1" or _train(repo, unit):
		return {"units": [unit]}
	var units: Array = []
	var final_capacity: Array = []
	var reserved_slots: Dictionary = {}
	var arms := repo.world_table("military", "unit_types").keys()
	arms.sort()
	for arm: String in arms:
		var count := int(final.get(arm, 0))
		if count <= 0:
			continue
		var crew := int(repo.world_row("military", "unit_types", arm)["crew"])
		@warning_ignore("integer_division")
		var equipment_cap := cap / crew
		if equipment_cap <= 0:
			return {"error": "An equipment crew exceeds ordinary personnel capacity"}
		var shares := ArmySplit.shares(count, equipment_cap)
		var current := BattleSystem.apportion(shares, int(unit.get(arm, 0)))
		var slots: Array = []
		for i: int in units.size():
			slots.append(0)
		for i: int in shares.size():
			var child := unit.duplicate(true)
			for key: String in arms:
				child[key] = "0"
			child[arm] = str(current[i])
			child["_organization_arm"] = arm
			child["source_parts"] = []
			units.append(child)
			final_capacity.append(int(shares[i]) * crew)
			slots.append(int(shares[i]) - int(current[i]))
		reserved_slots[arm] = slots
	for arm: String in reserved_slots:
		reserved_slots[arm].resize(units.size())
		for i: int in units.size():
			if reserved_slots[arm][i] == null:
				reserved_slots[arm][i] = 0
	var project_gear: Dictionary = {}
	var projects := pending.keys()
	projects.sort()
	for id: String in projects:
		var allocations: Array = []
		for child: Dictionary in units:
			allocations.append({})
		for arm: String in pending[id]:
			var amounts := BattleSystem.apportion(reserved_slots.get(arm, []), int(pending[id][arm]))
			for i: int in units.size():
				allocations[i][arm] = int(amounts[i])
				reserved_slots[arm][i] -= int(amounts[i])
		project_gear[id] = allocations
	# Consume each historical source part once, preserving its origin and crew.
	for part: Dictionary in provenance["parts"]:
		var left := int(part["equipment_count"])
		var arm := String(part["arm"])
		for child: Dictionary in units:
			var used := 0
			for held: Dictionary in child["source_parts"]:
				if held["arm"] == arm:
					used += int(held["equipment_count"])
			var take := mini(left, int(child.get(arm, 0)) - used)
			if take > 0:
				var fragment := part.duplicate(true)
				fragment["equipment_count"] = take
				child["source_parts"].append(fragment)
				left -= take
	return {"units": units, "final_capacity": final_capacity, "project_gear": project_gear}

static func _pending_gear(state: GameState, code: String) -> Dictionary:
	var out: Dictionary = {}
	for id: String in state.recruitment_projects:
		var project: Dictionary = state.recruitment_projects[id]
		var codes: Array = project.get("unit_codes", [project.get("unit_code", "")])
		if project.get("status", "") == "complete" or not code in codes:
			continue
		out[id] = (project.get("equipment_by_unit", {}).get(code, project.get("equipment", {}) if codes.size() == 1 else {}) as Dictionary).duplicate(true)
	return out

static func _train(repo: DataRepository, unit: Dictionary) -> bool:
	for row: Dictionary in repo.army_split:
		if bool(row.get("pooled", false)) and String(unit.get("regiment_code", "")) == "%s_%s" % [unit.get("kingdom_code", ""), row.get("code_word", "")]:
			return true
	return false

static func _split(repo: DataRepository, state: GameState, code: String, plan: Dictionary,
		mapping: Dictionary, cohort_mapping: Dictionary) -> String:
	var units: Array = plan["units"]
	var children: Array = []
	var weights: Array = []
	var taken := ArmyGround.new_taken(repo)
	for other: String in state.army_roster:
		var row: Dictionary = state.army_roster[other]
		if String(row.get("is_naval", "0")) != "1":
			ArmyGround.take(taken, ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, row)), ArmyGround.unit_radius(repo, row))
	var parent: Dictionary = state.army_roster[code]
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, parent))
	var town := ArmyGround.camped_by(repo, state, code)
	var centre := ArmyGround.town_point_m(repo, town) if town != "" else at
	for i: int in units.size():
		var child_code := code if i == 0 else code + ":organization:v1:" + str(i + 1)
		if i > 0 and (state.army_roster.has(child_code) or state.military_rosters.has(child_code)):
			return "Organization unit ID already exists: " + child_code
		children.append(child_code)
		weights.append(Roster.personnel_capacity(repo, units[i]))
		units[i]["regiment_code"] = child_code
		units[i]["organization_parent"] = code
		units[i]["organization_reason"] = REASON
		if i > 0:
			units[i]["is_royal"] = "0"
			var arm := String(units[i]["_organization_arm"])
			var slot := ArmyGround.free_slot(repo, centre, arm, taken, town)
			if slot == ArmyGround.NONE:
				return "No legal neighboring camp for " + child_code
			ArmyGround.take(taken, slot, ArmyGround.arm_radius(repo, arm))
			ArmySplit._put(repo, units[i], slot)
			units[i]["camp_town"] = town
		units[i].erase("_organization_arm")
		state.army_roster[child_code] = units[i]
	var error := _personnel(repo, state, code, children, weights, plan, cohort_mapping)
	if error != "":
		return error
	for field: String in ["regiments", "foes", "supply_lines", "war_drafts"]:
		var table: Dictionary = state.get(field)
		if not table.has(code):
			continue
		var old: Dictionary = table[code].duplicate(true)
		for i: int in children.size():
			var entry := old.duplicate(true)
			_quantities(entry, old, weights, i)
			if field in ["regiments", "foes"] and i > 0:
				var child_at := ArmySystem.pack_to_metres(repo, Vector2(float(units[i]["x"]), float(units[i]["y"])))
				entry["x_m"] = child_at.x
				entry["y_m"] = child_at.y
				entry["camp_town"] = town
				entry["organization_reason"] = REASON
				# A copied curved route must start from the child's actual camp.
				entry.erase("route_m")
			table[children[i]] = entry
	LawSystem.inherit_unit_scopes(state, code, children)
	if state.scout_log.has(code):
		for child: String in children:
			state.scout_log[child] = state.scout_log[code].duplicate(true)
	_remap_couriers(state, code, children)
	_remap_projects(state, code, children, weights, plan["project_gear"], cohort_mapping)
	mapping[code] = children
	return ""

static func _quantities(out: Dictionary, old: Dictionary, weights: Array, index: int) -> void:
	for key: String in old:
		if key in ["supplies", "spoils", "plunder", "fee_milli", "buy_milli", "arrive_milli", "claim_milli", "skim_milli", "desert_rem"] or key.begins_with("m_"):
			if old[key] is Dictionary:
				var amounts: Dictionary = {}
				for sub: String in old[key]:
					amounts[sub] = BattleSystem.apportion(weights, int(old[key][sub]))[index]
				out[key] = amounts
			elif old[key] is int or old[key] is float:
				out[key] = BattleSystem.apportion(weights, int(old[key]))[index]

static func _personnel(repo: DataRepository, state: GameState, code: String, children: Array,
		weights: Array, plan: Dictionary, mapping: Dictionary) -> String:
	var old: Dictionary = state.military_rosters[code].duplicate(true)
	var ids: Array = old.get("cohort_ids", [])
	var groups: Dictionary = {"active": []}
	var group_of: Dictionary = {}
	for id: String in ids:
		if state.military_cohorts[id].get("stage", "") == "active":
			groups["active"].append(id)
			group_of[id] = "active"
	var projects: Array = plan["project_gear"].keys()
	projects.sort()
	for project: String in projects:
		var group := "project:" + project
		groups[group] = []
		for id: String in state.recruitment_projects[project].get("cohort_ids", []):
			if not id in ids or state.military_cohorts[id].get("stage", "") != "assembling":
				continue
			if group_of.has(id):
				return "An assembling cohort belongs to multiple projects: " + id
			groups[group].append(id)
			group_of[id] = group
	if group_of.size() != ids.size():
		return "Assembling personnel need their saved paid project: " + code
	# Keep one active crew place in the original child for a paid commander
	# whose completion transaction appoints to that original unit code.
	var active_capacity: Array = weights.duplicate()
	var paid_commanders: Dictionary = {}
	var first_paid_commander_places := 0
	var needs_paid_commander := false
	for project: String in projects:
		var paid: Dictionary = state.recruitment_projects[project]
		if not bool(paid.get("quote", {}).get("needs_commander", false)):
			continue
		needs_paid_commander = true
		if not plan["project_gear"][project].is_empty():
			first_paid_commander_places = maxi(first_paid_commander_places,
				Roster.personnel_capacity(repo, plan["project_gear"][project][0]))
		for id: String in groups["project:" + project]:
			if state.military_cohorts[id].has("person_id"):
				paid_commanders[id] = true
				break
	if needs_paid_commander and not active_capacity.is_empty():
		var reserved_current_place := maxi(0, 1 - first_paid_commander_places)
		active_capacity[0] = maxi(0, int(active_capacity[0]) - reserved_current_place)
	var active_targets := _count_targets(state, groups["active"], active_capacity, String(old.get("commander_cohort_id", "")))
	if active_targets.has("error"):
		return String(active_targets["error"])
	var remaining: Dictionary = {"active": active_targets}
	var vacancies: Array = []
	for i: int in children.size():
		vacancies.append(int(weights[i]) - int(active_targets["fit"][i]) - int(active_targets["wounded"][i]))
	for project: String in projects:
		var room := vacancies.duplicate()
		for i: int in children.size():
			room[i] += Roster.personnel_capacity(repo, plan["project_gear"][project][i])
		var group := "project:" + project
		var commander_id := ""
		var paid_project: Dictionary = state.recruitment_projects[project]
		if bool(paid_project.get("quote", {}).get("needs_commander", false)):
			for id: String in groups[group]:
				if state.military_cohorts[id].has("person_id"):
					commander_id = id
					break
			if commander_id == "":
				return "A paid commander needs a named assembling cohort: " + project
		var targets := _count_targets(state, groups[group], room, commander_id)
		if targets.has("error"):
			return String(targets["error"])
		remaining[group] = targets
		for i: int in children.size():
			vacancies[i] = maxi(0, int(vacancies[i]) - int(targets["fit"][i]) - int(targets["wounded"][i]))
	for child: String in children:
		var roster := old.duplicate(true)
		roster["cohort_ids"] = []
		if child != code:
			roster["commander_id"] = ""
			roster["commander_cohort_id"] = ""
			roster["appointments"] = []
			roster["vacancy_reason"] = "Awaiting a qualified existing noble identity after reorganization"
		state.military_rosters[child] = roster
	# Named people reserve their indivisible place before anonymous aggregates.
	var ordered := ids.duplicate()
	ordered.sort_custom(func(a: String, b: String) -> bool:
		var named_a: bool = state.military_cohorts[a].has("person_id")
		var named_b: bool = state.military_cohorts[b].has("person_id")
		if named_a != named_b:
			return named_a
		return a < b)
	for id: String in ordered:
		var source: Dictionary = state.military_cohorts[id].duplicate(true)
		state.military_cohorts.erase(id)
		var targets: Dictionary = remaining[group_of[id]]
		var pieces: Array = []
		for child: String in children:
			var fragment := source.duplicate(true)
			fragment["unit_code"] = child
			fragment["initial"] = 0
			for count: String in COUNTS:
				fragment[count] = 0
			pieces.append(fragment)
		for count: String in COUNTS:
			var amount := int(source[count])
			var allocation: Array
			if source.has("person_id"):
				allocation = []
				allocation.resize(children.size())
				allocation.fill(0)
				if amount > 0:
					var recipient := 0 if id == old.get("commander_cohort_id", "") or paid_commanders.has(id) else _largest(targets[count])
					allocation[recipient] = amount
			else:
				allocation = BattleSystem.apportion(targets[count], amount)
			for i: int in children.size():
				pieces[i][count] = int(allocation[i])
				pieces[i]["initial"] += int(allocation[i])
				targets[count][i] -= int(allocation[i])
		var fragment_ids: Array = []
		for i: int in children.size():
			if int(pieces[i]["initial"]) == 0:
				continue
			var fragment_id := id if fragment_ids.is_empty() else id + ":organization:v1:" + str(i + 1)
			if state.military_cohorts.has(fragment_id):
				return "Organization cohort ID already exists: " + fragment_id
			pieces[i]["id"] = fragment_id
			pieces[i]["organization_reason"] = REASON
			state.military_cohorts[fragment_id] = pieces[i]
			state.military_rosters[children[i]]["cohort_ids"].append(fragment_id)
			fragment_ids.append(fragment_id)
		mapping[id] = fragment_ids
	for i: int in range(1, children.size()):
		_appoint_existing(repo, state, children[i], mapping)
	return ""

## Fit and wounded share one capacity budget; historical losses do not occupy crews.
static func _count_targets(state: GameState, ids: Array, capacities: Array, first: String) -> Dictionary:
	var totals: Dictionary = {}
	var forced: Dictionary = state.military_cohorts.get(first, {}) if first in ids else {}
	for count: String in COUNTS:
		totals[count] = 0
		for id: String in ids:
			totals[count] += int(state.military_cohorts[id][count])
	var room := capacities.duplicate()
	var forced_living := int(forced.get("fit", 0)) + int(forced.get("wounded", 0))
	if room.is_empty() or int(room[0]) < forced_living:
		return {"error": "The original commander needs an existing crew place"}
	room[0] -= forced_living
	var available := 0
	for n: int in room:
		available += n
	var living := int(totals["fit"]) + int(totals["wounded"]) - forced_living
	if living > available:
		return {"error": "Saved active or reserved personnel exceed planned crew headroom"}
	var living_targets := BattleSystem.apportion(room, living)
	var fit_targets := BattleSystem.apportion(living_targets, int(totals["fit"]) - int(forced.get("fit", 0)))
	var wounded_targets: Array = []
	for i: int in room.size():
		wounded_targets.append(int(living_targets[i]) - int(fit_targets[i]))
	fit_targets[0] += int(forced.get("fit", 0))
	wounded_targets[0] += int(forced.get("wounded", 0))
	var out := {"fit": fit_targets, "wounded": wounded_targets}
	var history_weights := capacities if capacities.any(func(n: int) -> bool: return n > 0) else range(1, capacities.size() + 1)
	for count: String in ["captured_current", "dead", "released"]:
		var allocation := BattleSystem.apportion(history_weights, int(totals[count]) - int(forced.get(count, 0)))
		allocation[0] += int(forced.get(count, 0))
		out[count] = allocation
	return out

static func _largest(values: Array) -> int:
	var best := 0
	for i: int in values.size():
		if int(values[i]) > int(values[best]):
			best = i
	return best

static func _appoint_existing(repo: DataRepository, state: GameState, code: String, mapping: Dictionary) -> void:
	# A qualified named soldier already assigned to this child takes precedence.
	for id: String in state.military_rosters[code]["cohort_ids"]:
		var cohort: Dictionary = state.military_cohorts[id]
		var person := String(cohort.get("person_id", ""))
		if person != "" and not Commanders.assign(repo, state, code, person, REASON).has("error"):
			state.military_rosters[code].erase("vacancy_reason")
			return
	var people := repo.commanders.keys()
	people.sort()
	for person: String in people:
		if Commanders.candidate_error(repo, state, person) != "":
			continue
		var available := true
		for cohort: Dictionary in state.military_cohorts.values():
			if cohort.get("person_id", "") == person:
				available = false
		if not available:
			continue
		var character: Character = state.characters[person] as Character
		var unit: Dictionary = state.army_roster[code]
		if character.kingdom != unit.get("kingdom_code", "") or not MapObjects.regiment_arm(repo, unit) in String(repo.commanders[person].get("unit_kinds", "")).split("|"):
			continue
		for id: String in (state.military_rosters[code]["cohort_ids"] as Array).duplicate():
			var cohort: Dictionary = state.military_cohorts[id]
			if cohort.get("identity", "") != "noble" or cohort.get("family_name", "") != character.family_name or cohort.has("person_id") or cohort.get("stage", "") != "active" or int(cohort["fit"]) <= 0:
				continue
			var officer_id := id + ":commander:" + person
			if state.military_cohorts.has(officer_id):
				continue
			var officer := cohort.duplicate(true)
			officer["id"] = officer_id
			officer["person_id"] = person
			officer["initial"] = 1
			for count: String in COUNTS:
				officer[count] = 1 if count == "fit" else 0
			cohort["initial"] -= 1
			cohort["fit"] -= 1
			state.military_cohorts[officer_id] = officer
			state.military_rosters[code]["cohort_ids"].append(officer_id)
			for source: String in mapping:
				if id in mapping[source]:
					mapping[source].append(officer_id)
			if int(cohort["initial"]) == 0:
				state.military_cohorts.erase(id)
				for roster: Dictionary in state.military_rosters.values():
					(roster["cohort_ids"] as Array).erase(id)
				for fragments: Array in mapping.values():
					fragments.erase(id)
			if not Commanders.assign(repo, state, code, person, REASON).has("error"):
				state.military_rosters[code].erase("vacancy_reason")
			return

static func _remap_couriers(state: GameState, code: String, children: Array) -> void:
	for courier: Dictionary in state.couriers:
		if courier.get("target", "") != code:
			continue
		if String(CourierSystem.first_order(courier).get("to_town", "")) != "":
			var targets: Array = courier.get("delivery_targets", [code]).duplicate()
			for child: String in children:
				if not child in targets:
					targets.append(child)
			courier["delivery_targets"] = targets
			continue
		var orders: Array = []
		for order: Dictionary in CourierSystem.orders_of(courier):
			if order.get("action_code", "") != "ARMY_SEAT":
				orders.append(order.duplicate(true))
		if orders.is_empty():
			continue
		var queue: Array = courier.get("recipient_queue", []).duplicate(true)
		for child: String in children.slice(1):
			var child_orders := orders.duplicate(true)
			for order: Dictionary in child_orders:
				if order.get("scope_key", "") == "unit:" + code:
					order["scope_key"] = "unit:" + child
			queue.append({"target": child, "orders": child_orders})
		courier["recipient_queue"] = queue

static func _remap_projects(state: GameState, code: String, children: Array, weights: Array,
		project_gear: Dictionary, mapping: Dictionary) -> void:
	for project_id: String in state.recruitment_projects:
		var project: Dictionary = state.recruitment_projects[project_id]
		var live_codes: Array = project.get("unit_codes", [project.get("unit_code", "")]).duplicate()
		if not code in live_codes:
			continue
		var expanded: Array = []
		for target: String in live_codes:
			expanded.append_array(children if target == code else [target])
		project["unit_codes"] = expanded
		var ids: Array = []
		for id: String in project.get("cohort_ids", []):
			ids.append_array(mapping.get(id, [id]))
		project["cohort_ids"] = ids
		var allocations: Dictionary = project.get("equipment_by_unit", {}).duplicate(true)
		allocations.erase(code)
		for i: int in children.size():
			var equipment: Dictionary = {}
			if project_gear.has(project_id):
				equipment = project_gear[project_id][i].duplicate(true)
			else:
				# Completed projects retain only a remapped allocation record.
				for arm: String in project.get("equipment", {}):
					equipment[arm] = BattleSystem.apportion(weights, int(project["equipment"][arm]))[i]
			allocations[children[i]] = equipment
		project["equipment_by_unit"] = allocations
