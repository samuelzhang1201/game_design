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
const SUBSTEP_ORDER := ["MARCH", "RECONCILE", "HOST_ARRIVAL", "CONTACT", "ENCOUNTER_DECISION", "BATTLE_STEP"]
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
		"substep_protocol_version": 3,
		"protocol_version": 3,
	}


## Refuse to resume a transaction whose saved execution protocol this build
## cannot interpret. Never silently run it with today's phase ordering.
static func incompatibility_reason(tx: Dictionary) -> String:
	if int(tx.get("protocol_version", -1)) != 3:
		return "unsupported day transaction protocol version"
	if int(tx.get("substep_protocol_version", -1)) != 3:
		return "unsupported tactical substep protocol version"
	if tx.get("substep_order", []) != SUBSTEP_ORDER:
		return "saved tactical substep order does not match this build"
	if tx.get("day_battle_order", []) != DAY_BATTLE_ORDER:
		return "saved daily battle order does not match this build"
	if int(tx.get("substep_count", 0)) < 1:
		return "saved tactical substep count is invalid"
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
