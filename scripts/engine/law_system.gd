class_name LawSystem
extends RefCounted
## The laws (spec 2026-10-08-laws-tab-design §2): data-driven rules the crown
## decrees and each place follows. This file holds the tables' reads and the
## state's seeding; the order and the couriers come later.
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
## annexed after the start, a unit no courier has reached).
static func value(repo: DataRepository, state: GameState, law: String, scope_code: String) -> String:
	var d := def(repo, law)
	if d.is_empty():
		return ""
	var key := ""
	if String(d["scope"]) == "province":
		key = PROVINCE_PREFIX + scope_code
	else:
		# A unit camped by a held town follows the town's entry; one in the
		# field or on the march follows its own (spec §2.3).
		var town := ArmyGround.camped_by(repo, state, scope_code)
		key = TOWN_PREFIX + town if town != "" else UNIT_PREFIX + scope_code
	if state.law_in_force.has(key) and (state.law_in_force[key] as Dictionary).has(law):
		return String(state.law_in_force[key][law]["value"])
	if state.law_decree.is_empty():
		return metric_value(law, state, String(d["default"]))
	return String(d["default"])

## A value as a number: a range's own int; a toggle 0 or 1 (its second name is
## "on"); a choice its index among the allowed names.
static func as_number(repo: DataRepository, law: String, text: String) -> int:
	var d := def(repo, law)
	if d.is_empty():
		return 0
	if String(d["kind"]) == "range":
		return int(text)
	return maxi((d["values"] as Array).find(text), 0)

## `value` as a number.
static func number(repo: DataRepository, state: GameState, law: String, scope_code: String) -> int:
	return as_number(repo, law, value(repo, state, law, scope_code))

## The in-force numbers of the realm's provinces weighted by each province's
## people (rural plus urban, the figures `TickEngine.court_people` sums).
## With no people anywhere the plain default is returned.
static func weighted_number(repo: DataRepository, state: GameState, law: String) -> float:
	var weighted := 0
	var people := 0
	for code: String in MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")):
		var here := RealmEconomy._figure(repo, state, "economy.provinces.%s.rural_population" % code) \
			+ RealmEconomy._figure(repo, state, "economy.provinces.%s.urban_population" % code)
		weighted += here * number(repo, state, law, code)
		people += here
	if people == 0:
		return float(as_number(repo, law, String(def(repo, law).get("default", ""))))
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
