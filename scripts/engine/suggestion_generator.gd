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

func _duplicate(out: Array, cand: Dictionary) -> bool:
	for s in out:
		if s["request"].action_code == cand["request"].action_code:
			return true
	return false

func _sug(seat: String, req: ActionRequest, pitch_key: String, tradeoff: String) -> Dictionary:
	return {"seat": seat, "request": req, "pitch_key": pitch_key, "tradeoff": tradeoff}

func _candidates_for(concern: Dictionary, _state: GameState) -> Array:
	match concern["metric"]:
		"grain":
			return [
				_sug("steward", ActionRequest.make("GRAIN_POLICY_SET", {"mode": "ration"}),
					"grain_ration", "Stretches stores through winter; the villages will grumble."),
				_sug("steward", ActionRequest.make("BUILD_ECONOMIC", {"project": "granary"}),
					"build_granary", "Costs gold now; we stop losing harvests to rot."),
			]
		"treasury":
			return [
				_sug("steward", ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}),
					"raise_tax", "Gold now; unrest creeps up while the rate stays high."),
				_sug("steward", ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}),
					"tithe_church", "Quick silver; Father Odo will not thank you."),
			]
		"unrest":
			return [
				_sug("chancellor", ActionRequest.make("TAX_RATE_ADJUST", {"delta": -1}),
					"ease_tax", "Costs income; cools the villages fastest."),
				_sug("chancellor", ActionRequest.make("JUSTICE_SEVERITY", {"delta": 1}),
					"harsh_justice", "Order through fear; contentment pays for it."),
			]
		"church_opinion":
			return [_sug("chaplain", ActionRequest.make("CHURCH_POLICY", {"mode": "endow"}),
				"endow_church", "Gold for grace; the pulpits turn friendly.")]
		"army_quality":
			return [_sug("marshal", ActionRequest.make("LEVY_RAISE"),
				"raise_levies", "Gold and grumbling; the ranks fill out.")]
		"legitimacy":
			return [_sug("spymaster", ActionRequest.make("SPY_MISSION", {"target": "rumors"}),
				"quiet_rumors", "Coin for whispers; the talk in the taverns turns kinder.")]
	return []

func _standing_menu(_state: GameState) -> Array:
	return [
		_sug("marshal", ActionRequest.make("LEVY_RAISE"),
			"raise_levies", "Gold and grumbling; the ranks fill out."),
		_sug("steward", ActionRequest.make("BUILD_ECONOMIC", {"project": "road"}),
			"build_road", "Costs gold; trade moves quicker every tick after."),
		_sug("chaplain", ActionRequest.make("CHURCH_POLICY", {"mode": "endow"}),
			"endow_church", "Gold for grace; the pulpits turn friendly."),
	]
