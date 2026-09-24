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

## The cast's realms (roles.csv kingdom column) must exist on the map.
## Every slot the pack binds, not a list of names: authored content names
## slots, so a re-export that renames the world only touches the bindings.
func test_fiction_kingdoms_are_on_the_map() -> void:
	assert_false(repo.realm_bindings.is_empty(), "the pack binds its realm slots")
	for slot: String in repo.realm_bindings:
		var code := repo.resolve_realm(slot)
		assert_true(repo.kingdoms.has(code),
			"slot %s binds to %s, a map kingdom" % [slot, code])
	for role in repo.roles:
		var kingdom := String(role.get("kingdom", ""))
		if kingdom != "":
			assert_true(repo.kingdoms.has(kingdom),
				"%s's kingdom %s is on the map" % [role["id"], kingdom])

func test_index_bitmap_decodes_each_kingdom_at_its_center() -> void:
	# Paths come from the loaded map pack, so this test follows whichever
	# map data/maps.csv points at rather than pinning one export's filenames.
	var idx_tex: Texture2D = load(Game.data.index_texture_path)
	assert_not_null(idx_tex)
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
	# The capital of whichever realm the pack binds the player to — Azgaar
	# always gives a capital a type and some walls or a citadel.
	var realm: Dictionary = repo.kingdoms[repo.resolve_realm("player_realm")]
	var k: Dictionary = repo.burgs[String(realm["capital_burg"])]
	assert_ne(String(k["type"]), "", "the capital has a settlement type")
	var features := String(k["features"]).split("|", false)
	assert_gt(features.size(), 0, "the capital carries features")
	for f: String in features:
		assert_true(f in ["walls", "citadel", "temple", "plaza", "shanty"],
			"%s is a known burg feature" % f)

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

## Structural, not a named road: the importer snaps route endpoints to the
## burg within SNAP_RADIUS, and whichever roads a given export happens to
## contain, the ones that snapped must name burgs this pack actually has.
func test_roads_snap_their_endpoints_to_real_towns() -> void:
	var snapped_ends := 0
	for code: String in repo.routes:
		var r: Dictionary = repo.routes[code]
		if String(r["group"]) != "roads":
			continue
		for end_col in ["from_burg", "to_burg"]:
			var burg := String(r[end_col])
			if burg == "":
				continue
			snapped_ends += 1
			assert_true(repo.burgs.has(burg),
				"road %s %s is the burg %s" % [code, end_col, burg])
	assert_gt(snapped_ends, 0, "some road snapped to a town")

func test_markers_lie_inside_the_map_and_carry_legends() -> void:
	var w := float(repo.map_info["width"])
	var h := float(repo.map_info["height"])
	for code: String in repo.markers:
		var m: Dictionary = repo.markers[code]
		var x := float(m["x"])
		var y := float(m["y"])
		assert_true(x >= 0.0 and x <= w and y >= 0.0 and y <= h, "%s at (%s, %s)" % [code, x, y])
		assert_false(String(m["legend"]).contains("\n"), "%s legend is one line" % code)
	# Named markers carry their legend through, whichever ones an export has.
	var named := 0
	for code: String in repo.markers:
		if String(repo.markers[code]["label"]) != "" \
				and String(repo.markers[code]["legend"]) != "":
			named += 1
	assert_gt(named, 0, "markers imported with both a name and a legend")

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

## The terrain tables (spec 2026-09-11): the game draws the map from these,
## so every reference in them must resolve.
func test_terrain_tables_load_and_cross_reference() -> void:
	assert_gt(repo.vertices.size(), 0, "vertices.csv loaded")
	assert_gt(repo.cells.size(), 0, "cells.csv loaded")
	assert_gt(repo.coasts.size(), 0, "coasts.csv loaded")
	var land := 0
	for id: int in repo.cells:
		var c: Dictionary = repo.cells[id]
		var vids: PackedInt32Array = c["vertex_ids"]
		assert_gte(vids.size(), 3, "cell %d has a polygon" % id)
		for v in vids:
			assert_true(repo.vertices.has(v), "cell %d vertex %d exists" % [id, v])
		for n in (c["neighbor_ids"] as PackedInt32Array):
			assert_true(repo.cells.has(n), "cell %d neighbour %d exists" % [id, n])
		var water := String(c["water"])
		if water == "":
			land += 1
			assert_true(repo.biomes.has(int(c["biome_id"])),
				"land cell %d has a named biome" % id)
			assert_gte(float(c["height"]), 20.0, "land is at or above sea level")
		else:
			assert_true(water == "ocean" or water == "lake", "cell %d water kind %s" % [id, water])
			assert_lt(float(c["height"]), 20.0, "water is below sea level")
	assert_gt(land, 0, "some cells are land")

## The committed pack (Game_dev, seed 954159497) has 12 islands and 4 lakes.
func test_coast_loops_match_the_packs_features() -> void:
	var land := 0
	var lakes := 0
	for row: Dictionary in repo.coasts:
		assert_gte((row["polyline"] as PackedVector2Array).size(), 3,
			"%s loop %s has 3+ points" % [row["kind"], row["loop"]])
		match String(row["kind"]):
			"land": land += 1
			"lake": lakes += 1
	assert_eq(lakes, 4, "one shore per lake")
	assert_gte(land, 12, "at least one land loop per island")

func test_terrain_palette_names_every_colour_the_map_draws() -> void:
	for key in ["sea_deep", "sea_far", "sea_nearer", "sea_near", "lake", "coast_line", "river", "road", "trail"]:
		assert_true(repo.terrain_palette.has(key), key)
	for id: int in repo.biomes:
		if id == 0:
			continue
		assert_true(repo.terrain_palette.has("biome_%d" % id),
			"biome %d (%s) has a land tint" % [id, repo.biomes[id]["label"]])

func test_terrain_balance_keys_are_present() -> void:
	for key in ["map_relief_strength", "map_relief_min", "map_relief_max", "map_light_x",
			"map_light_y", "map_altitude_gain", "map_sea_band_near_px", "map_sea_band_far_px",
			"map_coast_width",
			"map_river_min_px", "map_river_discharge_scale", "map_road_width",
			"map_trail_width", "map_trail_min_scale"]:
		assert_true(repo.balance.has(key), key)

## The terrain tables live in the same native space as the hit-test bitmaps
## (spec 2026-09-11 §8): a sampled cell's land/water class agrees with the
## biome bitmap under its centre. A shifted, scaled or mirrored terrain would
## fail this wholesale — it is the guard the deleted render calibration used
## to be.
func test_terrain_cells_share_the_bitmaps_coordinate_space() -> void:
	var biome_img: Image = (load(repo.biome_texture_path) as Texture2D).get_image()
	var checked := 0
	var ids: Array = repo.cells.keys()
	ids.sort()
	for i in range(0, ids.size(), 25):
		var cell: Dictionary = repo.cells[ids[i]]
		var center := MapTerrain.cell_center(repo, cell)
		var px := Vector2i(center.floor())
		if px.x < 0 or px.y < 0 or px.x >= biome_img.get_width() or px.y >= biome_img.get_height():
			continue
		var land_in_bitmap := MapIndex.biome_at(biome_img, px) > 0
		assert_eq(land_in_bitmap, String(cell["water"]) == "",
			"cell %d at %s: bitmap and cells.csv agree on land/water" % [ids[i], center])
		checked += 1
	assert_gt(checked, 100, "enough cells sampled")
