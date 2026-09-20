class_name EventEffects
extends RefCounted
## Executes an event choice's effect ops (spec §4.1). Deterministic, no RNG.

## `reason_label`: FIX 2(a) — when non-empty (EventSystem.apply_choice passes
## the resolved choice's label), metric/gold results carry it as "reason" so
## the conversation and court screens can narrate them the same way
## ActionSystem outcomes already are (see ConversationScene._on_event_choice /
## CourtScreen's outcome logging). Left "" for callers (e.g. direct unit tests)
## that don't need narration; those results simply omit the "reason" key, as
## before this fix.
static func apply(ops: String, state: GameState, data: DataRepository,
		reason_label: String = "") -> Array:
	var results: Array = []
	for raw in ops.split(";", false):
		var op := raw.strip_edges()
		if op == "":
			continue
		var p := op.split(":")
		match p[0]:
			"metric":
				# metric:<name>:<delta>[:<reason>] — an op's own reason wins
				# over the choice label, so a cost row can say why.
				state.metrics[p[1]] = float(state.metrics.get(p[1], 0.0)) + float(p[2])
				var r := {"kind": "metric", "metric": p[1], "delta": float(p[2])}
				if p.size() > 3 and p[3] != "":
					r["reason"] = p[3]
				elif reason_label != "":
					r["reason"] = reason_label
				results.append(r)
			"gold":
				# gold:<amount>[:<reason>]
				state.metrics["treasury"] = float(state.metrics["treasury"]) + float(p[1])
				var r2 := {"kind": "metric", "metric": "treasury", "delta": float(p[1])}
				if p.size() > 2 and p[2] != "":
					r2["reason"] = p[2]
				elif reason_label != "":
					r2["reason"] = reason_label
				results.append(r2)
			"world":
				# world:<path>:<delta>:<reason> — any ledger field (spec
				# 2026-09-09 §2); the ledger clamps, logs, and refuses the unlisted.
				var w := WorldLedger.apply(data, state, p[1], float(p[2]),
					p[3] if p.size() > 3 else reason_label, "event")
				if w.has("error"):
					push_error("EventEffects: " + String(w["error"]))
				else:
					results.append({"kind": "world", "path": w["path"], "delta": w["delta"],
						"reason": w["reason"]})
			"attribute":
				# attribute:<who>:<name>:<delta>:<reason> — a role-level metric.
				var who := _resolve(p[1], state)
				if who != "":
					state.characters[who].change_attribute(p[2], int(p[3]), p[4], state.tick)
					results.append({"kind": "attribute", "character_id": who, "attribute": p[2],
						"delta": int(p[3]), "reason": p[4]})
			"opinion":
				var id := _resolve(p[1], state)
				if id != "":
					state.characters[id].change_opinion(int(p[2]), p[3], state.tick)
					results.append({"kind": "opinion", "character_id": id,
						"delta": int(p[2]), "reason": p[3]})
			"rel":
				# rel:<from>:<to>:<delta>:<reason> — a relationship shock
				# between two roles (seat codes resolve like opinion's do).
				var rf := _resolve(p[1], state)
				var rt := _resolve(p[2], state)
				if rf != "" and rt != "":
					RelationshipGraph.adjust(state, rf, rt, float(p[3]), p[4], state.tick)
					results.append({"kind": "relationship", "from": rf, "to": rt,
						"delta": float(p[3]), "reason": p[4]})
			"schedule":
				state.event_state["scheduled"].append(
					{"event_id": p[1], "due_tick": state.tick + int(p[2])})
				results.append({"kind": "schedule", "event_id": p[1]})
			"branch":
				# branch:<branch_id> — a scripted chapter's fork
				# (data/chapter_branches.csv): schedule the FIRST rule whose
				# `requires` holds, in the table's own order. The rule
				# carries its own delay, so the chapter's calendar lives in
				# the table and not in every choice that reaches it. Every
				# table ends in an `always` rule, so a branch cannot
				# dead-end; a missing table is a loud error, not silence.
				var rules: Array = data.chapter_branches.get(p[1], [])
				if rules.is_empty():
					push_error("EventEffects: no branch table: " + p[1])
				var taken := ""
				for rule: Dictionary in rules:
					if TriggerDsl.evaluate(String(rule["requires"]), state, data):
						taken = String(rule["event_id"])
						state.event_state["scheduled"].append({"event_id": taken,
							"due_tick": state.tick + int(rule["ticks"])})
						break
				if taken == "":
					push_error("EventEffects: branch %s matched no rule" % p[1])
				else:
					results.append({"kind": "branch", "branch_id": p[1], "event_id": taken})
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
