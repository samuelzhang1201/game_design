class_name IndustrySystem
extends RefCounted
## Buildings eat (spec 2026-09-30-ledger-industry-trade-design, M5): every
## standing input building (data/economy/building_inputs.csv) is fed from its own
## manor's units first — ManorEconomy.line_of nets them, still the only
## rounding in the economy — and the rest it buys from the LORD's pool of
## each good (goods_economy.csv `pool`, at its `price_gold`) at the month's
## end; a building whose purchase the pool cannot pay stands IDLE the next
## month (GameState.idle_buildings), making and eating nothing. plan() is
## the one function the tick, the card and the LEDGER read.

const REASON := "the lord's workshops buy their inputs"

## Every standing building of the LORD's as [cell, code]: only manors the
## crown's own house holds, like WorkshopSystem.cells (fix round 1 ruling:
## a building on another house's manor neither buys nor idles through the
## lord — it works as the pack's economy counts it, eating its own manor's
## units, the holder's affair). Cells ascending, codes sorted — the one
## order the plan and the settlement walk.
static func buildings(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var keys: Array = state.manor_buildings.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		if not MapManors.is_crowns(repo, state, int(key)):
			continue
		var codes: Array = (state.manor_buildings[key] as Array).duplicate()
		codes.sort()
		for code: String in codes:
			out.append([int(key), code])
	return out

## The lord's metric a good's pool is bought from.
static func pool_metric(pool: String) -> String:
	return "lord_strategic" if pool == "strategic" else "lord_civil"

## One row per input of every standing input building of the lord's, cell
## then code then the input's file order: {cell, code, good, need, own,
## buy, gold, pool} — `own` what the manor's own units feed it (own_supply:
## a working building's line `fed`, an idle one's estimate, so a waking
## building is billed only its shortfall), `buy` the rest, `gold` its
## price, `pool` the good's pool (civil / strategic). Pure.
static func plan(repo: DataRepository, state: GameState) -> Array:
	var rows: Array = []
	var own_of: Dictionary = {}  # cell -> own_supply, one line per cell
	for pair: Array in buildings(repo, state):
		var cell := int(pair[0])
		var code := String(pair[1])
		if not repo.building_inputs.has(code):
			continue
		if not own_of.has(cell):
			own_of[cell] = own_supply(repo, state, cell)
		var fed: Dictionary = (own_of[cell] as Dictionary).get(code, {})
		for inp: Dictionary in repo.building_inputs[code]:
			var good := String(inp["good"])
			var need := int(inp["units"])
			var own := int(fed.get(good, 0))
			var ge := repo.goods_economy_of(good)
			rows.append({"cell": cell, "code": code, "good": good, "need": need, "own": own,
				"buy": need - own, "gold": (need - own) * int(ge["price_gold"]), "pool": String(ge["pool"])})
	return rows

## What each input building of a manor is fed from the manor's own units:
## code -> {good: units}. A working building's is its line's `fed`; an idle
## one ate nothing, so its estimate is what the idle line's units could
## give it, min(units, need), taken in the same sorted code order line_of
## eats in — the figure the plan bills against and missing_of reads.
static func own_supply(repo: DataRepository, state: GameState, cell: int) -> Dictionary:
	var line := ManorEconomy.line_of(repo, state, cell, state.tick)
	var fed: Dictionary = line["fed"]
	var left: Dictionary = (line["units"] as Dictionary).duplicate()
	var out: Dictionary = {}
	var standing: Array = MapManors.buildings_of(state, cell)
	standing.sort()
	for code: String in standing:
		if not repo.building_inputs.has(code):
			continue
		if fed.has(code):
			out[code] = (fed[code] as Dictionary).duplicate()
			continue
		var eaten: Dictionary = {}
		for inp: Dictionary in repo.building_inputs[code]:
			var good := String(inp["good"])
			var own := mini(int(left.get(good, 0)), int(inp["units"]))
			left[good] = int(left.get(good, 0)) - own
			eaten[good] = own
		out[code] = eaten
	return out

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
## it must buy, and so what an idle one lacks ("idle: no iron"); the same
## own_supply figures the plan bills against.
static func missing_of(repo: DataRepository, state: GameState, cell: int, code: String) -> Array:
	var out: Array = []
	if not repo.building_inputs.has(code):
		return out
	var fed: Dictionary = own_supply(repo, state, cell).get(code, {})
	for inp: Dictionary in repo.building_inputs[code]:
		if int(fed.get(String(inp["good"]), 0)) < int(inp["units"]):
			out.append(String(inp["good"]))
	return out

## The words for a list of missing goods: "idle: no iron", "idle: no tools
## and iron"; "idle" alone for none (a pool that could not pay for a need
## its manor could partly give).
static func idle_words(missing: Array) -> String:
	return "idle" if missing.is_empty() else "idle: no " + " and ".join(PackedStringArray(missing))

## The words an idle building wears on its card.
static func idle_text(repo: DataRepository, state: GameState, cell: int, code: String) -> String:
	return idle_words(missing_of(repo, state, cell, code))
