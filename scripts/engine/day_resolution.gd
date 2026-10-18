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
