class_name LawSystem
extends RefCounted
## The laws (spec 2026-10-08-laws-tab-design §2): data-driven rules the crown
## decrees and each place follows. This file holds the tables' reads and the
## state's seeding, and the order LAW_SET: who it is sent to, the couriers
## that carry it and what their arrival writes (§3).
##
## A law's value is always a String ("on", a choice's name, a range's digits),
## stored that way in every state map; `number` gives a range's int.
## State: `GameState.law_decree` (what the crown decreed), `law_in_force` (what
## each place or unit follows), `law_cooldown`. A place with no entry follows
## the law's default.

## The scope key of a province's entry in `law_in_force`.
const PROVINCE_PREFIX := "province:"
const TOWN_PREFIX := "town:"
const UNIT_PREFIX := "unit:"

## Publish the law scopes prepared on an atomic military transaction.
static func commit_scopes(state: GameState, candidate: GameState) -> void:
	state.law_in_force = candidate.law_in_force

## Organization changes inherit delivered law versions without issuing a
## new decree or replaying its effects. Every child's entry is independent.
static func inherit_unit_scopes(state: GameState, source: String, children: Array) -> void:
	var key := UNIT_PREFIX + source
	if not state.law_in_force.has(key):
		return
	for child: String in children:
		state.law_in_force[UNIT_PREFIX + child] = state.law_in_force[key].duplicate(true)

## The three laws that mirror a realm-wide metric: law -> metric key. The
## metric is the law's initial value and its display mirror (spec §2.5).
const METRIC_OF := {"tax_rate": "tax_rate", "tariff_rate": "tariff_rate", "grain_ration": "grain_ration"}

## A law's row; {} for a code that is no law.
static func def(repo: DataRepository, law: String) -> Dictionary:
	return repo.laws.get(law, {})

## The laws on one page (economy | politics | military), in file order.
static func codes_on(repo: DataRepository, tab: String) -> Array:
	var out: Array = []
	for code: String in repo.law_order:
		if String(repo.laws[code]["tab"]) == tab:
			out.append(code)
	return out

## The value a metric stands for, as the law's String: the rates are their
## whole digits, the grain ration is `ration` above zero and `market` at zero.
static func metric_value(law: String, state: GameState, fallback: String) -> String:
	if not METRIC_OF.has(law) or not state.metrics.has(String(METRIC_OF[law])):
		return fallback
	var m: float = state.metrics[String(METRIC_OF[law])]
	if law == "grain_ration":
		return "ration" if m > 0.0 else "market"
	return str(int(m))

## What the crown has decreed. With no law state at all (a hand-built test
## state, R8) the metric stands in; a law with no entry reads its default.
static func decreed(repo: DataRepository, state: GameState, law: String) -> String:
	var d := def(repo, law)
	if d.is_empty():
		return ""
	if state.law_decree.has(law):
		return String(state.law_decree[law]["value"])
	if state.law_decree.is_empty():
		return metric_value(law, state, String(d["default"]))
	return String(d["default"])

## The value in force in one place: a province code for a province-scoped law,
## a unit code for a camp-scoped one. The place's own entry; else the metric
## when the law state is empty (R8); else the law's default (R13: a province
## annexed after the start, a unit no courier has reached). A repository
## without the law (a hand-built test one) reads the metric, else "".
static func value(repo: DataRepository, state: GameState, law: String, scope_code: String) -> String:
	var d := def(repo, law)
	if d.is_empty():
		# a hand-built repository with no law tables (R8): the metric
		return metric_value(law, state, "")
	var entry := {}
	if String(d["scope"]) == "province":
		entry = _entry_of(state, PROVINCE_PREFIX + scope_code, law)
	else:
		# A unit camped by a held town follows the newer of the town's entry
		# and its own (a newer decree it carried in is not forgotten, spec
		# §2.4); one in the field or on the march follows its own (§2.3).
		entry = _camp_read(state, ArmyGround.camped_by(repo, state, scope_code), scope_code, law)
	if not entry.is_empty():
		return String(entry["value"])
	if state.law_decree.is_empty():
		return metric_value(law, state, String(d["default"]))
	return String(d["default"])

## `law`'s entry in the place `key` ({value, decree_id}), {} for none.
static func _entry_of(state: GameState, key: String, law: String) -> Dictionary:
	return (state.law_in_force.get(key, {}) as Dictionary).get(law, {})


## What a unit camped by `town` ("" for none) follows of a camp law: the
## entry with the HIGHER decree_id of the town's and its own (the town's on a
## tie); its own alone out of camp. {} for neither.
static func _camp_read(state: GameState, town: String, code: String, law: String) -> Dictionary:
	var own := _entry_of(state, UNIT_PREFIX + code, law)
	if town == "":
		return own
	var camp := _entry_of(state, TOWN_PREFIX + town, law)
	if camp.is_empty() or (not own.is_empty() and int(own["decree_id"]) > int(camp["decree_id"])):
		return own
	return camp


## The unit `code` makes what it follows round `town` its own entry, law by
## law (spec §2.4): the higher decree of its own and the camp's.
static func _take_camp(repo: DataRepository, state: GameState, code: String, town: String) -> void:
	if town == "":
		return
	for law: String in repo.law_order:
		if String(repo.laws[law]["scope"]) != "camp":
			continue
		var read := _camp_read(state, town, code, law)
		if read.is_empty() or read == _entry_of(state, UNIT_PREFIX + code, law):
			continue
		var here: Dictionary = state.law_in_force.get(UNIT_PREFIX + code, {})
		here[law] = read.duplicate()
		state.law_in_force[UNIT_PREFIX + code] = here


## A unit has settled into a camp (ArmyGround.settle, take_seat): it takes,
## law by law, the newer of its own decree and the camp's. The town's entry
## is a courier's alone to write.
static func on_settle(repo: DataRepository, state: GameState, code: String) -> void:
	_take_camp(repo, state, code, ArmyGround.camped_by(repo, state, code))


## A unit is leaving its camp (ArmyGround.leave, before its camp_town is
## cleared — its march order already stands): what it read there becomes its
## own entry, so it marches on under the same laws.
static func on_leave(repo: DataRepository, state: GameState, code: String) -> void:
	var entry: Dictionary = state.regiments.get(code, {})
	var reg := ArmySystem.regiment(repo, code, state)
	var town := String(entry.get("camp_town", ""))
	if town == "" or reg.is_empty() or not ArmyGround.holds(repo, state, String(reg["kingdom_code"]), town):
		return
	_take_camp(repo, state, code, town)


## The held towns with a camp: those a land unit of the realm is camped by.
static func _camped_towns(repo: DataRepository, state: GameState) -> Dictionary:
	var out := {}
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_naval", "0")) != "1":
			var town := ArmyGround.camped_by(repo, state, String(r["regiment_code"]))
			if town != "":
				out[town] = true
	return out


## Whether `code` is a land unit of the realm: the only units a camp law
## binds (fleets, foes and other kingdoms' columns follow none).
static func _realm_land(repo: DataRepository, state: GameState, code: String) -> bool:
	var reg := ArmySystem.regiment(repo, code, state)
	return not reg.is_empty() and not ArmySystem.is_foe(state, code) and String(reg.get("is_naval", "0")) != "1" \
		and String(reg.get("kingdom_code", "")) == repo.resolve_realm("player_realm")


## The day's forgetting (TickEngine._end_day, after ArmyGround.reconcile; spec
## §2.4): a province the realm no longer holds loses its entries — retaken, it
## reads the default until a courier reaches it (R13) — and so does a town the
## realm no longer holds or that has no camp left; the realm's units still
## camped round a lost town first keep what they followed there (another
## kingdom's never take a law). A unit's entry goes with the unit (gone, or
## no land unit of the realm's any more).
static func reconcile(repo: DataRepository, state: GameState) -> void:
	var realm := repo.resolve_realm("player_realm")
	var camped := _camped_towns(repo, state)
	var keys := state.law_in_force.keys()
	keys.sort()
	for k in keys:
		var key := String(k)
		if key.begins_with(PROVINCE_PREFIX):
			if MapOwnership.owner_of(repo, state, key.trim_prefix(PROVINCE_PREFIX)) != realm:
				state.law_in_force.erase(key)
		elif key.begins_with(TOWN_PREFIX):
			var town := key.trim_prefix(TOWN_PREFIX)
			if camped.has(town):
				continue
			var codes := state.regiments.keys()
			codes.sort()
			for c in codes:
				if String((state.regiments[c] as Dictionary).get("camp_town", "")) == town \
						and _realm_land(repo, state, String(c)):
					_take_camp(repo, state, String(c), town)
			state.law_in_force.erase(key)
		elif key.begins_with(UNIT_PREFIX):
			if not _realm_land(repo, state, key.trim_prefix(UNIT_PREFIX)):
				state.law_in_force.erase(key)


## A value as a number: a range's own int; a toggle 0 or 1 (its second name is
## "on"); a choice its index among the allowed names. With no such law
## (a hand-built repository) whole digits are their int, anything else 0.
static func as_number(repo: DataRepository, law: String, text: String) -> int:
	var d := def(repo, law)
	if d.is_empty():
		return int(text) if text.is_valid_int() else 0
	if String(d["kind"]) == "range":
		return int(text)
	return maxi((d["values"] as Array).find(text), 0)

## `value` as a number.
static func number(repo: DataRepository, state: GameState, law: String, scope_code: String) -> int:
	return as_number(repo, law, value(repo, state, law, scope_code))

## A province's people: rural plus urban, the figures `TickEngine.court_people`
## sums. The weight of `weighted_number` and of the one-shots' shares.
static func people_of(repo: DataRepository, state: GameState, code: String) -> int:
	return RealmEconomy._figure(repo, state, "economy.provinces.%s.rural_population" % code) \
		+ RealmEconomy._figure(repo, state, "economy.provinces.%s.urban_population" % code)

## The in-force numbers of the realm's provinces weighted by each province's
## people (rural plus urban, the figures `TickEngine.court_people` sums).
## With no people anywhere, what a place with no entry reads (the default;
## the metric with no law state, R8).
static func weighted_number(repo: DataRepository, state: GameState, law: String) -> float:
	var weighted := 0
	var people := 0
	for code: String in MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")):
		var here := people_of(repo, state, code)
		weighted += here * number(repo, state, law, code)
		people += here
	if people == 0:
		return float(number(repo, state, law, ""))
	return float(weighted) / float(people)

## Seed the laws at a new reign: every law decreed at its default (the three
## metric-mirrored ones at the metric's value), every province the realm holds
## following the decree. Military laws start with no in-force entry; every
## unit reads the default.
static func seed(repo: DataRepository, state: GameState) -> void:
	state.law_decree = {}
	state.law_in_force = {}
	state.law_cooldown = {}
	for law: String in repo.law_order:
		state.law_decree[law] = {"value": metric_value(law, state, String(repo.laws[law]["default"])),
			"decree_id": 0, "day": 0}
	for code: String in MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")):
		var entry := {}
		for law: String in repo.law_order:
			if String(repo.laws[law]["scope"]) == "province":
				entry[law] = {"value": String(state.law_decree[law]["value"]), "decree_id": 0}
		state.law_in_force[PROVINCE_PREFIX + code] = entry

## Seed only a state that has no laws yet (Game.load_campaign: a save from
## before the laws; its decreed values come from the metrics).
static func ensure(repo: DataRepository, state: GameState) -> void:
	if state.law_decree.is_empty():
		LawSystem.seed(repo, state)


## The order that decrees a law (§3).
const ACTION := "LAW_SET"


## A value as the law's String: a whole number (or a float that is one) its
## digits, anything else its text.
static func value_text(raw: Variant) -> String:
	if raw is int:
		return str(raw)
	if raw is float and is_equal_approx(float(raw), roundf(float(raw))):
		return str(int(roundf(float(raw))))
	return str(raw).strip_edges()


## A param as the law's own value: `value_text`, and a range's whole number
## in its plain digits ("06" and "+6" are "6"), so the stored value is one
## spelling and an unchanged value reads as unchanged.
static func canonical(repo: DataRepository, law: String, raw: Variant) -> String:
	var text := value_text(raw)
	if String(def(repo, law).get("kind", "")) == "range" and text.is_valid_int():
		return str(int(text))
	return text


## Whether `text` is one of the law's values: a range's whole number inside
## its bounds, a toggle's or a choice's name.
static func allowed(repo: DataRepository, law: String, text: String) -> bool:
	var d := def(repo, law)
	if d.is_empty():
		return false
	if String(d["kind"]) == "range":
		return text.is_valid_int() and int(text) >= int(d["values"][0]) and int(text) <= int(d["values"][1])
	return (d["values"] as Array).has(text)


## A value's word for the screen and the letters: law_words.csv's
## `value_<value>` when it has one (On, Off), else the value capitalised.
static func value_label(repo: DataRepository, text: String) -> String:
	return String(repo.law_words.get("value_" + text, text.capitalize()))


## A province's decree point: its capital town, else its centre (pack px).
static func province_px(repo: DataRepository, code: String) -> Vector2:
	var row: Dictionary = repo.provinces.get(code, {})
	var cap := String(row.get("capital_burg", ""))
	if repo.burgs.has(cap):
		return Vector2(float(repo.burgs[cap]["x"]), float(repo.burgs[cap]["y"]))
	return Vector2(float(row.get("center_x", 0.0)), float(row.get("center_y", 0.0)))


static func _town_px(repo: DataRepository, town: String) -> Vector2:
	var b: Dictionary = repo.burgs.get(town, {})
	return Vector2(float(b.get("x", 0.0)), float(b.get("y", 0.0)))


## A courier's or a recipient's place in words: `province:<code>` the
## province's name, `town:<code>` the town's, a unit code the unit's label.
static func place_label(repo: DataRepository, state: GameState, target: String) -> String:
	if target.begins_with(PROVINCE_PREFIX):
		var pcode := target.trim_prefix(PROVINCE_PREFIX)
		return String((repo.provinces.get(pcode, {}) as Dictionary).get("label", pcode))
	if target.begins_with(TOWN_PREFIX):
		var town := target.trim_prefix(TOWN_PREFIX)
		return String((repo.burgs.get(town, {}) as Dictionary).get("label", town))
	var code := target.trim_prefix(UNIT_PREFIX)
	return String(ArmySystem.regiment(repo, code, state).get("label", code))


## A place courier's end point in pack px (where his road was set to end).
static func place_px(repo: DataRepository, target: String) -> Vector2:
	if target.begins_with(PROVINCE_PREFIX):
		return province_px(repo, target.trim_prefix(PROVINCE_PREFIX))
	return _town_px(repo, target.trim_prefix(TOWN_PREFIX))


## Whether a held town has a camp: a land unit of the realm camped by it.
static func _has_camp(repo: DataRepository, state: GameState, town: String) -> bool:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_naval", "0")) != "1" \
				and ArmyGround.camped_by(repo, state, String(r["regiment_code"])) == town:
			return true
	return false


## Who a decree of `law` is sent to, sorted by scope key (§3): a province law
## each province the realm holds, ending at its capital town; a camp law each
## held town with a camp of the realm's land units (target `town:<code>`) and
## each land unit camped by no held town (target its code, chased as it
## moves). Fleets never. Each {scope_key, kind: province|town|unit, target,
## to_px}. `only_missing`: only the places `delivery` counts as missing.
static func recipients(repo: DataRepository, state: GameState, law: String, only_missing := false) -> Array:
	var d := def(repo, law)
	var out: Array = []
	if d.is_empty():
		return out
	var realm := repo.resolve_realm("player_realm")
	if String(d["scope"]) == "province":
		for code: String in MapOwnership.provinces_of(repo, state, realm):
			out.append({"scope_key": PROVINCE_PREFIX + code, "kind": "province",
				"target": PROVINCE_PREFIX + code, "to_px": province_px(repo, code)})
	else:
		var towns := {}
		for r: Dictionary in MapObjects.regiments_of(repo, realm, state):
			if not CourierSystem.carries_orders(r):
				continue
			var code := String(r["regiment_code"])
			var town := ArmyGround.camped_by(repo, state, code)
			if town != "":
				towns[town] = true
			else:
				out.append({"scope_key": UNIT_PREFIX + code, "kind": "unit", "target": code,
					"to_px": ArmySystem.position_of(repo, state, r)})
		for town: String in towns:
			out.append({"scope_key": TOWN_PREFIX + town, "kind": "town", "target": TOWN_PREFIX + town,
				"to_px": _town_px(repo, town)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["scope_key"]) < String(b["scope_key"]))
	if only_missing:
		var missing: Array = _tally(repo, state, law)["missing"]
		out = out.filter(func(r: Dictionary) -> bool: return String(r["scope_key"]) in missing)
	return out


## The decree's id now (0: never decreed since the reign began).
static func _decree_id(state: GameState, law: String) -> int:
	return int((state.law_decree.get(law, {}) as Dictionary).get("decree_id", 0))


## Whether a decree of `value` re-sends the standing decree (R5): the same
## value, with places it has not reached and no courier riding for.
static func _resend(repo: DataRepository, state: GameState, law: String, val: String) -> bool:
	return decreed(repo, state, law) == val and not (_tally(repo, state, law)["missing"] as Array).is_empty()


## Gold the law's own cost ops take, as a positive number.
static func _ops_gold(ops: String) -> int:
	var gold := 0
	for raw in ops.split(";", false):
		var p := raw.strip_edges().split(":")
		if p[0] == "gold" and p.size() > 1:
			gold += maxi(-int(p[1]), 0)
	return gold


## The gold a decree of `law` costs besides its couriers: the order's own row
## (order_costs.csv), the law's gold_cost and its cost ops' gold. A re-send
## (R5) changes no law, so it pays the order's row alone.
static func order_gold(repo: DataRepository, law: String, resend := false) -> int:
	var d := def(repo, law)
	if resend:
		return int(OrderCosts.gold_of(repo, ACTION))
	return int(OrderCosts.gold_of(repo, ACTION)) + int(d.get("gold_cost", 0)) + _ops_gold(String(d.get("cost_ops", "")))


## Whether a decree of `value` would re-send the standing decree (R5).
static func is_resend(repo: DataRepository, state: GameState, law: String, val: Variant) -> bool:
	return _resend(repo, state, law, canonical(repo, law, val))


## Why a decree of `law` to `value` (a law's String) is refused; "" when it
## may be sent. ActionSystem's LAW_SET validation (the model and the news bar
## read these words).
static func refusal(repo: DataRepository, state: GameState, law: String, val: String) -> String:
	return String(refusal_of(repo, state, law, val)["text"])


## The refusal as {text: `refusal`'s words, key: unchanged | cooldown | gold |
## no_recipient | invalid ("" when it may be sent), days: the cooldown's days
## left (0 for any other)}. The laws screen words a key from law_words.csv
## `refusal_<key>`; a cooldown's days count day-ends, the running day first,
## as every day count shown (the law may change again on the month the
## cooldown names, `law_cooldown`).
static func refusal_of(repo: DataRepository, state: GameState, law: String, val: String) -> Dictionary:
	val = canonical(repo, law, val)
	var d := def(repo, law)
	if d.is_empty():
		return {"text": "No such law: " + law, "key": "invalid", "days": 0}
	var label := String(d["label"])
	if not allowed(repo, law, val):
		return {"text": "%s is not a value of %s" % [val, label], "key": "invalid", "days": 0}
	if _honour_bound(repo, state, law, val):
		return {"text": String(repo.law_words.get("refusal_honour_bound", "")), "key": "honour_bound", "days": 0}
	var resend := _resend(repo, state, law, val)
	if decreed(repo, state, law) == val and not resend:
		return {"text": "%s is already %s" % [label, val], "key": "unchanged", "days": 0}
	var until := int(state.law_cooldown.get(law, 0))
	if not resend and until > state.tick:
		var days := (until - state.tick - 1) * Calendar.DAYS_PER_TICK + Calendar.DAYS_PER_TICK - state.day + 1
		return {"text": "%s is on cooldown until tick %d" % [label, until], "key": "cooldown", "days": days}
	var n := recipients(repo, state, law, resend).size()
	if n == 0:
		return {"text": "No place to send it to", "key": "no_recipient", "days": 0}
	if float(state.metrics.get("treasury", 0.0)) < float(order_gold(repo, law, resend) + n * CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)):
		return {"text": "The chancery cannot pay the couriers", "key": "gold", "days": 0}
	return {"text": "", "key": "", "days": 0}


## Whether the player's realm, at a tier carrying the `honour_bound` flag, may
## not decree this option (data/realm/honour_bound_options.csv).
static func _honour_bound(repo: DataRepository, state: GameState, law: String, val: String) -> bool:
	if not (repo.honour_bound_options.get(law, []) as Array).has(val):
		return false
	return DevelopmentSystem.flag(repo, state, repo.resolve_realm("player_realm"), "honour_bound")


## What a decree would cost and take, for the screen (§5): {couriers, fee
## (one ordinary fee a courier), gold (order_gold), max_days (the longest
## ride), refusal (`refusal`'s words), refusal_key and wait_days
## (`refusal_of`'s key and days)}. ActionSystem charges exactly gold + fee.
## An unchanged value (the decree's own, nothing missing — most rows of the
## screen) is refused before any ride is worked out: zeros, the same shape.
static func preview(repo: DataRepository, state: GameState, law: String, val: String) -> Dictionary:
	val = canonical(repo, law, val)
	var no := refusal_of(repo, state, law, val)
	var why := String(no["text"])
	if def(repo, law).is_empty() or not allowed(repo, law, val) or String(no["key"]) == "unchanged":
		return {"couriers": 0, "fee": 0, "gold": 0, "max_days": 0, "refusal": why,
			"refusal_key": String(no["key"]), "wait_days": 0}
	var resend := _resend(repo, state, law, val)
	var to := recipients(repo, state, law, resend)
	var longest := 0
	for r: Dictionary in to:
		longest = maxi(longest, CourierSystem.eta_days_to(repo, state, CourierSystem.ORDINARY, r["to_px"]))
	return {"couriers": to.size(), "fee": to.size() * CourierSystem.fee_gold(repo, CourierSystem.ORDINARY),
		"gold": order_gold(repo, law, resend), "max_days": longest, "refusal": why,
		"refusal_key": String(no["key"]), "wait_days": int(no["days"])}


## Decree `law` to `value` (validated by the caller): a new value is a new
## decree — the decree, its cooldown, the metric mirror (ruling P1) — sent to
## every recipient; the standing value re-sends that decree, same id, to the
## places it is missing in (R5). The decree's `sent` lists every place a
## courier of it set out for (so a missing place is told apart: its courier
## lost, or none sent — a place gained since). Returns the couriers sent, in
## scope-key order.
## Charges nothing: the fees are ActionSystem's ledger lines.
static func decree(repo: DataRepository, state: GameState, law: String, val: String) -> Array:
	val = canonical(repo, law, val)
	var resend := _resend(repo, state, law, val)
	var to := recipients(repo, state, law, resend)
	if not resend:
		state.law_decree[law] = {"value": val, "decree_id": _decree_id(state, law) + 1,
			"day": state.absolute_day(), "sent": []}
		var cd := int(def(repo, law).get("cooldown_ticks", 0))
		if cd > 0:
			state.law_cooldown[law] = state.tick + cd
		_mirror(state, law, val)
		# what TriggerDsl's action_since=LAW_<law> reads (an event that
		# follows a decree, data/story/events.csv)
		state.event_state["last_action_tick"]["LAW_" + law] = state.tick
	var id := _decree_id(state, law)
	var keys: Array = (state.law_decree[law] as Dictionary).get("sent", [])
	for r: Dictionary in to:
		if not String(r["scope_key"]) in keys:
			keys.append(String(r["scope_key"]))
	keys.sort()
	state.law_decree[law]["sent"] = keys
	var sent: Array = []
	for r: Dictionary in to:
		var order := {"action_code": ACTION, "law": law, "value": val, "decree_id": id,
			"scope_key": String(r["scope_key"])}
		if String(r["kind"]) == "unit":
			sent.append(CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, String(r["target"]), order))
		else:
			sent.append(CourierSystem.dispatch_to(repo, state, CourierSystem.ORDINARY, String(r["target"]),
				order, r["to_px"]))
	# the chancery's letter, at once: how many ride and the longest ride
	if not sent.is_empty():
		var last := 0
		for c: Dictionary in sent:
			last = maxi(last, CourierSystem.days_left(repo, state, c))
		MissiveLog.add(repo, state, MissiveWriter.law_decree(repo, state, law, sent.size(), last))
	return sent


## After a day's ride (CourierSystem.ride_day): a standing decree whose last
## courier is now home — delivered, set aside, lost or out of time — and none
## rides for it any more files its reach letter (`MissiveWriter.law_reach`:
## reached of its recipients now, days since it was decreed, the decree's
## day counted) and marks that day's LAST event of it with `reach`
## ({reached, total, days}), which the news bar says once
## (`CourierSystem.news`). A courier of an older decree closes nothing; a
## re-send (R5) closes again when its own couriers are home.
static func close_rides(repo: DataRepository, state: GameState, events: Array) -> void:
	var seen := {}
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		if not e.has("law") or String(e["type"]) == "slow":
			continue
		var law := String(e["law"])
		if seen.has(law) or int(e.get("decree_id", -1)) != _decree_id(state, law):
			continue
		seen[law] = true
		if not _riders(state, law).is_empty():
			continue
		var t := _tally(repo, state, law)
		var days := state.absolute_day() - int((state.law_decree[law] as Dictionary).get("day", 0)) + 1
		e["reach"] = {"reached": int(t["reached"]), "total": int(t["total"]), "days": days}
		MissiveLog.add(repo, state, MissiveWriter.law_reach(repo, state, law, int(t["reached"]),
			int(t["total"]), days))


## The metric a law mirrors, set to the decreed value (ruling P1; spec §2.5).
static func _mirror(state: GameState, law: String, val: String) -> void:
	if METRIC_OF.has(law):
		state.metrics[String(METRIC_OF[law])] = (1.0 if val == "ration" else 0.0) \
			if law == "grain_ration" else float(int(val))


## An event's change of law (EventEffects' `law:` op): no courier carries it,
## so it is a new decree (riding couriers of the old one arrive stale) that
## every place it would be sent to follows at once. `raw` is one of the law's
## values or, for a range law, a signed step ("+1", "-2") clamped to its
## range. No cooldown and no stamp: it is no order of the crown's. Returns
## {law, value, was} or {error}.
static func impose(repo: DataRepository, state: GameState, law: String, raw: String) -> Dictionary:
	var d := def(repo, law)
	if d.is_empty():
		return {"error": "No such law: " + law}
	var was := decreed(repo, state, law)
	var text := raw.strip_edges()
	if String(d["kind"]) == "range" and (text.begins_with("+") or text.begins_with("-")) \
			and text.substr(1).is_valid_int():
		text = str(clampi(int(was) + int(text), int(d["values"][0]), int(d["values"][1])))
	text = canonical(repo, law, text)
	if not allowed(repo, law, text):
		return {"error": "%s is not a value of %s" % [text, String(d["label"])]}
	var to := recipients(repo, state, law)
	var id := _decree_id(state, law) + 1
	state.law_decree[law] = {"value": text, "decree_id": id, "day": state.absolute_day()}
	_mirror(state, law, text)
	for r: Dictionary in to:
		var key := String(r["scope_key"])
		var here: Dictionary = state.law_in_force.get(key, {})
		here[law] = {"value": text, "decree_id": id}
		state.law_in_force[key] = here
	return {"law": law, "value": text, "was": was}


## A law courier arrives (CourierSystem._deliver): his place's entry takes
## the decree when it is newer than the entry's, or the same decree with a
## different value; else he is set aside ("stale"). A province the realm no
## longer holds, or a town with no camp now, is "lost": nothing is written.
## A unit's courier was already lost by CourierSystem if the unit is gone.
static func deliver(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var order := CourierSystem.first_order(c)   # a decree's courier carries it alone
	var key := String(order["scope_key"])
	var law := String(order["law"])
	var ev := CourierSystem._event("delivered", c)
	if key.begins_with(PROVINCE_PREFIX):
		if MapOwnership.owner_of(repo, state, key.trim_prefix(PROVINCE_PREFIX)) != repo.resolve_realm("player_realm"):
			ev["type"] = "lost"
			return ev
	elif key.begins_with(TOWN_PREFIX):
		if not _has_camp(repo, state, key.trim_prefix(TOWN_PREFIX)):
			ev["type"] = "lost"
			return ev
	var here: Dictionary = state.law_in_force.get(key, {})
	var id := int(order["decree_id"])
	var val := String(order["value"])
	if here.has(law):
		var was: Dictionary = here[law]
		if int(was["decree_id"]) > id or (int(was["decree_id"]) == id and String(was["value"]) == val):
			ev["type"] = "stale"
			return ev
	# what the province followed until now (its entry, else the default, R13)
	var before := LawSystem.value(repo, state, law, key.trim_prefix(PROVINCE_PREFIX)) \
		if key.begins_with(PROVINCE_PREFIX) else ""
	here[law] = {"value": val, "decree_id": id}
	state.law_in_force[key] = here
	# the one-shots (§4.3): paid here, once, only on a real change of value
	if key.begins_with(PROVINCE_PREFIX):
		LawEffects.apply_lines(repo, state, LawEffects.once_lines(repo, state, law, before, val,
			key.trim_prefix(PROVINCE_PREFIX)))
	return ev


## How far the standing decree of `law` has got (§5): {total: its recipients
## now, reached: those whose entry holds it, riding: those a courier of it
## still rides for, last_days: the longest ride left, missing: the scope keys
## neither reached nor ridden for, of which lost: those a courier set out for
## (`sent`) and never reached, not_sent: those none set out for (a camp or
## province gained since); kinds: recipient kind (province |
## town | unit) -> {reached, total}, the screen's "camps and units in the
## field"}. An undecreed law (decree id 0) is reached everywhere: a place with
## no entry follows the seeded value.
static func delivery(repo: DataRepository, state: GameState, law: String) -> Dictionary:
	var out := _tally(repo, state, law)
	var last := 0
	for c: Dictionary in _riders(state, law):
		last = maxi(last, CourierSystem.days_left(repo, state, c))
	out["last_days"] = last
	return out


## The couriers of the standing decree of `law` still on the road.
static func _riders(state: GameState, law: String) -> Array:
	var id := _decree_id(state, law)
	var out: Array = []
	for c: Dictionary in state.couriers:
		var recipients: Array = [{"target": c.get("target", ""), "orders": CourierSystem.orders_of(c)}]
		recipients.append_array(c.get("recipient_queue", []))
		for recipient: Dictionary in recipients:
			var orders: Array = recipient.get("orders", [])
			if orders.is_empty():
				continue
			var order: Dictionary = orders[0]
			if String(order.get("action_code", "")) != ACTION or String(order.get("law", "")) != law or int(order.get("decree_id", -1)) != id:
				continue
			var rider := c.duplicate(true)
			rider["orders"] = orders.duplicate(true)
			rider["pending_recipient"] = String(recipient["target"])
			out.append(rider)
	return out


## The places the standing decree of `law` has not reached (the laws
## screen's list, §5), sorted by scope key: each {scope_key, label, days: the
## ride its courier has left (-1 for none), lost: no courier rides for it — a
## decree of the same value sends it again (R5) — and sent: a courier set out
## for it (lost and not sent: a place gained since the decree)}.
static func untold(repo: DataRepository, state: GameState, law: String) -> Array:
	var days := {}
	for c: Dictionary in _riders(state, law):
		var key := String(CourierSystem.first_order(c)["scope_key"])
		var left := CourierSystem.days_left(repo, state, c)
		days[key] = mini(left, int(days[key])) if days.has(key) else left
	var t := _tally(repo, state, law)
	var keys: Array = (t["riding_keys"] as Array) + (t["missing"] as Array)
	keys.sort()
	var sent := _sent(state, law)
	var out: Array = []
	for k in keys:
		var key := String(k)
		out.append({"scope_key": key, "label": place_label(repo, state, key),
			"days": int(days.get(key, -1)), "lost": not days.has(key), "sent": sent.has(key)})
	return out


## The places a courier of the standing decree of `law` set out for (an
## event's decree, or a save from before `sent` was kept: none).
static func _sent(state: GameState, law: String) -> Array:
	return (state.law_decree.get(law, {}) as Dictionary).get("sent", [])


## The realm's land units by the held town they camp by: town -> codes, in
## code order.
static func _campers(repo: DataRepository, state: GameState) -> Dictionary:
	var out := {}
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if not CourierSystem.carries_orders(r):
			continue
		var code := String(r["regiment_code"])
		var town := ArmyGround.camped_by(repo, state, code)
		if town != "":
			var list: Array = out.get(town, [])
			list.append(code)
			out[town] = list
	return out


## Whether a camp no courier reached is told all the same: every unit camped
## there reads decree `id` of `law` or a newer one (a camp formed after the
## decree of units that carried it in).
static func _camp_told(state: GameState, town: String, codes: Array, law: String, id: int) -> bool:
	if codes.is_empty():
		return false
	for code: String in codes:
		var read := _camp_read(state, town, code, law)
		if read.is_empty() or int(read["decree_id"]) < id:
			return false
	return true


## `delivery` without the days (no ride is reckoned): the counts, missing,
## the kinds, and riding_keys (the places a courier still rides for).
static func _tally(repo: DataRepository, state: GameState, law: String) -> Dictionary:
	var id := _decree_id(state, law)
	var riding := {}
	for c: Dictionary in _riders(state, law):
		riding[String(CourierSystem.first_order(c)["scope_key"])] = true
	var total := 0
	var reached := 0
	var on_road: Array = []
	var missing: Array = []
	var kinds := {}
	var campers := _campers(repo, state) if String(def(repo, law).get("scope", "")) == "camp" else {}
	for r: Dictionary in recipients(repo, state, law):
		var key := String(r["scope_key"])
		var kind := String(r["kind"])
		if not kinds.has(kind):
			kinds[kind] = {"reached": 0, "total": 0}
		kinds[kind]["total"] = int(kinds[kind]["total"]) + 1
		total += 1
		var entry: Dictionary = (state.law_in_force.get(key, {}) as Dictionary).get(law, {})
		if id == 0 or (not entry.is_empty() and int(entry["decree_id"]) >= id) \
				or (kind == "town" and _camp_told(state, key.trim_prefix(TOWN_PREFIX),
					campers.get(key.trim_prefix(TOWN_PREFIX), []), law, id)):
			reached += 1
			kinds[kind]["reached"] = int(kinds[kind]["reached"]) + 1
		elif riding.has(key):
			on_road.append(key)
		else:
			missing.append(key)
	var sent := _sent(state, law)
	var lost := missing.filter(func(k: String) -> bool: return sent.has(k)).size()
	return {"total": total, "reached": reached, "riding": on_road.size(), "lost": lost,
		"not_sent": missing.size() - lost, "missing": missing, "kinds": kinds, "riding_keys": on_road}
