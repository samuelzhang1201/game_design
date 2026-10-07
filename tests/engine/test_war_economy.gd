extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The war economy on the sheet (spec 2026-10-07-war-room-p3-economy-layer §1).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_every_works_row_is_a_strategic_good_and_a_family_has_one_glyph() -> void:
	assert_gt(repo.war_works.size(), 0)
	var glyph_of: Dictionary = {}
	for good: String in repo.war_works:
		assert_eq(String(repo.goods_economy_of(good)["pool"]), "strategic", good)
		var row: Dictionary = repo.war_works[good]
		assert_true(WarMarkGlyph.knows(String(row["glyph"])), "%s's glyph" % good)
		if glyph_of.has(row["family"]):
			assert_eq(String(glyph_of[row["family"]]), String(row["glyph"]), "one glyph for %s" % row["family"])
		glyph_of[row["family"]] = row["glyph"]


func test_a_work_reaches_the_floor_and_takes_its_largest_listed_goods_family() -> void:
	var works := WarEconomy.works(repo)
	assert_gt(works.size(), 0)
	var floor_gold := int(repo.bal("war_works_min_gold"))
	for burg: String in works:
		var w: Dictionary = works[burg]
		assert_gte(int(w["gold"]), floor_gold, burg)
		var listed: Array = (w["goods"] as Array).filter(func(g: Dictionary) -> bool: return repo.war_works.has(String(g["good"])))
		assert_eq(String(w["family"]), String(repo.war_works[String(listed[0]["good"])]["family"]), burg)
		var golds: Array = (w["goods"] as Array).map(func(g: Dictionary) -> int: return int(g["gold"]))
		var sorted := golds.duplicate()
		sorted.sort()
		sorted.reverse()
		assert_eq(golds, sorted, "%s's goods largest first" % burg)


func test_no_floor_marks_every_town_with_a_listed_good_and_a_high_one_none() -> void:
	repo.balance["war_works_min_gold"] = 1000000.0
	assert_eq(WarEconomy.works(repo).size(), 0)
	var other := SuiteData.repo()
	other.balance["war_works_min_gold"] = 0.0
	var all := WarEconomy.works(other)
	assert_gt(all.size(), WarEconomy.works(SuiteData.repo()).size())


func test_a_town_with_no_listed_good_is_not_a_work() -> void:
	repo.war_works = {}
	assert_eq(WarEconomy.works(repo).size(), 0)


func test_the_markets_in_numeric_order_at_their_centre_towns() -> void:
	var ms := WarEconomy.markets(repo)
	assert_eq(ms.size(), repo.world_table("economy", "markets").size())
	for i in ms.size():
		var m: Dictionary = ms[i]
		var b: Dictionary = repo.burgs[String(m["burg"])]
		assert_eq(m["at"], Vector2(float(b["x"]), float(b["y"])))
		assert_eq(WarEconomy.market_of_town(repo, String(m["burg"])), String(m["id"]))
		if i > 0:
			assert_lt(int(ms[i - 1]["id"]), int(m["id"]))
	assert_eq(WarEconomy.market_of_town(repo, "no_such_town"), "")


func test_a_markets_food_price_by_hand() -> void:
	# market 1 on the default pack: stock x price of its food goods 533.64,
	# stock x catalogue 1131.93 (python over market_goods.csv, goods.csv tags,
	# goods_economy + defaults) -> 471 per mille
	var first := String(WarEconomy.markets(repo)[0]["id"])
	assert_eq(WarEconomy.food_price_permille(repo, first), 471)
	assert_eq(WarEconomy.food_price_permille(repo, "no_such_market"), 1000, "no food held: the catalogue")


## A town reachable on the roads from the first market's centre, by another node.
func _reachable_town(m: Dictionary) -> String:
	var g := RoadGraph.of_pack(repo)
	var start := g.nearest(ArmySystem.pack_to_metres(repo, m["at"]))
	var tree := g.shortest(start)
	var reach := repo.bal("courier_offroad_max_km") * 1000.0
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var at := ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"])))
		var node := g.nearest(at)
		if node != start and int(tree["dist"][node]) > 0 and Vector2(at).distance_to(Vector2(g.nodes[node])) <= reach:
			return code
	return ""


func test_a_pairs_gold_lies_on_every_segment_of_its_path_and_nowhere_else() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var town := _reachable_town(m)
	assert_ne(town, "")
	repo.deals = [{"seller_type": "market", "seller": String(m["id"]), "buyer_type": "burg", "buyer": town,
		"good": "grain", "units": 10.0, "price": 3.0}]
	var flows := WarEconomy.trade_flows(repo)
	var g := RoadGraph.of_pack(repo)
	var tree := g.shortest(g.nearest(ArmySystem.pack_to_metres(repo, m["at"])))
	var b: Dictionary = repo.burgs[town]
	var goal := g.nearest(ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"]))))
	assert_eq(flows.size(), g.route(tree, goal).size(), "one entry per segment of the path")
	for seg: Vector2i in flows:
		assert_eq(int(flows[seg]), 30)
		assert_lt(seg.x, seg.y)


func test_a_towns_sale_to_its_market_runs_the_same_road() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var town := _reachable_town(m)
	repo.deals = [{"seller_type": "burg", "seller": town, "buyer_type": "market", "buyer": String(m["id"]),
		"good": "grain", "units": 2.0, "price": 2.6}]
	var flows := WarEconomy.trade_flows(repo)
	assert_gt(flows.size(), 0)
	for seg: Vector2i in flows:
		assert_eq(int(flows[seg]), 5, "5.2 gold rounded once to whole gold")


func test_a_market_to_market_deal_runs_between_their_centres() -> void:
	var ms := WarEconomy.markets(repo)
	repo.deals = [{"seller_type": "market", "seller": String(ms[0]["id"]), "buyer_type": "market", "buyer": String(ms[1]["id"]),
		"good": "grain", "units": 10.0, "price": 1.0},
		{"seller_type": "market", "seller": String(ms[0]["id"]), "buyer_type": "burg", "buyer": String(ms[0]["burg"]),
		"good": "grain", "units": 10.0, "price": 1.0}]
	var flows := WarEconomy.trade_flows(repo)
	for seg: Vector2i in flows:
		assert_eq(int(flows[seg]), 10, "the market's own centre town adds nothing")


func test_towns_off_the_roads_add_nothing() -> void:
	repo.balance["courier_offroad_max_km"] = -1.0
	assert_eq(WarEconomy.trade_flows(repo).size(), 0)


func test_the_flows_are_built_once_per_pack() -> void:
	var a := WarEconomy.trade_flows(repo)
	var runs := RoadGraph.of_pack(repo).dijkstra_runs
	var b := WarEconomy.trade_flows(repo)
	assert_eq(RoadGraph.of_pack(repo).dijkstra_runs, runs)
	assert_eq(a, b)
	assert_eq(WarEconomy.trade_flows(SuiteData.repo()), a, "a fresh copy of the pack lays the same flows")
	for seg: Vector2i in a:
		assert_typeof(a[seg], TYPE_INT)


func test_tiers_by_the_thresholds() -> void:
	repo.balance["war_trade_tier1_gold"] = 40.0
	repo.balance["war_trade_tier2_gold"] = 120.0
	repo.balance["war_trade_tier3_gold"] = 300.0
	assert_eq(WarEconomy.trade_tier(repo, 39), 0)
	assert_eq(WarEconomy.trade_tier(repo, 40), 1)
	assert_eq(WarEconomy.trade_tier(repo, 299), 2)
	assert_eq(WarEconomy.trade_tier(repo, 300), 3)


func test_the_trade_at_a_point_on_and_off_the_road() -> void:
	var flows := WarEconomy.trade_flows(repo)
	var g := RoadGraph.of_pack(repo)
	var busiest := Vector2i(-1, -1)
	for seg: Vector2i in flows:
		if busiest.x < 0 or int(flows[seg]) > int(flows[busiest]):
			busiest = seg
	var mid_m := Vector2i((Vector2(g.nodes[busiest.x]) + Vector2(g.nodes[busiest.y])) * 0.5)
	assert_eq(WarEconomy.trade_at(repo, ArmySystem.metres_to_pack(repo, mid_m)), int(flows[busiest]))
	assert_eq(WarEconomy.trade_at(repo, Vector2(-100000, -100000)), 0)


func test_segments_are_the_drawn_tiers_touching_the_rect() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var rect := Rect2(m["at"] - Vector2(40, 40), Vector2(80, 80))
	var segs := WarEconomy.trade_segments(repo, rect)
	assert_gt(segs.size(), 0)
	for s: Dictionary in segs:
		assert_between(int(s["tier"]), 1, 3)
		var poly: PackedVector2Array = s["poly"]
		assert_eq(poly.size(), 2)
		assert_true(rect.has_point(poly[0]) or rect.has_point(poly[1]))


func test_a_segment_says_whether_it_is_a_road_or_a_trail() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var segs := WarEconomy.trade_segments(repo, Rect2(Vector2.ZERO, Vector2(1e6, 1e6)))
	var kinds: Dictionary = {}
	for s: Dictionary in segs:
		assert_true(["road", "trail"].has(String(s["kind"])), String(s["kind"]))
		kinds[String(s["kind"])] = true
	assert_true(kinds.has("road") and kinds.has("trail"), "the default pack's trade runs on both")
