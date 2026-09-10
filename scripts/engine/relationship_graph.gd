class_name RelationshipGraph
extends RefCounted
## Role-to-role relationship edges (design: role_player.md §Relationships).
## Deterministic, no RNG, no Nodes. Edges live in GameState.relationships as
## an Array of Dictionaries so the whole graph rides the one-JSON save:
##   {"from": id, "to": id, "type": kin|marriage|ally|rival|grudge|liege|
##    envoy|patron|admires|acquaintance, "sentiment": float -100..100,
##    "baseline": float (founding value drift heals toward),
##    "log": [{"tick", "delta", "reason"}]}
## Every discrete sentiment change carries a reason string (architecture
## invariant 4); per-tick drift is ambient and intentionally unlogged so a
## 60-year campaign's save does not balloon.

## Builds the starting graph from data/relationships.csv rows.
static func init_from_data(data: DataRepository) -> Array:
	var out: Array = []
	for row in data.relationships:
		var s := clampf(float(row["sentiment"]), -100.0, 100.0)
		out.append({"from": String(row["from_id"]), "to": String(row["to_id"]),
			"type": String(row["rel_type"]), "sentiment": s, "baseline": s,
			"log": [{"tick": 0, "delta": 0.0, "reason": String(row["reason"])}]})
	return out

## The directed edge from_id -> to_id, or {} when none exists.
static func edge(state: GameState, from_id: String, to_id: String) -> Dictionary:
	for e in state.relationships:
		if e["from"] == from_id and e["to"] == to_id:
			return e
	return {}

## Every edge touching id, outgoing and incoming, in stored (stable) order.
static func edges_for(state: GameState, id: String) -> Array:
	var out: Array = []
	for e in state.relationships:
		if e["from"] == id or e["to"] == id:
			out.append(e)
	return out

## Applies a sentiment shock. Creates the edge (type "acquaintance",
## baseline 0) when the pair has none. A reason is mandatory — no silent
## relationship changes, same rule as Character.change_opinion.
static func adjust(state: GameState, from_id: String, to_id: String,
		delta: float, reason: String, tick: int) -> void:
	assert(reason != "", "relationship change requires a reason")
	var e := edge(state, from_id, to_id)
	if e.is_empty():
		e = {"from": from_id, "to": to_id, "type": "acquaintance",
			"sentiment": 0.0, "baseline": 0.0, "log": []}
		state.relationships.append(e)
	e["sentiment"] = clampf(float(e["sentiment"]) + delta, -100.0, 100.0)
	e["log"].append({"tick": tick, "delta": delta, "reason": reason})

## Per-tick ambient healing: every edge moves relationship_drift_per_tick
## toward its baseline (never past it). Returns the nonzero moves for the
## tick report; does not write edge logs (see class comment).
static func drift(state: GameState, data: DataRepository) -> Array:
	var rate := data.bal("relationship_drift_per_tick")
	var out: Array = []
	for e in state.relationships:
		var gap := float(e["baseline"]) - float(e["sentiment"])
		if is_zero_approx(gap):
			continue
		var step := clampf(gap, -rate, rate)
		e["sentiment"] = float(e["sentiment"]) + step
		out.append({"from": e["from"], "to": e["to"], "delta": step})
	return out

## One role's relationships as prompt-ready text, strongest feelings first,
## capped — this is what feeds the role's LLM context window. Outgoing edges
## read as how the role feels; incoming as how others regard them.
static func describe_for(state: GameState, id: String, cap: int = 6) -> String:
	var edges := edges_for(state, id)
	edges.sort_custom(func(a, b) -> bool:
		return absf(float(a["sentiment"])) > absf(float(b["sentiment"])))
	var lines: Array = []
	for e in edges:
		if lines.size() >= cap:
			break
		var other_id: String = e["to"] if e["from"] == id else e["from"]
		if not state.characters.has(other_id):
			continue
		var other: Character = state.characters[other_id]
		var s := int(float(e["sentiment"]))
		var line: String
		if e["from"] == id:
			line = "%s (%s, %+d): %s" % [other.display_name, e["type"], s,
				_latest_reason(e)]
		else:
			line = "%s regards them (%s, %+d): %s" % [other.display_name,
				e["type"], s, _latest_reason(e)]
		lines.append(line)
	return "\n".join(lines)

static func _latest_reason(e: Dictionary) -> String:
	var entries: Array = e["log"]
	return String(entries[entries.size() - 1]["reason"]) if not entries.is_empty() else ""
