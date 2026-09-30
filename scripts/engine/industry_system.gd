class_name IndustrySystem
extends RefCounted
## Buildings eat (spec 2026-09-30-ledger-industry-trade-design, M5): every
## standing input building (data/building_inputs.csv) is fed from its own
## manor's units first — ManorEconomy.line_of nets them, still the only
## rounding in the economy — and the rest it buys from the LORD's pool of
## each good (goods_economy.csv `pool`, at its `price_gold`) at the month's
## end; a building whose purchase the pool cannot pay stands IDLE the next
## month (GameState.idle_buildings), making and eating nothing. plan() is
## the one function the tick, the card and the LEDGER read.

const REASON := "the lord's workshops buy their inputs"

## Every standing building as [cell, code]: cells ascending, codes sorted —
## the one order the plan and the settlement walk.
static func buildings(state: GameState) -> Array:
	var out: Array = []
	var keys: Array = state.manor_buildings.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var codes: Array = (state.manor_buildings[key] as Array).duplicate()
		codes.sort()
		for code: String in codes:
			out.append([int(key), code])
	return out

## The lord's metric a good's pool is bought from.
static func pool_metric(pool: String) -> String:
	return "lord_strategic" if pool == "strategic" else "lord_civil"

## One row per input of every standing input building, cell then code then
## the input's file order: {cell, code, good, need, own, buy, gold, pool} —
## `own` what the manor's own units fed it this month (0 for an idle
## building, which ate nothing), `buy` the rest, `gold` its price, `pool`
## the good's pool (civil / strategic). Pure.
static func plan(repo: DataRepository, state: GameState) -> Array:
	var rows: Array = []
	var fed_of: Dictionary = {}  # cell -> the line's `fed`, one line per cell
	for pair: Array in buildings(state):
		var cell := int(pair[0])
		var code := String(pair[1])
		if not repo.building_inputs.has(code):
			continue
		var fed: Dictionary = {}
		if not MapManors.is_idle(state, cell, code):
			if not fed_of.has(cell):
				fed_of[cell] = ManorEconomy.line_of(repo, state, cell, state.tick)["fed"]
			fed = (fed_of[cell] as Dictionary).get(code, {})
		for inp: Dictionary in repo.building_inputs[code]:
			var good := String(inp["good"])
			var need := int(inp["units"])
			var own := int(fed.get(good, 0))
			var ge := repo.goods_economy_of(good)
			rows.append({"cell": cell, "code": code, "good": good, "need": need, "own": own,
				"buy": need - own, "gold": (need - own) * int(ge["price_gold"]), "pool": String(ge["pool"])})
	return rows

## The month's purchase: building by building in the plan's order, each
## pays its whole bill out of the lord's pools or none of it; a building
## its pools cannot pay for idles next month. Rewrites
## state.idle_buildings whole and returns the tick's lines, one per pool
## spent from: [{metric, delta, reason}], whole gold.
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var left := {"lord_strategic": maxi(int(state.metrics.get("lord_strategic", 0.0)), 0),
		"lord_civil": maxi(int(state.metrics.get("lord_civil", 0.0)), 0)}
	var spent := {"lord_strategic": 0, "lord_civil": 0}
	# Building bills in plan order (a Dictionary keeps insertion order).
	var bills: Dictionary = {}
	for row: Dictionary in plan(repo, state):
		var key := "%d|%s" % [int(row["cell"]), String(row["code"])]
		if not bills.has(key):
			bills[key] = {"cell": int(row["cell"]), "code": String(row["code"]),
				"lord_strategic": 0, "lord_civil": 0}
		var metric := pool_metric(String(row["pool"]))
		bills[key][metric] = int(bills[key][metric]) + int(row["gold"])
	var idle: Dictionary = {}
	for key: String in bills:
		var b: Dictionary = bills[key]
		if int(b["lord_strategic"]) <= int(left["lord_strategic"]) and int(b["lord_civil"]) <= int(left["lord_civil"]):
			for metric: String in ["lord_strategic", "lord_civil"]:
				left[metric] = int(left[metric]) - int(b[metric])
				spent[metric] = int(spent[metric]) + int(b[metric])
		else:
			var k := str(int(b["cell"]))
			if not idle.has(k):
				idle[k] = []
			(idle[k] as Array).append(String(b["code"]))
	state.idle_buildings = idle
	var lines: Array = []
	for metric: String in ["lord_strategic", "lord_civil"]:
		if int(spent[metric]) > 0:
			lines.append({"metric": metric, "delta": -int(spent[metric]), "reason": REASON})
	return lines

## The goods a building's own manor cannot feed it, in input order — what
## it must buy, and so what an idle one lacks ("idle: no iron"). A working
## building reads its line's `fed`; an idle one ate nothing, so the manor's
## units of each good are all its own supply.
static func missing_of(repo: DataRepository, state: GameState, cell: int, code: String) -> Array:
	var out: Array = []
	if not repo.building_inputs.has(code):
		return out
	var line := ManorEconomy.line_of(repo, state, cell, state.tick)
	var fed: Dictionary = line["fed"]
	var units: Dictionary = line["units"]
	for inp: Dictionary in repo.building_inputs[code]:
		var good := String(inp["good"])
		var own := int((fed[code] as Dictionary).get(good, 0)) if fed.has(code) \
			else mini(int(units.get(good, 0)), int(inp["units"]))
		if own < int(inp["units"]):
			out.append(good)
	return out

## The words an idle building wears on its card and in the news:
## "idle: no iron", "idle: no tools and iron"; "idle" alone if it lacks
## nothing of its own manor's (a pool that could not pay for what it had).
static func idle_text(repo: DataRepository, state: GameState, cell: int, code: String) -> String:
	var missing := missing_of(repo, state, cell, code)
	return "idle" if missing.is_empty() else "idle: no " + " and ".join(PackedStringArray(missing))
