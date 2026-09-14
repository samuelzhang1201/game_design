extends GutTest
## data/goods_economy.csv (spec §3): every good of the pack has a pool, a
## whole-gold price and an integer growth; a good the table does not name
## takes its first tag's default row.

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_every_pack_good_resolves_to_a_pool_and_a_price() -> void:
	var goods: Dictionary = data.world_table("economy", "goods")
	assert_gt(goods.size(), 60, "the pack's goods loaded")
	for code: String in goods:
		var ge: Dictionary = data.goods_economy_of(code)
		assert_true(ge["pool"] in ["strategic", "civil"], "%s has a pool" % code)
		assert_gt(int(ge["price_gold"]), 0, "%s has a price" % code)
		assert_typeof(ge["price_gold"], TYPE_INT, "%s price is whole gold" % code)
		assert_typeof(ge["growth_permille"], TYPE_INT, "%s growth is per mille" % code)
		assert_true(data.goods_economy.has(code), "%s is named in the table, not defaulted" % code)

func test_the_scale_is_deliberate() -> void:
	assert_eq(data.goods_economy_of("grain")["pool"], "civil")
	assert_eq(int(data.goods_economy_of("grain")["price_gold"]), 1)
	assert_eq(data.goods_economy_of("iron")["pool"], "strategic")
	assert_eq(int(data.goods_economy_of("iron")["price_gold"]), 4)
	assert_eq(data.goods_economy_of("arms")["pool"], "strategic")
	assert_eq(int(data.goods_economy_of("ships")["price_gold"]), 30)
	assert_eq(int(data.goods_economy_of("gold")["price_gold"]), 40)
	assert_gt(int(data.goods_economy_of("silk")["growth_permille"]), int(data.goods_economy_of("grain")["growth_permille"]),
		"luxuries grow faster than bread")

func test_an_unnamed_good_takes_its_tags_default() -> void:
	var r: DataRepository = DataRepository.new()
	r.goods_economy_defaults = {"military": {"tag": "military", "pool": "strategic", "price_gold": "9", "growth_permille": "4"}}
	r._register_table("economy", "goods", {"halberds": {"good_code": "halberds", "tags": "military|luxury"}})
	var ge: Dictionary = r.goods_economy_of("halberds")
	assert_eq(ge["pool"], "strategic")
	assert_eq(int(ge["price_gold"]), 9)
	assert_eq(int(ge["growth_permille"]), 4)
	var none: Dictionary = r.goods_economy_of("nothing")
	assert_eq(none, {"pool": "civil", "price_gold": 1, "growth_permille": 0})
