class_name ResponseValidator
extends RefCounted

const TONES := ["respectful", "neutral", "curt", "flattering", "threatening", "dismissive"]

## The legacy parse reply: {actions, court_reaction} only.
static func parse(json_text: String, data: DataRepository) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg, "actions": [], "court_reaction": _neutral()}
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		return fail.call("not valid JSON")
	var acts := _parse_actions(parsed.get("actions", []), data)
	if not acts["ok"]:
		return fail.call(acts["error"])
	var cr := _parse_reaction(parsed.get("court_reaction", null), data)
	if not cr["ok"]:
		return fail.call(cr["error"])
	return {"ok": true, "error": "", "actions": acts["actions"], "court_reaction": cr["reaction"]}

## The two-part order reply (spec 2026-09-09 §4). Per-impact faults are
## reported in world_rejected, never fatal; malformed JSON or an unknown
## action still fails the whole reply. The flat legacy shape (actions at the
## top level) is accepted so older canned replies keep working.
static func parse_order(json_text: String, data: DataRepository, state: GameState) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg, "narrative": "", "actions": [], "world": [],
			"world_rejected": [], "court_reaction": _neutral()}
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		return fail.call("not valid JSON")
	var impacts = parsed.get("impacts", parsed)
	if not impacts is Dictionary:
		return fail.call("impacts must be an object")
	var acts := _parse_actions(impacts.get("actions", []), data)
	if not acts["ok"]:
		return fail.call(acts["error"])
	var cr := _parse_reaction(impacts.get("court_reaction", null), data)
	if not cr["ok"]:
		return fail.call(cr["error"])
	var narrative := String(parsed.get("narrative", "")).strip_edges()
	var cap := int(data.bal("order_narrative_max_chars"))
	if narrative.length() > cap:
		narrative = narrative.substr(0, cap)
	var world: Array = []
	var world_rejected: Array = []
	var raw_world = impacts.get("world", [])
	if raw_world is Array:
		for imp in raw_world:
			var checked := _check_impact(imp, data, state)
			if checked.has("error"):
				world_rejected.append(checked)
			else:
				world.append(checked)
	# An empty reply (no words, no actions, no impacts) is not an error: the
	# screens fall back to "So noted." — the same as a legacy no-action parse.
	return {"ok": true, "error": "", "narrative": narrative, "actions": acts["actions"],
		"world": world, "world_rejected": world_rejected, "court_reaction": cr["reaction"]}

## One proposed world delta: needs a reason, a number, a schema row the model
## may move (llm_cap > 0, not an enum), and a field of the player's own realm.
## The delta is clamped to the cap and flagged when it was.
static func _check_impact(imp, data: DataRepository, state: GameState) -> Dictionary:
	if not imp is Dictionary:
		return {"path": "", "error": "malformed impact"}
	var path := String(imp.get("path", ""))
	var reason := String(imp.get("reason", "")).strip_edges()
	if reason == "":
		return {"path": path, "error": "an impact needs a reason"}
	var raw_delta = imp.get("delta", null)
	if not (raw_delta is float or raw_delta is int):
		return {"path": path, "error": "delta must be a number"}
	var row := WorldLedger.schema_for(data, path)
	if row.is_empty():
		return {"path": path, "error": "no such field"}
	if String(row.get("type", "")) == "enum":
		return {"path": path, "error": "not a number the court can move"}
	var cap := WorldLedger.llm_cap(data, path)
	if cap <= 0.0:
		return {"path": path, "error": "engine-only field"}
	if not WorldLedger.belongs_to_player(data, state, path):
		return {"path": path, "error": "not yours to move"}
	var delta := float(raw_delta)
	var clamped := absf(delta) > cap
	return {"path": path, "delta": clampf(delta, -cap, cap), "reason": reason, "clamped": clamped}

static func _parse_actions(raw_actions, data: DataRepository) -> Dictionary:
	var actions: Array = []
	if not raw_actions is Array:
		return {"ok": false, "error": "actions must be a list", "actions": []}
	for a in raw_actions:
		if not a is Dictionary or not a.get("action_code") is String:
			return {"ok": false, "error": "malformed action entry", "actions": []}
		var code: String = a["action_code"]
		var params = a.get("params", {})
		if not params is Dictionary:
			return {"ok": false, "error": "params must be an object", "actions": []}
		if code == "EVENT_CHOICE":
			actions.append(ActionRequest.make(code, params, String(a.get("target", ""))))
			continue
		if not data.actions.has(code):
			return {"ok": false, "error": "unknown action: " + code, "actions": []}
		actions.append(ActionRequest.make(code, params, String(a.get("target", ""))))
	return {"ok": true, "error": "", "actions": actions}

static func _parse_reaction(cr, data: DataRepository) -> Dictionary:
	var reaction := _neutral()
	if cr == null:
		return {"ok": true, "error": "", "reaction": reaction}
	if not cr is Dictionary:
		return {"ok": false, "error": "court_reaction must be an object", "reaction": reaction}
	var tone := String(cr.get("tone", "neutral"))
	if not tone in TONES:
		return {"ok": false, "error": "invalid tone: " + tone, "reaction": reaction}
	reaction["tone"] = tone
	var addressed = cr.get("addressed", null)
	if addressed != null:
		if not addressed is Array:
			return {"ok": false, "error": "addressed must be a list", "reaction": reaction}
		for id in addressed:
			reaction["addressed"].append(String(id))
	var promises = cr.get("promises", null)
	if promises != null:
		if not promises is Array:
			return {"ok": false, "error": "promises must be a list", "reaction": reaction}
		for p in promises:
			if p is Dictionary and p.has("character_id") and p.has("promise_code"):
				var promise_code: String = String(p["promise_code"])
				if not data.actions.has(promise_code):
					return {"ok": false, "error": "unknown promise action: " + promise_code,
						"reaction": reaction}
				reaction["promises"].append({
					"character_id": String(p["character_id"]),
					"promise_code": promise_code,
					"tick_due": int(p.get("tick_due", 0)),
				})
	return {"ok": true, "error": "", "reaction": reaction}

static func _neutral() -> Dictionary:
	return {"addressed": [], "tone": "neutral", "promises": []}
