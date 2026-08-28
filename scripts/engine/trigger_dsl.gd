class_name TriggerDsl
extends RefCounted
## Deterministic trigger evaluator for random_events.csv (spec §4.1). No RNG.

static func evaluate(expr: String, state: GameState, data: DataRepository) -> bool:
	if expr.strip_edges() == "always":
		return true
	for clause in expr.split("&"):
		if not _clause(clause.strip_edges(), state, data):
			return false
	return true

static func _clause(c: String, state: GameState, _data: DataRepository) -> bool:
	if c.begins_with("season="):
		return state.season() == c.substr(7)
	if c.begins_with("year>="):
		return state.year() >= int(c.substr(6))
	if c.begins_with("trait_at_court="):
		var t := c.substr(15)
		for id in state.characters:
			if t in state.characters[id].traits:
				return true
		return false
	if c.begins_with("seat_filled="):
		return state.council.has(c.substr(12))
	if c.begins_with("action_since="):
		var parts := c.substr(13).split(":")
		var last := int(state.event_state["last_action_tick"].get(parts[0], -99999))
		return last >= state.tick - int(parts[1])
	if c.begins_with("flag="):
		return c.substr(5) in state.event_state["flags"]
	if "<" in c:
		var kv := c.split("<")
		return float(state.metrics.get(kv[0], 0.0)) < float(kv[1])
	if ">" in c:
		var kv := c.split(">")
		return float(state.metrics.get(kv[0], 0.0)) > float(kv[1])
	push_error("TriggerDsl: unknown clause: " + c)
	return false
