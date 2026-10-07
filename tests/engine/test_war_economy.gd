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
