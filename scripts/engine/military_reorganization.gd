class_name MilitaryReorganization
extends RefCounted
## Saved living-cap migration is planned on one private, wholly disposable candidate.
const Roster := preload("res://scripts/engine/military_roster.gd")
const REASON := "Saved military units partitioned by assigned living personnel"
const COUNTS := ["fit", "wounded", "captured_current", "dead", "released"]

static func reconcile(repo: DataRepository, state: GameState) -> Dictionary:
	if int(state.military_migration.get("living_cap_version", 0)) == 2 \
			and not bool(state.military_migration.get("organization_pending", false)):
		return {"status": "complete"}
	if not state.day_resolution.is_empty():
		return {"status": "deferred", "reason": "A day transaction is still running"}
	var candidate := GameState.from_dict(state.to_dict(), false)
	var result := _reconcile(repo, candidate)
	if result.status == "error":
		return result
	if result.status == "deferred" and candidate.military_migration == state.military_migration:
		return result
	for field: String in ["army_roster", "military_rosters", "military_cohorts", "military_migration",
			"regiments", "foes", "supply_lines", "recruitment_projects", "battles", "ai_hosts", "war_plans", "unit_prize_gold"]:
		state.set(field, candidate.get(field))
	LawSystem.commit_scopes(state, candidate)
	return result

static func _reconcile(repo: DataRepository, state: GameState) -> Dictionary:
	var cap := int(repo.bal("army_living_cap_men"))
	if cap <= 0:
		return {"status": "error", "error": "Living personnel capacity must be positive"}
	var mapping: Dictionary = state.military_migration.get("living_unit_mapping", {}).duplicate(true)
	var cohorts: Dictionary = state.military_migration.get("living_cohort_mapping", {}).duplicate(true)
	var codes := state.army_roster.keys()
	codes.sort()
	var deferred: Array = []
	var changed := false
	for code: String in codes:
		var validation := _validate(repo, state, code)
		if validation.has("error"):
			return {"status": "error", "error": validation.error}
		var living := int(validation.living)
		if living <= cap:
			continue
		if _frozen(state, code):
			deferred.append(code)
			continue
		var targets := ArmySplit.halves(living, cap)
		var paths: Array[String] = []
		_paths(living, cap, "", paths)
		var error := _split(repo, state, code, targets, paths, validation.parts, mapping, cohorts)
		if error != "":
			return {"status": "error", "error": error}
		changed = true
	if changed:
		state.military_migration.living_unit_mapping = mapping
		state.military_migration.living_cohort_mapping = cohorts
		state.military_migration.living_reason = REASON
	if deferred.is_empty():
		state.military_migration.organization_pending = false
		state.military_migration.organization_version = 1
		state.military_migration.living_cap_version = 2
	elif changed:
		state.military_migration.organization_pending = true
	return {"status": "complete" if deferred.is_empty() else "deferred", "deferred": deferred}

static func _validate(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var provenance := ArmySplit.saved_sources(repo, state.army_roster[code])
	if provenance.has("error"):
		return provenance
	if not state.military_rosters.has(code):
		return {"error": "Saved unit has no personnel roster: " + code}
	var living := 0
	var ids: Dictionary = {}
	var people: Dictionary = {}
	for id: String in state.military_rosters[code].get("cohort_ids", []):
		var cohort: Dictionary = state.military_cohorts.get(id, {})
		if ids.has(id) or cohort.get("id", "") != id or cohort.get("unit_code", "") != code \
				or not repo.provinces.has(String(cohort.get("source_province", ""))) \
				or not String(cohort.get("source_population_field", "")) in ["rural_population", "urban_population"] \
				or not cohort.get("stage", "") in ["active", "assembling"]:
			return {"error": "Invalid saved personnel origin or reference: " + id}
		ids[id] = true
		var total := 0
		for count: String in COUNTS:
			if not ArmySplit.is_whole_count(cohort.get(count, -1)):
				return {"error": "Invalid saved personnel count: " + id}
			total += int(cohort[count])
		if total != int(cohort.get("initial", -1)) or (cohort.has("person_id") and total != 1):
			return {"error": "Invalid saved personnel identity: " + id}
		if cohort.has("person_id"):
			var person := String(cohort.person_id)
			if people.has(person):
				return {"error": "Duplicate saved named person: " + person}
			people[person] = true
		var promised := 0
		for promise: Dictionary in cohort.get("civilian_promises", []):
			if not ArmySplit.is_whole_count(promise.get("count", -1)):
				return {"error": "Invalid saved civilian promise: " + id}
			promised += int(promise.count)
		if promised > int(cohort.released):
			return {"error": "Civilian promises exceed released personnel: " + id}
		living += int(cohort.fit) + int(cohort.wounded)
		if cohort.stage == "assembling":
			var owners := 0
			for project: Dictionary in state.recruitment_projects.values():
				if project.get("status", "") != "complete" and id in project.get("cohort_ids", []):
					owners += 1
			if owners != 1:
				return {"error": "Assembling personnel need one saved paid project: " + id}
	return {"living": living, "parts": provenance.parts}

static func _frozen(state: GameState, code: String) -> bool:
	for battle: Dictionary in state.battles:
		if code in battle.get("att", []) or code in battle.get("def", []):
			if not (battle.get("pending_round", {}) as Dictionary).is_empty():
				return true
	return false

static func _in_battle(state: GameState, code: String) -> bool:
	for battle: Dictionary in state.battles:
		if not bool(battle.get("ended", false)) and not bool(battle.get("finished", false)) \
				and (code in battle.get("att", []) or code in battle.get("def", [])):
			return true
	return false

static func _paths(living: int, cap: int, path: String, out: Array[String]) -> void:
	if living <= cap:
		out.append(path)
		return
	@warning_ignore("integer_division")
	var small := living / 2
	_paths(living - small, cap, path + "0", out)
	_paths(small, cap, path + "1", out)

static func _split(repo: DataRepository, state: GameState, code: String, targets: Array[int],
		paths: Array[String], parts: Array, mapping: Dictionary, cohort_mapping: Dictionary) -> String:
	var parent: Dictionary = state.army_roster[code]
	var arm := MapObjects.regiment_arm(repo, parent)
	var units: Array = []
	var children: Array = [code]
	for i: int in range(1, targets.size()):
		var child := code + ":living:v2:" + paths[i]
		if state.army_roster.has(child) or state.military_rosters.has(child):
			return "Living organization unit ID already exists: " + child
		children.append(child)
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, parent))
	var town := ArmyGround.camped_by(repo, state, code)
	var battle := _in_battle(state, code)
	var naval := String(parent.get("is_naval", "0")) == "1"
	if naval:
		var point := ArmySystem.metres_to_pack(repo, at)
		if point.x < 0 or point.y < 0 or point.x > float(repo.map_info.get("width", 0)) \
				or point.y > float(repo.map_info.get("height", 0)) or MapEconomy.contains_land(repo, point):
			return "Saved fleet has no legal water point: " + code
		arm = "fleet"
	var taken := ArmyGround.held_taken(repo, state, "")
	var centre := ArmyGround.town_point_m(repo, town) if town != "" else at
	for i: int in children.size():
		var unit := parent.duplicate(true)
		unit.regiment_code = children[i]
		unit.organization_parent = code
		unit.organization_reason = REASON
		unit.organization_arm = arm
		unit.source_parts = []
		if i > 0:
			unit.is_royal = "0"
			var point := at
			if not naval and not battle:
				point = ArmyGround.free_slot(repo, centre, arm, taken, town)
				if point == ArmyGround.NONE:
					return "No legal neighboring camp for " + String(children[i])
				ArmyGround.take(taken, point, ArmyGround.arm_radius(repo, arm))
			ArmySplit._put(repo, unit, point)
			unit.camp_town = town if not battle else ""
		units.append(unit)
	for kind: String in repo.world_table("military", "unit_types"):
		var amounts := BattleSystem.apportion(targets, int(parent.get(kind, 0)))
		for i: int in children.size():
			units[i][kind] = str(amounts[i])
	for part: Dictionary in parts:
		var left := int(part.equipment_count)
		var kind := String(part.arm)
		for unit: Dictionary in units:
			var used := 0
			for assigned: Dictionary in unit.source_parts:
				if assigned.arm == kind: used += int(assigned.equipment_count)
			var take := mini(left, int(unit[kind]) - used)
			if take > 0:
				var fragment := part.duplicate(true)
				fragment.equipment_count = take
				unit.source_parts.append(fragment)
				left -= take
		if left != 0:
			return "Saved equipment source could not be allocated: " + code
	var error := _personnel(state, code, children, targets, paths, cohort_mapping)
	if error != "": return error
	for i: int in children.size():
		state.army_roster[children[i]] = units[i]
	for field: String in ["regiments", "foes", "supply_lines"]:
		var table: Dictionary = state.get(field)
		if not table.has(code): continue
		var old: Dictionary = table[code].duplicate(true)
		for i: int in children.size():
			var entry := old.duplicate(true)
			_quantities(entry, old, targets, i)
			if i > 0 and field == "supply_lines":
				entry.erase("pending")
			if i > 0 and field != "supply_lines":
				# Received intent and receipts belong to the retained source alone.
				for key: String in ["charge", "route_m", "waypoints_m", "hold_after", "stance_next", "stance_order_id",
						"dest_x_m", "dest_y_m", "order_id", "last_order_id", "carry_order_id", "departure", "camp_state", "battle_retreat",
						"withdrawal_reason", "withdrawal_dest", "gait", "gait_reason"]:
					entry.erase(key)
				entry.order = ArmySystem.ORDER_STANDBY
				var point := ArmySystem.pack_to_metres(repo, Vector2(float(units[i].x), float(units[i].y)))
				entry.x_m = point.x
				entry.y_m = point.y
				entry.camp_town = units[i].get("camp_town", "")
				entry.organization_reason = REASON
			table[children[i]] = entry
	if state.unit_prize_gold.has(code):
		var prizes := BattleSystem.apportion(targets, int(state.unit_prize_gold[code]))
		for i: int in children.size(): state.unit_prize_gold[children[i]] = int(prizes[i])
	LawSystem.inherit_unit_scopes(state, code, children)
	for current: Dictionary in state.battles:
		if bool(current.get("ended", false)) or bool(current.get("finished", false)): continue
		if not code in current.get("att", []) and not code in current.get("def", []): continue
		error = _battle(repo, state, current, code, children)
		if error != "": return error
	for host: Dictionary in state.ai_hosts.values():
		if host.has("unit_codes"): host.unit_codes = _expanded_codes(host.unit_codes, code, children)
	for stroke: Dictionary in state.war_plans.get("strokes", {}).values():
		if stroke.has("codes"): stroke.codes = _expanded_codes(stroke.codes, code, children)
	error = _projects(repo, state, code, children, targets, cohort_mapping)
	if error != "": return error
	mapping[code] = children
	return ""

static func _personnel(state: GameState, code: String, children: Array, targets: Array[int],
		paths: Array[String], mapping: Dictionary) -> String:
	var old: Dictionary = state.military_rosters[code].duplicate(true)
	var ids: Array = old.cohort_ids.duplicate()
	ids.sort()
	var ordered: Array = []
	var incumbent := String(old.get("commander_cohort_id", ""))
	if incumbent in ids: ordered.append(incumbent)
	# Paid commanders complete against the original unit, like the incumbent.
	for project: Dictionary in state.recruitment_projects.values():
		if project.get("status", "") == "complete" or not bool(project.get("quote", {}).get("needs_commander", false)): continue
		for id: String in ids:
			if id in project.get("cohort_ids", []) and state.military_cohorts[id].has("person_id") and not id in ordered:
				ordered.append(id)
	for id: String in ids:
		if state.military_cohorts[id].has("person_id") and not id in ordered: ordered.append(id)
	for id: String in ids:
		if not id in ordered: ordered.append(id)
	var room := targets.duplicate()
	var named_recipients: Dictionary = {}
	var allocations: Dictionary = {}
	for id: String in ordered:
		var source: Dictionary = state.military_cohorts[id]
		if not source.has("person_id"):
			allocations[id] = {}
			continue
		var living := int(source.fit) + int(source.wounded)
		var recipient := 0
		if living > 0:
			while recipient < room.size() and int(room[recipient]) == 0: recipient += 1
			if recipient >= room.size(): return "No room for named saved person: " + id
			room[recipient] -= living
		named_recipients[id] = recipient
	# All anonymous fit precede all anonymous wounded, in cohort-ID order.
	for count: String in ["fit", "wounded"]:
		for id: String in ordered:
			if named_recipients.has(id): continue
			var left := int(state.military_cohorts[id][count])
			var amounts: Array[int] = []
			for i: int in room.size():
				var take := mini(left, int(room[i]))
				amounts.append(take)
				room[i] -= take
				left -= take
			if left != 0: return "Saved living allocation exceeds its targets: " + id
			allocations[id][count] = amounts
	for child: String in children:
		var roster := old.duplicate(true)
		roster.cohort_ids = []
		if child != code:
			roster.commander_id = ""
			roster.commander_cohort_id = ""
			roster.appointments = []
			roster.vacancy_reason = "Awaiting a qualified existing noble identity after reorganization"
		state.military_rosters[child] = roster
	for id: String in ordered:
		var source: Dictionary = state.military_cohorts[id].duplicate(true)
		var pieces: Array = []
		for i: int in children.size():
			var piece := source.duplicate(true)
			piece.unit_code = children[i]
			for count: String in COUNTS: piece[count] = 0
			if i > 0: piece.erase("civilian_promises")
			pieces.append(piece)
		if source.has("person_id"):
			var recipient := int(named_recipients[id])
			var named := source.duplicate(true)
			named.unit_code = children[recipient]
			state.military_cohorts[id] = named
			state.military_rosters[children[recipient]].cohort_ids.append(id)
			mapping[id] = [id]
			continue
		for count: String in ["captured_current", "dead", "released"]: pieces[0][count] = int(source[count])
		for count: String in ["fit", "wounded"]:
			for i: int in children.size(): pieces[i][count] = int(allocations[id][count][i])
		var fragment_ids: Array = []
		for i: int in children.size():
			var piece: Dictionary = pieces[i]
			piece.initial = 0
			for count: String in COUNTS: piece.initial += int(piece[count])
			if i > 0 and int(piece.initial) == 0: continue
			var fragment_id := id if i == 0 else id + ":living:v2:" + paths[i]
			if i > 0 and state.military_cohorts.has(fragment_id): return "Living cohort ID already exists: " + fragment_id
			piece.id = fragment_id
			piece.organization_reason = REASON
			state.military_cohorts[fragment_id] = piece
			state.military_rosters[children[i]].cohort_ids.append(fragment_id)
			fragment_ids.append(fragment_id)
		mapping[id] = fragment_ids
	return ""

static func _quantities(out: Dictionary, old: Dictionary, weights: Array, index: int) -> void:
	for key: String in old:
		if key in ["supplies", "spoils", "plunder", "fee_milli", "buy_milli", "arrive_milli", "claim_milli", "skim_milli", "desert_rem", "inventory", "inventories"] or key.begins_with("m_") or key.ends_with("_milli"):
			if old[key] is Dictionary:
				var amounts: Dictionary = {}
				for sub: String in old[key]: amounts[sub] = BattleSystem.apportion(weights, int(old[key][sub]))[index]
				out[key] = amounts
			elif old[key] is int or old[key] is float:
				out[key] = BattleSystem.apportion(weights, int(old[key]))[index]

static func _battle(repo: DataRepository, state: GameState, battle: Dictionary, code: String, children: Array) -> String:
	var rows: Array = battle.get("groups", {}).get(code, [])
	var fit := 0
	for row: Dictionary in rows:
		if not ArmySplit.is_whole_count(row.get("count", -1)): return "Invalid saved battle group count: " + code
		fit += int(row.count)
	var expected := 0
	for child: String in children: expected += Roster.fit(state, child)
	if fit != expected: return "Saved battle groups disagree with fit personnel: " + code
	var row_index := 0
	var consumed := 0
	var next_slot := int(BattleSystem._stored(state, code).get("group_next_slot", 0))
	for i: int in rows.size():
		next_slot = maxi(next_slot, int(rows[i].get("slot", i)) + 1)
	for child: String in children:
		var groups: Array = []
		var left := Roster.fit(state, child)
		while left > 0:
			if row_index >= rows.size(): return "Saved battle groups exhausted: " + code
			var row: Dictionary = rows[row_index]
			var take := mini(left, int(row.count) - consumed)
			if take > 0:
				var fragment := row.duplicate(true)
				fragment.count = take
				fragment.slot = int(row.get("slot", row_index))
				groups.append(fragment)
				left -= take
				consumed += take
			if consumed == int(row.count):
				row_index += 1
				consumed = 0
		battle.get_or_add("groups", {})[child] = groups
		var entry := BattleSystem._stored(state, child)
		if not entry.is_empty(): entry.group_next_slot = next_slot
		if not battle.get("group_anchor_m", {}).has(child):
			var at := BattleSystem._at_m(repo, state, child)
			battle.get_or_add("group_anchor_m", {})[child] = [at.x, at.y]
		if child != code and not entry.is_empty():
			entry.living_hold_battle = int(battle["id"])
		if battle.get("group_facing", {}).has(code): battle.group_facing[child] = battle.group_facing[code]
		if child != code and battle.get("unit_formations", {}).has(code):
			battle.unit_formations[child] = battle.unit_formations[code].duplicate(true)
	for side: String in ["att", "def"]:
		if battle.has(side): battle[side] = _expanded_codes(battle[side], code, children)
	return ""

static func _projects(repo: DataRepository, state: GameState, code: String, children: Array,
		weights: Array[int], mapping: Dictionary) -> String:
	for project: Dictionary in state.recruitment_projects.values():
		if project.get("status", "") == "complete": continue
		var codes: Array = project.get("unit_codes", [project.get("unit_code", "")])
		if not code in codes: continue
		var ids: Array = []
		for id: String in project.get("cohort_ids", []): ids.append_array(mapping.get(id, [id]))
		project.cohort_ids = ids
		var gear: Dictionary = project.get("equipment_by_unit", {}).get(code, project.get("equipment", {}) if codes.size() == 1 else {})
		var allocations: Dictionary = project.get("equipment_by_unit", {}).duplicate(true)
		allocations.erase(code)
		for child: String in children: allocations[child] = {}
		for arm: String in gear:
			if not repo.world_table("military", "unit_types").has(arm) or not ArmySplit.is_whole_count(gear[arm]):
				return "Invalid pending paid equipment: " + code
			var amounts := BattleSystem.apportion(weights, int(gear[arm]))
			for i: int in children.size(): allocations[children[i]][arm] = int(amounts[i])
		project.equipment_by_unit = allocations
		project.unit_codes = _expanded_codes(codes, code, children)
	return ""

static func _expanded_codes(codes: Array, parent: String, children: Array) -> Array:
	var out: Array = []
	for code: String in codes:
		for child: String in children if code == parent else [code]:
			if not child in out: out.append(child)
	return out
