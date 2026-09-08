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

## The cast's realms (roles.csv kingdom column) must exist on the map
## (owner ruling 2026-09-03: the fiction adopted the Azgaar state names).
func test_fiction_kingdoms_are_on_the_map() -> void:
	for code in ["brampia", "hetalia", "snere", "tsalutia"]:
		assert_true(repo.kingdoms.has(code), "%s is a map kingdom" % code)
	for role in repo.roles:
		var kingdom := String(role.get("kingdom", ""))
		if kingdom != "":
			assert_true(repo.kingdoms.has(kingdom),
				"%s's kingdom %s is on the map" % [role["id"], kingdom])

func test_index_bitmap_matches_map_and_kingdoms() -> void:
	# Paths come from the loaded map pack, so this test follows whichever
	# map data/maps.csv points at rather than pinning one export's filenames.
	var map_tex: Texture2D = load(Game.data.map_texture_path)
	var idx_tex: Texture2D = load(Game.data.index_texture_path)
	assert_not_null(map_tex)
	assert_not_null(idx_tex)
	# The render may be an integer-scale export (see tools/import_azgaar.gd);
	# the index bitmap stays at native scale.
	var k := int(map_tex.get_width()) / int(idx_tex.get_width())
	assert_gt(k, 0, "render at least native size")
	assert_eq(map_tex.get_size(), idx_tex.get_size() * float(k),
		"render is an integer multiple of the index bitmap")
	var img: Image = idx_tex.get_image()
	for code: String in repo.kingdoms:
		var row: Dictionary = repo.kingdoms[code]
		var px := Vector2i(int(float(row["center_x"])), int(float(row["center_y"])))
		assert_eq(MapIndex.state_at(img, px), int(row["state_id"]),
			"%s center pixel decodes to its state_id" % code)

## Border loops (borders.csv, from tools/import_azgaar.gd): every kingdom has
## at least one closed loop, and every loop point actually lies on that
## kingdom's edge — within two pixels of a bitmap pixel carrying its state.
func test_every_kingdom_has_border_loops() -> void:
	for code: String in repo.kingdoms:
		var loops: Array = repo.borders.get(code, [])
		assert_gt(loops.size(), 0, "%s has at least one border loop" % code)
		for loop: PackedVector2Array in loops:
			assert_gte(loop.size(), 3, "%s: a loop needs 3+ points" % code)

func test_border_points_hug_their_kingdom_in_the_bitmap() -> void:
	var img: Image = (load(repo.index_texture_path) as Texture2D).get_image()
	for code: String in repo.kingdoms:
		var sid := int(repo.kingdoms[code]["state_id"])
		var off := 0
		var total := 0
		for loop: PackedVector2Array in repo.borders.get(code, []):
			for p: Vector2 in loop:
				total += 1
				if not _touches_state(img, p, sid):
					off += 1
		assert_eq(off, 0, "%s: %d of %d border points are not adjacent to the kingdom"
			% [code, off, total])

func _touches_state(img: Image, p: Vector2, sid: int) -> bool:
	var c := Vector2i(p.floor())
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if MapIndex.state_at(img, c + Vector2i(dx, dy)) == sid:
				return true
	return false
