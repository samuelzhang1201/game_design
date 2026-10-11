class_name WarEconomy
extends RefCounted
## The war economy on the WAR ROOM's sheet (spec 2026-10-07-war-room-p3-economy-layer
## §1): the works — towns making war_works_min_gold of strategic goods a month,
## marked by the family of their largest listed good (data/army/war_works.csv) — the
## markets and their food price, and the pack's trade flows laid on the road
## network. Public, static facts of the pack (ruling 2); pure; cached per repo
## and map, as MapEconomy caches.

static var _cache: Dictionary = {}

## Drop the per-repo cache (DataRepository.forget_derived).
static func forget() -> void:
	_cache.clear()



static func _key(repo: DataRepository, what: String) -> String:
	return "%d:%s:%s" % [repo.get_instance_id(), repo.map_id, what]


## Every town at or over war_works_min_gold: {burg: {gold, family, glyph,
## goods: [{good, units, gold}]}}, goods largest gold first (ties on the code).
## A town none of whose strategic goods is listed in war_works is not a work.
static func works(repo: DataRepository) -> Dictionary:
	var key := _key(repo, "works")
	if _cache.has(key):
		return _cache[key]
	var by: Dictionary = {}   # burg -> {good: units}
	for row: Dictionary in repo.world_table("economy", "production").values():
		var good := String(row.get("good_code", ""))
		var burg := String(row.get("burg_code", ""))
		if not repo.burgs.has(burg) or String(repo.goods_economy_of(good).get("pool", "")) != "strategic":
			continue
		if not by.has(burg):
			by[burg] = {}
		by[burg][good] = float((by[burg] as Dictionary).get(good, 0.0)) + float(row.get("units", 0))
	var floor_gold := int(repo.bal("war_works_min_gold"))
	var out: Dictionary = {}
	var burgs: Array = by.keys()
	burgs.sort()
	for burg: String in burgs:
		var goods: Array = []
		var total := 0
		var codes: Array = (by[burg] as Dictionary).keys()
		codes.sort()
		for good: String in codes:
			var units := float(by[burg][good])
			var gold := roundi(units * float(int(repo.goods_economy_of(good)["price_gold"])))
			total += gold
			goods.append({"good": good, "units": units, "gold": gold})
		if total < floor_gold:
			continue
		goods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["gold"]) > int(b["gold"]) or (int(a["gold"]) == int(b["gold"]) and String(a["good"]) < String(b["good"])))
		var top := ""
		for g: Dictionary in goods:
			if repo.war_works.has(String(g["good"])):
				top = String(g["good"])
				break
		if top == "":
			continue
		var row: Dictionary = repo.war_works[top]
		out[burg] = {"gold": total, "family": String(row["family"]), "glyph": String(row["glyph"]), "goods": goods}
	_cache[key] = out
	return out


## The pack's markets at their centre towns, ids in numeric order.
static func markets(repo: DataRepository) -> Array:
	var table: Dictionary = repo.world_table("economy", "markets")
	var ids: Array = table.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	var out: Array = []
	for id: Variant in ids:
		var burg := String((table[id] as Dictionary).get("center_burg", ""))
		if not repo.burgs.has(burg):
			continue
		var b: Dictionary = repo.burgs[burg]
		out.append({"id": String(id), "burg": burg, "at": Vector2(float(b["x"]), float(b["y"]))})
	return out


## The market centred on this town, "" when none is.
static func market_of_town(repo: DataRepository, burg: String) -> String:
	for m: Dictionary in markets(repo):
		if String(m["burg"]) == burg:
			return String(m["id"])
	return ""


## The market's food price against the catalogue, per mille: stock-weighted
## over its food-tagged goods, the catalogue being the one
## MarketSystem.basket_price_permille weighs a pool against. 1000 when it holds no food.
static func food_price_permille(repo: DataRepository, market_id: String) -> int:
	var tags: Dictionary = repo.world_table("economy", "goods")
	var paid := 0.0
	var list := 0.0
	for row: Dictionary in MarketSystem.goods_of_market(repo, market_id):
		var good := String(row["good_code"])
		if not String((tags.get(good, {}) as Dictionary).get("tags", "")).split("|").has("food"):
			continue
		paid += float(row["stock"]) * float(row["price"])
		list += float(row["stock"]) * float(repo.goods_economy_of(good)["price_gold"])
	return 1000 if list <= 0.0 else roundi(paid / list * 1000.0)


## A good's name as goods.csv gives it; its code when the table has none.
static func good_label(repo: DataRepository, good: String) -> String:
	return String((repo.world_table("economy", "goods").get(good, {}) as Dictionary).get("label", good))


## The pack's trade laid on the road network (ruling 5): {Vector2i(a, b) (RoadGraph
## node ids, a < b): gold a month}. Every deal has a market on one side; its
## month (units x price, the gold MarketSystem counts) is summed per market–
## town pair (a market buying from a market: its centre town), rounded once,
## and laid on every segment of the shortest road from the market's centre
## town — one tree per market, markets in numeric order. A town farther than
## courier_offroad_max_km from the network, or not reached, adds nothing.
static func trade_flows(repo: DataRepository) -> Dictionary:
	var key := _key(repo, "flows")
	if _cache.has(key):
		return _cache[key]
	var centre: Dictionary = {}
	for m: Dictionary in markets(repo):
		centre[String(m["id"])] = String(m["burg"])
	var pairs: Dictionary = {}   # market id -> {town: gold}
	for d: Dictionary in repo.deals:
		var market := ""
		var other := ""
		var other_type := ""
		if String(d["seller_type"]) == "market":
			market = String(d["seller"])
			other = String(d["buyer"])
			other_type = String(d["buyer_type"])
		elif String(d["buyer_type"]) == "market":
			market = String(d["buyer"])
			other = String(d["seller"])
			other_type = String(d["seller_type"])
		if not centre.has(market):
			continue
		var town := String(centre.get(other, "")) if other_type == "market" else other
		if not repo.burgs.has(town) or town == String(centre[market]):
			continue
		if not pairs.has(market):
			pairs[market] = {}
		pairs[market][town] = float((pairs[market] as Dictionary).get(town, 0.0)) + float(d["units"]) * float(d["price"])
	var g := RoadGraph.of_pack(repo)
	var reach := repo.bal("courier_offroad_max_km") * 1000.0
	var node_of: Dictionary = {}   # town -> node, -1 off the roads
	var out: Dictionary = {}
	var ids: Array = pairs.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id: String in ids:
		var start := _node_of(repo, g, String(centre[id]), reach, node_of)
		if start < 0:
			continue
		var tree := g.shortest(start)
		var towns: Array = (pairs[id] as Dictionary).keys()
		towns.sort()
		for town: String in towns:
			var gold := roundi(float(pairs[id][town]))
			var goal := _node_of(repo, g, town, reach, node_of)
			if gold <= 0 or goal < 0 or goal == start or int(tree["dist"][goal]) < 0:
				continue
			var at := goal
			while int(tree["prev"][at]) >= 0:
				var p := int(tree["prev"][at])
				var seg := Vector2i(mini(p, at), maxi(p, at))
				out[seg] = int(out.get(seg, 0)) + gold
				at = p
	_cache[key] = out
	return out


static func _node_of(repo: DataRepository, g: RoadGraph, town: String, reach: float, memo: Dictionary) -> int:
	if memo.has(town):
		return int(memo[town])
	var b: Dictionary = repo.burgs[town]
	var at := ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"])))
	var node := g.nearest(at)
	if node >= 0 and Vector2(at).distance_to(Vector2(g.nodes[node])) > reach:
		node = -1
	memo[town] = node
	return node


## A segment's weight on the sheet, 0..3 by war_trade_tier<N>_gold.
static func trade_tier(repo: DataRepository, gold: int) -> int:
	var tier := 0
	for n in [1, 2, 3]:
		if float(gold) >= repo.bal("war_trade_tier%d_gold" % n):
			tier = n
	return tier


## The drawn segments (tier >= 1) with an end inside `rect`: {poly (pack px),
## tier, kind ("road" | "trail")}, in the flows' own order.
static func trade_segments(repo: DataRepository, rect: Rect2) -> Array:
	var g := RoadGraph.of_pack(repo)
	var flows := trade_flows(repo)
	var out: Array = []
	for seg: Vector2i in flows:
		var tier := trade_tier(repo, int(flows[seg]))
		if tier <= 0:
			continue
		var a := ArmySystem.metres_to_pack(repo, g.nodes[seg.x])
		var b := ArmySystem.metres_to_pack(repo, g.nodes[seg.y])
		if rect.has_point(a) or rect.has_point(b):
			# the edge's own kind: a trail keeps its dashes however busy it is
			out.append({"poly": PackedVector2Array([a, b]), "tier": tier, "kind": g._kind_between(seg.x, seg.y)})
	return out


## The gold a month on the flow segment nearest `at` (pack px) within
## army_road_reach_m; 0 when no trade road is that near. The first of equals wins.
static func trade_at(repo: DataRepository, at: Vector2) -> int:
	var g := RoadGraph.of_pack(repo)
	var flows := trade_flows(repo)
	var m := Vector2(ArmySystem.pack_to_metres(repo, at))
	var reach := repo.bal("army_road_reach_m")
	var best := INF
	var gold := 0
	for seg: Vector2i in flows:
		var d := m.distance_to(Geometry2D.get_closest_point_to_segment(m, Vector2(g.nodes[seg.x]), Vector2(g.nodes[seg.y])))
		if d <= reach and d < best:
			best = d
			gold = int(flows[seg])
	return gold
