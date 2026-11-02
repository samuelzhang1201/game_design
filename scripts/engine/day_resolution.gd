class_name DayResolution
extends RefCounted

## Stable phase names are part of the saved day-transaction protocol.
const PHASES: Array[String] = [
	"WORKS", "MARCH_ORDERS_AND_ROUTE_SETUP", "COURIERS", "AI_AND_SCOUT",
	"SIGHTING_AND_INTEL_REFRESH", "FIXED_TACTICAL_SUBSTEPS", "SIEGES", "RAIDS",
	"CAMPS_AND_SIGHTING", "SUPPLY_AND_CONDUCT", "DAILY_ECONOMY", "REPORTS",
	"MONTH_END_IF_NEEDED", "CALENDAR", "COMPLETE",
]
const DEFAULT_SUBSTEP_COUNT := 10
const LEGACY_SUBSTEP_ORDER := ["MARCH", "RECONCILE", "HOST_ARRIVAL", "CONTACT", "ENCOUNTER_DECISION", "BATTLE_STEP"]
const SUBSTEP_ORDER := ["MARCH", "RECONCILE", "KING", "HOST_ARRIVAL", "CONTACT", "ENCOUNTER_DECISION", "BATTLE_STEP"]
const DAY_BATTLE_ORDER := ["CONTACT", "ENCOUNTER_DECISION", "BATTLE_STEP"]

static func begin(day: int, month_end: bool, absolute_day := -1,
		substep_count := DEFAULT_SUBSTEP_COUNT) -> Dictionary:
	return {
		"day": day,
		"absolute_day": day if absolute_day < 0 else absolute_day,
		"month_end": month_end,
		"phase": PHASES[0],
		"substep_index": 0,
		"phase_cursor": 0,
		"battle_ids": [],
		"battle_index": 0,
		"battle_step": "",
		"substep_battle_ids": [],
		"processed_battle_ids": [],
		"decision_sequence": 0,
		"pending_decision": {},
		"consumed_tokens": [],
		"journal": {
			"works": [], "arrivals": [], "couriers": [], "battles": [], "sieges": [],
			"raids": [], "supply": [], "conduct": [], "reports": [],
		},
		"substep_count": maxi(substep_count, 1),
		"substep_order": SUBSTEP_ORDER.duplicate(),
		"day_battle_order": DAY_BATTLE_ORDER.duplicate(),
		"substep_protocol_version": 4,
		"protocol_version": 4,
	}


## Refuse to resume a transaction whose saved execution protocol this build
## cannot interpret. Never silently run it with today's phase ordering.
static func incompatibility_reason(tx: Dictionary) -> String:
	if tx.has("body_battle"): return "Candidate body battle requires its explicit consumer"
	if tx.has("body_march"): return "Candidate body march requires its explicit consumer"
	return _protocol_error(tx)

static func _protocol_error(tx: Dictionary) -> String:
	if not tx.has("protocol_version"):
		return "" if String(tx.get("phase", "")) in ["prepare", "encounters", "battles", "finish"] else "unsupported legacy day phase"
	for field: String in ["protocol_version", "substep_protocol_version", "substep_count", "phase_cursor", "substep_index", "battle_index"]:
		if not _whole_cursor(tx.get(field, -1)):
			return "saved day cursor must contain whole numbers: " + field
	var version := int(tx.get("protocol_version", -1))
	if not version in [3, 4] or int(tx.get("substep_protocol_version", -1)) != version:
		return "unsupported day transaction protocol version"
	var order: Array = LEGACY_SUBSTEP_ORDER if version == 3 else SUBSTEP_ORDER
	if tx.get("substep_order", []) != order:
		return "saved tactical substep order does not match this build"
	if tx.get("day_battle_order", []) != DAY_BATTLE_ORDER:
		return "saved daily battle order does not match this build"
	if int(tx.get("substep_count", 0)) < 1:
		return "saved tactical substep count is invalid"
	var cursor := int(tx.get("phase_cursor", -1))
	if cursor < 0 or cursor >= PHASES.size() or String(tx.get("phase", "")) != PHASES[cursor]:
		return "saved day phase cursor is invalid"
	if int(tx.get("substep_index", -1)) < 0 or int(tx["substep_index"]) > int(tx["substep_count"]):
		return "saved tactical substep cursor is invalid"
	return _battle_cursor_error(tx)

static func _whole_cursor(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) == floor(float(value))

static func _battle_cursor_error(tx: Dictionary) -> String:
	for field: String in ["battle_ids", "substep_battle_ids", "processed_battle_ids", "over_battle_ids", "acknowledged_encounters"]:
		var ids: Variant = tx.get(field, null if field in ["battle_ids", "substep_battle_ids", "processed_battle_ids"] else [])
		if not ids is Array:
			return "saved battle IDs must be an array: " + field
		var seen: Dictionary = {}
		for id: Variant in ids:
			if not _whole_cursor(id) or seen.has(id):
				return "saved battle IDs must be unique whole numbers: " + field
			seen[id] = true
	if not tx.get("pending_decision", null) is Dictionary or not tx.get("battle_step", null) is String:
		return "saved battle decision or step has an invalid type"
	var step: String = tx["battle_step"]
	var ids: Array = tx["battle_ids"]
	var index := int(tx["battle_index"])
	if not step in ["", "contacted", "fighting"] or index > ids.size():
		return "saved battle step or cursor is invalid"
	if step != "fighting" and (index != 0 or not ids.is_empty()):
		return "saved battle cursor has no fighting step"
	if step != "" and (tx["phase"] != "FIXED_TACTICAL_SUBSTEPS" or int(tx["substep_index"]) >= int(tx["substep_count"])):
		return "saved battle step lies outside tactical substeps"
	if step == "fighting":
		var processed: Array = tx.get("processed_battle_ids", [])
		for i: int in ids.size():
			if (ids[i] in processed) != (i < index):
				return "saved battle cursor disagrees with processed battles"
	var pending: Dictionary = tx["pending_decision"]
	if not pending.is_empty():
		if step == "" or not _whole_cursor(pending.get("battle_id", -1)):
			return "saved decision has no active battle step"
		if step == "fighting" and (index >= ids.size() or pending["battle_id"] != ids[index]):
			return "saved decision disagrees with current battle"
		if step == "contacted" and not pending["battle_id"] in tx.get("substep_battle_ids", []):
			return "saved contact decision has no new encounter"
	return ""

## Accept a current legal decision once. Stale and duplicate acknowledgements
## are observable outcomes and never change the saved transaction.
static func acknowledge(tx: Dictionary, token: String, choice: String) -> Dictionary:
	var consumed: Array = tx.get("consumed_tokens", [])
	if token in consumed:
		return {"status": "duplicate"}
	var pending: Dictionary = tx.get("pending_decision", {})
	if pending.is_empty() or String(pending.get("token", "")) != token:
		return {"status": "stale"}
	if not choice in (pending.get("choices", []) as Array):
		return {"status": "invalid"}
	pending["selected"] = choice
	consumed.append(token)
	tx["consumed_tokens"] = consumed
	if String(pending.get("kind", "")) == "encounter":
		var acknowledged: Array = tx.get("acknowledged_encounters", [])
		var battle_id := int(pending.get("battle_id", 0))
		if not battle_id in acknowledged:
			acknowledged.append(battle_id)
		tx["acknowledged_encounters"] = acknowledged
	tx["pending_decision"] = {}
	return {"status": "accepted", "kind": String(pending.get("kind", "")),
		"battle_id": int(pending.get("battle_id", 0)), "choice": choice}

static func block_on_encounter(tx: Dictionary, battle_id: int) -> Dictionary:
	var sequence := int(tx.get("decision_sequence", 0)) + 1
	tx["decision_sequence"] = sequence
	var token := "%d:%d:%d:%d" % [int(tx.get("absolute_day", tx["day"])),
		int(tx["substep_index"]), battle_id, sequence]
	var pending := {"token": token, "kind": "encounter", "battle_id": battle_id,
		"substep_index": int(tx["substep_index"]), "choices": ["continue"], "selected": ""}
	tx["pending_decision"] = pending
	return pending

## Candidate-only MARCH protocol. Raw decimal strings survive legacy save rounding.
static func body_march_incompatibility_reason(tx: Dictionary) -> String:
	if tx.has("body_battle"): return "Mixed candidate day protocols"
	var error := _protocol_error(tx)
	if not error.is_empty(): return error
	if int(tx.get("protocol_version", 0)) != 4 or tx.phase != "FIXED_TACTICAL_SUBSTEPS" \
		or tx.battle_step != "" or not tx.pending_decision.is_empty() or not tx.substep_battle_ids.is_empty(): return "Candidate requires an idle v4 MARCH boundary"
	for key: String in ["day", "absolute_day"]:
		if not _whole_cursor(tx.get(key)): return "Invalid candidate day"
	var control: Variant = tx.get("body_march")
	if not control is Dictionary or not BodyMotion._keys(control, ["version", "abs_day", "next_substep", "substep_count", "last"]):
		return "Invalid body march control schema"
	if not control.version is String or control.version not in ["1", "2"]: return "Unsupported body march version"
	for field: String in ["abs_day", "next_substep", "substep_count"]:
		if not BodyMotion._decimal(control[field]): return "Invalid raw body march cursor: " + field
	var next := int(control.next_substep)
	if int(control.abs_day) != int(tx.absolute_day) or next != int(tx.substep_index) \
		or int(control.substep_count) != int(tx.substep_count): return "Body march cursor disagrees with day header"
	if not control.last is Dictionary: return "Invalid body march receipt"
	var last: Dictionary = control.last
	if next == 0:
		if not last.is_empty(): return "Unexpected initial body march receipt"
	elif not BodyMotion._keys(last, ["substep", "receipt", "result"] if control.version == "2" else ["substep", "receipt"]) or not BodyMotion._decimal(last.substep) \
		or int(last.substep) != next - 1 or not last.receipt is String or not BodyMotion._digest(last.receipt):
		return "Missing or inconsistent body march receipt"
	if next > 0 and control.version == "2" and (not last.result is String or not BodyMotion._digest(last.result)):
		return "Invalid locomotion march result digest"
	if not tx.get("march_entries") is Dictionary or not tx.get("march_budgets") is Dictionary \
		or not tx.get("marching_codes") is Array or not tx.get("journal") is Dictionary:
		return "Missing frozen march inputs"
	if not tx.journal.get("arrivals") is Array: return "Invalid frozen march arrival journal"
	return ""

## Admission only; the ordinary day consumer cannot advance this marker.
static func body_battle_incompatibility_reason(tx: Dictionary) -> String:
	if tx.has("body_march"): return "Mixed candidate day protocols"
	if not tx.get("phase") is String: return "Invalid raw battle day phase"
	var error := _protocol_error(tx)
	if not error.is_empty(): return error
	if tx.get("protocol_version") != 4 or tx.get("phase") != "FIXED_TACTICAL_SUBSTEPS":
		return "Candidate battle requires v4 tactical substeps"
	for field: String in ["day", "absolute_day", "substep_count", "substep_index", "battle_index", "decision_sequence"]:
		if not BodyMotion._loco_integer(tx.get(field)) or tx[field] < 0: return "Invalid raw battle day cursor: " + field
	var raw: Variant = tx.get("body_battle")
	if not raw is Dictionary or not BodyMotion._keys(raw, ["version", "abs_day", "sequence", "next_substep", "substep_count", "stage", "battle_ids", "battle_index", "processed_units"]):
		return "Invalid body battle control schema"
	var control: Dictionary = raw
	if not control.version is String or control.version != "1": return "Unsupported body battle version"
	for field: String in ["abs_day", "sequence", "next_substep", "substep_count", "battle_index"]:
		if not _body_decimal(control[field]): return "Invalid raw battle cursor: " + field
	if int(control.abs_day) != int(tx.absolute_day) or int(control.next_substep) != int(tx.substep_index) \
		or int(control.substep_count) != int(tx.substep_count) or int(control.battle_index) != int(tx.battle_index):
		return "Body battle cursor disagrees with day header"
	if control.stage not in ["move", "contact", "round", "advance", "complete"]: return "Invalid battle stage"
	if not control.battle_ids is Array or control.battle_ids.size() != tx.battle_ids.size(): return "Invalid mirrored battle queue"
	var previous := 0
	for i: int in control.battle_ids.size():
		var id: Variant = control.battle_ids[i]
		if not _body_decimal(id) or int(id) <= previous or int(id) != tx.battle_ids[i]: return "Invalid mirrored battle ID"
		previous = int(id)
	if not control.processed_units is Array: return "Invalid processed units"
	var last := ""
	for unit: Variant in control.processed_units:
		if not unit is String or unit.is_empty() or unit <= last: return "Invalid sorted processed units"
		last = unit
	for field: String in ["processed_battle_ids", "substep_battle_ids"]:
		previous = 0
		for id: Variant in tx[field]:
			if not BodyMotion._loco_integer(id) or id <= previous: return "Invalid canonical battle IDs: " + field
			previous = int(id)
	if not tx.get("march_entries") is Dictionary or not tx.get("march_budgets") is Dictionary \
		or not tx.get("marching_codes") is Array or not tx.get("journal") is Dictionary \
		or not tx.journal.get("arrivals") is Array or not tx.get("consumed_tokens") is Array:
		return "Missing frozen battle day inputs"
	var index := int(control.battle_index)
	var count: int = control.battle_ids.size()
	if control.stage in ["move", "contact", "complete"]:
		if tx.battle_step != "" or count != 0 or index != 0 or not tx.substep_battle_ids.is_empty() or not tx.pending_decision.is_empty():
			return "Battle stage requires idle cursor"
	elif tx.battle_step != "fighting": return "Battle queue requires fighting cursor"
	if control.stage == "round" and index >= count: return "Round requires an unresolved battle"
	if control.stage == "advance" and (index != count or not tx.pending_decision.is_empty()): return "Advance requires an exhausted queue"
	if (control.stage == "complete") != (int(control.next_substep) == int(control.substep_count)):
		return "Battle completion disagrees with substep count"
	for id: Variant in tx.substep_battle_ids:
		if id not in tx.battle_ids: return "New encounter is outside battle queue"
	if not tx.pending_decision.is_empty():
		var pending: Dictionary = tx.pending_decision
		if not pending.get("token") is String or pending.token.is_empty() or pending.get("kind") not in ["encounter", "battle_event"] \
			or not pending.get("choices") is Array or pending.choices.is_empty() or not pending.get("selected") is String or pending.selected != "":
			return "Invalid pending battle decision"
		if pending.kind == "encounter" and (not BodyMotion._loco_integer(pending.get("substep_index")) or pending.substep_index != tx.substep_index):
			return "Encounter decision disagrees with substep"
		if pending.kind == "battle_event" and (not BodyMotion._loco_integer(pending.get("day")) or pending.day != tx.absolute_day):
			return "Battle event decision disagrees with day"
		for choice: Variant in pending.choices:
			if not choice is String or choice.is_empty(): return "Invalid battle decision choice"
		if pending.token in tx.consumed_tokens: return "Pending battle decision already consumed"
	return ""

static func _body_decimal(value: Variant) -> bool:
	return BodyMotion._decimal(value) and int(value) <= BodyMotion.JSON_INTEGER_MAX
