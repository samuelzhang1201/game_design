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
	return apportion_by(metric, total, people_weights(repo, state))


## `apportion` over given weights (code -> whole weight): whole units for the
## whole pools, tenths otherwise; the sign re-applied to every part.
static func apportion_by(metric: String, total: float, weights: Dictionary) -> Dictionary:
	var scale := 1 if metric in WHOLE_POOLS else 10
	var units := roundi(absf(total) * float(scale))
	var dir := -1.0 if total < 0.0 else 1.0
	var shares := TownStores.apportion(units, weights)
	var out := {}
	for code: String in shares:
		out[code] = dir * float(int(shares[code])) / float(scale)
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


## --- The military laws (spec §4.1, §4.2, §4.4) ------------------------------
##
## A `share=unit` row (channels `morale_mark`, `pace`) is paid by each land
## unit of the realm on ITS value in force (`LawSystem.value`): its morale
## mark (`unit_mark`, added to the mark its morale drifts toward) and its
## pace (`unit_pace_permille`). A `share=army` row is a realm channel paid
## monthly (`month_lines`), scaled by the share of the realm's land men under
## the value (`army_share_permille`): one rounding per line, to tenths — or,
## on a whole pool (treasury), to whole gold, where the row's amount is PER
## 1,000 MEN under the value (amount x men / 1000). A `flag` row changes
## nothing: its law is read by the system it governs through `LawSystem.value`.
## Fleets follow no camp law: neutral for both unit channels and no man of the
## host's shares.

const MONTHLY := "monthly"
const ARMY := "army"
const UNIT := "unit"
const CHANNEL_MARK := "morale_mark"
const CHANNEL_PACE := "pace"
const CHANNEL_FLAG := "flag"

## repo instance id -> the unit channels' index (`_index`). Four at most are
## kept, as ArmySplit's: the suite makes a repository copy per test.
static var _cache: Dictionary = {}


## Forget the indexes (a test that rewrites law_effects in place).
static func forget() -> void:
	_cache.clear()


## The unit channels by law and value, read once per repository (they run per
## unit per day): {rows (the table indexed), mark_laws, mark: law -> value ->
## thousandths of a mark, pace_laws, pace: law -> value -> per mille}.
static func _index(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if _cache.has(key):
		var held: Dictionary = _cache[key]
		if is_same(held["rows"], repo.law_effects) and int(held["size"]) == repo.law_effects.size():
			return held
	if _cache.size() >= 4 and not _cache.has(key):
		_cache.erase(_cache.keys()[0])
	var mark := {}
	var pace := {}
	for row: Dictionary in repo.law_effects:
		if String(row["share"]) != UNIT or String(row["timing"]) != MONTHLY:
			continue
		var law := String(row["law_code"])
		var v := String(row["value"])
		var channel := String(row["channel"])
		if channel == CHANNEL_MARK:
			var by: Dictionary = mark.get(law, {})
			by[v] = int(by.get(v, 0)) + roundi(amount_of(repo, String(row["amount"])) * 1000.0)
			mark[law] = by
		elif channel == CHANNEL_PACE:
			var by: Dictionary = pace.get(law, {})
			by[v] = int(by.get(v, 0)) + roundi(amount_of(repo, String(row["amount"])))
			pace[law] = by
	var out := {"rows": repo.law_effects, "size": repo.law_effects.size(),
		"mark_laws": _in_law_order(repo, mark), "mark": mark,
		"pace_laws": _in_law_order(repo, pace), "pace": pace}
	_cache[key] = out
	return out


static func _in_law_order(repo: DataRepository, by_law: Dictionary) -> Array:
	return repo.law_order.filter(func(l: String) -> bool: return by_law.has(l))


## `a / b` rounded once, half away from zero (b > 0).
static func _round_div(a: int, b: int) -> int:
	@warning_ignore("integer_division")  # whole units, rounded half away from zero
	var q := (absi(a) * 2 + b) / (b * 2)
	return -q if a < 0 else q


## Whether `code` is a land unit of the realm, the only units a camp law binds
## (never a foe in the field, GameState.foes).
static func _bound(repo: DataRepository, state: GameState, code: String) -> bool:
	var reg := ArmySystem.regiment(repo, code, state)
	return not reg.is_empty() and not ArmySystem.is_foe(state, code) and String(reg.get("is_naval", "0")) != "1" \
		and String(reg.get("kingdom_code", "")) == repo.resolve_realm("player_realm")


## The morale mark the camp laws add to `code`'s: the sum of its `morale_mark`
## rows for the values it follows, rounded once to whole points (half away
## from zero). 0 for a fleet or a unit not the realm's.
static func unit_mark(repo: DataRepository, state: GameState, code: String) -> int:
	if not _bound(repo, state, code):
		return 0
	var idx := _index(repo)
	var sum := 0
	for law: String in idx["mark_laws"]:
		sum += int((idx["mark"][law] as Dictionary).get(LawSystem.value(repo, state, law, code), 0))
	return _round_div(sum, 1000)


## `code`'s pace under the camp laws, per mille: 1000 plus its `pace` rows for
## the values it follows (truce days on: -50). 1000 for a fleet or a unit not
## the realm's. ArmySystem.day_step_m and speed_km_per_day multiply by it.
static func unit_pace_permille(repo: DataRepository, state: GameState, code: String) -> int:
	if not _bound(repo, state, code):
		return 1000
	var idx := _index(repo)
	var out := 1000
	for law: String in idx["pace_laws"]:
		out += int((idx["pace"][law] as Dictionary).get(LawSystem.value(repo, state, law, code), 0))
	return maxi(out, 0)


## The realm's host under `law`: {total: its land men, men: value -> men,
## units: value -> units}, the units walked in code order; a unit no courier
## has told follows the default (`LawSystem.value`).
static func _host(repo: DataRepository, state: GameState, law: String) -> Dictionary:
	var men := {}
	var units := {}
	var total := 0
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_naval", "0")) == "1":
			continue
		var n := int(MapObjects.regiment_size(repo, r))
		var v := LawSystem.value(repo, state, law, String(r["regiment_code"]))
		men[v] = int(men.get(v, 0)) + n
		units[v] = int(units.get(v, 0)) + 1
		total += n
	return {"total": total, "men": men, "units": units}


static func _share_of(host: Dictionary, value: String) -> int:
	var total := int(host["total"])
	if total <= 0:
		return 0
	return _round_div(int((host["men"] as Dictionary).get(value, 0)) * 1000, total)


## Per mille of the realm's land men (MapObjects.regiment_size) whose unit
## follows `value` of `law`, rounded once; 0 with no land men.
static func army_share_permille(repo: DataRepository, state: GameState, law: String, value: String) -> int:
	return _share_of(_host(repo, state, law), value)


## A law at a value in words, for a reason line: law_words' `phrase_<law>_<value>`
## when it has one; else a toggle's label ("register prisoners", "… off"), a
## choice's value and label ("allow plunder").
static func phrase(repo: DataRepository, law: String, value: String) -> String:
	var key := "phrase_%s_%s" % [law, value]
	if repo.law_words.has(key):
		return String(repo.law_words[key])
	var d := LawSystem.def(repo, law)
	var label := String(d.get("label", law)).to_lower()
	if String(d.get("kind", "")) == "toggle":
		return label if value == "on" else "%s %s" % [label, value]
	return "%s %s" % [value, label]


## A channel's word on the screen and in the lines (law_words `channel_<c>`).
static func channel_word(repo: DataRepository, channel: String) -> String:
	return String(repo.law_words.get("channel_" + channel, channel.replace("_", " ")))


## A signed figure: whole pools and whole numbers as "+2", else "+0.4"; the
## minus is a real minus sign.
static func _signed(value: float, whole: bool) -> String:
	var text := ("%+d" % roundi(value)) if whole else ("%+.1f" % value)
	return text.replace("-", "−")


## The month's realm lines of the military laws (spec §4.2): for each monthly
## `share=army` row, in file order, its amount times the share of the land men
## under its value — rounded once to tenths; a whole pool's (treasury) amount
## is per 1,000 men under the value, rounded once to whole gold. A line that
## rounds to zero is skipped. Each {metric, delta, reason}; TickEngine.advance
## applies them after the regiments' month.
static func month_lines(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var hosts := {}
	for row: Dictionary in repo.law_effects:
		if String(row["timing"]) != MONTHLY or String(row["share"]) != ARMY:
			continue
		var law := String(row["law_code"])
		var v := String(row["value"])
		if LawSystem.def(repo, law).is_empty() or v == "":
			continue
		if not hosts.has(law):
			hosts[law] = _host(repo, state, law)
		var host: Dictionary = hosts[law]
		var share := _share_of(host, v)
		if share <= 0:
			continue
		var metric := String(row["channel"])
		var milli := roundi(amount_of(repo, String(row["amount"])) * 1000.0)
		var whole := metric in WHOLE_POOLS
		var delta := 0.0
		if whole:
			delta = float(_round_div(milli * int((host["men"] as Dictionary).get(v, 0)), 1000 * 1000))
		else:
			delta = float(_round_div(milli * share, 100 * 1000)) / 10.0
		if is_zero_approx(delta):
			continue
		var n := int((host["units"] as Dictionary).get(v, 0))
		out.append({"metric": metric, "delta": delta, "reason": "%s: %s %s (%d %s, %d%% of the host)" % [
			phrase(repo, law, v), channel_word(repo, metric), _signed(delta, whole), n,
			"unit" if n == 1 else "units", _round_div(share, 10)]})
	return out


## The screen's words for what `law` at `value` does, spelled from its
## law_effects.csv rows in file order and joined by " · ", each part
## capitalised: "Morale +2", "Contentment −0.4/month", "Treasury −2/month per
## 1,000 men", "Pace −50‰", "Unrest −2 per point, once"; a row with no number
## is its channel's word ("A standing order" for a flag). Whole figures lose
## their ".0", others keep tenths. A range law's rows with no value hold at
## every value. "" when the value does nothing.
static func summary(repo: DataRepository, law: String, value: String) -> String:
	var d := LawSystem.def(repo, law)
	if d.is_empty():
		return ""
	var is_range := String(d["kind"]) == "range"
	var parts: PackedStringArray = []
	for row: Dictionary in repo.law_effects:
		if String(row["law_code"]) != law:
			continue
		var v := String(row["value"])
		if v != value and not (v == "" and is_range):
			continue
		var channel := String(row["channel"])
		var word := channel_word(repo, channel)
		var raw := String(row["amount"]).strip_edges()
		var text := ""
		if channel == CHANNEL_FLAG or raw == "":
			text = word
		else:
			var amount := amount_of(repo, raw)
			if channel == CHANNEL_PACE:
				text = "%s %s%s" % [word, _figure(amount), String(repo.law_words.get("per_mille", "‰"))]
			elif channel == CHANNEL_MARK:
				text = "%s %s" % [word, _figure(amount)]
			elif String(row["timing"]) == ONCE:
				text = "%s %s" % [word, _figure(amount)]
				if v == "" and is_range:
					text += " " + String(repo.law_words.get("per_point", "per point"))
				text += ", " + String(repo.law_words.get("once", "once"))
			else:
				text = "%s %s%s" % [word, _figure(amount), String(repo.law_words.get("per_month", "/month"))]
				if channel in WHOLE_POOLS and String(row["share"]) == ARMY:
					text += " " + String(repo.law_words.get("per_1000_men", "per 1,000 men"))
		parts.append(text.left(1).to_upper() + text.substr(1))
	return " · ".join(parts)


## A signed figure for the screen: a whole one without ".0" ("−2"), any other
## in tenths ("−0.4"); the minus a real minus sign.
static func _figure(value: float) -> String:
	return _signed(value, is_equal_approx(value, roundf(value)))
