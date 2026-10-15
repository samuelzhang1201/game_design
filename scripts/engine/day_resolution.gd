class_name DayResolution
extends RefCounted
## A synchronous stage commits its effects and cursor together. The only
## yield is a saved decision, so loading cannot replay earlier work.

static func begin(day: int, month_end: bool) -> Dictionary:
	return {"day": day, "month_end": month_end, "phase": "prepare",
		"battle_ids": [], "battle_index": 0, "battle_step": "",
		"pending_decision": {}, "consumed_tokens": [],
		"journal": {"works": [], "arrivals": [], "couriers": [], "battles": [],
			"sieges": [], "raids": [], "supply": [], "conduct": [], "ai": []}}

static func acknowledge(tx: Dictionary, token: String, choice: String) -> Dictionary:
	if tx.is_empty():
		return {"status": "stale"}
	if token in tx["consumed_tokens"]:
		return {"status": "duplicate"}
	var pending: Dictionary = tx["pending_decision"]
	if pending.is_empty() or String(pending["token"]) != token:
		return {"status": "stale"}
	if not choice in pending["choices"]:
		return {"status": "invalid"}
	pending["selected"] = choice
	tx["consumed_tokens"].append(token)
	return {"status": "accepted"}
