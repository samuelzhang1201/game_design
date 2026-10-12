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
