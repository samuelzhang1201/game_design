class_name ActionSystem
extends RefCounted

var data: DataRepository

## gold cost formula name -> balance key (formulas beyond flat keys come later)
const COST_KEYS := {
	"levy_cost": "levy_cost", "build_cost": "build_cost", "spy_cost": "spy_cost",
	"formula_reward_cost": "reward_gold_cost",
}

func _init(d: DataRepository) -> void:
	data = d

func gold_cost(row: Dictionary) -> float:
	var formula: String = row.get("gold_cost_formula", "none")
	if formula == "none" or formula == "":
		return 0.0
	if COST_KEYS.has(formula):
		return data.bal(COST_KEYS[formula])
	return 0.0  # unknown formulas are free in slice 1; slice 2 adds real formulas

func validate(req: ActionRequest, state: GameState) -> String:
	if not data.actions.has(req.action_code):
		return "Unknown action: " + req.action_code
	var row: Dictionary = data.actions[req.action_code]
	if state.cooldowns.get(req.action_code, 0) > state.tick:
		return "%s is on cooldown until tick %d" % [req.action_code, state.cooldowns[req.action_code]]
	if state.metrics["treasury"] < gold_cost(row):
		return "Cannot afford %s (needs %d gold)" % [req.action_code, int(gold_cost(row))]
	if row.get("target_type", "none") == "character" and not state.characters.has(req.target):
		return "No such target character for " + req.action_code
	match req.action_code:
		"TAX_RATE_ADJUST", "TARIFF_ADJUST":
			var d := int(req.params.get("delta", 0))
			if d < -3 or d > 3 or d == 0:
				return "delta must be -3..3 and nonzero"
		"JUSTICE_SEVERITY":
			var d := int(req.params.get("delta", 0))
			if d < -2 or d > 2 or d == 0:
				return "delta must be -2..2 and nonzero"
		"GRAIN_POLICY_SET":
			if not req.params.get("mode", "") in ["market", "ration", "release"]:
				return "mode must be market|ration|release"
		"CHURCH_POLICY":
			if not req.params.get("mode", "") in ["endow", "tithe"]:
				return "mode must be endow|tithe"
		"BUILD_ECONOMIC":
			if not req.params.get("project", "") in ["granary", "road"]:
				return "project must be granary|road"
		"CHARACTER_REWARD":
			if not req.params.get("mode", "gold") in ["gold"]:
				return "mode must be gold (slice 1)"
	return ""

func execute(req: ActionRequest, state: GameState) -> Dictionary:
	var err := validate(req, state)
	assert(err == "", "execute called with invalid request: " + err)
	var row: Dictionary = data.actions[req.action_code]
	var effects: Array = []
	var cost := gold_cost(row)
	if cost > 0.0:
		_apply(state, effects, "treasury", -cost, "paid for " + String(row["label"]))
	match req.action_code:
		"TAX_RATE_ADJUST":
			var d := int(req.params["delta"])
			var new_rate := clampf(state.metrics["tax_rate"] + d, 1.0, 10.0)
			_set_metric(state, effects, "tax_rate", new_rate, "adjusted the tax rate")
		"TARIFF_ADJUST":
			var d := int(req.params["delta"])
			var new_rate := clampf(state.metrics["tariff_rate"] + d, 0.0, 10.0)
			_set_metric(state, effects, "tariff_rate", new_rate, "adjusted tariffs")
		"LEVY_RAISE":
			_apply(state, effects, "army_quality", data.bal("levy_army_gain"), "fresh levies drilled")
			_apply(state, effects, "unrest", data.bal("levy_unrest"), "villages resent the levy")
		"GRAIN_POLICY_SET":
			var mode: String = req.params["mode"]
			_set_metric(state, effects, "grain_ration", 1.0 if mode == "ration" else 0.0, "grain policy: " + mode)
			if mode == "ration":
				_apply(state, effects, "peasant_contentment", data.bal("grain_ration_contentment"), "rationing bites")
			elif mode == "release":
				_apply(state, effects, "grain", -data.bal("grain_release_amount"), "stores opened")
				_apply(state, effects, "peasant_contentment", data.bal("grain_release_contentment"), "grain released to the people")
		"CHURCH_POLICY":
			if req.params["mode"] == "endow":
				_apply(state, effects, "treasury", -data.bal("church_endow_cost"), "endowed the church")
				_apply(state, effects, "church_opinion", data.bal("church_endow_gain"), "the church blessed the endowment")
			else:
				_apply(state, effects, "treasury", data.bal("church_tithe_gain"), "tithed the church")
				_apply(state, effects, "church_opinion", data.bal("church_tithe_opinion"), "the church resents the tithe")
		"JUSTICE_SEVERITY":
			var d := int(req.params["delta"])
			_apply(state, effects, "unrest", data.bal("justice_unrest_per_point") * d, "justice severity changed")
			_apply(state, effects, "peasant_contentment", data.bal("justice_contentment_per_point") * d, "harsher courts")
		"BUILD_ECONOMIC":
			if req.params["project"] == "granary":
				_apply(state, effects, "grain_capacity_bonus", 50.0, "granary raised")
			else:
				_apply(state, effects, "road_income_bonus", 2.0, "road improves trade")
		"SPY_MISSION":
			_apply(state, effects, "legitimacy", data.bal("spy_legitimacy_gain"), "rumors quietly answered")
		"COUNCIL_CONSULT":
			pass  # outcome record only; the Voicer renders the consult
		"CHARACTER_REWARD":
			var c: Character = state.characters[req.target]
			var gain := int(data.bal("reward_opinion"))
			if "vain" in c.traits:
				gain += int(data.bal("reward_opinion_vain_bonus"))
			c.change_opinion(gain, "rewarded with gold", state.tick)
		"CHARACTER_PUNISH":
			state.characters[req.target].change_opinion(
				int(data.bal("punish_opinion")), "publicly reprimanded", state.tick)
		"CHARACTER_CONFIDE":
			state.characters[req.target].change_opinion(
				int(data.bal("confide_opinion")), "you confided in them", state.tick)
	var cd := int(row.get("cooldown_ticks", 0))
	if cd > 0:
		state.cooldowns[req.action_code] = state.tick + cd
	var outcome := {"action_code": req.action_code, "ok": true, "effects": effects,
		"notes": String(row["label"]), "target": req.target, "params": req.params.duplicate()}
	state.recent_outcomes.append(outcome)
	return outcome

func _apply(state: GameState, effects: Array, metric: String, delta: float, reason: String) -> void:
	state.metrics[metric] = state.metrics[metric] + delta
	effects.append({"metric": metric, "delta": delta, "reason": reason})

func _set_metric(state: GameState, effects: Array, metric: String, value: float, reason: String) -> void:
	var delta: float = value - state.metrics[metric]
	state.metrics[metric] = value
	effects.append({"metric": metric, "delta": delta, "reason": reason})
