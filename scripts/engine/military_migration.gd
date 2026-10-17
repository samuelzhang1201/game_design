class_name MilitaryMigration
extends RefCounted
## Upgrade saved equipment and service without replaying costs or population deaths.

const VERSION: int = 1
const REASON: String = "initialize historical military service from saved equipment and recorded origins"
const STOCK_FIELDS: Array[String] = ["supplies", "desert_rem", "dead", "wounded", "deserted", "captured_current", "spoils", "plunder",
	"fee_milli", "buy_milli", "arrive_milli", "claim_milli", "skim_milli", "inventory", "inventories",
	"m_drawn", "m_arrived", "m_claimed", "m_skim", "m_fee", "m_buy"]

static func ensure(repo: DataRepository, state: GameState) -> Dictionary:
	if state.military_organization_version >= VERSION:
		return {"version": VERSION}
	if state.army_roster.is_empty():
		return {"error": "military migration requires the saved roster"}
	var plans: Dictionary = {}
	var errors: Array = []
	var codes := state.army_roster.keys()
	codes.sort()
	for code: String in codes:
		var plan := _plan(repo, state.army_roster[code], code)
		if plan.has("error"):
			state.military_migration_pending = true
			errors.append(plan)
			var province := String(state.army_roster[code].get("province_code", ""))
			if not province in state.military_conflicts: state.military_conflicts.append(province)
			continue
		for child: Dictionary in plan["children"]:
			var id := String(child["regiment_code"])
			if id != code and state.army_roster.has(id):
				return {"error": "derived military ID already exists: " + id}
		plans[code] = plan
	# Bootstrap unsplit personnel while the saved transaction still owns its IDs.
	for code: String in codes:
		if not plans.has(code): continue
		if state.military_rosters.has(code):
			continue
		var cohorts := _cohorts(repo, state, code, plans[code])
		if cohorts.has("error"):
			state.military_migration_pending = true
			return cohorts
		if (cohorts["cohorts"] as Array).is_empty():
			state.military_rosters[code] = {"cohort_ids": [], "commander_id": "", "appointments": []}
			continue
		var result := MilitaryRoster.initialize_historical(repo, state, "military:initial:" + code, cohorts["cohorts"], REASON)
		if result.has("error"):
			return result
	if not errors.is_empty():
		return {"error": "unresolved military migration", "conflicts": errors, "pending": true}
	if not state.day_resolution.is_empty():
		state.military_migration_pending = true
		return {"pending": true}
	var camps := _camp_positions(repo, state, plans)
	if camps.has("error"):
		state.military_migration_pending = true
		return camps
	var aliases: Dictionary = {}
	for code: String in codes:
		var children: Array = plans[code]["children"]
		var ids: Array = []
		var weights: Dictionary = {}
		for child: Dictionary in children:
			var id := String(child["regiment_code"])
			ids.append(id)
			weights[id] = MilitaryRoster.personnel_capacity(repo, child)
			state.army_roster[id] = child
		aliases[code] = ids
		if ids.size() > 1:
			_split_cohorts(state, code, ids, weights)
			for table: Dictionary in [state.regiments, state.foes, state.supply_lines]:
				_split_entry(table, code, ids, weights)
			for id: String in ids:
				for table: Dictionary in [state.regiments, state.foes]:
					if table.has(id):
						table[id]["dead"] = MilitaryRoster.count(state, id, "dead")
						table[id]["wounded"] = MilitaryRoster.count(state, id, "wounded")
						table[id]["deserted"] = MilitaryRoster.count(state, id, "released")
						table[id]["captured_current"] = MilitaryRoster.count(state, id, "captured_current")
			for id: String in ids.slice(1):
				var at: Vector2i = camps[id]
				var px := ArmySystem.metres_to_pack(repo, at)
				state.army_roster[id]["x"] = "%.3f" % px.x
				state.army_roster[id]["y"] = "%.3f" % px.y
				for table: Dictionary in [state.regiments, state.foes]:
					if table.has(id):
						table[id]["x_m"] = at.x
						table[id]["y_m"] = at.y
	_references(state, aliases)
	state.military_events["military:organization:1"] = {"kind": "organization", "reason": REASON,
		"aliases": aliases.duplicate(true), "equipment_note": "saved equipment preserved; unrecorded historical equipment destruction cannot be reconstructed"}
	state.military_unit_aliases = aliases
	state.military_organization_version = VERSION
	state.military_migration_pending = false
	var assignment_errors := BattleCommand.ensure_assignments(repo, state, REASON)
	return {"version": VERSION, "aliases": aliases.duplicate(true), "assignment_errors": assignment_errors}

static func _plan(repo: DataRepository, row: Dictionary, code: String) -> Dictionary:
	if MilitaryRoster.personnel_capacity(repo, row) < 0:
		return {"error": "invalid equipment or crew: " + code}
	var sources: Array = row.get("source_parts", []).duplicate(true)
	var children: Array = []
	var pieces: Array = []
	var naval := String(row.get("is_naval", "0")) == "1"
	var pooled := false
	for arm_row: Dictionary in repo.army_split:
		if bool(arm_row["pooled"]) and int(row.get(String(arm_row["arm"]), 0)) > 0:
			pooled = true
	if sources.is_empty():
		if pooled:
			return {"error": "unresolved legacy royal train provenance: " + code, "unit_code": code}
		for arm: String in repo.world_table("military", "unit_types"):
			if int(row.get(arm, 0)) > 0:
				sources.append(ArmySplit.source_part(repo, row, arm, int(row[arm])))
	if naval or pooled:
		pieces.append(row.duplicate(true))
	else:
		for arm: String in repo.world_table("military", "unit_types"):
			var elements := int(row.get(arm, 0))
			if elements <= 0:
				continue
			var crew := int(repo.world_row("military", "unit_types", arm)["crew"])
			var shares := ArmySplit.element_shares(elements, crew, int(repo.bal("army_split_cap_men")))
			if shares.is_empty():
				return {"error": "crew exceeds personnel cap: " + code}
			for share: int in shares:
				var child := row.duplicate(true)
				for other: String in repo.world_table("military", "unit_types"):
					child[other] = str(share if other == arm else 0)
				pieces.append(child)
	if pieces.is_empty():
		pieces.append(row.duplicate(true))
	for i: int in pieces.size():
		var child: Dictionary = pieces[i]
		child["regiment_code"] = code if i == 0 else "%s:military:%d" % [code, i + 1]
		child["source_parts"] = []
		children.append(child)
	# Source equipment is consumed in recorded order, never reconstructed from the new pack.
	var left: Array = sources.duplicate(true)
	for child: Dictionary in children:
		for arm: String in repo.world_table("military", "unit_types"):
			var need := int(child.get(arm, 0))
			for part: Dictionary in left:
				if String(part.get("arm", "")) != arm or need == 0:
					continue
				var amount := mini(need, int(part.get("equipment_count", 0)))
				if amount > 0:
					var claim := part.duplicate(true)
					claim["equipment_count"] = amount
					child["source_parts"].append(claim)
					part["equipment_count"] = int(part["equipment_count"]) - amount
					need -= amount
			if need != 0:
				return {"error": "source equipment does not cover saved force: " + code}
	for part: Dictionary in left:
		if int(part.get("equipment_count", 0)) != 0:
			return {"error": "source equipment exceeds saved force: " + code}
	for part: Dictionary in sources:
		var arm := String(part.get("arm", ""))
		if int(part.get("crew_per_element", 0)) != int(repo.world_row("military", "unit_types", arm).get("crew", 0)):
			return {"error": "historical crew disagrees with unit type: " + code}
	return {"children": children, "sources": sources}

static func _cohorts(repo: DataRepository, state: GameState, code: String, plan: Dictionary) -> Dictionary:
	var row: Dictionary = state.army_roster[code]
	var total := MilitaryRoster.personnel_capacity(repo, row)
	if total == 0:
		return {"cohorts": []}
	var out: Array = []
	for i: int in (plan["sources"] as Array).size():
		var part: Dictionary = plan["sources"][i]
		var province := String(part.get("province_code", ""))
		var arm := String(part.get("arm", ""))
		var type := repo.world_row("military", "unit_types", arm)
		var weights: Dictionary = {}
		for field: String in MilitaryPopulation.FIELDS:
			var population: Variant = WorldLedger.value_of(repo, state, "economy.provinces.%s.%s" % [province, field])
			if population == null:
				return {"error": "unknown historical source: " + code + ":" + province}
			var rate := float(type.get("rural_rate" if field == "rural_population" else "urban_rate", 0))
			weights[field] = roundi(float(population) * rate * 1000)
		if int(weights["rural_population"]) + int(weights["urban_population"]) <= 0:
			if not province in state.military_conflicts: state.military_conflicts.append(province)
			return {"error": "zero historical recruitment weights: " + code + ":" + province}
		var people := int(part["equipment_count"]) * int(part["crew_per_element"])
		var shares := TownStores.apportion(people, weights)
		for field: String in MilitaryPopulation.FIELDS:
			var amount := int(shares[field])
			if amount <= 0: continue
			out.append({"id": "%s:initial:%d:%s" % [code, i, field], "unit_code": code,
				"source_province": province, "source_population_field": field, "identity": "commoner", "family_name": "",
				"stage": "active", "initial": amount, "fit": amount, "wounded": 0, "dead": 0, "released": 0, "captured_current": 0})
	var entry: Dictionary = state.regiments.get(code, state.foes.get(code, {}))
	# These legacy counters already count people; their deaths were already charged.
	for pair: Array in [["dead", "dead"], ["wounded", "wounded"], ["deserted", "released"], ["captured_current", "captured_current"]]:
		var amount := int(entry.get(pair[0], 0))
		var weights: Dictionary = {}
		for cohort: Dictionary in out: weights[cohort["id"]] = int(cohort["fit"])
		var available := 0
		for n: int in weights.values(): available += n
		if amount < 0 or amount > available:
			return {"error": "legacy losses exceed saved personnel: " + code}
		var shares := TownStores.apportion(amount, weights)
		for cohort: Dictionary in out:
			var n := int(shares[cohort["id"]])
			cohort["fit"] = int(cohort["fit"]) - n
			cohort[pair[1]] = n
	# Reserve one counted fit noble per resulting unit, including transaction bootstrap.
	var needed := 0
	for child: Dictionary in plan["children"]:
		var capacity := MilitaryRoster.personnel_capacity(repo, child)
		@warning_ignore("integer_division")
		var nobles := maxi(1, capacity * int(repo.bal("army_initial_noble_permille")) / 1000)
		var cap := int(repo.bal("army_noble_cap_permille"))
		if capacity * cap >= 1000 and nobles * 1000 > capacity * cap:
			return {"error": "initial noble composition exceeds configured cap: " + code}
		needed += nobles
	var noble: Array = []
	for cohort: Dictionary in out:
		var amount := mini(needed, int(cohort["fit"]))
		if amount == 0: continue
		var named := cohort.duplicate(true)
		named["id"] = String(cohort["id"]) + ":noble"
		named["identity"] = "noble"
		for field: String in ["initial", "fit", "wounded", "dead", "released", "captured_current"]:
			named[field] = amount if field in ["initial", "fit"] else 0
		cohort["initial"] = int(cohort["initial"]) - amount
		cohort["fit"] = int(cohort["fit"]) - amount
		noble.append(named)
		needed -= amount
	out = out.filter(func(c: Dictionary) -> bool: return int(c["initial"]) > 0)
	out.append_array(noble)
	return {"cohorts": out}

static func _split_cohorts(state: GameState, code: String, ids: Array, weights: Dictionary) -> void:
	var old: Dictionary = state.military_rosters[code]
	var cohort_ids: Array = old["cohort_ids"].duplicate()
	for id: String in ids:
		state.military_rosters[id] = {"commander_id": old.get("commander_id", "") if id == code else "",
			"cohort_ids": [], "appointments": old.get("appointments", []).duplicate(true) if id == code else []}
	# Fill named/noble places first, then apportion remaining states within equipment capacity.
	cohort_ids.sort_custom(func(a: String, b: String) -> bool:
		var left: Dictionary = state.military_cohorts[a]
		var right: Dictionary = state.military_cohorts[b]
		var lr := 0 if String(left.get("person_id", "")) != "" else (1 if left["identity"] == "noble" else 2)
		var rr := 0 if String(right.get("person_id", "")) != "" else (1 if right["identity"] == "noble" else 2)
		return lr < rr if lr != rr else a < b)
	var remaining := weights.duplicate()
	var noble_places: Dictionary = {}
	for id: String in ids: noble_places[id] = 1
	for cohort_id: String in cohort_ids:
		var cohort: Dictionary = state.military_cohorts[cohort_id].duplicate(true)
		var allocations: Dictionary = {}
		for field: String in MilitaryRoster.STATES:
			var amount := int(cohort[field])
			var shares: Dictionary = {}
			if String(cohort.get("person_id", "")) != "":
				for id: String in ids: shares[id] = amount if id == code else 0
			elif cohort["identity"] == "noble" and field == "fit":
				var open := 0
				for n: int in noble_places.values(): open += n
				shares = TownStores.apportion(mini(amount, open), noble_places)
				for id: String in ids: noble_places[id] = int(noble_places[id]) - int(shares[id])
				if amount > open:
					var extra := TownStores.apportion(amount - open, remaining)
					for id: String in ids: shares[id] = int(shares[id]) + int(extra[id])
			else:
				shares = TownStores.apportion(amount, remaining)
			for id: String in ids: remaining[id] = int(remaining[id]) - int(shares[id])
			allocations[field] = shares
		if String(cohort.get("person_id", "")) != "" and cohort["identity"] == "noble" and int(cohort["fit"]) == 1:
			noble_places[code] = 0
		state.military_cohorts.erase(cohort_id)
		for i: int in ids.size():
			var id: String = ids[i]
			var child := cohort.duplicate(true)
			child["initial"] = 0
			for field: String in MilitaryRoster.STATES:
				child[field] = int(allocations[field][id])
				child["initial"] += int(child[field])
			if int(child["initial"]) == 0: continue
			child["id"] = cohort_id if i == 0 else cohort_id + ":" + id
			child["unit_code"] = id
			state.military_cohorts[child["id"]] = child
			state.military_rosters[id]["cohort_ids"].append(child["id"])

static func _split_entry(table: Dictionary, code: String, ids: Array, weights: Dictionary) -> void:
	if not table.has(code): return
	var old: Dictionary = table[code].duplicate(true)
	for id: String in ids: table[id] = old.duplicate(true)
	for field: String in old:
		if field in STOCK_FIELDS or field.ends_with("_milli") or field.begins_with("m_"):
			if old[field] is Dictionary:
				for key: String in old[field]:
					var shares := TownStores.apportion(int(old[field][key]), weights)
					for id: String in ids: table[id][field][key] = int(shares[id])
			elif old[field] is int:
				var shares := TownStores.apportion(int(old[field]), weights)
				for id: String in ids: table[id][field] = int(shares[id])

static func _camp_positions(repo: DataRepository, state: GameState, plans: Dictionary) -> Dictionary:
	var taken := ArmyGround.held_taken(repo, state, "")
	var positions: Dictionary = {}
	for code: String in plans:
		var original: Dictionary = state.army_roster[code]
		var centre := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, original))
		for row: Dictionary in (plans[code]["children"] as Array).slice(1):
			var id := String(row["regiment_code"])
			var arm := MapObjects.regiment_arm(repo, row)
			var town := String(row.get("camp_town", ""))
			var at := ArmyGround.free_slot(repo, centre, arm, taken, town)
			if at == ArmyGround.NONE and town != "":
				at = ArmyGround.free_slot(repo, centre, arm, taken, town, true)
			if at == ArmyGround.NONE:
				return {"error": "no legal adjacent migration camp: " + id}
			ArmyGround.take(taken, at, ArmyGround.arm_radius(repo, arm))
			positions[id] = at
	return positions

static func _references(state: GameState, aliases: Dictionary) -> void:
	for courier: Dictionary in state.couriers:
		state.next_courier_id = maxi(state.next_courier_id, int(courier.get("id", 0)))
	for stroke: Dictionary in (state.war_plans.get("strokes", {}) as Dictionary).values():
		if stroke.has("codes"): stroke["codes"] = _expand(stroke["codes"], aliases)
	for host: Dictionary in state.ai_hosts.values():
		if host.has("unit_codes"): host["unit_codes"] = _expand(host["unit_codes"], aliases)
	for battle: Dictionary in state.battles:
		for field: String in ["att", "def"]:
			var expanded: Array = []
			for code: String in battle.get(field, []): expanded.append_array(aliases.get(code, [code]))
			battle[field] = expanded
	for code: String in aliases:
		var ids: Array = aliases[code]
		if ids.size() <= 1: continue
		if state.war_drafts.has(code):
			for id: String in ids.slice(1): state.war_drafts[id] = state.war_drafts[code].duplicate(true)
		LawSystem.inherit_unit_laws(state, code, ids.slice(1))
		var extra: Array = []
		var order_maps: Dictionary = {}
		for id: String in ids.slice(1): order_maps[id] = _copy_order_ids(state, id)
		for courier: Dictionary in state.couriers:
			if String(courier.get("target", "")) != code: continue
			for id: String in ids.slice(1):
				var copy := courier.duplicate(true)
				copy["id"] = order_maps[id][int(courier["id"])]
				copy["target"] = id
				for order: Dictionary in copy.get("orders", []):
					if String(order.get("action_code", "")) == "ARMY_SEAT": order["action_code"] = "ARMY_GARRISON"
					for field: String in ["regiment", "regiment_code", "unit_code"]:
						if String(order.get(field, "")) == code: order[field] = id
						var params: Dictionary = order.get("params", {})
						if String(params.get(field, "")) == code: params[field] = id
				extra.append(copy)
		state.couriers.append_array(extra)

static func _expand(codes: Array, aliases: Dictionary) -> Array:
	var out: Array = []
	for code: String in codes: out.append_array(aliases.get(code, [code]))
	return out

## Reserve IDs in the old order, including delivered markers, so stale warrants stay stale.
static func _copy_order_ids(state: GameState, code: String) -> Dictionary:
	var old_ids: Dictionary = {}
	for courier: Dictionary in state.couriers:
		old_ids[int(courier["id"])] = true
	for table: Dictionary in [state.regiments, state.foes, state.supply_lines]:
		if not table.has(code): continue
		for field: String in ["order_id", "stance_order_id", "carry_order_id"]:
			if int(table[code].get(field, 0)) > 0: old_ids[int(table[code][field])] = true
		var pending: Dictionary = table[code].get("pending", {})
		if int(pending.get("order_id", 0)) > 0: old_ids[int(pending["order_id"])] = true
	var sorted_ids := old_ids.keys()
	sorted_ids.sort()
	var mapping: Dictionary = {}
	for old: int in sorted_ids:
		state.next_courier_id += 1
		mapping[old] = state.next_courier_id
	for table: Dictionary in [state.regiments, state.foes, state.supply_lines]:
		if not table.has(code): continue
		for field: String in ["order_id", "stance_order_id", "carry_order_id"]:
			var old := int(table[code].get(field, 0))
			if mapping.has(old): table[code][field] = mapping[old]
		var pending: Dictionary = table[code].get("pending", {})
		var old := int(pending.get("order_id", 0))
		if mapping.has(old): pending["order_id"] = mapping[old]
	return mapping
