extends GutTest
## The Azgaar-imported world tables (see tools/import_azgaar.gd) load and
## cross-reference cleanly, and the hit-test bitmap agrees with them.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")
	assert_not_null(repo, DataRepository.last_error)

func test_map_tables_load() -> void:
	assert_gt(repo.kingdoms.size(), 0, "kingdoms.csv loaded")
	assert_gt(repo.provinces.size(), 0, "provinces.csv loaded")
	assert_gt(repo.burgs.size(), 0, "burgs.csv loaded")

func test_every_province_kingdom_resolves() -> void:
	for code: String in repo.provinces:
		var row: Dictionary = repo.provinces[code]
		assert_true(repo.kingdoms.has(row["kingdom_code"]),
			"%s -> %s" % [code, row["kingdom_code"]])

func test_every_burg_reference_resolves() -> void:
	for code: String in repo.burgs:
		var row: Dictionary = repo.burgs[code]
		assert_true(repo.provinces.has(row["province_code"]),
			"%s province %s" % [code, row["province_code"]])
		assert_true(repo.kingdoms.has(row["kingdom_code"]),
			"%s kingdom %s" % [code, row["kingdom_code"]])

func test_every_kingdom_capital_and_neighbors_resolve() -> void:
	for code: String in repo.kingdoms:
		var row: Dictionary = repo.kingdoms[code]
		assert_true(repo.burgs.has(row["capital_burg"]),
			"%s capital %s" % [code, row["capital_burg"]])
		for n: String in String(row["neighbor_codes"]).split("|", false):
			assert_true(repo.kingdoms.has(n), "%s neighbor %s" % [code, n])

func test_index_bitmap_matches_map_and_kingdoms() -> void:
	var map_tex: Texture2D = load("res://assets/maps/world_map.png")
	var idx_tex: Texture2D = load("res://assets/maps/world_state_index.png")
	assert_not_null(map_tex)
	assert_not_null(idx_tex)
	assert_eq(idx_tex.get_size(), map_tex.get_size(), "bitmap sizes match")
	var img: Image = idx_tex.get_image()
	for code: String in repo.kingdoms:
		var row: Dictionary = repo.kingdoms[code]
		var px := Vector2i(int(float(row["center_x"])), int(float(row["center_y"])))
		assert_eq(MapIndex.state_at(img, px), int(row["state_id"]),
			"%s center pixel decodes to its state_id" % code)
