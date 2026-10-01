extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## economy/deals.csv (importer-only, spec: 10,815 Azgaar trade flows): every
## recorded flow between a market and a burg, or between two markets. These
## assertions read the pack file directly, the way test_map_pack.gd's maps.csv
## row-shape test does; DataRepository.deals (LEDGER M6, MarketSystem's trade
## routes) must hold every row of it, in file order.

var repo: DataRepository
var deals_path: String

func before_all() -> void:
	repo = SuiteData.repo()
	assert_not_null(repo, DataRepository.last_error)
	deals_path = String(repo.maps[repo.map_id]["data_dir"]) + "/economy/deals.csv"

func test_deals_csv_exists_and_parses_with_expected_columns() -> void:
	var rows := DataRepository.parse_csv(deals_path,
		["seller_type", "seller", "buyer_type", "buyer", "good_code", "units", "price", "tax"])
	assert_gt(rows.size(), 0, "deals.csv has rows: " + DataRepository.last_error)

func test_every_deal_resolves_its_good_and_its_market_or_burg_party() -> void:
	var rows := DataRepository.parse_csv(deals_path,
		["seller_type", "seller", "buyer_type", "buyer", "good_code", "units", "price", "tax"])
	assert_gt(rows.size(), 0, "deals.csv loaded")
	var goods := repo.world_table("economy", "goods")
	var markets := repo.world_table("economy", "markets")
	var burgs := repo.burgs
	var types_seen: Dictionary = {}
	for row: Dictionary in rows:
		assert_true(goods.has(String(row["good_code"])),
			"deal good %s resolves" % String(row["good_code"]))
		for side in [["seller_type", "seller"], ["buyer_type", "buyer"]]:
			var kind := String(row[side[0]])
			var id := String(row[side[1]])
			types_seen[kind] = true
			assert_true(kind == "market" or kind == "burg",
				"%s is either market or burg, got '%s'" % [side[0], kind])
			if kind == "burg":
				assert_true(burgs.has(id), "deal burg %s resolves" % id)
			elif kind == "market":
				assert_true(markets.has(id), "deal market %s resolves" % id)
	for kind: String in types_seen:
		assert_true(kind == "market" or kind == "burg",
			"only market/burg party types appear, saw '%s'" % kind)

func test_the_repository_loads_every_deal_in_file_order() -> void:
	var rows := DataRepository.parse_csv(deals_path,
		["seller_type", "seller", "buyer_type", "buyer", "good_code", "units", "price", "tax"])
	assert_eq(repo.deals.size(), rows.size())
	for i in [0, rows.size() - 1]:
		var d: Dictionary = repo.deals[i]
		assert_eq(String(d["seller"]), String(rows[i]["seller"]))
		assert_eq(String(d["buyer"]), String(rows[i]["buyer"]))
		assert_eq(String(d["good"]), String(rows[i]["good_code"]))
		assert_almost_eq(float(d["units"]), float(rows[i]["units"]), 0.0001)
