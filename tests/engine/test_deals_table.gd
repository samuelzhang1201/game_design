extends GutTest
## economy/deals.csv (importer-only, spec: 10,815 Azgaar trade flows): every
## recorded flow between a market and a burg, or between two markets. Nothing
## reads this table yet (DataRepository is deliberately not wired to it), so
## these assertions read the pack file directly, the way test_map_pack.gd's
## maps.csv row-shape test does.

var repo: DataRepository
var deals_path: String

func before_all() -> void:
	repo = DataRepository.load_all("res://data")
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
