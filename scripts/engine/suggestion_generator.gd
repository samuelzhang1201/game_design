class_name SuggestionGenerator
extends RefCounted

var data: DataRepository
var actions: ActionSystem

func _init(d: DataRepository, a: ActionSystem) -> void:
	data = d
	actions = a

## Each suggestion carries its `source`: "concern" when a scanned concern
## raised the topic this tick, "standing" for the always-available menu
## fillers. The conversation stage offers only concern-driven suggestions as
## reply options (user request 2026-08-31: no default options for topics
## nobody raised); the court order bar shows both.
func generate(state: GameState, concerns: Array) -> Array:
	var out: Array = []
	for concern in concerns:
		for cand in _candidates_for(concern, state):
			if out.size() >= 3:
				break
			if actions.validate(cand["request"], state) == "" and not _duplicate(out, cand):
				cand["source"] = "concern"
				out.append(cand)
	for cand in _standing_menu(state):
		if out.size() >= 3:
			break
		if out.size() < 2 and actions.validate(cand["request"], state) == "" and not _duplicate(out, cand):
			cand["source"] = "standing"
			out.append(cand)
	return out

## One suggestion an order: two laws are two orders, one law twice (easing
## and raising the tax) is one.
func _duplicate(out: Array, cand: Dictionary) -> bool:
	for s in out:
		if _order_key(s["request"]) == _order_key(cand["request"]):
			return true
	return false

func _order_key(req: ActionRequest) -> String:
	return req.action_code + ":" + str(req.params.get("law", ""))

## A LAW_SET suggestion from the decreed value: a range law's `step` (+1 or
## -1) clamped to its range, or a choice's `value`. [] when it would change
## nothing (the law already stands there), so no suggestion re-sends a decree.
func _law_sug(state: GameState, seat: String, law: String, step: int, value: String,
		pitch_key: String, tradeoff: String) -> Array:
	var d := LawSystem.def(data, law)
	if d.is_empty():
		return []
	var now := LawSystem.decreed(data, state, law)
	var to := value
	if String(d["kind"]) == "range":
		to = str(clampi(int(now) + step, int(d["values"][0]), int(d["values"][1])))
	if to == now:
		return []
	return [_sug(seat, ActionRequest.make(LawSystem.ACTION, {"law": law, "value": to}), pitch_key, tradeoff)]

func _sug(seat: String, req: ActionRequest, pitch_key: String, tradeoff: String) -> Dictionary:
	return {"seat": seat, "request": req, "pitch_key": pitch_key, "tradeoff": tradeoff}

func _candidates_for(concern: Dictionary, state: GameState) -> Array:
	match concern["metric"]:
		"grain":
			return _law_sug(state, "steward", "grain_ration", 0, "ration",
					"grain_ration", "Stretches stores through winter; the villages will grumble.") + [
				_sug("steward", ActionRequest.make("BUILD_ECONOMIC", {"project": "granary"}),
					"build_granary", "Costs gold now; we stop losing harvests to rot."),
			]
		"treasury":
			return _law_sug(state, "steward", "tax_rate", 1, "",
					"raise_tax", "Gold now; unrest creeps up while the rate stays high.") \
				+ _law_sug(state, "steward", "church_policy", 0, "tithe",
					"tithe_church", "Quick silver; Father Odo will not thank you.")
		"unrest":
			return _law_sug(state, "chancellor", "tax_rate", -1, "",
					"ease_tax", "Costs income; cools the villages fastest.") \
				+ _law_sug(state, "chancellor", "justice_severity", 1, "",
					"harsh_justice", "Order through fear; contentment pays for it.")
		"church_opinion":
			return _law_sug(state, "chaplain", "church_policy", 0, "endow",
				"endow_church", "Gold for grace; the pulpits turn friendly.")
		"army_quality":
			return [_sug("marshal", ActionRequest.make("LEVY_RAISE"),
				"raise_levies", "Gold and grumbling; the ranks fill out.")]
		"legitimacy":
			return [_sug("spymaster", ActionRequest.make("SPY_MISSION", {"target": "rumors"}),
				"quiet_rumors", "Coin for whispers; the talk in the taverns turns kinder.")]
	return []

func _standing_menu(state: GameState) -> Array:
	return [
		_sug("marshal", ActionRequest.make("LEVY_RAISE"),
			"raise_levies", "Gold and grumbling; the ranks fill out."),
		_sug("steward", ActionRequest.make("BUILD_ECONOMIC", {"project": "road"}),
			"build_road", "Costs gold; trade moves quicker every tick after."),
	] + _law_sug(state, "chaplain", "church_policy", 0, "endow",
		"endow_church", "Gold for grace; the pulpits turn friendly.")
