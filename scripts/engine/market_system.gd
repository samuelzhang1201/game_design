class_name MarketSystem
extends RefCounted
## Markets and trade routes (spec 2026-09-30-ledger-industry-trade-design,
## M6): the pack's markets and trade flows (deals.csv) read through LIVE
## ownership (invariant 6). A trade route is every deal a seller in the
## realm (a market it holds, or one of its towns) makes with a buyer of one
## foreign kingdom, a month's units × price; the crown takes
## trade_toll_permille of an open route, scaled and skimmed by the steward
## (Governance flow "trade_route"). Pure; no RNG.

## The routes' per-kingdom sums ({kingdom: {value (float), deals}}), cached
## against the ownership signature: 10,815 deals are walked only when a
## province or an annexed manor has moved, never once per LEDGER snapshot.
static var _sums: Dictionary = {}
static var _sums_key := ""
## market id -> [market_goods rows], per pack.
static var _goods_by_market: Dictionary = {}
static var _goods_key := ""


## Drop every cache (a pack swap: DataRepository.load_map).
static func forget() -> void:
	_sums.clear()
	_sums_key = ""
	_goods_by_market.clear()
	_goods_key = ""


## A market id as the tables key it: the LEDGER hands ids over as ints
## (Ledger.params_of) and JSON as floats; world_table rows key on Strings.
static func market_key(id: Variant) -> String:
	if typeof(id) == TYPE_FLOAT and is_equal_approx(float(id), roundf(float(id))):
		return str(int(id))
	return str(id)


## The province a town lies in NOW: the province its manor was annexed into
## when the crown bought that manor across the border (GameState
## .manor_province), else the pack's.
static func province_of_burg(repo: DataRepository, state: GameState, burg: String) -> String:
	if state != null:
		for cell_s: String in state.manor_province:
			if MapManors.burg_of(repo, int(cell_s)) == burg:
				return String(state.manor_province[cell_s])
	return String((repo.burgs.get(burg, {}) as Dictionary).get("province_code", ""))


## The kingdom holding a deal's party now: a town's province's holder, a
## market's centre town's. "" for a party the pack does not know.
static func kingdom_of_party(repo: DataRepository, state: GameState, type: String, code: String) -> String:
	var burg := code
	if type == "market":
		burg = String((repo.world_table("economy", "markets").get(code, {}) as Dictionary).get("center_burg", ""))
	var prov := province_of_burg(repo, state, burg)
	return "" if prov == "" else MapOwnership.owner_of(repo, state, prov)


## The realm's markets: those whose centre town the realm holds NOW, sorted
## as numbers.
static func realm_markets(repo: DataRepository, state: GameState) -> Array:
	var realm := repo.resolve_realm("player_realm")
	var out: Array = []
	for id: String in repo.world_table("economy", "markets"):
		if kingdom_of_party(repo, state, "market", id) == realm:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return out


static func is_realm_market(repo: DataRepository, state: GameState, id: Variant) -> bool:
	return market_key(id) in realm_markets(repo, state)


## A market's goods rows (market_goods.csv), in file order.
static func goods_of_market(repo: DataRepository, market_id: String) -> Array:
	var key := "%d:%s" % [repo.get_instance_id(), repo.map_id]
	if _goods_key != key:
		_goods_by_market.clear()
		for row: Dictionary in repo.world_table("economy", "market_goods").values():
			var id := String(row["market_id"])
			if not _goods_by_market.has(id):
				_goods_by_market[id] = []
			(_goods_by_market[id] as Array).append(row)
		_goods_key = key
	return _goods_by_market.get(market_id, [])


## Σ stock × price of a market's goods in one pool, whole gold.
static func market_value(repo: DataRepository, market_id: String, pool: String) -> int:
	var total := 0.0
	for row: Dictionary in goods_of_market(repo, market_id):
		if String(repo.goods_economy_of(String(row["good_code"]))["pool"]) == pool:
			total += float(row["stock"]) * float(row["price"])
	return int(roundf(total))


## The market's price for a pool's goods against their catalogue price, per
## mille (1000 = catalogue): stock-weighted over the goods it holds. A market
## holding none of the pool trades at the catalogue.
static func basket_price_permille(repo: DataRepository, market_id: String, pool: String) -> int:
	var paid := 0.0
	var list := 0.0
	for row: Dictionary in goods_of_market(repo, market_id):
		var ge := repo.goods_economy_of(String(row["good_code"]))
		if String(ge["pool"]) != pool:
			continue
		paid += float(row["stock"]) * float(row["price"])
		list += float(row["stock"]) * float(ge["price_gold"])
	return 1000 if list <= 0.0 else int(roundf(paid / list * 1000.0))


## What a unit of a pool's goods costs the crown at a realm market, per
## mille of its catalogue price: the market's basket, but never under what
## the factor pays for it (goods_trade_spread under the catalogue) — the
## export's markets mostly trade under the catalogue, and a cheaper buy
## than the flat sale would let a king buy there and sell to the factor for
## a sure profit every month.
static func buy_permille(repo: DataRepository, market_id: String, pool: String) -> int:
	var floor_permille := int(roundf(1000.0 * (1.0 - repo.bal("goods_trade_spread"))))
	return maxi(basket_price_permille(repo, market_id, pool), floor_permille)


## What a realm market pays the crown for a unit of a pool's goods, per mille:
## its basket less the factor's cut, but never more than the cheapest buy in
## the realm (a realm market's, or the factor's) — so no sale anywhere pays
## more than a purchase anywhere costs, and no round trip is a profit.
static func sell_permille(repo: DataRepository, state: GameState, market_id: String, pool: String) -> int:
	var spread := repo.bal("goods_trade_spread")
	var cheapest := int(roundf(1000.0 * (1.0 + spread)))
	for id: String in realm_markets(repo, state):
		cheapest = mini(cheapest, buy_permille(repo, id, pool))
	var own := int(roundf(float(basket_price_permille(repo, market_id, pool)) * (1.0 - spread)))
	return mini(own, cheapest)


## GOODS_BUY at a realm market: what `gold` of the pool's goods costs the
## treasury, whole gold (buy_permille).
static func buy_price(repo: DataRepository, market_id: String, pool: String, gold: int) -> int:
	return int(roundf(float(gold) * float(buy_permille(repo, market_id, pool)) / 1000.0))


## GOODS_SELL at a realm market: what `gold` of the pool's goods brings the
## treasury, whole gold (sell_permille).
static func sell_price(repo: DataRepository, state: GameState, market_id: String, pool: String, gold: int) -> int:
	return int(roundf(float(gold) * float(sell_permille(repo, state, market_id, pool)) / 1000.0))


## The per-kingdom sums of the realm's exports, {kingdom: {value, deals}},
## deals walked in file order (a float sum in a fixed order is a fixed sum).
static func _route_sums(repo: DataRepository, state: GameState) -> Dictionary:
	var realm := repo.resolve_realm("player_realm")
	var key := "%d:%s:%d:%s:%d:%d" % [repo.get_instance_id(), repo.map_id, repo.deals.size(), realm,
		state.province_owner.hash(), state.manor_province.hash()]
	if key == _sums_key:
		return _sums
	var kingdom_of: Dictionary = {}
	var by: Dictionary = {}
	for d: Dictionary in repo.deals:
		var seller := _party_kingdom(repo, state, kingdom_of, String(d["seller_type"]), String(d["seller"]))
		if seller != realm:
			continue
		var buyer := _party_kingdom(repo, state, kingdom_of, String(d["buyer_type"]), String(d["buyer"]))
		if buyer == "" or buyer == realm:
			continue
		if not by.has(buyer):
			by[buyer] = {"value": 0.0, "deals": 0}
		var row: Dictionary = by[buyer]
		row["value"] = float(row["value"]) + float(d["units"]) * float(d["price"])
		row["deals"] = int(row["deals"]) + 1
	_sums = by
	_sums_key = key
	return by


static func _party_kingdom(repo: DataRepository, state: GameState, memo: Dictionary,
		type: String, code: String) -> String:
	var k := type + ":" + code
	if not memo.has(k):
		memo[k] = kingdom_of_party(repo, state, type, code)
	return String(memo[k])


## Every trade route of the realm, sorted by kingdom code: {kingdom, value
## (whole gold a month), deals, open, claimed, skimmed, toll, governor}.
## `claimed` is the steward's word — the toll as his efficiency collects it,
## the whole of it; `skimmed` his cut; `toll` = claimed − skimmed is what
## reaches the treasury. A closed route still shows its value, and takes
## nothing.
static func routes(repo: DataRepository, state: GameState) -> Array:
	var by := _route_sums(repo, state)
	var g := Governance.factors(repo, state, "trade_route")
	var toll_permille := int(repo.bal("trade_toll_permille"))
	var eff := int(g["efficiency"])
	var skim := int(g["skim"])
	var codes: Array = by.keys()
	codes.sort()
	var out: Array = []
	for k: String in codes:
		var value := int(roundf(float(by[k]["value"])))
		var open := not k in state.closed_routes
		@warning_ignore("integer_division")
		var claimed := value * toll_permille / 1000 * eff / 1000 if open else 0
		@warning_ignore("integer_division")
		var skimmed := claimed * skim / 1000
		out.append({"kingdom": k, "value": value, "deals": int(by[k]["deals"]), "open": open,
			"claimed": claimed, "skimmed": skimmed, "toll": claimed - skimmed,
			"governor": String(g["governor"])})
	return out


## A route's name for prose: the buyer kingdom's live label (invariant 5).
static func label_of(repo: DataRepository, kingdom: String) -> String:
	return String((repo.kingdoms.get(kingdom, {}) as Dictionary).get("label", kingdom))


## The month's toll lines for the tick to apply (it owns the report); the
## steward's skim goes to his own books on the flow (Governance.add_skims).
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var rows := routes(repo, state)
	var lines: Array = []
	for r: Dictionary in rows:
		if int(r["toll"]) > 0:
			lines.append({"metric": "treasury", "delta": int(r["toll"]),
				"reason": "tolls on the trade with " + label_of(repo, String(r["kingdom"]))})
	Governance.add_skims(state, rows, "trade_route")
	return lines
