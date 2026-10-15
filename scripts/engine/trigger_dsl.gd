class_name TriggerDsl
extends RefCounted
## Deterministic trigger evaluator for events.csv, a choice's `requires` and
## a chapter branch's rule (spec §4.1). No RNG.
##
## An expression is clauses joined by `&`; a clause may be negated with a
## leading `!`. `always` is true, `never` is false — a chapter beat is fired
## off its chain, never sampled, and says so in its own trigger column.

static func evaluate(expr: String, state: GameState, data: DataRepository) -> bool:
	var e := expr.strip_edges()
	if e == "always":
		return true
	if e == "never":
		return false
	for clause in e.split("&"):
		var c := clause.strip_edges()
		if c.begins_with("!"):
			if _clause(c.substr(1).strip_edges(), state, data):
				return false
		elif not _clause(c, state, data):
			return false
	return true

static func _clause(c: String, state: GameState, data: DataRepository) -> bool:
	if c == "always":
		return true
	if c == "never":
		return false
	if c == "host_hungry":
		return SupplySystem.any_hungry(data, state)
	if c.begins_with("season="):
		return state.season() == c.substr(7)
	if c.begins_with("year>="):
		return state.year() >= int(c.substr(6))
	if c.begins_with("trait_at_court="):
		var t := c.substr(15)
		var present: Dictionary = {"you": true}
		for id: String in state.council.values():
			present[id] = true
		var ids: Array = present.keys()
		ids.sort()
		for id: String in ids:
			var person: Character = state.characters.get(id) as Character
			if person != null and t in person.traits:
				return true
		return false
	if c.begins_with("trait_of="):
		# trait_of=<seat or character id>:<trait> — ONE person's trait, which
		# is what a branch on "is your spymaster ambitious" actually asks.
		# An empty seat or an unknown id is false, never an error: a council
		# seat can be vacant and the chapter still has to go somewhere.
		var parts := c.substr(9).split(":")
		if parts.size() != 2:
			push_error("TriggerDsl: trait_of needs <who>:<trait>: " + c)
			return false
		var who := _resolve(String(parts[0]), state)
		if who == "":
			return false
		return String(parts[1]) in state.characters[who].traits
	if c.begins_with("seat_filled="):
		return state.council.has(c.substr(12))
	if c.begins_with("action_since="):
		var parts2 := c.substr(13).split(":")
		var last := int(state.event_state["last_action_tick"].get(parts2[0], -99999))
		return last >= state.tick - int(parts2[1])
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

## A seat code or a character id, resolved the same way EventEffects resolves
## an opinion op's target — one rule for who a row means.
static func _resolve(key: String, state: GameState) -> String:
	if state.characters.has(key):
		return key
	if state.council.has(key):
		return String(state.council[key])
	return ""
