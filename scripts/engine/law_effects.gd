class_name LawEffects
extends RefCounted
## What the laws do (spec 2026-10-08-laws-tab-design §4; rows in
## data/law_effects.csv, columns law_code, value, channel, target, amount,
## timing, share, reason — plan ruling R11).
##
## A `once` row is a one-shot (spec §4.3, R7): paid when a province's courier
## CHANGES the value in force there to the row's value — to pay it again the
## value must first change — its part of the old order's realm-wide total,
## apportioned over the realm's provinces by people (`share=people`), so
## delivered everywhere the provinces pay the old total exactly. A once-row of a RANGE law has no value: it is paid
## per point of change (justice severity 3 → 5 pays it twice; 5 → 3 twice the
## other way). Its `channel` is the metric it moves.
##
## `amount` is a number, or a balance.csv key (a leading "-" negates it), so
## the one-shots keep the old orders' keys (`church_endow_cost` …) as their
## one source.

const ONCE := "once"
const PEOPLE := "people"
## The pseudo order the deliveries' lines are gathered under in
## `state.recent_outcomes` (one a month; templates.csv `outcome_LAW_EFFECTS`).
const OUTCOME := "LAW_EFFECTS"


## A row's amount: its number, else the balance key it names ("-key" negated).
static func amount_of(repo: DataRepository, text: String) -> float:
	var t := text.strip_edges()
	if t.is_valid_float():
		return float(t)
	if t.begins_with("-"):
		return -repo.bal(t.substr(1))
	return repo.bal(t)


## The whole pools (root invariant 11, the economy is whole gold): a one-shot
## on them is apportioned in whole units; every other channel in tenths.
const WHOLE_POOLS := ["treasury", "grain"]


## The realm's provinces -> their people (`LawSystem.people_of`): the
## weights a one-shot is apportioned by. {} when the realm holds none.
static func people_weights(repo: DataRepository, state: GameState) -> Dictionary:
	var out := {}
	for code: String in MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")):
		out[code] = LawSystem.people_of(repo, state, code)
	return out


## A realm-wide `total` of `metric` split over the realm's provinces by their
## people, largest remainder (`TownStores.apportion`: ties to the code that
## sorts first, even when no one lives anywhere), in whole units for the whole
## pools and tenths otherwise, so the provinces' lines sum to the total
## exactly whatever order the couriers arrive in. code -> delta.
static func apportion(repo: DataRepository, state: GameState, metric: String, total: float) -> Dictionary:
	var scale := 1 if metric in WHOLE_POOLS else 10
	var units := roundi(absf(total) * float(scale))
	var sign := -1.0 if total < 0.0 else 1.0
	var shares := TownStores.apportion(units, people_weights(repo, state))
	var out := {}
	for code: String in shares:
		out[code] = sign * float(int(shares[code])) / float(scale)
	return out


## The one-shot lines a province pays when its value of `law` changes from
## `old_value` to `new_value`: each once-row's old realm-wide total (a range
## law's per point times the points of change) apportioned over the realm's
## provinces by people (`apportion`), this province's part. [] when nothing
## changed, no row applies, or the province is not the realm's. Each
## {metric, delta, reason}.
static func once_lines(repo: DataRepository, state: GameState, law: String, old_value: String,
		new_value: String, province: String) -> Array:
	var out: Array = []
	var d := LawSystem.def(repo, law)
	if d.is_empty() or old_value == new_value:
		return out
	var is_range := String(d["kind"]) == "range"
	var place := ""
	for row: Dictionary in repo.law_effects:
		if String(row["law_code"]) != law or String(row["timing"]) != ONCE or String(row["share"]) != PEOPLE:
			continue
		var total := 0.0
		if is_range:
			total = amount_of(repo, String(row["amount"])) * float(int(new_value) - int(old_value))
		elif String(row["value"]) == new_value:
			total = amount_of(repo, String(row["amount"]))
		else:
			continue
		var metric := String(row["channel"])
		var delta := float(apportion(repo, state, metric, total).get(province, 0.0))
		if is_zero_approx(delta):
			continue
		if place == "":
			place = LawSystem.place_label(repo, state, LawSystem.PROVINCE_PREFIX + province)
		var shown := ("%+d" % roundi(delta)) if metric in WHOLE_POOLS else ("%+.1f" % delta)
		out.append({"metric": metric, "delta": delta, "reason": "%s %s → %s reaches %s: %s %s (%s)" % [
			String(d["label"]).to_lower(), old_value, new_value, place, metric.replace("_", " "),
			shown.replace("-", "−"), String(row["reason"])]})
	return out


## Apply effect lines to the realm's metrics (no clamp: unrest is clamped at
## the month's end) and gather them, with their reasons, under the month's
## one LAW_EFFECTS outcome in `state.recent_outcomes` (ActionSystem's
## {metric, delta, reason} shape), which the month's report voices.
static func apply_lines(repo: DataRepository, state: GameState, lines: Array) -> void:
	if lines.is_empty():
		return
	for l: Dictionary in lines:
		var metric := String(l["metric"])
		state.metrics[metric] = float(state.metrics.get(metric, 0.0)) + float(l["delta"])
	var outcome: Dictionary = {}
	for o: Dictionary in state.recent_outcomes:
		if String(o.get("action_code", "")) == OUTCOME:
			outcome = o
	if outcome.is_empty():
		outcome = {"action_code": OUTCOME, "ok": true, "effects": [],
			"notes": String(repo.law_words.get("effects_paid", "")), "target": "", "params": {}, "drift": []}
		state.recent_outcomes.append(outcome)
	(outcome["effects"] as Array).append_array(lines)
