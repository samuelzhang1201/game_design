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
	var prefix := "dev_%s" % axis
	if realm != repo.resolve_realm("player_realm"):
		prefix = "dev_foreign_%s_%s" % [realm, axis]
	# Every tier crossed gets its flag (a score may jump several tiers).
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
	# SEAM (Task 6): foreign realms' lines are appended to `out` here, before
	# the player's lines are filed; they are never filed as the player's outcome.
	_file(repo, state, out.filter(func(l: Dictionary) -> bool: return String(l["realm"]) == player))
	return out


const OUTCOME := "DEVELOPMENT"


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
