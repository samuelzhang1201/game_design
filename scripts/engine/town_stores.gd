class_name TownStores
extends RefCounted
## Each realm town's strategic stores (owner 2026-10-07, spec
## docs/superpowers/specs/2026-10-07-army-supply-lines-design.md §2–3):
## GameState.town_stock, burg -> {crown, lord, house} in SUPPLY UNITS. Every
## manor of the realm feeds the nearest town of its province (the catchment);
## the crown's and the lord's units ARE metrics.strategic / lord_strategic
## (their gold, rounded down once over the whole pool), the house's are a
## house's stock the crown may buy. A writer that moves those two metrics
## without touching a town is absorbed by reconcile(). Whole numbers, burg
## code order.

const POOLS := ["crown", "lord", "house"]
const METRIC := {"crown": "strategic", "lord": "lord_strategic"}

static var _catch_cache: Dictionary = {}
static var _near_cache: Dictionary = {}


static func units_per_gold(repo: DataRepository) -> int:
	@warning_ignore("integer_division")  # the permille divides 1000 (test_army_supply_data)
	return 1000 / maxi(1, int(repo.bal("army_supply_gold_permille")))


static func gold_of_units(repo: DataRepository, units: int) -> int:
	@warning_ignore("integer_division")  # whole gold, rounded down once
	return maxi(units, 0) * int(repo.bal("army_supply_gold_permille")) / 1000


## A burg whose province the player's kingdom holds now, whatever house holds it.
static func is_realm_town(repo: DataRepository, state: GameState, burg: String) -> bool:
	var b: Dictionary = repo.burgs.get(burg, {})
	if b.is_empty():
		return false
	return MapOwnership.owner_of(repo, state, String(b.get("province_code", ""))) \
		== repo.resolve_realm("player_realm")


static func realm_towns(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for code: String in repo.burgs:
		if is_realm_town(repo, state, code):
			out.append(code)
	out.sort()
	return out


## Where goods with no town of their own land: the realm's capital while the
## realm holds it, else the first realm town by code; "" with none.
static func depot(repo: DataRepository, state: GameState) -> String:
	var cap := String((repo.kingdoms.get(repo.resolve_realm("player_realm"), {}) as Dictionary).get("capital_burg", ""))
	if cap != "" and is_realm_town(repo, state, cap):
		return cap
	var towns := realm_towns(repo, state)
	return String(towns[0]) if not towns.is_empty() else ""


static func _burg_px(b: Dictionary) -> Vector2:
	return Vector2(float(b.get("x", 0)), float(b.get("y", 0)))


static func _nearest(repo: DataRepository, at: Vector2, towns: Array) -> String:
	var best := ""
	var best_d := INF
	for code: String in towns:
		var d := at.distance_squared_to(_burg_px(repo.burgs[code]))
		if d < best_d or (d == best_d and code < best):
			best_d = d
			best = code
	return best


## The other realm towns, nearest `burg` first (straight line; ties by burg
## code) — where a dry town's garrison draws on the crown's stores (spec
## §3.2 step 4, owner 2026-10-07 option A). Cached on who holds what.
static func nearest_first(repo: DataRepository, state: GameState, burg: String) -> Array:
	var key := hash([repo.get_instance_id(), state.province_owner.hash()])
	if not _near_cache.has(key):
		if _near_cache.size() > 16:
			_near_cache.clear()
		_near_cache[key] = {}
	var by_town: Dictionary = _near_cache[key]
	if by_town.has(burg):
		return by_town[burg]
	var at := _burg_px(repo.burgs.get(burg, {}))
	var ranked: Array = []
	for code: String in realm_towns(repo, state):
		if code != burg:
			ranked.append([at.distance_squared_to(_burg_px(repo.burgs[code])), code])
	ranked.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) < float(b[0]) or (float(a[0]) == float(b[0]) and String(a[1]) < String(b[1])))
	var out: Array = ranked.map(func(r: Array) -> String: return String(r[1]))
	by_town[burg] = out
	return out


## cell -> burg for every manor of the realm (spec §2.2): the nearest realm
## town of the same province; a province with none sends to the nearest
## realm town anywhere. Cached on what moves it.
static func catchment(repo: DataRepository, state: GameState) -> Dictionary:
	var key := hash([repo.get_instance_id(), state.manor_province.hash(), state.province_owner.hash()])
	if _catch_cache.has(key):
		return _catch_cache[key]
	if _catch_cache.size() > 16:
		_catch_cache.clear()
	var towns := realm_towns(repo, state)
	var by_prov: Dictionary = {}
	for code: String in towns:
		var p := String(repo.burgs[code].get("province_code", ""))
		if not by_prov.has(p):
			by_prov[p] = []
		(by_prov[p] as Array).append(code)
	var out: Dictionary = {}
	var provs: Array = Array(MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")))
	provs.sort()
	for prov: String in provs:
		var pool: Array = by_prov.get(prov, towns)
		if pool.is_empty():
			continue
		for cell: int in MapManors.manors_of_province(repo, prov, state):
			out[cell] = _nearest(repo, MapTerrain.cell_center(repo, repo.cells[cell]), pool)
	_catch_cache[key] = out
	return out


static func town_of_cell(repo: DataRepository, state: GameState, cell: int) -> String:
	return String(catchment(repo, state).get(cell, depot(repo, state)))


static func stock_of(state: GameState, burg: String) -> Dictionary:
	var s: Dictionary = state.town_stock.get(burg, {})
	return {"crown": int(s.get("crown", 0)), "lord": int(s.get("lord", 0)), "house": int(s.get("house", 0))}


## How many days a town's stores last at `monthly_draw` units a month (the
## engine's `holds`; whole days).
static func days_of_stock(state: GameState, burg: String, monthly_draw: int) -> int:
	var st := stock_of(state, burg)
	@warning_ignore("integer_division")
	return (int(st["crown"]) + int(st["lord"]) + int(st["house"])) * Calendar.DAYS_PER_TICK / maxi(monthly_draw, 1)


static func total(state: GameState, pool: String) -> int:
	var n := 0
	for b: String in state.town_stock:
		n += int((state.town_stock[b] as Dictionary).get(pool, 0))
	return n


static func add(state: GameState, burg: String, pool: String, units: int) -> void:
	if burg == "" or units == 0:
		return
	var s := stock_of(state, burg)
	s[pool] = maxi(0, int(s[pool]) + units)
	state.town_stock[burg] = s


## Takes up to `units` of `pool` from `burg`; returns what was taken.
static func take(state: GameState, burg: String, pool: String, units: int) -> int:
	if burg == "" or not state.town_stock.has(burg):
		return 0  # a town with no entry holds nothing
	var s := stock_of(state, burg)
	var got := clampi(units, 0, int(s[pool]))
	s[pool] = int(s[pool]) - got
	state.town_stock[burg] = s
	return got


## `total` split over `weights` (key -> int >= 0) by largest remainder, ties
## to the key that sorts first; all-zero weights share it evenly.
static func apportion(total: int, weights: Dictionary) -> Dictionary:
	var keys: Array = weights.keys()
	keys.sort()
	var out: Dictionary = {}
	if keys.is_empty():
		return out
	var sum := 0
	for k in keys:
		sum += maxi(int(weights[k]), 0)
	var w: Dictionary = {}
	for k in keys:
		w[k] = 1 if sum == 0 else maxi(int(weights[k]), 0)
	if sum == 0:
		sum = keys.size()
	var given := 0
	var rems: Array = []
	for k in keys:
		@warning_ignore("integer_division")
		var whole: int = total * int(w[k]) / sum
		out[k] = whole
		given += whole
		rems.append([total * int(w[k]) % sum, k])
	rems.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and String(a[1]) < String(b[1])))
	for i in range(total - given):
		var k: String = rems[i % rems.size()][1]
		out[k] = int(out[k]) + 1
	return out


## The two metrics are the gold of their pools' units (spec §2.1).
static func sync_metrics(repo: DataRepository, state: GameState) -> void:
	for pool: String in METRIC:
		state.metrics[METRIC[pool]] = float(gold_of_units(repo, total(state, pool)))


## Absorb what other writers did to the two metrics (spec §3.1, plan
## "Measures"): a rise lands in the depot, a fall is taken from the towns in
## proportion to their stock. Then the metrics are re-synced. A town the realm
## has lost takes its stores with it (its entry is erased first, and the
## metric follows the towns down). A realm with no town keeps no strategic
## stores: a rise with no depot to land in is dropped.
static func reconcile(repo: DataRepository, state: GameState) -> void:
	var upg := units_per_gold(repo)
	var before: Dictionary = {}
	for pool: String in METRIC:
		before[pool] = gold_of_units(repo, total(state, pool))
	var gone: Array = state.town_stock.keys()
	gone.sort()
	for b: String in gone:
		if not is_realm_town(repo, state, b):
			state.town_stock.erase(b)
	for pool: String in METRIC:
		# the metric less what the lost towns carried off: only what OTHER
		# writers did to it is left to absorb
		var lost: int = int(before[pool]) - gold_of_units(repo, total(state, pool))
		var want := maxi(int(state.metrics.get(METRIC[pool], 0.0)) - lost, 0)
		var have := gold_of_units(repo, total(state, pool))
		var diff := want - have
		if diff > 0:
			add(state, depot(repo, state), pool, diff * upg)
		elif diff < 0:
			var weights: Dictionary = {}
			for b: String in state.town_stock:
				weights[b] = int((state.town_stock[b] as Dictionary).get(pool, 0))
			var cut := apportion(mini(-diff * upg, total(state, pool)), weights)
			for b: String in cut:
				take(state, b, pool, int(cut[b]))
	sync_metrics(repo, state)


## The month's strategic goods by town, in GOLD (spec §3.1): a manor of a
## province the crown controls gives all of it to `lord`; any other realm
## manor's goods are split between `crown` (crown_share_permille of the
## realm's, apportioned over the towns by what reaches them, so the crown's
## sum equals RealmEconomy.purses exactly) and `house` (the rest).
## burg -> {lord, crown, house}.
static func month_inflow(repo: DataRepository, state: GameState) -> Dictionary:
	var catch := catchment(repo, state)
	var home := depot(repo, state)
	var lord: Dictionary = {}
	var other: Dictionary = {}
	var provs: Array = Array(MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")))
	provs.sort()
	for prov: String in provs:
		var mine := MapManors.crown_controls(repo, state, prov)
		var lines := RealmEconomy.lines_of_province(repo, state, prov)
		var cells: Array = lines.keys()
		cells.sort()
		for cell: int in cells:
			var town := String(catch.get(cell, home))
			if town == "":
				continue
			var g := int((lines[cell] as Dictionary)["strategic"])
			if mine:
				lord[town] = int(lord.get(town, 0)) + g
			else:
				other[town] = int(other.get(town, 0)) + g
	var crown_total := int(RealmEconomy.purses(repo, state)["realm_share"]["strategic"])
	var crown: Dictionary = apportion(crown_total, other) if not other.is_empty() else {}
	var towns: Array = lord.keys()
	for t in other.keys():
		if not towns.has(t):
			towns.append(t)
	towns.sort()
	var out: Dictionary = {}
	for t: String in towns:
		var c := int(crown.get(t, 0))
		out[t] = {"lord": int(lord.get(t, 0)), "crown": c, "house": maxi(int(other.get(t, 0)) - c, 0)}
	return out


## Settle the month's goods into the towns (TickEngine._settle_economy, beside
## the purse lines that raise the two metrics by the same gold). A house keeps
## at most `town_house_stock_months` of its own goods in a town.
static func deposit_month(repo: DataRepository, state: GameState) -> void:
	var upg := units_per_gold(repo)
	var months := int(repo.bal("town_house_stock_months"))
	var inflow := month_inflow(repo, state)
	var towns: Array = inflow.keys()
	towns.sort()
	for t: String in towns:
		var row: Dictionary = inflow[t]
		add(state, t, "lord", int(row["lord"]) * upg)
		add(state, t, "crown", int(row["crown"]) * upg)
		var cap := int(row["house"]) * months * upg
		var s := stock_of(state, t)
		s["house"] = mini(int(s["house"]) + int(row["house"]) * upg, cap)
		state.town_stock[t] = s


## Spread the two pools as they stand over the towns by each town's share of
## a month's inflow (a new campaign; an old save), and fill each house stock
## to its cap. When every town's weight for a pool is 0 the pool is shared
## evenly over the inflow towns; the depot takes it only when there are no
## inflow towns at all.
static func seed_from_pools(repo: DataRepository, state: GameState) -> void:
	state.town_stock = {}
	var upg := units_per_gold(repo)
	var inflow := month_inflow(repo, state)
	var months := int(repo.bal("town_house_stock_months"))
	for pool: String in METRIC:
		var units := maxi(int(state.metrics.get(METRIC[pool], 0.0)), 0) * upg
		var weights: Dictionary = {}
		for t: String in inflow:
			weights[t] = int((inflow[t] as Dictionary)[pool])
		if weights.is_empty():
			add(state, depot(repo, state), pool, units)
			continue
		var split := apportion(units, weights)
		var keys: Array = split.keys()
		keys.sort()
		for t: String in keys:
			add(state, t, pool, int(split[t]))
	var towns: Array = inflow.keys()
	towns.sort()
	for t: String in towns:
		add(state, t, "house", int((inflow[t] as Dictionary)["house"]) * months * upg)
	sync_metrics(repo, state)


## Seed only a state that has no stores yet (Game.load_campaign: a save from
## before the town stores).
static func ensure(repo: DataRepository, state: GameState) -> void:
	if state.town_stock.is_empty():
		TownStores.seed_from_pools(repo, state)
