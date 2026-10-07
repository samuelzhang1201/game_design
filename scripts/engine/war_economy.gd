class_name WarEconomy
extends RefCounted
## The war economy on the WAR ROOM's sheet (spec 2026-10-07-war-room-p3-economy-layer
## §1): the works — towns making war_works_min_gold of strategic goods a month,
## marked by the family of their largest listed good (data/war_works.csv) — the
## markets and their food price, and the pack's trade flows laid on the road
## network. Public, static facts of the pack (ruling 2); pure; cached per repo
## and map, as MapEconomy caches.

static var _cache: Dictionary = {}


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
