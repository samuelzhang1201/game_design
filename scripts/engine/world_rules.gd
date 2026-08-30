class_name WorldRules
extends RefCounted
## The deterministic impossibility floor (spec D8). Whatever plausibility a
## model returns, a claim matching an `impossible` rule is worth nothing.
## Pure, no RNG, no Nodes: the one part of credibility a player cannot argue
## with, because no model is consulted.

## Returns {"vetoed": bool, "rule_code": String, "reason": String}.
## `magnitude` is the claim's numeric size where one applies (army size, gold);
## pass 0.0 for claims that carry no number.
static func veto(data: DataRepository, claim_type: String, text: String,
		magnitude: float) -> Dictionary:
	var lowered := text.to_lower()
	for code in data.world_rules:
		var row: Dictionary = data.world_rules[code]
		if String(row["verdict"]) != "impossible":
			continue
		if _matches(row, claim_type, lowered, magnitude):
			return {"vetoed": true, "rule_code": String(code),
				"reason": String(row.get("notes", ""))}
	return {"vetoed": false, "rule_code": "", "reason": ""}

static func _matches(row: Dictionary, claim_type: String, lowered_text: String,
		magnitude: float) -> bool:
	var kind := String(row["kind"])
	if kind == "magnitude":
		if String(row.get("claim_type", "")) != claim_type:
			return false
		return magnitude < float(row["bound_min"]) or magnitude > float(row["bound_max"])
	# ontology and era rules match on substrings of the claim text.
	var row_type := String(row.get("claim_type", ""))
	if row_type != "" and row_type != claim_type:
		return false
	for needle in String(row.get("pattern", "")).split("|", false):
		if String(needle).strip_edges() != "" and lowered_text.contains(String(needle)):
			return true
	return false
