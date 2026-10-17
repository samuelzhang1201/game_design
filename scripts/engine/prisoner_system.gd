class_name PrisonerSystem
extends RefCounted
## Custody references the personnel ledger; named people and wounds are subsets.

static func allocate(participants: Dictionary, count: int) -> Dictionary:
	if count < 0 or participants.is_empty():
		return {"error": "Capture needs actual receivers and a nonnegative count."}
	for code: Variant in participants:
		if not code is String or code.is_empty() or not _positive_whole(participants[code]):
			return {"error": "Capture weights need unit codes and positive whole numbers."}
	var codes := participants.keys()
	codes.sort()
	var weights: Array = []
	for code: String in codes:
		weights.append(int(participants[code]))
	var shares := BattleSystem.apportion(weights, count)
	var result: Dictionary = {}
	for i: int in codes.size():
		result[codes[i]] = int(shares[i])
	return result

static func capture(repo: DataRepository, state: GameState, raw: Dictionary) -> Dictionary:
	var normalized := _normalize(raw)
	if normalized.has("error"):
		return normalized
	var request: Dictionary = normalized["request"]
	var id := String(request["capture_id"])
	var replay := _replay(state, id, request)
	if not replay.is_empty():
		return replay
	var participants: Dictionary = request["participants"]
	var codes := participants.keys()
	codes.sort()
	for code: String in codes:
		if not _live_holder(repo, state, code):
			return {"error": "A receiver must be a live land unit with fit personnel: " + code}
	var battle := BattleSystem.battle_by_id(state, int(request["battle_id"]))
	var receiver_side := ""
	if not battle.is_empty():
		for code: String in codes:
			var side := "att" if code in battle.get("att", []) else "def" if code in battle.get("def", []) else ""
			if side.is_empty() or (receiver_side != "" and receiver_side != side):
				return {"error": "Capture receivers must actually share one battlefield side."}
			receiver_side = side
	var total := 0
	var sources: Dictionary = {}
	var people: Dictionary = {}
	for change: Dictionary in request["changes"]:
		var cohort_id := String(change["cohort_id"])
		var cohort: Dictionary = state.military_cohorts.get(cohort_id, {})
		var unit := ArmySystem.regiment(repo, String(cohort.get("unit_code", "")), state)
		if participants.has(cohort.get("unit_code", "")):
			return {"error": "A capture receiver cannot capture its own personnel."}
		if cohort.get("stage", "") != "active" or unit.is_empty() \
				or not cohort.get("identity", "") in ["commoner", "noble"] \
				or not repo.provinces.has(cohort.get("source_province", "")) \
				or not cohort.get("source_population_field", "") in MilitaryPopulation.FIELDS \
				or String(unit.get("kingdom_code", "")).is_empty() \
				or int(cohort.get(change["from"], 0)) < int(change["count"]):
			return {"error": "Capture source is inactive, missing or insufficient: " + cohort_id}
		if not cohort_id in state.military_rosters.get(cohort.get("unit_code", ""), {}).get("cohort_ids", []):
			return {"error": "Capture source is outside its military roster."}
		if receiver_side != "" and not cohort.get("unit_code", "") in battle.get("def" if receiver_side == "att" else "att", []):
			return {"error": "Capture sources must belong to the opposing battlefield side."}
		var person := String(cohort.get("person_id", ""))
		if person != "":
			var character: Character = state.characters.get(person) as Character
			if person == "you" or character == null or character.category == "player" \
					or cohort.get("identity", "") != "noble" or int(cohort.get("initial", 0)) != 1:
				return {"error": "The king cannot be captured; named captives need one noble place."}
			if people.has(person):
				return {"error": "A named captive cannot occur twice."}
			people[person] = cohort_id
		if not sources.has(cohort_id):
			sources[cohort_id] = {"count": 0, "wounded": 0, "origin_realm": String(unit.get("kingdom_code", ""))}
		sources[cohort_id]["count"] += int(change["count"])
		if change["from"] == "wounded":
			sources[cohort_id]["wounded"] += int(change["count"])
		total += int(change["count"])
	var pinned: Dictionary = request["named_holders"]
	var reserved: Dictionary = {}
	for code: String in codes:
		reserved[code] = 0
	for person: String in pinned:
		var holder := String(pinned[person])
		if not people.has(person) or not participants.has(holder):
			return {"error": "Named custody must identify a captured person and actual receiver."}
		reserved[holder] += 1
	# Actual named custody reserves places before unnamed people are apportioned.
	var allocation := allocate(participants, total - pinned.size())
	for code: String in codes:
		allocation[code] += int(reserved[code])
	var remaining := allocation.duplicate()
	var assignments: Dictionary = {}
	var names := people.keys()
	names.sort()
	for person: String in names:
		if pinned.has(person):
			assignments[people[person]] = String(pinned[person])
			remaining[pinned[person]] -= 1
	for person: String in names:
		if pinned.has(person):
			continue
		for code: String in codes:
			if int(remaining[code]) > 0:
				assignments[people[person]] = code
				remaining[code] -= 1
				break
	var batches: Dictionary = {}
	var cohort_ids := sources.keys()
	cohort_ids.sort()
	for cohort_id: String in cohort_ids:
		var cohort: Dictionary = state.military_cohorts[cohort_id]
		var source: Dictionary = sources[cohort_id]
		var left := int(source["count"])
		var wounds := int(source["wounded"])
		var person := String(cohort.get("person_id", ""))
		for code: String in codes:
			var count := 1 if assignments.get(cohort_id, "") == code else 0
			if person.is_empty():
				count = mini(left, int(remaining[code]))
				remaining[code] -= count
			if count == 0:
				continue
			var batch_id := "prisoner:" + JSON.stringify([id, cohort_id, code])
			if state.prisoner_batches.has(batch_id):
				return {"error": "Capture batch ID already exists."}
			var wounded := mini(wounds, count)
			batches[batch_id] = {"id": batch_id, "source_cohort": cohort_id,
				"origin_realm": source["origin_realm"], "holder_code": code, "captor_code": code,
				"commoners": count if cohort["identity"] == "commoner" else 0,
				"nobles": count if cohort["identity"] == "noble" else 0,
				"named_ids": [person] if person != "" else [], "wounded_subset": wounded,
				"initial_count": count, "capture_id": id, "battle_id": request["battle_id"], "round": request["round"],
				"disposition": "held", "ransom_protected": BattleRules._policy(battle, "noble_ransom", state.absolute_day()) == "allow",
				"reason": request["reason"]}
			left -= count
			wounds -= wounded
		if left != 0 or wounds != 0:
			return {"error": "Capture allocation did not conserve source personnel."}
	var transition := MilitaryRoster.transition(repo, state, "prisoner_capture:" + id,
		request["changes"], request["reason"])
	if transition.has("error"):
		return transition
	state.prisoner_batches.merge(batches)
	return _record(state, id, request, {"status": "applied", "batch_ids": batches.keys(),
		"personnel": total, "allocation": allocation})

static func holder_defeated(repo: DataRepository, state: GameState, holder: String, controllers: Array[String], event_id: String = "") -> Dictionary:
	var codes: Array[String] = []
	for code: String in controllers:
		if not code in codes:
			codes.append(code)
	codes.sort()
	# A holder can receive prisoners again; default replay identity follows its custody generation.
	var generation: Array = []
	var ids := state.prisoner_batches.keys()
	ids.sort()
	for id: String in ids:
		var batch: Dictionary = state.prisoner_batches[id]
		if batch.get("holder_code", "") == holder:
			generation.append([id, batch.get("disposition", ""), batch.get("capture_id", "")])
	if event_id.is_empty():
		# Replaying after publication finds the original generation via its saved result.
		var event_ids := state.prisoner_events.keys()
		event_ids.reverse()
		for previous_id: String in event_ids:
			var previous: Dictionary = state.prisoner_events[previous_id]
			var old: Dictionary = previous["request"]
			if old.get("kind", "") == "holder_defeated" and old.get("holder", "") == holder \
					and old.get("controllers", []) == codes and old.get("after", []) == generation:
				return (previous["result"] as Dictionary).duplicate(true)
		event_id = "prisoner_holder_defeated:" + JSON.stringify([holder, codes, generation])
	var request := {"kind": "holder_defeated", "holder": holder, "controllers": codes}
	var replay := _replay(state, event_id, request)
	if not replay.is_empty():
		return replay
	var held: Array[String] = []
	var source_totals: Dictionary = {}
	for id: String in ids:
		var batch: Dictionary = state.prisoner_batches[id]
		if batch.get("holder_code", "") == holder and batch.get("disposition", "") == "held":
			held.append(id)
			var source := String(batch.get("source_cohort", ""))
			var count := int(batch.get("commoners", 0)) + int(batch.get("nobles", 0))
			if count <= 0 or not state.military_cohorts.has(source):
				return {"error": "Held prisoner batch has no valid personnel source."}
			source_totals[source] = int(source_totals.get(source, 0)) + count
			if int(source_totals[source]) > int(state.military_cohorts[source].get("captured_current", 0)):
				return {"error": "Held prisoner batches exceed captured source personnel."}
	if held.is_empty():
		request["after"] = generation
		return _record(state, event_id, request, {"status": "applied", "released": 0, "transferred": 0, "batch_ids": []})
	for code: String in codes:
		if code == holder or not _live_holder(repo, state, code):
			return {"error": "A battlefield controller must be another fit live land unit."}
	var changes: Array = []
	var updated: Dictionary = {}
	var released := 0
	var transferred := 0
	var reason := "No surviving field controller can guard them; prisoners released as civilians: " + holder if codes.is_empty() else "Prisoners accounted for after holder defeat: " + holder
	for id: String in held:
		var batch: Dictionary = state.prisoner_batches[id].duplicate(true)
		var rescued := codes.is_empty()
		for code: String in codes:
			if ArmySystem.regiment(repo, code, state).get("kingdom_code", "") == batch["origin_realm"]:
				rescued = true
				break
		var count := int(batch["commoners"]) + int(batch["nobles"])
		if rescued:
			changes.append({"cohort_id": batch["source_cohort"], "from": "captured_current", "to": "released", "count": count})
			batch["released_count"] = int(batch.get("released_count", 0)) + count
			batch["disposition"] = "released"
			batch["civilian"] = true
			batch["holder_code"] = ""
			released += count
		else:
			batch["holder_code"] = codes[0]
			transferred += count
		batch["reason"] = reason
		updated[id] = batch
	if not changes.is_empty():
		var transition := MilitaryRoster.transition(repo, state, "prisoner_rescue:" + event_id, changes, reason)
		if transition.has("error"):
			return transition
	state.prisoner_batches.merge(updated, true)
	var after: Array = []
	for id: String in ids:
		var batch: Dictionary = state.prisoner_batches[id]
		if batch.get("holder_code", "") == holder:
			after.append([id, batch.get("disposition", ""), batch.get("capture_id", "")])
	request["after"] = after
	return _record(state, event_id, request, {"status": "applied", "released": released,
		"transferred": transferred, "batch_ids": held})

## One personnel transition releases every agreed slice, including both sides
## of an exchange. initial_count remains the immutable capture quantity.
static func release(repo: DataRepository, state: GameState, event_id: String, selections: Array, reason: String) -> Dictionary:
	var request := {"kind": "release", "selections": selections.duplicate(true), "reason": reason}
	var replay := _replay(state, event_id, request)
	if not replay.is_empty():
		return replay
	var changes: Array = []
	var updated := {}
	var total := 0
	for selection: Dictionary in selections:
		var id := String(selection["batch_id"])
		var batch: Dictionary = state.prisoner_batches.get(id, {}).duplicate(true)
		var count := int(selection["count"])
		var wounds := int(selection["wounded_count"])
		var held := int(batch.get("commoners", 0)) + int(batch.get("nobles", 0))
		if updated.has(id) or batch.get("disposition", "") != "held" or count <= 0 or count > held \
				or wounds < 0 or wounds > count or wounds > int(batch.get("wounded_subset", 0)) \
				or count - wounds > held - int(batch.get("wounded_subset", 0)):
			return {"error": "A release needs unique currently held personnel and valid wound subsets."}
		changes.append({"cohort_id": batch["source_cohort"], "from": "captured_current", "to": "released", "count": count})
		var identity := "nobles" if int(batch["nobles"]) > 0 else "commoners"
		batch[identity] = int(batch[identity]) - count
		batch["wounded_subset"] = int(batch["wounded_subset"]) - wounds
		batch["released_count"] = int(batch.get("released_count", 0)) + count
		batch["named_ids"] = [] if count == held else batch.get("named_ids", [])
		if count == held:
			batch["disposition"] = "released"
			batch["civilian"] = true
			batch["holder_code"] = ""
		batch["reason"] = reason
		updated[id] = batch
		total += count
	var result := MilitaryRoster.transition(repo, state, event_id, changes, reason)
	if result.has("error"):
		return result
	state.prisoner_batches.merge(updated, true)
	return _record(state, event_id, request, {"status": "applied", "released": total})

## Older batches encode the actual captor in their stable capture identity.
static func captor_of(batch: Dictionary) -> String:
	if String(batch.get("captor_code", "")) != "":
		return String(batch.captor_code)
	var id := String(batch.get("id", ""))
	if id.begins_with("prisoner:"):
		var parts: Variant = JSON.parse_string(id.trim_prefix("prisoner:"))
		if parts is Array and parts.size() == 3 and parts[0] == batch.get("capture_id", "") \
				and parts[1] == batch.get("source_cohort", "") and parts[2] is String:
			return String(parts[2])
	return String(batch.get("holder_code", ""))

static func held_counts(state: GameState, holder: String) -> Dictionary:
	var counts := {"commoners": 0, "nobles": 0, "wounded": 0, "total": 0}
	if state == null:
		return counts
	for batch: Dictionary in state.prisoner_batches.values():
		if batch.get("holder_code", "") == holder and batch.get("disposition", "") == "held":
			counts["commoners"] += int(batch.get("commoners", 0))
			counts["nobles"] += int(batch.get("nobles", 0))
			counts["wounded"] += int(batch.get("wounded_subset", 0))
	counts["total"] = int(counts["commoners"]) + int(counts["nobles"])
	return counts

## Noncombat losses have no battlefield controller to inherit custody.
static func settle_unguarded(repo: DataRepository, state: GameState) -> Dictionary:
	var holders: Dictionary = {}
	for batch: Dictionary in state.prisoner_batches.values():
		if batch.get("disposition", "") == "held":
			holders[String(batch["holder_code"])] = true
	var codes := holders.keys()
	codes.sort()
	for code: String in codes:
		if MilitaryRoster.fit(state, code) > 0 or not BattleSystem.battle_of(state, code).is_empty():
			continue
		var result := holder_defeated(repo, state, code, [], "unguarded:%d:%s" % [state.absolute_day(), code])
		if result.has("error"):
			return result
	return {"status": "applied"}

static func _live_holder(repo: DataRepository, state: GameState, code: String) -> bool:
	var unit := ArmySystem.regiment(repo, code, state)
	return not unit.is_empty() and String(unit.get("is_naval", "0")) != "1" \
		and (state.regiments.has(code) or state.foes.has(code)) and MilitaryRoster.fit(state, code) > 0

static func _positive_whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value > 0 and value == floor(value)

static func _normalize(raw: Dictionary) -> Dictionary:
	for key: String in ["capture_id", "reason"]:
		if not raw.get(key) is String or String(raw[key]).strip_edges().is_empty():
			return {"error": "Capture needs a stable ID and reason."}
	if not raw.get("participants") is Dictionary or not raw.get("changes") is Array \
			or not raw.get("named_holders", {}) is Dictionary:
		return {"error": "Capture needs receiver and personnel records."}
	var participants: Dictionary = raw["participants"].duplicate(true)
	var allocation := allocate(participants, 0)
	if allocation.has("error"):
		return allocation
	for code: String in participants:
		participants[code] = int(participants[code])
	var grouped: Dictionary = {}
	for row: Variant in raw["changes"]:
		if not row is Dictionary or not row.get("cohort_id") is String \
				or String(row["cohort_id"]).is_empty() or not row.get("from", "") in ["fit", "wounded"] \
				or row.get("to", "") != "captured_current" or not _positive_whole(row.get("count")):
			return {"error": "Capture needs whole fit or wounded source counts."}
		var key := JSON.stringify([row["cohort_id"], row["from"]])
		if not grouped.has(key):
			grouped[key] = {"cohort_id": row["cohort_id"], "from": row["from"], "to": "captured_current", "count": 0}
		grouped[key]["count"] += int(row["count"])
	if grouped.is_empty():
		return {"error": "Capture needs personnel."}
	var changes: Array = []
	var keys := grouped.keys()
	keys.sort()
	for key: String in keys:
		changes.append(grouped[key])
	var named: Dictionary = raw.get("named_holders", {}).duplicate(true)
	for person: Variant in named:
		if not person is String or not named[person] is String:
			return {"error": "Named holders need person and unit codes."}
	for field: String in ["battle_id", "round"]:
		var number: Variant = raw.get(field, 0)
		if not (number is int or number is float) or not is_finite(number) or number < 0 or number != floor(number):
			return {"error": "Battle and round must be nonnegative whole numbers."}
	return {"request": {"kind": "capture", "capture_id": raw["capture_id"], "battle_id": int(raw.get("battle_id", 0)),
		"round": int(raw.get("round", 0)), "participants": participants, "changes": changes,
		"named_holders": named, "reason": raw["reason"]}}

static func _replay(state: GameState, id: String, request: Dictionary) -> Dictionary:
	if not state.prisoner_events.has(id):
		return {}
	var previous: Dictionary = state.prisoner_events[id]
	var saved: Dictionary = previous["request"].duplicate(true)
	saved.erase("after")
	if saved != request:
		return {"error": "Prisoner event ID already records a different request."}
	return (previous["result"] as Dictionary).duplicate(true)

static func _record(state: GameState, id: String, request: Dictionary, result: Dictionary) -> Dictionary:
	state.prisoner_events[id] = {"request": request.duplicate(true), "result": result.duplicate(true)}
	return result

## P4.2 receipts moved personnel without creating custody. Reconstruct only
## exact, unambiguous surviving captures; never move those personnel again.
static func migrate_legacy(repo: DataRepository, state: GameState) -> Dictionary:
	var held: Dictionary = {}
	for batch: Dictionary in state.prisoner_batches.values():
		if batch.get("disposition", "") == "held":
			var source := String(batch.get("source_cohort", ""))
			held[source] = int(held.get(source, 0)) + int(batch.get("commoners", 0)) + int(batch.get("nobles", 0))
	var missing: Dictionary = {}
	for id: String in state.military_cohorts:
		var count := int(state.military_cohorts[id].get("captured_current", 0))
		var accounted := int(held.get(id, 0))
		if accounted > count:
			return {"error": "Prisoner batches exceed current captured personnel: " + id}
		if accounted < count:
			if accounted != 0:
				return {"error": "Legacy capture has ambiguous partial custody: " + id}
			missing[id] = count
	for id: String in held:
		if not state.military_cohorts.has(id):
			return {"error": "Prisoner custody has no source cohort: " + id}
	if missing.is_empty():
		return {"status": "unchanged", "batch_ids": []}
	var additions: Dictionary = {}
	var found: Dictionary = {}
	var orders := state.battle_orders.keys()
	orders.sort()
	for order_id: String in orders:
		var order: Dictionary = state.battle_orders[order_id]
		var handoff: Dictionary = order.get("result", {}).get("capture_handoff", {})
		if order.get("status", "") != "delivered" or not bool(handoff.get("accepted", false)):
			continue
		var capture_id := "legacy_surrender:" + order_id
		if state.prisoner_events.has(capture_id):
			continue
		var event: Dictionary = state.military_events.get("battle_surrender:" + order_id, {})
		var reason := String(handoff.get("reason", ""))
		var holder := String(handoff.get("captor_unit", ""))
		var request := {"capture_id": capture_id, "battle_id": handoff.get("battle_id", 0), "round": 0,
			"participants": {holder: 1}, "named_holders": {}, "reason": reason,
			"changes": handoff.get("personnel", [])}
		var normalized := _normalize(request)
		if normalized.has("error"):
			continue
		var saved_request := request.duplicate(true)
		saved_request["changes"] = event.get("request", {}).get("changes", [])
		var saved := _normalize(saved_request)
		if saved.has("error") or saved["request"] != normalized["request"] \
				or event.get("request", {}).get("reason", "") != reason \
				or event.get("result", {}).get("status", "") != "applied":
			continue
		var sources: Dictionary = {}
		for change: Dictionary in normalized["request"]["changes"]:
			var id := String(change["cohort_id"])
			if not missing.has(id):
				continue
			if not sources.has(id):
				sources[id] = {"count": 0, "wounded": 0}
			sources[id]["count"] += int(change["count"])
			if change["from"] == "wounded":
				sources[id]["wounded"] += int(change["count"])
		for id: String in sources:
			if found.has(id) or int(sources[id]["count"]) != int(missing[id]):
				return {"error": "Legacy capture has ambiguous surviving custody: " + id}
			if not _live_holder(repo, state, holder):
				return {"error": "Legacy capture holder is no longer a fit live land unit."}
			var cohort: Dictionary = state.military_cohorts[id]
			var unit := ArmySystem.regiment(repo, String(cohort.get("unit_code", "")), state)
			var person := String(cohort.get("person_id", ""))
			var character: Character = state.characters.get(person) as Character
			if unit.is_empty() or cohort.get("stage", "") != "active" \
					or not cohort.get("identity", "") in ["commoner", "noble"] \
					or person == "you" or (person != "" and (character == null or character.category == "player" \
					or cohort.get("identity", "") != "noble" or int(cohort.get("initial", 0)) != 1)):
				return {"error": "Legacy capture has invalid source provenance."}
			var count := int(sources[id]["count"])
			var batch_id := "prisoner:" + JSON.stringify([capture_id, id, holder])
			if state.prisoner_batches.has(batch_id):
				return {"error": "Legacy capture batch ID conflicts with existing custody."}
			additions[batch_id] = {"id": batch_id, "source_cohort": id, "origin_realm": String(unit.get("kingdom_code", "")),
				"holder_code": holder, "captor_code": holder, "commoners": count if cohort["identity"] == "commoner" else 0,
				"nobles": count if cohort["identity"] == "noble" else 0, "named_ids": [person] if person != "" else [],
				"wounded_subset": int(sources[id]["wounded"]), "initial_count": count, "capture_id": capture_id,
				"battle_id": int(handoff.get("battle_id", 0)), "round": 0, "disposition": "held", "reason": reason}
			found[id] = true
	for id: String in missing:
		if not found.has(id):
			return {"error": "Current captured personnel have no unambiguous holder evidence: " + id}
	state.prisoner_batches.merge(additions)
	return {"status": "applied", "batch_ids": additions.keys()}
