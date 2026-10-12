class_name DevelopmentSystem
extends RefCounted
## The development axes (spec 2026-10-12-development-axes-design §2): every
## realm has a Renaissance and a Chivalry score (whole numbers, 0..1000) and a
## confirmed tier per axis. Tiers are cut by data/realm/development_axes.csv
## with hysteresis, so a score hovering on a bound does not flicker. Every move
## carries a reason and is logged in `GameState.development_log`.

const AXES: Array = ["renaissance", "chivalry"]
const SLOTS: Array = ["player_realm", "raider_realm", "neighbor_realm", "empire_realm"]
const SCORE_MAX := 1000


## The four slot realms' codes, sorted.
static func realms(repo: DataRepository, _state: GameState = null) -> Array:
	var out: Array = []
	for slot: String in SLOTS:
		var code := repo.resolve_realm(slot)
		if code != "" and not out.has(code):
			out.append(code)
	out.sort()
	return out


## Fill every realm's missing axes with the start score and tier 0. Idempotent:
## an entry already present is left alone.
static func seed(repo: DataRepository, state: GameState) -> void:
	for realm: String in realms(repo, state):
		var entry: Dictionary = state.development.get(realm, {})
		for axis: String in AXES:
			if not entry.has(axis):
				entry[axis] = clampi(int(repo.bal("dev_start_" + axis)), 0, SCORE_MAX)
			if not entry.has("tier_" + axis):
				entry["tier_" + axis] = 0
		state.development[realm] = entry


## A save from before the axes (Game.load_campaign).
static func ensure(repo: DataRepository, state: GameState) -> void:
	DevelopmentSystem.seed(repo, state)


static func score(state: GameState, realm: String, axis: String) -> int:
	return int(state.development.get(realm, {}).get(axis, 0))


## The confirmed tier.
static func tier(state: GameState, realm: String, axis: String) -> int:
	return int(state.development.get(realm, {}).get("tier_" + axis, 0))


static func _rows(repo: DataRepository, axis: String) -> Dictionary:
	var out: Dictionary = {}
	for r: Dictionary in repo.development_axes:
		if String(r["axis"]) == axis:
			out[int(r["tier"])] = r
	return out


## The tier a score holds given the confirmed one: it rises to tier n when the
## score reaches min_score(n); it falls from tier t only when the score is below
## min_score(t) - hysteresis(t). It lands on the tier the score implies at most.
static func tier_for(repo: DataRepository, axis: String, score_value: int, confirmed: int) -> int:
	var rows := _rows(repo, axis)
	var t := confirmed
	while rows.has(t + 1) and score_value >= int(rows[t + 1]["min_score"]):
		t += 1
	while t > 0 and rows.has(t) and score_value < int(rows[t]["min_score"]) - int(rows[t]["hysteresis"]):
		t -= 1
	return t


## Move a score by `delta` (clamped to 0..1000) for a reason. Returns the
## applied move {axis, realm, delta, reason, from_tier, to_tier}, {} when
## nothing moved. A tier change sets its crossing flag.
static func move(repo: DataRepository, state: GameState, realm: String, axis: String,
		delta: int, reason: String) -> Dictionary:
	DevelopmentSystem.seed(repo, state)
	if not state.development.has(realm):
		return {}
	var before := score(state, realm, axis)
	var after := clampi(before + delta, 0, SCORE_MAX)
	var applied := after - before
	if applied == 0:
		return {}
	var from_tier := tier(state, realm, axis)
	var to_tier := tier_for(repo, axis, after, from_tier)
	state.development[realm][axis] = after
	state.development[realm]["tier_" + axis] = to_tier
	if to_tier != from_tier:
		_flag(repo, state, realm, axis, from_tier, to_tier)
	var result := {"axis": axis, "realm": realm, "delta": applied, "reason": reason,
		"from_tier": from_tier, "to_tier": to_tier}
	var entry := result.duplicate()
	entry["tick"] = state.tick
	state.development_log.append(entry)
	return result


static func _flag(repo: DataRepository, state: GameState, realm: String, axis: String,
		from_tier: int, to_tier: int) -> void:
	var flags: Array = state.event_state.get("flags", [])
	var up := to_tier > from_tier
	var prefixes: Array = []
	if realm == repo.resolve_realm("player_realm"):
		prefixes.append("dev_%s" % axis)
	else:
		# A foreign crossing is named by the SLOT the realm fills (authored
		# triggers name slots, never a pack's kingdom codes); a realm in two
		# slots raises both flags.
		for slot: String in SLOTS:
			if slot != "player_realm" and repo.resolve_realm(slot) == realm:
				prefixes.append("dev_foreign_%s_%s" % [slot, axis])
		if prefixes.is_empty():
			prefixes.append("dev_foreign_%s_%s" % [realm, axis])
	# Every tier crossed gets its flag (a score may jump several tiers).
	for prefix: String in prefixes:
		var n := from_tier
		while n != to_tier:
			n += 1 if up else -1
			var name := "%s_%s_%d" % [prefix, "up" if up else "down", n if up else n + 1]
			if not flags.has(name):
				flags.append(name)
	state.event_state["flags"] = flags


## The player realm's drift lines on `axis` from the laws (spec §5): every
## law_effects row whose channel is `dev_<axis>`, monthly, whose value is the
## one the crown has DECREED (decree_id above 0) (`LawSystem.decreed`), in file order. A row of a
## range law has a blank value and pays amount x (decreed value - the law's
## default). Each {delta: int, reason: String}; a row that pays nothing is
## skipped.
static func law_drift(repo: DataRepository, state: GameState, axis: String) -> Array:
	var out: Array = []
	var channel := LawEffects.DEV_PREFIX + axis
	for row: Dictionary in repo.law_effects:
		if String(row["channel"]) != channel or String(row["timing"]) != LawEffects.MONTHLY:
			continue
		var law := String(row["law_code"])
		var d := LawSystem.def(repo, law)
		if d.is_empty():
			continue
		var v := String(row["value"])
		# Only a law the crown has actually decreed counts: a law at its seeded
		# default (decree_id 0) is no policy yet, so a fresh reign drifts nothing.
		if int(state.law_decree.get(law, {}).get("decree_id", 0)) <= 0:
			continue
		var held := LawSystem.decreed(repo, state, law)
		var amount := LawEffects.amount_of(repo, String(row["amount"]))
		var delta := 0
		var reason := ""
		if v == "" and String(d["kind"]) == "range":
			var steps := int(held) - int(String(d["default"]))
			delta = roundi(amount * float(steps))
			reason = "%s %s (%d from the usual %s, %s per point): %s" % [
				String(d["label"]).to_lower(), held, steps, String(d["default"]), _signed(amount), String(row["reason"])]
		elif v == held:
			delta = roundi(amount)
			reason = "%s: %s" % [LawEffects.phrase(repo, law, v), String(row["reason"])]
		if delta != 0:
			out.append({"delta": delta, "reason": reason})
	return out


## A ruler's lean on an axis: the sum of his traits' `dev_<axis>` columns,
## -100..100. Derived from the trait rows, never stored.
static func preference(repo: DataRepository, character: Character, axis: String) -> int:
	var total := 0
	for code in character.traits:
		total += int(repo.traits.get(String(code), {}).get(LawEffects.DEV_PREFIX + axis, 0))
	return clampi(total, -100, 100)


## The sign (-1, 0, 1) a decree of `law` = `value` pushes `axis`: the sum of the
## monthly drift amounts of that value's rows (a range law's blank-value row
## counts amount x (value - default)).
static func decree_sign(repo: DataRepository, law: String, value: String, axis: String) -> int:
	var d := LawSystem.def(repo, law)
	if d.is_empty():
		return 0
	var channel := LawEffects.DEV_PREFIX + axis
	var sum := 0.0
	for row: Dictionary in repo.law_effects:
		if String(row["law_code"]) != law or String(row["channel"]) != channel \
				or String(row["timing"]) != LawEffects.MONTHLY:
			continue
		var amount := LawEffects.amount_of(repo, String(row["amount"]))
		if String(row["value"]) == "" and String(d["kind"]) == "range":
			sum += amount * float(int(value) - int(String(d["default"])))
		elif String(row["value"]) == value:
			sum += amount
	return signi(roundi(sum))


## The opinion every council minister takes from a decree that shifts an axis:
## roundi(preference x sign x dev_decree_opinion_per_100 / 100), one reasoned
## line per axis, applied now. Returns [{character_id, delta, reason}].
static func decree_opinions(repo: DataRepository, state: GameState, law: String, value: String) -> Array:
	var out: Array = []
	var label := String(LawSystem.def(repo, law).get("label", law)).to_lower()
	var per_100 := repo.bal("dev_decree_opinion_per_100")
	for axis: String in AXES:
		var s := decree_sign(repo, law, value, axis)
		if s == 0:
			continue
		for seat in state.council:
			var id := String(state.council[seat])
			if not state.characters.has(id):
				continue
			var c: Character = state.characters[id]
			var delta := roundi(preference(repo, c, axis) * s * per_100 / 100.0)
			if delta == 0:
				continue
			var reason := "decreed %s (%s %s development)" % [
				label, "favours" if delta > 0 else "opposes", axis]
			c.change_opinion(delta, reason, state.tick)
			out.append({"character_id": id, "delta": delta, "reason": reason})
	return out


static func _signed(n: float) -> String:
	var text := ("%+d" % roundi(n)) if is_equal_approx(n, roundf(n)) else ("%+.1f" % n)
	return text.replace("-", "−")


## The untended line: `score` moves toward `dev_start_<axis>` by
## min(dev_decay_per_month, distance). {delta, reason}, {} when it does not move.
static func decay_line(repo: DataRepository, state: GameState, realm: String, axis: String) -> Dictionary:
	var start := clampi(int(repo.bal("dev_start_" + axis)), 0, SCORE_MAX)
	var gap := start - score(state, realm, axis)
	var step := mini(maxi(int(repo.bal("dev_decay_per_month")), 0), absi(gap))
	if step == 0:
		return {}
	return {"delta": step if gap > 0 else -step, "reason": "untended: the old ways return"}


## The month's settlement of the axes (TickEngine.advance, once a month):
## for the player's realm and each axis, the laws' drift lines in file order via
## `move`, then the decay line. Returns the applied lines
## {metric, axis, realm, delta, reason}, and files the player's under one
## DEVELOPMENT outcome in `state.recent_outcomes` (the shape of
## LawEffects.apply_lines' LAW_EFFECTS one: effects {metric: axis, delta, reason}).
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	DevelopmentSystem.seed(repo, state)
	var out: Array = []
	var player := repo.resolve_realm("player_realm")
	for axis: String in AXES:
		var lines: Array = DevelopmentSystem.law_drift(repo, state, axis)
		# The decay is read AFTER the drift has moved the score, so it never
		# overshoots the start.
		for l: Dictionary in lines:
			DevelopmentSystem._apply_line(repo, state, player, axis, l, out)
		DevelopmentSystem._apply_line(repo, state, player, axis, decay_line(repo, state, player, axis), out)
	# The foreign realms follow their rulers; their lines join the returned list
	# but are never filed as the player's DEVELOPMENT outcome.
	_file(repo, state, out.filter(func(l: Dictionary) -> bool: return String(l["realm"]) == player))
	for l: Dictionary in ai_lines(repo, state):
		DevelopmentSystem._apply_line(repo, state, String(l["realm"]), String(l["axis"]), l, out)
	return out


const OUTCOME := "DEVELOPMENT"


## The ruler of a foreign realm: the lowest-id character with trait
## `crowned_head` whose `kingdom` names the realm. The roster's `kingdom` column
## holds the SLOT (`raider_realm`), not the kingdom code, so a character matches
## when `kingdom` is the realm's code or a slot that resolves to it. null for
## the player's realm or when nobody rules it.
static func ruler_of(repo: DataRepository, state: GameState, realm: String) -> Character:
	if realm == "" or realm == repo.resolve_realm("player_realm"):
		return null
	var keys: Array = [realm]
	for slot: String in SLOTS:
		if repo.resolve_realm(slot) == realm and not keys.has(slot):
			keys.append(slot)
	var ids: Array = state.characters.keys()
	ids.sort()
	for id in ids:
		var c: Character = state.characters[id]
		if c.traits.has("crowned_head") and keys.has(c.kingdom):
			return c
	return null


## Each foreign realm's monthly lines {realm, axis, delta, reason}: the score
## steps toward clamp(start + preference x dev_ai_target_per_pref, 0, 1000) by
## at most dev_ai_step. Realms in sorted order, then AXES order; a realm without
## a ruler, or already at its target, gives no line.
static func ai_lines(repo: DataRepository, state: GameState) -> Array:
	DevelopmentSystem.seed(repo, state)
	var out: Array = []
	var player := repo.resolve_realm("player_realm")
	var per_pref := int(repo.bal("dev_ai_target_per_pref"))
	var step_max := maxi(int(repo.bal("dev_ai_step")), 0)
	for realm: String in realms(repo, state):
		if realm == player:
			continue
		var ruler := ruler_of(repo, state, realm)
		if ruler == null:
			continue
		for axis: String in AXES:
			var pref := preference(repo, ruler, axis)
			var target := clampi(int(repo.bal("dev_start_" + axis)) + pref * per_pref, 0, SCORE_MAX)
			var gap := target - score(state, realm, axis)
			var step := mini(step_max, absi(gap))
			if step == 0:
				continue
			out.append({"realm": realm, "axis": axis, "delta": step if gap > 0 else -step,
				"reason": "%s %s %s" % [ruler.display_name, "favours" if gap > 0 else "turns from", axis]})
	return out


static func _apply_line(repo: DataRepository, state: GameState, realm: String, axis: String,
		line: Dictionary, out: Array) -> void:
	if line.is_empty():
		return
	var applied := DevelopmentSystem.move(repo, state, realm, axis, int(line["delta"]), String(line["reason"]))
	if not applied.is_empty():
		out.append({"metric": axis, "axis": axis, "realm": realm,
			"delta": int(applied["delta"]), "reason": String(line["reason"])})


static func _file(repo: DataRepository, state: GameState, lines: Array) -> void:
	if lines.is_empty():
		return
	var effects: Array = []
	for l: Dictionary in lines:
		effects.append({"metric": String(l["axis"]), "delta": float(l["delta"]), "reason": String(l["reason"])})
	state.recent_outcomes.append({"action_code": OUTCOME, "ok": true, "effects": effects,
		"notes": String(repo.law_words.get("development_moved", "")), "target": "", "params": {}, "drift": []})


# --- tier effects (spec §4) ---------------------------------------------------

## The rows of both axes at the realm's CONFIRMED tier, only that tier's own
## (the table lists each tier's full modifier, so tiers do not add up), for one
## channel, in file order.
static func effect_rows(repo: DataRepository, state: GameState, realm: String, channel: String) -> Array:
	var out: Array = []
	for r: Dictionary in repo.development_tier_effects:
		if String(r["channel"]) != channel:
			continue
		if int(r["tier"]) == tier(state, realm, String(r["axis"])):
			out.append(r)
	return out


static func _sum_permille(repo: DataRepository, state: GameState, realm: String, channel: String,
		target: String) -> int:
	var sum := 0
	for r: Dictionary in effect_rows(repo, state, realm, channel):
		if target == "" or String(r["target"]) == target:
			sum += roundi(LawEffects.amount_of(repo, String(r["amount"])))
	return sum


## arm -> 1000 + the sum of the realm's arm_power_permille rows (never below 0),
## for every arm in unit_types.
static func arm_permille(repo: DataRepository, state: GameState, realm: String) -> Dictionary:
	var out: Dictionary = {}
	for arm: String in repo.world_table("military", "unit_types"):
		# No state (a state-less host): no development, every arm at 1000.
		out[arm] = 1000 if state == null else maxi(0, 1000 + _sum_permille(repo, state, realm, "arm_power_permille", arm))
	return out


## Whether the realm's confirmed tiers carry a `flag` row of that name.
static func flag(repo: DataRepository, state: GameState, realm: String, name: String) -> bool:
	for r: Dictionary in effect_rows(repo, state, realm, "flag"):
		if String(r["target"]) == name:
			return true
	return false


## The ids of the `unlock` rows at tiers up to the confirmed tier, per axis.
static func unlocked(repo: DataRepository, state: GameState, realm: String) -> Array:
	var out: Array = []
	for r: Dictionary in repo.development_tier_effects:
		if String(r["channel"]) == "unlock" and int(r["tier"]) <= tier(state, realm, String(r["axis"])) \
				and not out.has(String(r["target"])):
			out.append(String(r["target"]))
	return out


## The cavalry heads of the player realm's regiments.
static func cavalry_heads(repo: DataRepository, state: GameState) -> int:
	var heads := 0
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		heads += int(float(reg.get("cavalry", 0)))
	return heads


## The month's ledger lines of the player realm {metric, delta: float, reason}:
## every monthly metric-channel row at the confirmed tiers (one rounding, to
## tenths), then the cavalry upkeep on the treasury (whole gold, one rounding;
## no line without cavalry or at 0 gold). TickEngine.advance calls this AFTER
## settle_month, so a tier reached this month pays this month.
static func month_lines(repo: DataRepository, state: GameState) -> Array:
	var player := repo.resolve_realm("player_realm")
	var out: Array = []
	for r: Dictionary in repo.development_tier_effects:
		if String(r["timing"]) != LawEffects.MONTHLY or int(r["tier"]) != tier(state, player, String(r["axis"])):
			continue
		var delta := roundf(LawEffects.amount_of(repo, String(r["amount"])) * 10.0) / 10.0
		if delta != 0.0:
			out.append({"metric": String(r["channel"]), "delta": delta, "reason": String(r["reason"])})
	var heads := cavalry_heads(repo, state)
	if heads > 0:
		var rows := effect_rows(repo, state, player, "cavalry_upkeep_permille")
		var milli := _sum_permille(repo, state, player, "cavalry_upkeep_permille", "")
		# Whole integers, one rounding at the end, half away from zero.
		var num := roundi(repo.bal("dev_cavalry_upkeep_per_head")) * heads * milli
		@warning_ignore("integer_division")  # whole gold, rounded half away from zero
		var gold := (absi(num) + 500) / 1000 * (1 if num >= 0 else -1)
		if gold != 0:
			out.append({"metric": "treasury", "delta": -float(gold),
				"reason": "%s (%d horse)" % [String(rows[0]["reason"]), heads]})
	return out
