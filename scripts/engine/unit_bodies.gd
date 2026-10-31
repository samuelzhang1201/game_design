class_name UnitBodies
extends RefCounted
## Passive snapshots and isolated transactions only; no production writer calls here.

static func rows(_repo: DataRepository, state: GameState, unit: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or _entry(state, unit).is_empty() or _naval(state, unit): return out
	var index := _owners(state)
	if not index.error.is_empty(): return out
	var battle: Dictionary = index.owners.get(unit, {})
	var value: Variant = battle.get("groups", {}).get(unit) if not battle.is_empty() else _entry(state, unit).get("body_groups")
	if not value is Array: return out
	var current := battle.is_empty() or state.military_migration.has("body_version") or battle.has("body_version") or _entry(state, unit).has("body_reconciliation")
	var slots := {}
	var homes := {}
	for row: Variant in value:
		if not row is Dictionary or not _row_error(row, 0, current).is_empty(): return []
		if row.has("slot"):
			if slots.has(int(row.slot)): return []
			slots[int(row.slot)] = true
		if current:
			if homes.has(int(row.home_slot)): return []
			homes[int(row.home_slot)] = true
		out.append(row.duplicate(true))
	return out

static func footprint(repo: DataRepository, unit: String, state: GameState) -> Vector2i:
	var config := _config(repo, state, unit)
	return Vector2i(int(config.width_m), int(config.depth_m)) if not config.is_empty() else Vector2i.ZERO

static func home_slots(repo: DataRepository, state: GameState, unit: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var config := _config(repo, state, unit)
	if config.is_empty(): return out
	for i: int in int(config.files) * int(config.ranks):
		@warning_ignore("integer_division")
		var rank: int = i / int(config.files)
		out.append(Vector2i((2 * (i % int(config.files)) - int(config.files) + 1) * int(config.pitch_m) / 2,
			(2 * rank - int(config.ranks) + 1) * int(config.pitch_m) / 2))
	return out

static func migrate_candidate(repo: DataRepository, source: GameState) -> Dictionary:
	return _migration(repo, source)

static func reconcile_candidate(repo: DataRepository, source: GameState, unit: String, previous_fit: Variant) -> Dictionary:
	if repo == null or source == null: return _failure("Reconciliation requires data and source")
	var size := int(repo.bal("battle_group_size"))
	if not _whole(previous_fit) or float(previous_fit) < 0 or float(previous_fit) > size * 10:
		return _failure("Invalid raw previous fit")
	if not source.military_migration.has("body_version") or _entry(source, unit).is_empty() or _naval(source, unit):
		return _failure("Reconciliation requires an initialized land unit")
	for code: String in source.regiments.keys() + source.foes.keys():
		if _entry(source, code).has("body_reconciliation"): return _failure("Reconciliation cannot consume pending bodies")
	var validated := _migration(repo, source, unit, int(previous_fit))
	if validated.status != "complete": return validated
	var candidate: GameState = validated.candidate
	var index := _owners(candidate)
	var battle: Dictionary = index.owners.get(unit, {})
	var entry := _entry(candidate, unit)
	var saved: Array = entry.body_groups if battle.is_empty() else battle.groups[unit]
	var target := MilitaryRoster.fit(source, unit)
	var partition := BattleGroups.counts(target, size)
	var kept: Array[Dictionary] = []
	for i: int in mini(saved.size(), partition.size()):
		var row: Dictionary = saved[i]
		row.count = partition[i]
		kept.append(row)
	if battle.is_empty(): entry.body_groups = kept
	else: battle.groups[unit] = kept
	if kept.size() < partition.size():
		entry.body_reconciliation = {"version": 1, "basis_fit": int(previous_fit), "target_fit": target}
		candidate.military_migration.erase("body_version")
	# Reuse the same pending/complete validator; it cannot stage personnel twice.
	return _migration(repo, candidate)

static func _migration(repo: DataRepository, source: GameState, reconciled: String = "", previous_fit: int = 0) -> Dictionary:
	if repo == null or source == null: return _failure("Migration requires data and source state")
	if source.loaded_save_version < GameState.MIN_SAVE_VERSION or source.loaded_save_version > GameState.SAVE_VERSION:
		return _failure("Unsupported source save version")
	var size := int(repo.bal("battle_group_size"))
	if size <= 0: return _failure("Invalid configured group size")
	var index := _owners(source)
	if not index.error.is_empty(): return _failure(index.error)
	if not _control_ok(source.military_migration): return _failure("Invalid body version or descriptor store")
	for battle: Dictionary in source.battles:
		if BattleGroups.saved_size(repo, battle) <= 0:
			return _failure("Invalid saved battle group size/version")
	var frozen := _frozen(source)
	var current := source.military_migration.has("body_version")
	var candidate := _copy(source)
	var requests: Array[Dictionary] = []
	var envelopes: Array[Dictionary] = []
	for code: String in index.codes:
		var entry := _entry(source, code)
		if _naval(source, code):
			if entry.has("body_reconciliation"): return _failure("Fleet cannot have pending bodies")
			continue
		var config := _config(repo, source, code)
		if config.is_empty(): return _failure("Invalid measured configuration: " + code)
		if not _fit_valid(source, code, size * 10): return _failure("Invalid raw fit personnel: " + code)
		var fit := MilitaryRoster.fit(source, code)
		var expected := previous_fit if code == reconciled else fit
		var battle: Dictionary = index.owners.get(code, {})
		var pending := entry.has("body_reconciliation")
		var marked := current or battle.has("body_version") or pending or (battle.is_empty() and entry.has("body_groups"))
		var saved_size := size if battle.is_empty() else BattleGroups.saved_size(repo, battle)
		if marked and not battle.is_empty() and (not battle.has("body_version") or not _whole(battle.get("group_size_version")) or int(battle.group_size_version) != 2):
			return _failure("Current battle requires converted group-size markers: " + code)
		var basis_count := -1
		if pending:
			var descriptor: Variant = entry.body_reconciliation
			if not descriptor is Dictionary or descriptor.size() != 3: return _failure("Invalid reconciliation descriptor")
			for key: String in ["version", "basis_fit", "target_fit"]:
				if not _whole(descriptor.get(key)): return _failure("Invalid reconciliation " + key)
			if int(descriptor.version) != 1 or int(descriptor.basis_fit) < 0 or float(descriptor.basis_fit) > size * 10 or int(descriptor.target_fit) != fit or current:
				return _failure("Contradictory reconciliation descriptor")
			basis_count = BattleGroups.counts(int(descriptor.basis_fit), size).size()
			var target_count := BattleGroups.counts(fit, size).size()
			if basis_count >= target_count or target_count > 10: return _failure("Invalid reconciliation growth")
		var store: Dictionary = entry if battle.is_empty() else battle.get("groups", {})
		var field := "body_groups" if battle.is_empty() else code
		var value: Variant = store.get(field)
		var target_entry := _entry(candidate, code)
		var target_battle := _battle(candidate, int(battle.get("id", 0)))
		if not store.has(field):
			if marked: return _failure("Current unit missing bodies: " + code)
			if not battle.is_empty() and battle.has("groups"): return _failure("Present legacy groups omit a battle member: " + code)
			if not _counter_ok(entry, false): return _failure("Invalid slot counter")
			var request := _request(source, code, battle, "legacy_missing_pose", [], fit, size)
			if request.is_empty(): return _failure("Invalid placement anchor/facing")
			requests.append(request)
			continue
		if not value is Array: return _failure("Invalid body array: " + code)
		if not _counter_ok(entry, marked): return _failure("Missing or invalid slot counter")
		var normalized: Array[Dictionary] = []
		var slots := {}
		var homes := {}
		var total := 0
		var next := int(entry.get("group_next_slot", 0))
		for i: int in value.size():
			var raw: Variant = value[i]
			if not raw is Dictionary: return _failure("Invalid body row")
			var error := _row_error(raw, saved_size, marked)
			if not error.is_empty(): return _failure(error + ": " + code)
			var row: Dictionary = raw.duplicate(true)
			row.slot = int(row.get("slot", i))
			if slots.has(row.slot): return _failure("Duplicate body slot")
			slots[row.slot] = true
			if (marked or raw.has("slot")) and entry.has("group_next_slot") and int(entry.group_next_slot) <= int(row.slot):
				return _failure("Slot counter reuses identity")
			if int(row.slot) == 0x7fffffffffffffff: return _failure("Body slot has no representable successor")
			next = maxi(next, int(row.slot) + 1)
			for key: String in ["count", "x_m", "y_m", "home_slot", "facing_deg"]:
				if row.has(key): row[key] = int(row[key])
			if row.has("path_m"):
				for point: Array in row.path_m:
					point[0] = int(point[0])
					point[1] = int(point[1])
			if marked:
				if homes.has(row.home_slot): return _failure("Duplicate body home")
				homes[row.home_slot] = true
			total += int(row.count)
			normalized.append(row)
		if marked and normalized.size() > 10: return _failure("Current body overflow")
		if pending:
			if normalized.size() != basis_count: return _failure("Pending row count differs from basis")
			var partition := BattleGroups.counts(fit, size)
			for i: int in normalized.size():
				if int(normalized[i].count) != partition[i]: return _failure("Noncanonical pending counts")
		elif frozen:
			var frozen_fit := previous_fit if code == reconciled else _frozen_fit(source, code, battle)
			if total != frozen_fit: return _failure("Frozen bodies disagree with frozen personnel")
		else:
			if total != expected: return _failure("Bodies disagree with fit personnel")
		if not pending and value.is_empty() and expected > 0: return _failure("Present empty bodies are malformed")
		if marked and not pending and not _canonical(normalized, total, saved_size): return _failure("Noncanonical current counts")
		if frozen: continue
		var regroup := false
		if not marked:
			var regrouped := _regroup(normalized.duplicate(), total, size)
			regroup = saved_size != size or bool(battle.get("group_size_regroup_pending", false)) or regrouped != normalized
			normalized = regrouped
		homes.clear()
		var face := _facing(entry, battle, code)
		if face < 0: return _failure("Invalid legacy facing")
		for i: int in normalized.size():
			var row: Dictionary = normalized[i]
			if not marked:
				if regroup or not row.has("home_slot"): row.home_slot = i
				if not row.has("facing_deg"): row.facing_deg = face
			if not _row_error(row, size, true).is_empty() or homes.has(row.home_slot): return _failure("Invalid converted body")
			homes[row.home_slot] = true
			envelopes.append({"x": row.x_m, "y": row.y_m, "radius": int(config.radius_m), "unit": code})
		if normalized.size() > 10: return _failure("Converted body overflow")
		target_entry.group_next_slot = next
		if battle.is_empty(): target_entry.body_groups = normalized
		else:
			if not target_battle.has("groups"): target_battle.groups = {}
			target_battle.groups[code] = normalized
			target_battle.body_version = 1
			target_battle.group_size_version = 2
			target_battle.group_size_men = size
			if regroup:
				target_battle.erase("group_size_regroup_pending")
				target_battle.group_size_reason = "Saved fit groups regrouped at a safe transaction boundary"
		if pending:
			var request := _request(source, code, battle, "reconciliation_requires_pose", normalized, fit, size)
			if request.is_empty(): return _failure("Invalid pending anchor/facing")
			requests.append(request)
	if frozen: return _result("deferred", "Frozen day or round retains original body transaction")
	for i: int in envelopes.size():
		for j: int in range(i):
			var a: Dictionary = envelopes[i]
			var b: Dictionary = envelopes[j]
			var dx: int = a.x - b.x
			var dy: int = a.y - b.y
			var radius: int = a.radius + b.radius
			if dx * dx + dy * dy < radius * radius: return _failure("Measured bodies overlap: %s / %s" % [a.unit, b.unit])
	for battle: Dictionary in candidate.battles:
		if _live(battle) and battle.att.is_empty() and battle.def.is_empty():
			battle.body_version = 1
			battle.group_size_version = 2
			battle.group_size_men = size
			if not battle.has("groups"): battle.groups = {}
	requests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.unit < b.unit or (a.unit == b.unit and a.battle_id < b.battle_id))
	if requests.is_empty(): candidate.military_migration.body_version = 1
	else: candidate.military_migration.erase("body_version")
	return _result("complete" if requests.is_empty() else "needs_placement", "Validated isolated body candidate", candidate, requests)

static func _fit_valid(state: GameState, code: String, cap: int) -> bool:
	var total := 0
	for id: Variant in state.military_rosters.get(code, {}).get("cohort_ids", []):
		var cohort: Variant = state.military_cohorts.get(id)
		if not cohort is Dictionary: return false
		if cohort.get("stage") != "active": continue
		if not _whole(cohort.get("fit")) or float(cohort.fit) < 0 or float(cohort.fit) > cap: return false
		total += int(cohort.fit)
	return total <= cap

static func transfer_candidate(source: GameState, unit: String, from_battle_id: int, to_battle_id: int) -> Dictionary:
	if source == null or from_battle_id < 0 or to_battle_id < 0 or from_battle_id == to_battle_id:
		return _failure("Invalid transfer endpoints")
	if source.loaded_save_version < GameState.MIN_SAVE_VERSION or source.loaded_save_version > GameState.SAVE_VERSION:
		return _failure("Unsupported transfer source save version")
	if not _control_ok(source.military_migration) or not source.military_migration.has("body_version"):
		return _failure("Transfer requires initialized current bodies")
	var index := _owners(source)
	if not index.error.is_empty(): return _failure(index.error)
	if not index.codes.has(unit) or _naval(source, unit): return _failure("Unknown land unit")
	var from := _battle(source, from_battle_id)
	var to := _battle(source, to_battle_id)
	if (from_battle_id > 0 and from.is_empty()) or (to_battle_id > 0 and to.is_empty()):
		return _failure("Unknown transfer battle")
	var group_size := 0
	for battle: Dictionary in source.battles:
		if not _live(battle): continue
		if not battle.has("body_version") or not _control_ok(battle) or not battle.get("groups") is Dictionary \
				or not _whole(battle.get("group_size_version")) or int(battle.group_size_version) != 2:
			return _failure("Incompatible transfer battle schema")
		if not _whole(battle.get("group_size_men")) or int(battle.group_size_men) <= 0:
			return _failure("Invalid transfer group size")
		if group_size > 0 and group_size != int(battle.group_size_men):
			return _failure("Incompatible transfer group sizes")
		group_size = int(battle.group_size_men)
	for code: String in index.codes:
		var entry := _entry(source, code)
		if entry.has("body_reconciliation"): return _failure("Pending reconciliation cannot transfer")
		if _naval(source, code): continue
		var battle: Dictionary = index.owners.get(code, {})
		if not _fit_valid(source, code, group_size * 10): return _failure("Invalid transfer fit personnel")
		if not _counter_ok(entry, true): return _failure("Invalid transfer slot counter: " + code)
		var saved: Variant = entry.get("body_groups") if battle.is_empty() else battle.get("groups", {}).get(code)
		if not saved is Array: return _failure("Missing transfer bodies: " + code)
		var slots := {}
		var homes := {}
		var total := 0
		for row: Variant in saved:
			if not row is Dictionary or not _row_error(row, 0, true).is_empty(): return _failure("Malformed transfer rows")
			if slots.has(row.slot) or homes.has(row.home_slot) or int(row.slot) >= int(entry.group_next_slot):
				return _failure("Duplicate or reused transfer identities")
			slots[row.slot] = true
			homes[row.home_slot] = true
			total += int(row.count)
		if saved.size() > 10 or total != MilitaryRoster.fit(source, code) or not _canonical(saved, total, group_size): return _failure("Invalid initialized transfer counts")
	if _frozen(source): return _result("deferred", "Frozen day or battle round prevents ownership transfer")
	var owner: Dictionary = index.owners.get(unit, {})
	var owner_id := int(owner.get("id", 0))
	if owner_id == to_battle_id:
		return _result("complete", "Ownership transfer already applied", _copy(source))
	if owner_id != from_battle_id: return _failure("Unit is not owned by transfer source")
	var side := ""
	if to_battle_id > 0:
		if from_battle_id > 0: side = "att" if unit in from.att else "def"
		else:
			var realm := _realm(source, unit)
			for target_side: String in ["att", "def"]:
				var realms := {}
				for member: String in to[target_side]: realms[_realm(source, member)] = true
				if realm != "" and realms.size() == 1 and realms.has(realm):
					if side != "": return _failure("Ambiguous destination realm side")
					side = target_side
			if side == "": return _failure("No unambiguous destination realm side")
	var candidate := _copy(source)
	var entry := _entry(candidate, unit)
	var src := _battle(candidate, from_battle_id)
	var dst := _battle(candidate, to_battle_id)
	var moving: Array = entry.body_groups if from_battle_id == 0 else src.groups[unit]
	var metadata := {}
	for field: String in ["group_facing", "group_anchor_m"]:
		if from_battle_id == 0 and entry.has(field):
			metadata[field] = entry[field]
			entry.erase(field)
		elif src.get(field, {}).has(unit): metadata[field] = src[field][unit]
	if from_battle_id == 0: entry.erase("body_groups")
	else:
		for old_side: String in ["att", "def"]: src[old_side].erase(unit)
		for field: String in ["groups", "group_facing", "group_anchor_m"]:
			if src.has(field): src[field].erase(unit)
	if to_battle_id == 0:
		entry.body_groups = moving
		for field: String in metadata: entry[field] = metadata[field]
	else:
		dst[side].append(unit)
		dst.groups[unit] = moving
		for field: String in ["group_facing", "group_anchor_m"]:
			if metadata.has(field):
				if not dst.has(field): dst[field] = {}
				dst[field][unit] = metadata[field]
	return _result("complete", "Transferred body ownership without movement", candidate)

static func _entry(state: GameState, code: String) -> Dictionary:
	var value: Variant = state.foes.get(code, state.regiments.get(code, {}))
	return value if value is Dictionary else {}

static func _naval(state: GameState, code: String) -> bool:
	return str(state.army_roster.get(code, {}).get("is_naval", "0")) == "1"

static func _realm(state: GameState, code: String) -> String:
	return str(state.army_roster.get(code, {}).get("kingdom_code", ""))

static func _live(battle: Dictionary) -> bool:
	return not bool(battle.get("ended", false)) and not bool(battle.get("finished", false))

static func _battle(state: GameState, id: int) -> Dictionary:
	if id == 0: return {}
	for battle: Dictionary in state.battles:
		if _live(battle) and int(battle.get("id", -1)) == id: return battle
	return {}

static func _owners(state: GameState) -> Dictionary:
	var owners := {}
	var codes: Array = state.regiments.keys()
	for code: Variant in state.foes:
		if codes.has(code): return {"error": "Duplicate regiment/foe owner", "codes": [], "owners": {}}
		codes.append(code)
	var ids := {}
	for raw: Variant in state.battles:
		if not raw is Dictionary: return {"error": "Invalid battle", "codes": [], "owners": {}}
		var battle: Dictionary = raw
		if not _control_ok(battle): return {"error": "Invalid battle body controls", "codes": [], "owners": {}}
		if battle.has("group_size_version") and (not _whole(battle.group_size_version) or int(battle.group_size_version) not in [1, 2]):
			return {"error": "Unknown saved group version", "codes": [], "owners": {}}
		if battle.has("body_version") and (not _whole(battle.get("group_size_version")) or int(battle.group_size_version) != 2 \
			or not _whole(battle.get("group_size_men")) or int(battle.group_size_men) <= 0):
			return {"error": "Current battle requires explicit group-size metadata", "codes": [], "owners": {}}
		if not _live(battle): continue
		if battle.has("pending_round") and not battle.pending_round is Dictionary:
			return {"error": "Invalid frozen transaction", "codes": [], "owners": {}}
		if not _whole(battle.get("id")) or int(battle.id) <= 0 or ids.has(int(battle.id)):
			return {"error": "Invalid or duplicate battle ID", "codes": [], "owners": {}}
		ids[int(battle.id)] = true
		for field: String in ["groups", "group_facing", "group_anchor_m"]:
			if battle.has(field) and not battle[field] is Dictionary:
				return {"error": "Invalid battle body metadata", "codes": [], "owners": {}}
		var members := {}
		for side: String in ["att", "def"]:
			if not battle.get(side) is Array: return {"error": "Invalid battle side", "codes": [], "owners": {}}
			for code: Variant in battle[side]:
				if not code is String or not codes.has(code) or owners.has(code) or members.has(code):
					return {"error": "Invalid or duplicate battle member", "codes": [], "owners": {}}
				members[code] = true
				owners[code] = battle
		for field: String in ["groups", "group_facing", "group_anchor_m"]:
			for code: Variant in battle.get(field, {}):
				if not members.has(code): return {"error": "Orphan battle body metadata", "codes": [], "owners": {}}
				var value: Variant = battle[field][code]
				if field == "group_facing" and (not _whole(value) or int(value) < 0 or int(value) >= 360):
					return {"error": "Invalid saved group facing", "codes": [], "owners": {}}
				if field == "group_anchor_m" and not _pair(value):
					return {"error": "Invalid saved group anchor", "codes": [], "owners": {}}
	for code: Variant in codes:
		if not code is String or not state.foes.get(code, state.regiments.get(code)) is Dictionary:
			return {"error": "Invalid unit entry", "codes": [], "owners": {}}
		var entry := _entry(state, code)
		if owners.has(code) and (entry.has("body_groups") or entry.has("group_facing") or entry.has("group_anchor_m")):
			return {"error": "Duplicate battle/nonbattle body ownership", "codes": [], "owners": {}}
		if (entry.has("group_facing") or entry.has("group_anchor_m")) and not entry.has("body_groups"):
			return {"error": "Current body metadata requires its row store", "codes": [], "owners": {}}
		if entry.has("group_facing") and (not _whole(entry.group_facing) or int(entry.group_facing) < 0 or int(entry.group_facing) >= 360):
			return {"error": "Invalid nonbattle body facing", "codes": [], "owners": {}}
		if entry.has("group_anchor_m") and not _pair(entry.group_anchor_m):
			return {"error": "Invalid nonbattle body anchor", "codes": [], "owners": {}}
	codes.sort()
	return {"error": "", "codes": codes, "owners": owners}

static func _config(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	if repo == null or state == null or not state.army_roster.has(code) or _naval(state, code): return {}
	var piece := MapObjects.army_piece(repo, state.army_roster[code])
	var config: Dictionary = repo.unit_footprints.get(piece, {})
	for field: String in ["radius_m", "pitch_m", "width_m", "depth_m", "files", "ranks"]:
		if not _whole(config.get(field)) or int(config[field]) <= 0: return {}
	if int(config.files) * int(config.ranks) != 10: return {}
	if int(config.width_m) != (int(config.files) - 1) * int(config.pitch_m) + 2 * int(config.radius_m) \
			or int(config.depth_m) != (int(config.ranks) - 1) * int(config.pitch_m) + 2 * int(config.radius_m) \
			or int(config.pitch_m) < 2 * int(config.radius_m): return {}
	return config

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _whole(value[0]) and _whole(value[1])

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value))

static func _control_ok(record: Dictionary) -> bool:
	# Global/battle records cannot own a unit's reconciliation descriptor.
	return not record.has("body_reconciliation") and (not record.has("body_version") \
		or (_whole(record.body_version) and int(record.body_version) == 1))

static func _counter_ok(entry: Dictionary, required: bool) -> bool:
	return (not required and not entry.has("group_next_slot")) or (_whole(entry.get("group_next_slot")) and int(entry.group_next_slot) >= 0)

static func _row_error(row: Dictionary, size: int, current: bool) -> String:
	if row.has("body_reconciliation"): return "Reconciliation descriptor belongs on the unit entry"
	for field: String in ["count", "x_m", "y_m"]:
		if not _whole(row.get(field)): return "Invalid body " + field
	if int(row.count) <= 0 or (size > 0 and int(row.count) > size) or row.get("role") not in ["front", "reserve"]:
		return "Invalid body count/role"
	for field: String in ["slot", "home_slot", "facing_deg"]:
		if (current or row.has(field)) and (not _whole(row.get(field)) or int(row[field]) < 0): return "Invalid body " + field
	if row.has("home_slot") and current and int(row.home_slot) >= 10: return "Invalid body home"
	if row.has("facing_deg") and int(row.facing_deg) >= 360: return "Invalid body facing"
	if row.has("path_m"):
		if not row.path_m is Array: return "Invalid body path"
		for point: Variant in row.path_m:
			if not _pair(point): return "Invalid body path point"
	return ""

static func _canonical(saved: Array, total: int, size: int) -> bool:
	var counts := BattleGroups.counts(total, size)
	if counts.size() != saved.size(): return false
	for i: int in counts.size():
		if int(saved[i].count) != counts[i]: return false
	return true

static func _regroup(saved: Array[Dictionary], total: int, size: int) -> Array[Dictionary]:
	saved.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.slot) < int(b.slot))
	var out: Array[Dictionary] = []
	var cursor := 0
	var consumed := 0
	for amount: int in BattleGroups.counts(total, size):
		var row: Dictionary = saved[cursor].duplicate(true)
		row.count = amount
		out.append(row)
		var left := amount
		while left > 0:
			var take := mini(left, int(saved[cursor].count) - consumed)
			left -= take
			consumed += take
			if consumed == int(saved[cursor].count):
				cursor += 1
				consumed = 0
	return out

static func _facing(entry: Dictionary, battle: Dictionary, code: String) -> int:
	var value: Variant = entry.get("facing_deg", battle.get("group_facing", {}).get(code, 0))
	return int(value) if _whole(value) and int(value) >= 0 and int(value) < 360 else -1

static func _request(state: GameState, code: String, battle: Dictionary, reason: String, saved: Array,
		fit: int, size: int) -> Dictionary:
	var entry := _entry(state, code)
	if not _whole(entry.get("x_m")) or not _whole(entry.get("y_m")): return {}
	var face := _facing(entry, battle, code)
	if face < 0: return {}
	var occupied := {}
	for row: Dictionary in saved: occupied[int(row.home_slot)] = true
	var missing: Array[int] = []
	for i: int in 10:
		if missing.size() == BattleGroups.counts(fit, size).size() - saved.size(): break
		if not occupied.has(i): missing.append(i)
	return {"unit": code, "battle_id": int(battle.get("id", 0)), "reason": reason,
		"anchor_m": [int(entry.x_m), int(entry.y_m)], "facing_deg": face, "missing_home_slots": missing}

static func _frozen_fit(state: GameState, code: String, battle: Dictionary) -> int:
	var fit := MilitaryRoster.fit(state, code)
	if battle.is_empty(): return fit
	var pending: Dictionary = battle.get("pending_round", {})
	var id := "battle:%d:round:%d:personnel" % [int(battle.id), int(pending.get("round", -1))]
	for change: Dictionary in state.military_events.get(id, {}).get("result", {}).get("changes", []):
		if state.military_cohorts.get(change.get("cohort_id"), {}).get("unit_code") != code: continue
		if change.get("from") == "fit": fit += int(change.count)
		if change.get("to") == "fit": fit -= int(change.count)
	return fit

static func _frozen(state: GameState) -> bool:
	if not state.day_resolution.is_empty(): return true
	for battle: Dictionary in state.battles:
		if _live(battle) and not battle.get("pending_round", {}).is_empty(): return true
	return false

static func _copy(source: GameState) -> GameState:
	# Save loading normalizes legacy fields; a transaction must instead preserve every raw extension.
	var candidate := GameState.new()
	for property: Dictionary in source.get_property_list():
		if not int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: continue
		var key := String(property.name)
		var value: Variant = source.get(key)
		if key == "characters":
			var chars := {}
			for id: String in source.characters: chars[id] = Character.from_dict(source.characters[id].to_dict())
			candidate.characters = chars
		elif key == "rng": candidate.rng = Rng.from_dict(source.rng.to_dict())
		else: candidate.set(key, value.duplicate(true) if value is Dictionary or value is Array else value)
	return candidate

static func _result(status: String, reason: String, candidate: GameState = null, requests: Array[Dictionary] = []) -> Dictionary:
	return {"status": status, "reason": reason, "error": "", "candidate": candidate, "placement_requests": requests}

static func _failure(reason: String) -> Dictionary:
	var result := _result("error", reason)
	result.error = reason
	return result
