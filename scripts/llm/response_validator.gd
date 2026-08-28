class_name ResponseValidator
extends RefCounted

const TONES := ["respectful", "neutral", "curt", "flattering", "threatening", "dismissive"]

static func parse(json_text: String, data: DataRepository) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg, "actions": [], "court_reaction": _neutral()}
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		return fail.call("not valid JSON")
	var actions: Array = []
	var raw_actions = parsed.get("actions", [])
	if not raw_actions is Array:
		return fail.call("actions must be a list")
	for a in raw_actions:
		if not a is Dictionary or not a.get("action_code") is String:
			return fail.call("malformed action entry")
		var code: String = a["action_code"]
		if not data.actions.has(code):
			return fail.call("unknown action: " + code)
		var params = a.get("params", {})
		if not params is Dictionary:
			return fail.call("params must be an object")
		actions.append(ActionRequest.make(code, params, String(a.get("target", ""))))
	var cr = parsed.get("court_reaction", null)
	var reaction := _neutral()
	if cr != null:
		if not cr is Dictionary:
			return fail.call("court_reaction must be an object")
		var tone := String(cr.get("tone", "neutral"))
		if not tone in TONES:
			return fail.call("invalid tone: " + tone)
		reaction["tone"] = tone
		var addressed = cr.get("addressed", null)
		if addressed != null:
			if not addressed is Array:
				return fail.call("addressed must be a list")
			for id in addressed:
				reaction["addressed"].append(String(id))
		var promises = cr.get("promises", null)
		if promises != null:
			if not promises is Array:
				return fail.call("promises must be a list")
			for p in promises:
				if p is Dictionary and p.has("character_id") and p.has("promise_code"):
					reaction["promises"].append({
						"character_id": String(p["character_id"]),
						"promise_code": String(p["promise_code"]),
						"tick_due": int(p.get("tick_due", 0)),
					})
	return {"ok": true, "error": "", "actions": actions, "court_reaction": reaction}

static func _neutral() -> Dictionary:
	return {"addressed": [], "tone": "neutral", "promises": []}
