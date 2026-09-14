class_name ActionSystem
extends RefCounted

var data: DataRepository

## gold cost formula name -> balance key (formulas beyond flat keys come later)
const COST_KEYS := {
	"levy_cost": "levy_cost", "build_cost": "build_cost", "spy_cost": "spy_cost",
	"formula_reward_cost": "reward_gold_cost",
}

const TONE_DELTAS := {
	"respectful": 2, "neutral": 0, "curt": -2, "flattering": 2,
	"threatening": -3, "dismissive": -3,
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
	# The cost row's gold counts too (RECRUIT_COURTIER's retainer, the dowry...),
	# so an order never leaves the chest below zero.
	var needs := gold_cost(row) + OrderCosts.gold_of(data, req.action_code)
	if state.metrics["treasury"] < needs:
		return "Cannot afford %s (needs %d gold)" % [req.action_code, int(needs)]
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
		"MANOR_BUY", "MANOR_SELL", "MANOR_BUILD", "MANOR_SEIZE", "MANOR_FOCUS", "MANOR_DEMOLISH", "MANOR_RUSH":
			return _validate_manor(req, state, needs)
		"GOODS_BUY", "GOODS_SELL":
			var pool := String(req.params.get("pool", ""))
			if not pool in ["strategic", "civil"]:
				return "pool must be strategic|civil"
			var gold := int(req.params.get("gold", 0))
			if gold <= 0:
				return "gold must be a whole number above zero"
			if req.action_code == "GOODS_BUY":
				var price := int(roundf(float(gold) * (1.0 + data.bal("goods_trade_spread"))))
				if state.metrics["treasury"] < price + needs:
					return "Cannot afford %d gold of %s goods (%d with the factor's cut)" % [gold, pool, price]
			else:
				var have := int(state.metrics.get(pool_metric(pool), 0.0))
				if have < gold:
					return "The %s stock holds only %d gold of goods" % [pool, have]
	return ""

## The manor an order names: params.manor (a code, a label in any case, or
## a cell id) or params.cell. -1 for none.
func manor_of(req: ActionRequest) -> int:
	var named := str(req.params.get("manor", req.params.get("cell", "")))
	return MapManors.find(data, named)

## The metric that holds a pool: strategic -> strategic, civil -> grain
## (the civil pool's key, kept for its readers; spec §5).
static func pool_metric(pool: String) -> String:
	return "strategic" if pool == "strategic" else "grain"

## MANOR_SYSTEM.md §5: a manor must exist and lie in the crown's realm; the
## crown buys or seizes what it does not hold and sells or builds on what it
## does; a purchase or a building must be affordable on top of the order's
## own cost; seizing is gated by manor_seize_enabled until the military
## system can resolve it.
func _validate_manor(req: ActionRequest, state: GameState, needs: float) -> String:
	var cell := manor_of(req)
	if cell < 0:
		return "No such manor: %s" % str(req.params.get("manor", req.params.get("cell", "")))
	var label := MapManors.label_of(data, cell)
	var realm := data.resolve_realm("player_realm")
	if MapOwnership.owner_of(data, state, MapManors.province_of(data, cell)) != realm:
		return "%s lies outside the realm" % label
	var crowns := MapManors.is_crowns(data, state, cell)
	match req.action_code:
		"MANOR_BUY":
			if crowns:
				return "The crown already holds %s" % label
			var price := MapManors.price_of(data, state, cell)
			if state.metrics["treasury"] < price + needs:
				return "Cannot afford %s (House %s asks %d gold)" % [label,
					MapManors.owner_of(data, state, cell), int(price)]
		"MANOR_SEIZE":
			if data.bal("manor_seize_enabled") <= 0.0:
				return "Seizing manors is not permitted"
			if crowns:
				return "The crown already holds %s" % label
		"MANOR_SELL":
			if not crowns:
				return "The crown does not hold %s" % label
			var buyer := MapManors.default_owner(data, state, cell)
			if buyer == "" or buyer == MapManors.crown(state):
				return "No house to sell %s to" % label
		"MANOR_BUILD":
			if not crowns:
				return "The crown does not hold %s" % label
			# Building needs the province, not just the manor (owner 2026-09-13):
			# the crown improves the land it controls.
			if not MapManors.crown_controls(data, state, MapManors.province_of(data, cell)):
				return "%s lies in a province the crown does not control" % label
			var building := String(req.params.get("building", ""))
			if not data.manor_buildings.has(building):
				return "No such building: " + building
			if MapManors.has_building(state, cell, building):
				return "%s already has a %s" % [label, String(data.manor_buildings[building]["label"]).to_lower()]
			if MapManors.is_building(state, cell, building):
				return "A %s is already being built at %s" % [String(data.manor_buildings[building]["label"]).to_lower(), label]
			if MapManors.free_slots(data, state, cell) <= 0:
				return "%s has no room: %d of %d slots taken" % [label, MapManors.slots_used(state, cell),
					MapManors.slots_of(data, cell)]
			var civil := int(float(data.manor_buildings[String(req.params.get("building", ""))].get("civil_cost", 0)))
			if int(state.metrics.get("grain", 0.0)) < civil:
				return "Not enough civil goods for a %s at %s (%d needed)" % [
					String(data.manor_buildings[String(req.params.get("building", ""))]["label"]).to_lower(), label, civil]
		"MANOR_RUSH":
			if not crowns:
				return "%s is not the crown's" % label
			var building_r := String(req.params.get("building", ""))
			if MapManors.work_days_left(state, cell, building_r) < 0:
				return "There is no work on a %s at %s" % [building_r, label]
			var days := int(req.params.get("days", 0))
			if days <= 0:
				return "days must be a whole number above zero"
			var price := days * int(data.bal("build_rush_gold_per_day"))
			if state.metrics["treasury"] < price + needs:
				return "Cannot afford to hurry %s by %d days (%d gold)" % [label, days, price]
		"MANOR_DEMOLISH":
			if not crowns:
				return "The crown does not hold %s" % label
			var building := String(req.params.get("building", ""))
			if not data.manor_buildings.has(building):
				return "No such building: " + building
			if not MapManors.has_building(state, cell, building) and not MapManors.is_building(state, cell, building):
				return "There is no %s at %s" % [String(data.manor_buildings[building]["label"]).to_lower(), label]
		"MANOR_FOCUS":
			if not crowns:
				return "The crown does not hold %s" % label
			if not MapManors.crown_controls(data, state, MapManors.province_of(data, cell)):
				return "%s lies in a province the crown does not control" % label
			var focus := String(req.params.get("focus", ""))
			if not data.manor_focus.has(focus):
				return "No such focus: " + focus
			var name := String(data.manor_focus[focus]["label"]).to_lower()
			if not MapManors.focus_allowed(data, cell, focus):
				return "%s cannot work %s on its land" % [label, name]
			if MapManors.focus_of(data, state, cell) == focus:
				return "%s already works %s" % [label, name]
			var fee := float(data.manor_focus[focus]["switch_cost_gold"])
			if state.metrics["treasury"] < fee + needs:
				return "Cannot afford to turn %s to %s (%d gold)" % [label, name, int(fee)]
	return ""

func execute(req: ActionRequest, state: GameState) -> Dictionary:
	var err := validate(req, state)
	assert(err == "", "execute called with invalid request: " + err)
	var row: Dictionary = data.actions[req.action_code]
	# Opinions before, so a direct loss (a punishment) counts as this order's
	# cost without changing the effects shape (OrderCosts).
	var before := OrderCosts.snapshot_opinions(state)
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
				_apply(state, effects, "grain", data.bal("granary_civil_gain"), "a royal granary stocked")
			else:
				_apply(state, effects, "road_income_bonus", data.bal("road_income_gain"), "road improves trade")
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
		"MANOR_BUY":
			var cell := manor_of(req)
			var label := MapManors.label_of(data, cell)
			var seller := MapManors.owner_of(data, state, cell)
			var price := MapManors.price_of(data, state, cell)
			_apply(state, effects, "treasury", -price, "bought %s from House %s" % [label, seller])
			MapManors.set_owner(data, state, cell, MapManors.crown(state),
				"bought from House %s for %d gold" % [seller, int(price)])
			# A house paid well thinks better of the crown, and its councillor
			# is the richer for it.
			for c: Character in _house_members(state, seller):
				c.change_opinion(int(data.bal("manor_trade_goodwill")),
					"the crown paid well for %s" % label, state.tick)
				if state.council.values().has(c.id):
					c.change_attribute("wealth", int(data.bal("manor_trade_wealth")),
						"sold %s to the crown" % label, state.tick)
			effects.append({"metric": "manor", "delta": 1.0,
				"reason": "%s is the crown's, bought from House %s" % [label, seller]})
		"MANOR_SELL":
			var cell := manor_of(req)
			var label := MapManors.label_of(data, cell)
			var buyer := MapManors.default_owner(data, state, cell)
			var price := MapManors.sell_price_of(data, state, cell)
			_apply(state, effects, "treasury", price, "sold %s to House %s" % [label, buyer])
			MapManors.set_owner(data, state, cell, buyer, "sold to House %s for %d gold" % [buyer, int(price)])
			effects.append({"metric": "manor", "delta": -1.0,
				"reason": "%s passed to House %s" % [label, buyer]})
		"MANOR_BUILD":
			var cell := manor_of(req)
			var building := String(req.params["building"])
			var row_b: Dictionary = data.manor_buildings[building]
			var label := MapManors.label_of(data, cell)
			_apply(state, effects, "grain", -float(int(float(row_b.get("civil_cost", 0)))),
				"timber and stone for a %s at %s" % [String(row_b["label"]).to_lower(), label])
			MapManors.start_work(data, state, cell, building, "begun by the crown")
			effects.append({"metric": "manor", "delta": 0.0,
				"reason": "a %s is begun at %s, %d days' work" % [String(row_b["label"]).to_lower(), label,
					int(float(row_b.get("build_days", 0)))]})
		"MANOR_RUSH":
			var cell := manor_of(req)
			var building := String(req.params["building"])
			var days := int(req.params["days"])
			var label := MapManors.label_of(data, cell)
			var cut := MapManors.rush_work(data, state, cell, building, days, "hurried by the crown")
			_apply(state, effects, "treasury", -float(cut * int(data.bal("build_rush_gold_per_day"))),
				"hurried the %s at %s by %d days" % [building, label, cut])
			effects.append({"metric": "manor", "delta": 0.0,
				"reason": "the %s at %s is %d days nearer done" % [building, label, cut]})
		"MANOR_DEMOLISH":
			var cell := manor_of(req)
			var building := String(req.params["building"])
			var row_d: Dictionary = data.manor_buildings[building]
			var label := MapManors.label_of(data, cell)
			var stood := MapManors.has_building(state, cell, building)
			var refund := MapManors.demolish(data, state, cell, building,
				"pulled down by the crown" if stood else "the work stopped by the crown")
			_apply(state, effects, "treasury", maxf(refund, 0.0),
				"the stones and timber of the %s at %s" % [String(row_d["label"]).to_lower(), label])
			effects.append({"metric": "manor", "delta": 0.0,
				"reason": ("the %s at %s is pulled down" if stood else "the %s at %s is left unbuilt") % [
					String(row_d["label"]).to_lower(), label]})
		"MANOR_FOCUS":
			var cell := manor_of(req)
			var focus := String(req.params["focus"])
			var row_f: Dictionary = data.manor_focus[focus]
			var label := MapManors.label_of(data, cell)
			var was := String((data.manor_focus.get(MapManors.focus_of(data, state, cell), {}) as Dictionary).get("label", "nothing")).to_lower()
			_apply(state, effects, "treasury", -float(row_f["switch_cost_gold"]),
				"turned %s to %s" % [label, String(row_f["label"]).to_lower()])
			MapManors.set_focus(data, state, cell, focus, "turned from %s to %s by the crown" % [was, String(row_f["label"]).to_lower()])
			effects.append({"metric": "manor", "delta": 0.0,
				"reason": "%s turns to %s; %d ticks to settle in" % [label, String(row_f["label"]).to_lower(), int(float(row_f["transition_ticks"]))]})
		"MANOR_SEIZE":
			# The skeleton (MANOR_SYSTEM.md §5): the outcome is automatic success
			# until the military system can roll defence against the host.
			var cell := manor_of(req)
			var label := MapManors.label_of(data, cell)
			var victim := MapManors.owner_of(data, state, cell)
			MapManors.set_owner(data, state, cell, MapManors.crown(state),
				"seized by force from House %s" % victim)
			_apply(state, effects, "legitimacy", -data.bal("manor_seize_legitimacy"),
				"took %s by force" % label)
			_apply(state, effects, "unrest", data.bal("manor_seize_unrest"),
				"the seizure of %s" % label)
			for c: Character in _house_members(state, victim):
				c.change_opinion(-int(data.bal("manor_seize_outrage")),
					"the crown seized %s from their house" % label, state.tick)
			effects.append({"metric": "manor", "delta": 1.0,
				"reason": "%s taken from House %s by force" % [label, victim]})
		"GOODS_BUY":
			var pool := String(req.params["pool"])
			var gold := int(req.params["gold"])
			var price := int(roundf(float(gold) * (1.0 + data.bal("goods_trade_spread"))))
			_apply(state, effects, "treasury", float(-price), "bought %d gold of %s goods" % [gold, pool])
			_apply(state, effects, pool_metric(pool), float(gold), "%s goods bought" % pool)
		"GOODS_SELL":
			var pool := String(req.params["pool"])
			var gold := int(req.params["gold"])
			var paid := int(roundf(float(gold) * (1.0 - data.bal("goods_trade_spread"))))
			_apply(state, effects, pool_metric(pool), float(-gold), "%s goods sold" % pool)
			_apply(state, effects, "treasury", float(paid), "sold %d gold of %s goods" % [gold, pool])
	var cd := int(row.get("cooldown_ticks", 0))
	if cd > 0:
		state.cooldowns[req.action_code] = state.tick + cd
	var drift := OpinionDrift.apply(data, state,
		OpinionDrift.signature_for(data, req.action_code, req.params),
		String(row["label"]))
	for pr in state.promises:
		if String(pr["status"]) != "open":
			continue
		if String(pr["promise_code"]) != req.action_code:
			continue
		if req.target != "" and req.target != String(pr["character_id"]):
			continue
		pr["status"] = "kept"
		var who: String = String(pr["character_id"])
		if state.characters.has(who):
			state.characters[who].change_opinion(int(data.bal("promise_kept_opinion")),
				"a promise kept: " + String(row["label"]), state.tick)
			# Kept promises apply the opinion delta above but, unlike every
			# other opinion-affecting branch here, had no corresponding entry
			# in `effects` — so the effects-driven narration path (both
			# ConversationScene and CourtScreen's own _promise_kept_suffix)
			# never voiced it and the promise_kept template row went
			# unreachable. This pseudo-effect
			# isn't a real metric mutation (nothing named "promise" lives in
			# state.metrics); it exists solely so the existing effects-driven
			# narration path picks it up for free.
			effects.append({"metric": "promise", "delta": data.bal("promise_kept_opinion"),
				"reason": "a promise kept: " + String(row["label"])})
	# Every order carries a cost (spec 2026-09-09 §3): always-rows ride along
	# every time, the fallback row only when nothing above cost anything.
	if OrderCosts.always(data, req.action_code):
		effects.append_array(OrderCosts.charge(data, state, req.action_code, req.target))
	else:
		OrderCosts.ensure(data, state, effects, drift, before, req.action_code, req.target)
	state.event_state["last_action_tick"][req.action_code] = state.tick
	var outcome := {"action_code": req.action_code, "ok": true, "effects": effects,
		"notes": String(row["label"]), "target": req.target, "params": req.params.duplicate(),
		"drift": drift}
	state.recent_outcomes.append(outcome)
	return outcome

## Every character of a house, for a trade's goodwill or a seizure's outrage.
func _house_members(state: GameState, family: String) -> Array:
	var out: Array = []
	if family == "":
		return out
	for id in state.characters:
		var c: Character = state.characters[id]
		if c.family_name == family:
			out.append(c)
	return out

func _apply(state: GameState, effects: Array, metric: String, delta: float, reason: String) -> void:
	state.metrics[metric] = state.metrics[metric] + delta
	effects.append({"metric": metric, "delta": delta, "reason": reason})

func _set_metric(state: GameState, effects: Array, metric: String, value: float, reason: String) -> void:
	var delta: float = value - state.metrics[metric]
	state.metrics[metric] = value
	effects.append({"metric": metric, "delta": delta, "reason": reason})

func apply_court_reaction(cr: Dictionary, state: GameState) -> void:
	var cap := int(data.bal("tone_delta_cap"))
	var delta: int = clampi(TONE_DELTAS.get(cr.get("tone", "neutral"), 0), -cap, cap)
	for id in cr.get("addressed", []):
		if state.characters.has(id) and delta != 0:
			state.characters[id].change_opinion(delta, "tone: " + cr["tone"], state.tick)
	for p in cr.get("promises", []):
		var due := int(p["tick_due"])
		if due <= 0:
			due = state.tick + int(data.bal("promise_default_ticks"))
		state.promises.append({"character_id": p["character_id"],
			"promise_code": p["promise_code"], "made_tick": state.tick,
			"tick_due": due, "status": "open"})
