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

## Map objects (spec 2026-09-08): routes, rivers, markers, biomes, map info,
## plus the province and biome index bitmaps, all from tools/import_azgaar.gd.
func test_map_object_tables_load() -> void:
	assert_gt(repo.routes.size(), 0, "routes.csv loaded")
	assert_gt(repo.rivers.size(), 0, "rivers.csv loaded")
	assert_gt(repo.markers.size(), 0, "markers.csv loaded")
	assert_gt(repo.biomes.size(), 0, "biomes.csv loaded")
	assert_eq(String(repo.map_info.get("distance_unit", "")), "km", "map_info.csv carries the unit")

func test_burgs_carry_type_and_features() -> void:
	var k: Dictionary = repo.burgs["kuojarpan"]
	assert_eq(String(k["type"]), "Naval")
	assert_eq(String(k["features"]), "walls|citadel|temple|plaza")

func test_route_and_river_references_resolve() -> void:
	for code: String in repo.routes:
		var r: Dictionary = repo.routes[code]
		for end in ["from_burg", "to_burg"]:
			var b := String(r[end])
			assert_true(b == "" or repo.burgs.has(b), "%s %s -> '%s'" % [code, end, b])
		assert_gte((r["polyline"] as PackedVector2Array).size(), 2, "%s is drawable" % code)
		assert_true((r["bbox"] as Rect2).has_area(), "%s has a bounding box" % code)
	for code: String in repo.rivers:
		var rv: Dictionary = repo.rivers[code]
		assert_gte((rv["polyline"] as PackedVector2Array).size(), 2, "%s is drawable" % code)
		for k: String in String(rv["kingdom_codes"]).split("|", false):
			assert_true(repo.kingdoms.has(k), "%s flows through %s" % [code, k])

## Azgaar leaves most trails/sea routes nameless; the importer titles them.
func test_every_route_has_a_label() -> void:
	for code: String in repo.routes:
		assert_ne(String(repo.routes[code]["label"]), "", "%s has a title for its card" % code)

func test_a_known_road_snaps_to_its_towns() -> void:
	var r: Dictionary = repo.routes["ororeanian_road"]
	assert_eq(String(r["group"]), "roads")
	assert_eq(String(r["from_burg"]), "cocalomo")
	assert_eq(String(r["to_burg"]), "ororeanes")

func test_markers_lie_inside_the_map_and_carry_legends() -> void:
	var w := float(repo.map_info["width"])
	var h := float(repo.map_info["height"])
	for code: String in repo.markers:
		var m: Dictionary = repo.markers[code]
		var x := float(m["x"])
		var y := float(m["y"])
		assert_true(x >= 0.0 and x <= w and y >= 0.0 and y <= h, "%s at (%s, %s)" % [code, x, y])
		assert_false(String(m["legend"]).contains("\n"), "%s legend is one line" % code)
	assert_true(repo.markers.has("the_orange_jackal"), "a named inn imported")

func test_province_bitmap_decodes_each_province_at_its_center() -> void:
	var img: Image = (load(repo.province_texture_path) as Texture2D).get_image()
	var state_img: Image = (load(repo.index_texture_path) as Texture2D).get_image()
	assert_eq(img.get_size(), state_img.get_size(), "province bitmap matches the state bitmap")
	for code: String in repo.provinces:
		var p: Dictionary = repo.provinces[code]
		var px := Vector2i(int(float(p["center_x"])), int(float(p["center_y"])))
		assert_eq(MapIndex.id_at(img, px), int(p["province_id"]),
			"%s center pixel decodes to its province_id" % code)

func test_biome_bitmap_marks_land_with_a_real_biome() -> void:
	var img: Image = (load(repo.biome_texture_path) as Texture2D).get_image()
	var state_img: Image = (load(repo.index_texture_path) as Texture2D).get_image()
	assert_eq(img.get_size(), state_img.get_size(), "biome bitmap matches the state bitmap")
	for code: String in repo.kingdoms:
		var row: Dictionary = repo.kingdoms[code]
		var px := Vector2i(int(float(row["center_x"])), int(float(row["center_y"])))
		var biome := MapIndex.biome_at(img, px)
		assert_true(biome > 0 and repo.biomes.has(biome),
			"%s center is land with a named biome, got %d" % [code, biome])
