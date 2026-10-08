class_name LawEffects
extends RefCounted
## What the laws do (spec 2026-10-08-laws-tab-design §4; rows in
## data/law_effects.csv, columns law_code, value, channel, target, amount,
## timing, share, reason — plan ruling R11).
##
## A `once` row is a one-shot (spec §4.3, R7): paid when a province's courier
## CHANGES the value in force there to the row's value — to pay it again the
## value must first change — times that province's share of the realm's
## people (`share=people`). A once-row of a RANGE law has no value: it is paid
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


## Each province of the realm's share of its people, in whole per mille:
## floor(people × 1000 / the realm's), the remainder to the most peopled
## province (ties to the lower code), so the shares sum to exactly 1000.
## People are rural plus urban (`LawSystem.people_of`). With no people at all
## every province counts as one. {} when the realm holds no province.
static func people_permille(repo: DataRepository, state: GameState) -> Dictionary:
	var codes: Array = []
	for code: String in MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")):
		codes.append(code)
	codes.sort()
	var out := {}
	if codes.is_empty():
		return out
	var people := {}
	var total := 0
	for code: String in codes:
		people[code] = LawSystem.people_of(repo, state, code)
		total += int(people[code])
	if total == 0:
		for code: String in codes:
			people[code] = 1
		total = codes.size()
	var given := 0
	var top: String = codes[0]
	for code: String in codes:
		out[code] = int(people[code]) * 1000 / total
		given += int(out[code])
		if int(people[code]) > int(people[top]):
			top = code
	out[top] = int(out[top]) + 1000 - given
	return out


## The one-shot lines a province pays when its value of `law` changes from
## `old_value` to `new_value`: each once-row's old realm-wide total times the
## province's per mille, rounded ONCE to one decimal. [] when nothing changed
## or the province is not the realm's. Each {metric, delta, reason}.
static func once_lines(repo: DataRepository, state: GameState, law: String, old_value: String,
		new_value: String, province: String) -> Array:
	var out: Array = []
	var d := LawSystem.def(repo, law)
	if d.is_empty() or old_value == new_value:
		return out
	var permille := int(people_permille(repo, state).get(province, 0))
	if permille == 0:
		return out
	var is_range := String(d["kind"]) == "range"
	var place := LawSystem.place_label(repo, state, LawSystem.PROVINCE_PREFIX + province)
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
		var delta := roundf(total * float(permille) / 1000.0 * 10.0) / 10.0
		if is_zero_approx(delta):
			continue
		var metric := String(row["channel"])
		out.append({"metric": metric, "delta": delta, "reason": "%s %s → %s reaches %s: %s %s (%s)" % [
			String(d["label"]).to_lower(), old_value, new_value, place, metric.replace("_", " "),
			("%+.1f" % delta).replace("-", "−"), String(row["reason"])]})
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
