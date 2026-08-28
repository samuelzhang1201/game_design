class_name EventEffects
extends RefCounted
## Executes an event choice's effect ops (spec §4.1). Deterministic, no RNG.

static func apply(ops: String, state: GameState, data: DataRepository) -> Array:
	var results: Array = []
	for raw in ops.split(";", false):
		var op := raw.strip_edges()
		if op == "":
			continue
		var p := op.split(":")
		match p[0]:
			"metric":
				state.metrics[p[1]] = float(state.metrics.get(p[1], 0.0)) + float(p[2])
				results.append({"kind": "metric", "metric": p[1], "delta": float(p[2])})
			"gold":
				state.metrics["treasury"] = float(state.metrics["treasury"]) + float(p[1])
				results.append({"kind": "metric", "metric": "treasury", "delta": float(p[1])})
			"opinion":
				var id := _resolve(p[1], state)
				if id != "":
					state.characters[id].change_opinion(int(p[2]), p[3], state.tick)
					results.append({"kind": "opinion", "character_id": id,
						"delta": int(p[2]), "reason": p[3]})
			"schedule":
				state.event_state["scheduled"].append(
					{"event_id": p[1], "due_tick": state.tick + int(p[2])})
				results.append({"kind": "schedule", "event_id": p[1]})
			"flag":
				if not p[1] in state.event_state["flags"]:
					state.event_state["flags"].append(p[1])
				results.append({"kind": "flag", "flag": p[1]})
			"promise":
				var id2 := _resolve(p[1], state)
				if id2 != "":
					state.promises.append({"character_id": id2, "promise_code": p[2],
						"made_tick": state.tick, "tick_due": state.tick + int(p[3]),
						"status": "open"})
					results.append({"kind": "promise", "character_id": id2})
			_:
				push_error("EventEffects: unknown op: " + op)
	return results

static func _resolve(key: String, state: GameState) -> String:
	if state.characters.has(key):
		return key
	if state.council.has(key):
		return String(state.council[key])
	return ""
