extends GutTest
## MapObjects: what lies under a map point (pin > line > land > water), the
## zoom-based LOD rule for town pins, and the text each info card shows.
## Engine-pure: a hand-built repository and 4x4 bitmaps for the unit cases,
## the real Beria pack for the integration cases.

var real: DataRepository

func before_all() -> void:
	real = DataRepository.load_all("res://data")
	assert_not_null(real, DataRepository.last_error)

## A 4x4 world: state 6 / province 72 / biome 6 on the left half, water right.
## Capital "cap" at (0.5, 0.5), village "vil" at (1.5, 2.5) with 300 people,
## road "rd" from cap to vil, trail "tr" starting ON the road at (1, 1.5),
## marker "inn" exactly on the village.
func _tiny() -> DataRepository:
	var repo := DataRepository.new()
	repo.balance = {"map_lod_town_scale": 0.5, "map_lod_village_scale": 1.0,
		"map_lod_marker_scale": 0.5, "map_lod_town_pop": 5000.0,
		"map_pick_radius_px": 6.0, "map_line_pick_px": 4.0,
		"map_show_markers": 0.0}
	repo.map_info = {"distance_unit": "km", "distance_scale": "2", "width": "4", "height": "4"}
	repo.kingdoms = {"k": {"kingdom_code": "k", "state_id": "6", "label": "Kingdom", "capital_burg": "cap",
		"neighbor_codes": "", "population": "9000", "center_x": "0", "center_y": "0"}}
	repo.provinces = {"p": {"province_code": "p", "label": "Province", "kingdom_code": "k",
		"capital_burg": "cap", "province_id": "72"}}
	repo.burgs = {
		"cap": {"burg_code": "cap", "label": "Capital", "province_code": "p", "kingdom_code": "k",
			"population": "8000", "is_capital": "1", "is_port": "1", "x": "0.5", "y": "0.5",
			"type": "Naval", "features": "walls|citadel"},
		"vil": {"burg_code": "vil", "label": "Village", "province_code": "p", "kingdom_code": "k",
			"population": "300", "is_capital": "0", "is_port": "0", "x": "1.5", "y": "2.5",
			"type": "Generic", "features": ""},
	}
	var road := {"route_code": "rd", "label": "Old Road", "group": "roads", "from_burg": "cap",
		"to_burg": "vil", "length": "2.2", "points": "0.5 0.5|1.5 2.5"}
	road["polyline"] = MapGeometry.parse_points(String(road["points"]))
	road["bbox"] = MapGeometry.bounds(road["polyline"])
	var trail := {"route_code": "tr", "label": "Trail to Village", "group": "trails", "from_burg": "",
		"to_burg": "", "length": "2", "points": "1 1.5|3 1.5"}
	trail["polyline"] = MapGeometry.parse_points(String(trail["points"]))
	trail["bbox"] = MapGeometry.bounds(trail["polyline"])
	repo.routes = {"rd": road, "tr": trail}
	var river := {"river_code": "rv", "label": "Silver", "type": "River", "length": "3",
		"kingdom_codes": "k", "points": "0 3.5|3 3.5"}
	river["polyline"] = MapGeometry.parse_points(String(river["points"]))
	river["bbox"] = MapGeometry.bounds(river["polyline"])
	repo.rivers = {"rv": river}
	repo.markers = {"inn": {"marker_code": "inn", "label": "The Inn", "type": "inns",
		"x": "1.5", "y": "2.5", "legend": "A warm hearth."}}
	repo.biomes = {6: {"biome_id": "6", "label": "Forest", "color": "", "habitability": "50"}}
	return repo

func _bitmap(id: int) -> Image:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color8(255, 255, 255))
	for y in 4:
		for x in 2:
			img.set_pixel(x, y, Color8(id & 0xFF, (id >> 8) & 0xFF, 0))
	return img

func _at(repo: DataRepository, p: Vector2, min_pop: int) -> Dictionary:
	return MapObjects.object_at(repo, _bitmap(6), _bitmap(72), _bitmap(6), p, 0.3, 0.2, min_pop)

func test_lod_rule_from_balance() -> void:
	var repo := _tiny()
	assert_eq(MapObjects.min_burg_pop_for_scale(repo, 0.3), MapObjects.CAPITALS_ONLY)
	assert_eq(MapObjects.min_burg_pop_for_scale(repo, 0.5), 5000)
	assert_eq(MapObjects.min_burg_pop_for_scale(repo, 1.0), 0)

func test_burg_visible_respects_capitals_and_population() -> void:
	var repo := _tiny()
	assert_true(MapObjects.burg_visible(repo.burgs["cap"], MapObjects.CAPITALS_ONLY))
	assert_false(MapObjects.burg_visible(repo.burgs["vil"], MapObjects.CAPITALS_ONLY))
	assert_false(MapObjects.burg_visible(repo.burgs["vil"], 5000))
	assert_true(MapObjects.burg_visible(repo.burgs["vil"], 0))

## Owner ruling 2026-09-12: the pack's points of interest are off the sheet,
## and MapObjects.markers_visible is the one place that decides — so a click
## can never pick something that is not drawn. With them on, a marker still
## outranks a burg sharing its point.
func test_a_hidden_marker_cannot_be_picked() -> void:
	var repo := _tiny()
	assert_false(MapObjects.markers_visible(repo), "points of interest are off")
	var hit := _at(repo, Vector2(1.5, 2.5), 0)
	assert_eq(hit["kind"], "burg", "the village under it is picked instead")
	assert_eq(hit["code"], "vil")

func test_marker_beats_a_burg_at_the_same_spot_when_shown() -> void:
	var repo := _tiny()
	repo.balance["map_show_markers"] = 1.0
	var hit := _at(repo, Vector2(1.5, 2.5), 0)
	assert_eq(hit["kind"], "marker")
	assert_eq(hit["code"], "inn")

func test_capital_pin_is_picked_within_radius() -> void:
	var hit := _at(_tiny(), Vector2(0.7, 0.5), MapObjects.CAPITALS_ONLY)
	assert_eq(hit["kind"], "burg")
	assert_eq(hit["code"], "cap")

func test_hidden_village_falls_through_to_the_road_under_it() -> void:
	# The marker sits on the village too; pick a road point away from both.
	var hit := _at(_tiny(), Vector2(1.0, 1.5), MapObjects.CAPITALS_ONLY)
	assert_eq(hit["kind"], "route")
	assert_eq(hit["code"], "rd")

## The trail starts exactly on the road: equal distance, and the road wins.
func test_road_beats_trail_on_a_shared_point() -> void:
	var hit := _at(_tiny(), Vector2(1.0, 1.5), 0)
	assert_eq(hit["kind"], "route")
	assert_eq(hit["code"], "rd")
	var on_trail_only := _at(_tiny(), Vector2(2.5, 1.5), 0)
	assert_eq(on_trail_only["code"], "tr")

func test_river_is_picked_when_no_route_is_closer() -> void:
	var hit := _at(_tiny(), Vector2(1.0, 3.6), 0)
	assert_eq(hit["kind"], "river")
	assert_eq(hit["code"], "rv")

func test_bare_land_reports_its_ids_and_position() -> void:
	var hit := _at(_tiny(), Vector2(0.5, 2.0), 0)
	assert_eq(hit["kind"], "land")
	assert_eq(hit["state_id"], 6)
	assert_eq(hit["province_id"], 72)
	assert_eq(hit["biome_id"], 6)
	assert_almost_eq(float(hit["x"]), 0.5, 0.0001)

func test_water_is_water() -> void:
	assert_eq(_at(_tiny(), Vector2(3.5, 1.0), 0)["kind"], "water")

func test_nearest_burg_ignores_lod() -> void:
	assert_eq(MapObjects.nearest_burg(_tiny(), Vector2(1.4, 2.4)), "vil")

func test_describe_burg() -> void:
	var d := MapObjects.describe(_tiny(), {"kind": "burg", "code": "cap"})
	assert_eq(d["title"], "Capital")
	assert_eq(d["lines"][0], "Capital of Province, Kingdom")
	assert_eq(d["lines"][1], "Population: 8000")
	assert_eq(d["lines"][2], "Port, Walled, Citadel")
	assert_eq(d["lines"][3], "Roads: 1")
	assert_eq(d["ask"], "What do we know of Capital?")

func test_describe_route_and_river_use_real_distances() -> void:
	var road := MapObjects.describe(_tiny(), {"kind": "route", "code": "rd"})
	assert_eq(road["title"], "Old Road")
	assert_eq(road["lines"][0], "Road")
	assert_eq(road["lines"][1], "From Capital to Village")
	assert_eq(road["lines"][2], "Length: 4 km", "2.2 px * scale 2, rounded")
	assert_eq(road["ask"], "What do we know of the Old Road?")
	var river := MapObjects.describe(_tiny(), {"kind": "river", "code": "rv"})
	assert_eq(river["lines"], ["River", "Length: 6 km", "Flows through: Kingdom"])

func test_describe_marker_and_land() -> void:
	var inn := MapObjects.describe(_tiny(), {"kind": "marker", "code": "inn"})
	assert_eq(inn["title"], "The Inn")
	assert_eq(inn["lines"], ["Inns", "A warm hearth."])
	assert_eq(inn["ask"], "What is known of The Inn?")
	var land := MapObjects.describe(_tiny(), {"kind": "land", "state_id": 6, "province_id": 72,
		"biome_id": 6, "x": 1.0, "y": 2.0})
	assert_eq(land["title"], "Province")
	assert_eq(land["lines"][0], "Kingdom")
	assert_eq(land["lines"][1], "Terrain: Forest")
	assert_eq(land["lines"][2], "Nearest town: Village (1 km)")
	assert_eq(land["lines"][3], "Capital: Capital", "the kingdom summary follows the local facts")
	assert_eq(land["ask"], "What do we know of Province?")

func test_describe_water_is_empty() -> void:
	assert_eq(MapObjects.describe(_tiny(), {"kind": "water"}), {})

func test_label_of_each_kind() -> void:
	var repo := _tiny()
	assert_eq(MapObjects.label_of(repo, {"kind": "burg", "code": "vil"}), "Village")
	assert_eq(MapObjects.label_of(repo, {"kind": "route", "code": "rd"}), "Old Road")
	assert_eq(MapObjects.label_of(repo, {"kind": "marker", "code": "inn"}), "The Inn")
	assert_eq(MapObjects.label_of(repo, {"kind": "water"}), "")

## Real pack: the player's capital and a known road resolve where the export
## says they are.
func test_real_capital_and_road_resolve() -> void:
	var state_img: Image = (load(real.index_texture_path) as Texture2D).get_image()
	var prov_img: Image = (load(real.province_texture_path) as Texture2D).get_image()
	var biome_img: Image = (load(real.biome_texture_path) as Texture2D).get_image()
	# No literal town or road: the pack is generated, so this takes the realm
	# the bindings point at, its own capital, and the map's longest road.
	var realm: Dictionary = real.kingdoms[real.resolve_realm("player_realm")]
	var capital_code := String(realm["capital_burg"])
	var k: Dictionary = real.burgs[capital_code]
	var at_capital := MapObjects.object_at(real, state_img, prov_img, biome_img,
		Vector2(float(k["x"]), float(k["y"])), 6.0, 4.0, MapObjects.CAPITALS_ONLY)
	assert_eq(at_capital["kind"], "burg")
	assert_eq(at_capital["code"], capital_code)
	var road_code := _longest_road(real)
	var on_road := MapObjects.object_at(real, state_img, prov_img, biome_img,
		_open_point_on(real, road_code), 0.5, 4.0, MapObjects.CAPITALS_ONLY)
	assert_eq(on_road["kind"], "route", "a point on a road hits that road")
	assert_eq(on_road["code"], road_code)
	var d := MapObjects.describe(real, at_capital)
	assert_eq(d["title"], String(k["label"]))
	assert_eq(d["lines"][0], "Capital of %s, %s" % [
		String(real.provinces[String(k["province_code"])]["label"]),
		String(realm["label"])])

## The vertex of `code` that is farthest from every town and marker, so the
## point is unambiguously on the road: burgs and markers win the pick over
## routes, and on a generated map a road often runs right past one.
func _open_point_on(repo: DataRepository, code: String) -> Vector2:
	var line: PackedVector2Array = repo.routes[code]["polyline"]
	var rivals: Array[Vector2] = []
	for b: String in repo.burgs:
		rivals.append(Vector2(float(repo.burgs[b]["x"]), float(repo.burgs[b]["y"])))
	for m: String in repo.markers:
		rivals.append(Vector2(float(repo.markers[m]["x"]), float(repo.markers[m]["y"])))
	var best := line[0]
	var best_d := -1.0
	for p in line:
		var d := INF
		for r in rivals:
			d = minf(d, p.distance_squared_to(r))
		if d > best_d:
			best_d = d
			best = p
	return best

## The road with the most points, ties going to the earlier code — a stable
## pick on any export, and long enough to have a vertex out in open country.
func _longest_road(repo: DataRepository) -> String:
	var best := ""
	var best_n := 0
	var codes := repo.routes.keys()
	codes.sort()
	for code: String in codes:
		var r: Dictionary = repo.routes[code]
		if String(r["group"]) != "roads":
			continue
		var n := (r["polyline"] as PackedVector2Array).size()
		if n > best_n:
			best_n = n
			best = code
	return best

# --- the province panel (user request 2026-09-09) ----------------------------

func _player_realm() -> String:
	return Game.data.resolve_realm("player_realm")

func _own_province() -> String:
	return MapOwnership.provinces_of(Game.data, Game.state, _player_realm())[0]

func _foreign_province() -> String:
	for code: String in Game.data.provinces:
		if String(Game.data.provinces[code]["kingdom_code"]) != _player_realm():
			return code
	return ""

func test_house_of_uses_the_binding_then_the_capital_town() -> void:
	Game.start_campaign(42)
	assert_false(Game.data.house_bindings.is_empty(), "the pack binds houses to land")
	var bound: String = Game.data.house_bindings.keys()[0]
	assert_eq(MapObjects.house_of(Game.data, bound),
		"House " + String(Game.data.house_bindings[bound]))
	var unbound := _foreign_province()
	var cap: Dictionary = Game.data.burgs[String(Game.data.provinces[unbound]["capital_burg"])]
	assert_eq(MapObjects.house_of(Game.data, unbound), "House " + String(cap["label"]),
		"an unbound province is held by the house of its seat")

func test_own_province_is_described_in_full_and_a_foreign_one_barely() -> void:
	Game.start_campaign(42)
	var mine := MapObjects.describe_province(Game.data, Game.state, _own_province())
	assert_eq(String(mine["known"]), "full")
	var joined := "\n".join(mine["lines"])
	for word in ["Province of", "Held by House", "Seat:", "Towns:", "Population:", "Area:"]:
		assert_string_contains(joined, word)
	var theirs := MapObjects.describe_province(Game.data, Game.state, _foreign_province())
	assert_eq(String(theirs["known"]), "basic")
	var basic := "\n".join(theirs["lines"])
	assert_string_contains(basic, "Province of")
	assert_string_contains(basic, "Held by House")
	assert_string_contains(basic, "Seat:")
	assert_false(basic.contains("Population"), "no details abroad")
	assert_false(basic.contains("Towns"), "no details abroad")
	assert_eq(theirs["lines"].size(), 3, "name, kingdom, house, seat and nothing more")

func test_the_province_account_follows_conquest() -> void:
	Game.start_campaign(42)
	var lost := _own_province()
	MapOwnership.set_owner(Game.data, Game.state, lost, Game.data.resolve_realm("raider_realm"), "a raid")
	var after := MapObjects.describe_province(Game.data, Game.state, lost)
	assert_eq(String(after["known"]), "basic", "lost land is foreign land")
	var won := _foreign_province()
	MapOwnership.set_owner(Game.data, Game.state, won, _player_realm(), "conquest")
	var gained := MapObjects.describe_province(Game.data, Game.state, won)
	assert_eq(String(gained["known"]), "full")
	assert_string_contains("\n".join(gained["lines"]), "Changed hands:")

# --- info cards after Azgaar's burg editor (user request 2026-09-09) --------

func test_burg_card_carries_the_towns_facts_and_goods() -> void:
	Game.start_campaign(42)
	var realm: Dictionary = Game.data.kingdoms[_player_realm()]
	var code := String(realm["capital_burg"])
	var card := MapObjects.burg_card(Game.data, Game.state, code)
	assert_eq(String(card["kind"]), "burg")
	assert_eq(String(card["title"]), String(Game.data.burgs[code]["label"]))
	assert_string_contains(String(card["subtitle"]), String(realm["label"]))
	var labels: Array = []
	for f in card["fields"]:
		labels.append(String(f[0]))
	for want in ["Group", "Type", "Culture", "Population"]:
		assert_has(labels, want)
	assert_true(card["features"].size() > 0, "a capital has walls or a citadel")
	for f in card["features"]:
		assert_true(Game.data.resource_icons.has(String(f)), "%s has a glyph" % f)
	assert_true(card["production"].size() > 0, "the capital makes something")
	assert_gt(float(card["treasury"]), 0.0)
	assert_eq(card["center"], Vector2(float(Game.data.burgs[code]["x"]), float(Game.data.burgs[code]["y"])))

func test_province_card_is_full_at_home_and_basic_abroad() -> void:
	Game.start_campaign(42)
	var mine := MapObjects.province_card(Game.data, Game.state, _own_province())
	assert_eq(String(mine["known"]), "full")
	var labels: Array = []
	for f in mine["fields"]:
		labels.append(String(f[0]))
	for want in ["Held by", "Seat", "Population", "Area", "Terrain", "Towns"]:
		assert_has(labels, want)
	assert_true(mine["production"].size() > 0, "the province's towns make goods")
	var theirs := MapObjects.province_card(Game.data, Game.state, _foreign_province())
	assert_eq(String(theirs["known"]), "basic")
	assert_eq(theirs["fields"].size(), 2, "house and seat, nothing more")
	assert_true(theirs["production"].is_empty())

func test_goods_are_shown_under_a_tag_with_a_glyph() -> void:
	Game.start_campaign(42)
	var goods := Game.data.world_table("economy", "goods")
	assert_eq(MapObjects.good_tag(Game.data, "grain"), "tag_food")
	var tagged := 0
	for g: String in goods:
		if MapObjects.good_tag(Game.data, g) != "":
			tagged += 1
	assert_gt(tagged, goods.size() / 2, "most goods fall under a tagged glyph")

## Settlement art (user request 2026-09-09): every burg group in the pack has
## a drawing, walled towns draw behind walls, and every drawing exists.
func test_settlement_art_covers_the_packs_groups() -> void:
	Game.start_campaign(42)
	var seen: Dictionary = {}
	for code: String in Game.data.burgs:
		var b: Dictionary = Game.data.burgs[code]
		var art := MapObjects.settlement_art(Game.data, b)
		assert_false(art.is_empty(), "%s (%s) has a drawing" % [code, b.get("group", "")])
		seen[String(art["tier"])] = true
	assert_true(seen.has("capital") and seen.has("city") and seen.has("town"))
	for row: Dictionary in Game.data.settlement_art:
		assert_true(ResourceLoader.exists(String(row["texture"])) or FileAccess.file_exists(String(row["texture"])),
			"%s exists" % String(row["texture"]))
	var walled := {"group": "town", "features": "walls|citadel"}
	assert_eq(String(MapObjects.settlement_art(Game.data, walled)["tier"]), "walled_town")
	var open := {"group": "town", "features": "plaza"}
	assert_eq(String(MapObjects.settlement_art(Game.data, open)["tier"]), "town")
	var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
	assert_eq(String(MapObjects.settlement_art(Game.data, Game.data.burgs[String(realm["capital_burg"])])["tier"]),
		"capital")

func test_burg_card_has_no_climate_or_elevation() -> void:
	Game.start_campaign(42)
	var realm: Dictionary = Game.data.kingdoms[_player_realm()]
	var card := MapObjects.burg_card(Game.data, Game.state, String(realm["capital_burg"]))
	for f in card["fields"]:
		assert_false(String(f[0]) in ["Climate", "Elevation"], "%s is not on the card" % String(f[0]))

## One tree is not a forest and one peak is not a range (owner request
## 2026-09-12): a chosen cell yields `clump` small marks scattered inside it,
## not one big mark on its centre — and the scatter comes from the cell id, so
## the same wood stands in the same place every run.
func _decor_repo(clump: int, spread: float) -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"map_decor_density": 1.0, "map_decor_scale": 1.0}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 10), 3: Vector2(0, 10)}
	r.cells = {1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 30.0,
		"biome_id": 6, "water": "", "neighbor_ids": PackedInt32Array()}}
	r.terrain_art = [{"key": "wood", "biome_id": "6", "min_height": "", "max_height": "",
		"texture": "res://x.png", "density": "1.0", "height_px": "4", "clump": str(clump),
		"spread": str(spread)}]
	return r

## Ships and a whale on the open sea (owner request 2026-09-13): candidates
## spread over a sea cell by its area, kept by the hash against
## map_sea_decor_density, and only beyond the row's min_shore_px from the
## land coast. A 200x200 sea square east of a shore running down x = 10.
func _sea_repo(take: float, min_shore: float, gap: float = 0.0) -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"map_sea_decor_density": take, "map_sea_decor_scale": 1.0,
		"map_sea_decor_spacing_px": 40.0, "map_sea_decor_min_gap_px": gap}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 200), 3: Vector2(0, 200),
		4: Vector2(210, 0), 5: Vector2(210, 200)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 30.0, "biome_id": 6,
			"water": "", "neighbor_ids": PackedInt32Array([2])},
		2: {"vertex_ids": PackedInt32Array([1, 4, 5, 2]), "height": 5.0, "biome_id": 0,
			"water": "ocean", "neighbor_ids": PackedInt32Array([1])}}
	r.coasts = [{"kind": "land", "polyline": PackedVector2Array([Vector2(10, 0),
		Vector2(10, 100), Vector2(10, 200)])}]
	r.sea_art = [{"key": "whale", "texture": "res://w.png", "weight": "1",
		"height_px": "22", "min_shore_px": str(min_shore)}]
	return r

func test_sea_marks_keep_off_the_shore_and_inside_the_water() -> void:
	MapObjects.forget_decor()
	var marks := MapObjects.sea_decor(_sea_repo(1.0, 50.0))
	assert_gt(marks.size(), 5, "a 200x200 sea sampled every 40 px holds a good many")
	for m: Dictionary in marks:
		var p: Vector2 = m["pos"]
		assert_gte(p.x, 60.0, "at least 50 px off the shore at x = 10")
		assert_lte(p.x, 210.0, "inside the sea cell")
		assert_true(p.y >= 0.0 and p.y <= 200.0, "inside the sea cell")
		assert_eq(m["texture"], "res://w.png")
		assert_eq(m["height"], 22.0)
	MapObjects.forget_decor()
	assert_eq(MapObjects.sea_decor(_sea_repo(0.0, 50.0)).size(), 0, "density 0: an empty sea")
	MapObjects.forget_decor()
	assert_eq(MapObjects.sea_decor(_sea_repo(1.0, 500.0)).size(), 0,
		"a shore margin wider than the sea: nothing fits")

## Spread out and never overlapping (owner 2026-09-13): with a minimum gap
## no two marks come closer than it, and the sea still gets its share.
func test_sea_marks_keep_their_distance_from_each_other() -> void:
	MapObjects.forget_decor()
	var crowded := MapObjects.sea_decor(_sea_repo(1.0, 0.0, 0.0)).size()
	MapObjects.forget_decor()
	var marks := MapObjects.sea_decor(_sea_repo(1.0, 0.0, 60.0))
	assert_gt(marks.size(), 1, "more than one still fits a 200x200 sea at 60 px apart")
	assert_lt(marks.size(), crowded, "the gap thinned the crowd")
	for a in marks.size():
		for b in range(a + 1, marks.size()):
			assert_gte((marks[a]["pos"] as Vector2).distance_to(marks[b]["pos"]), 60.0,
				"no two marks within the gap")

func test_sea_marks_stand_in_the_same_place_every_time() -> void:
	MapObjects.forget_decor()
	var first := MapObjects.sea_decor(_sea_repo(0.5, 20.0)).duplicate(true)
	MapObjects.forget_decor()
	var second := MapObjects.sea_decor(_sea_repo(0.5, 20.0))
	assert_gt(first.size(), 0)
	assert_eq(first.size(), second.size())
	for i in first.size():
		assert_eq(first[i]["pos"], second[i]["pos"], "no RNG: the scatter is the cell id")

func test_a_wood_is_several_marks_scattered_inside_its_cell() -> void:
	MapObjects.forget_decor()
	var repo := _decor_repo(5, 0.8)
	var marks := MapObjects.terrain_decor(repo)
	assert_eq(marks.size(), 5, "five marks, not one")
	# The cell is the square (0,0)-(10,10): centre (5,5), mean vertex distance
	# 7.071, so the marks fall within 0.8 of that.
	var reach := 7.0711 * 0.8
	var distinct: Dictionary = {}
	for m: Dictionary in marks:
		var p: Vector2 = m["pos"]
		assert_lte(p.distance_to(Vector2(5, 5)), reach + 0.001, "inside the cell's reach")
		distinct[p] = true
	assert_eq(distinct.size(), 5, "and no two land on the same spot")

func test_the_same_cell_decorates_the_same_way_every_time() -> void:
	MapObjects.forget_decor()
	var first := MapObjects.terrain_decor(_decor_repo(4, 0.7)).duplicate(true)
	MapObjects.forget_decor()
	var second := MapObjects.terrain_decor(_decor_repo(4, 0.7))
	assert_eq(first.size(), second.size())
	for i in first.size():
		assert_eq(first[i]["pos"], second[i]["pos"], "no RNG: the scatter is the cell id")

func test_marks_vary_in_size_around_the_rows_height() -> void:
	MapObjects.forget_decor()
	var marks := MapObjects.terrain_decor(_decor_repo(6, 0.8))
	var lo := INF
	var hi := 0.0
	for m: Dictionary in marks:
		lo = minf(lo, float(m["height"]))
		hi = maxf(hi, float(m["height"]))
	assert_gte(lo, 4.0 * 0.8 - 0.001, "no mark smaller than 0.8 of the row")
	assert_lte(hi, 4.0 * 1.2 + 0.001, "none larger than 1.2 of it")
	assert_gt(hi - lo, 0.0, "and they are not all the same size")

## --- Manors (MANOR_SYSTEM.md §3, §6) ----------------------------------------

func _campaign() -> GameState:
	return GameState.new_campaign(real, 42)

func _manor_where(state: GameState, crowns: bool, in_realm: bool = true) -> int:
	var realm := real.resolve_realm("player_realm")
	for province: String in real.provinces:
		if (MapOwnership.owner_of(real, state, province) == realm) != in_realm:
			continue
		for cell: int in MapManors.manors_of_province(real, province):
			if MapManors.is_crowns(real, state, cell) == crowns:
				return cell
	return -1

func test_a_land_pixel_answers_as_its_manor_only_when_the_cell_index_is_given() -> void:
	var state := _campaign()
	var cell := _manor_where(state, true)
	assert_gt(cell, -1)
	var centre := MapTerrain.cell_center(real, real.cells[cell])
	var state_img: Image = (load(real.index_texture_path) as Texture2D).get_image()
	var province_img: Image = (load(real.province_texture_path) as Texture2D).get_image()
	var biome_img: Image = (load(real.biome_texture_path) as Texture2D).get_image()
	var cell_img: Image = (load(real.cell_texture_path) as Texture2D).get_image()
	var plain := MapObjects.object_at(real, state_img, province_img, biome_img, centre, 0.0, 0.0,
		1 << 30, state)
	assert_eq(String(plain["kind"]), "land", "the political map: land")
	var manor := MapObjects.object_at(real, state_img, province_img, biome_img, centre, 0.0, 0.0,
		1 << 30, state, cell_img)
	assert_eq(String(manor["kind"]), "manor")
	assert_eq(int(manor["cell"]), cell)
	assert_eq(MapObjects.label_of(real, manor), MapManors.label_of(real, cell))
	var entry := MapObjects.describe(real, manor, state)
	assert_eq(String(entry["title"]), MapManors.label_of(real, cell))

func test_the_manor_card_offers_the_orders_the_crown_can_give() -> void:
	var state := _campaign()
	state.metrics["treasury"] = 100000.0
	var own := _manor_where(state, true)
	var card := MapObjects.manor_card(real, state, own)
	assert_eq(String(card["kind"]), "manor")
	assert_eq(int(card["cell"]), own)
	assert_eq(String(card["known"]), "full")
	var fields: Dictionary = {}
	for f in card["fields"]:
		fields[String(f[0])] = String(f[1])
	assert_eq(fields["Held by"], "The crown")
	for key in ["Province", "Land", "Area", "People", "Rent", "Chief good", "Defence", "Buildings", "Slots", "Value", "Sells for"]:
		assert_true(fields.has(key), key + " is on the card")
	assert_string_contains(fields["Chief good"], " a year", "the focus and its yield")
	var codes: Array = []
	for a: Dictionary in card["actions"]:
		codes.append(String(a["action_code"]))
		# The demesne has no house to sell back to; every other order stands.
		if String(a["action_code"]) != "MANOR_SELL":
			assert_eq(String(a["error"]), "", "%s can be given: %s" % [a["label"], a["error"]])
	assert_has(codes, "MANOR_SELL")
	assert_has(codes, "MANOR_BUILD")
	assert_does_not_have(codes, "MANOR_BUY")
	assert_eq(codes.count("MANOR_BUILD"), real.manor_buildings.size(), "one BUILD per building not raised")
	assert_eq(int(card["slots"]), MapManors.slots_of(real, own))
	assert_true((card["slot_actions"] as Array).is_empty(), "nothing to pull down yet")
	for a: Dictionary in card["actions"]:
		if String(a["action_code"]) == "MANOR_BUILD":
			assert_true(String(a["label"]).ends_with("d"), "a building says how long it takes: " + String(a["label"]))
	# A work begun (2026-09-13): the card carries it with its days, and a
	# cross to stop it.
	assert_true(MapManors.start_work(real, state, own, "mill", "test"))
	var begun := MapObjects.manor_card(real, state, own)
	assert_eq((begun["works"] as Array).size(), 1)
	assert_eq(String(begun["works"][0]["building"]), "mill")
	assert_eq(int(begun["works"][0]["days_left"]), int(float(real.manor_buildings["mill"]["build_days"])))
	assert_eq((begun["slot_actions"] as Array).size(), 1)
	assert_eq(String(begun["slot_actions"][0]["action_code"]), "MANOR_DEMOLISH")
	assert_eq(String(begun["slot_actions"][0]["error"]), "")
	var begun_fields: Dictionary = {}
	for f in begun["fields"]:
		begun_fields[String(f[0])] = String(f[1])
	assert_string_contains(begun_fields["Buildings"], "days to go")
	assert_string_contains(begun_fields["Slots"], "1 of")
	assert_eq(codes.count("MANOR_FOCUS"), MapManors.focuses_for(real, own).size() - 1,
		"one WORK per chief good the land allows, less the one it works")
	# Another house's manor in the realm: buy, no seize while the flag is off.
	var theirs := _manor_where(state, false)
	var other := MapObjects.manor_card(real, state, theirs)
	var other_codes: Array = []
	for a: Dictionary in other["actions"]:
		other_codes.append(String(a["action_code"]))
	assert_eq(other_codes, ["MANOR_BUY"])
	assert_true(String(other["actions"][0]["label"]).begins_with("BUY — "))
	var of: Dictionary = {}
	for f in other["fields"]:
		of[String(f[0])] = String(f[1])
	assert_true(of["Held by"].begins_with("House "))
	assert_true(of.has("Asking price"))
	# Poor: the button stays but carries its reason.
	state.metrics["treasury"] = 0.0
	var poor := MapObjects.manor_card(real, state, theirs)
	assert_string_contains(String(poor["actions"][0]["error"]), "afford")
	# Abroad: basic, no orders.
	var abroad := _manor_where(state, false, false)
	var far := MapObjects.manor_card(real, state, abroad)
	assert_eq(String(far["known"]), "basic")
	assert_true((far["actions"] as Array).is_empty())

func test_the_province_card_counts_its_manors_by_house() -> void:
	var state := _campaign()
	var realm := real.resolve_realm("player_realm")
	var province: String = MapOwnership.provinces_of(real, state, realm)[0]
	var card := MapObjects.province_card(real, state, province)
	var fields: Dictionary = {}
	for f in card["fields"]:
		fields[String(f[0])] = String(f[1])
	assert_true(fields.has("Manors"))
	assert_true(String(fields["Manors"]).begins_with(str(MapManors.manors_of_province(real, province).size())))

## The manors' marks (owner 2026-09-13): every manor without a town carries
## farmsteads by its people and its chief good's marks; a manor with a town
## carries nothing; no two marks of one manor overlap; the same every call.
func test_manors_without_towns_carry_farmsteads_and_their_chief_good() -> void:
	var state := _campaign()
	var marks := MapObjects.manor_decor(real, state)
	assert_gt(marks.size(), 2000, "thousands of manors, marked")
	var rows: Dictionary = {}
	for row: Dictionary in real.manor_decor:
		rows[String(row["texture"])] = row
	var hamlet_row: Dictionary = {}
	for row: Dictionary in real.manor_decor:
		if String(row["kind"]) == "hamlet":
			hamlet_row = row
	assert_false(hamlet_row.is_empty())
	var per_cell: Dictionary = {}
	for m: Dictionary in marks:
		var cell := int(m["cell"])
		assert_true(MapManors.is_manor(real, cell))
		assert_eq(MapManors.burg_of(real, cell), "", "a town's manor carries no mark")
		if not per_cell.has(cell):
			per_cell[cell] = {"hamlet": 0, "focus": 0, "marks": []}
		if String(m["texture"]) == String(hamlet_row["texture"]):
			per_cell[cell]["hamlet"] += 1
		else:
			per_cell[cell]["focus"] += 1
		(per_cell[cell]["marks"] as Array).append(m)
		assert_gt(float(m["height"]), 0.0)
		assert_true(Geometry2D.is_point_in_polygon(m["pos"], MapEconomy.cell_polygon(real, real.cells[cell])),
			"a mark stands inside its manor")
	# Farmsteads follow the people: a big manor has the cap, a small one one;
	# the fields never outnumber what the people call for.
	var max_count := int(float(hamlet_row["max_count"]))
	var per := float(hamlet_row["per_people"])
	var people := MapManors.population_table(real, state, per_cell.keys())
	var seen_max := false
	var seen_one := false
	var flipped := 0
	var turned := 0
	for cell: int in per_cell:
		var pop := float((people[cell] as Dictionary)["total"])
		var want := clampi(roundi(pop / per), 1, max_count)
		assert_eq(int(per_cell[cell]["hamlet"]), want, "manor %d: %d people" % [cell, int(pop)])
		seen_max = seen_max or want == max_count
		seen_one = seen_one or want == 1
		# No two marks of one manor overlap (circles of half their larger side).
		var ms: Array = per_cell[cell]["marks"]
		for i in ms.size():
			var a: Dictionary = ms[i]
			var ra := 0.5 * float(a["height"]) * maxf(float(rows[String(a["texture"])]["aspect"]), 1.0)
			if bool(a["flip"]):
				flipped += 1
			if float(a["angle"]) != 0.0:
				turned += 1
			for j in range(i + 1, ms.size()):
				var b: Dictionary = ms[j]
				var rb := 0.5 * float(b["height"]) * maxf(float(rows[String(b["texture"])]["aspect"]), 1.0)
				# Fields never touch anything; a farmstead squeezed into a full
				# cell may touch another farmstead, never a field.
				var both_houses := String(a["texture"]) == String(hamlet_row["texture"]) \
					and String(b["texture"]) == String(hamlet_row["texture"])
				if not both_houses:
					assert_gte((a["pos"] as Vector2).distance_to(b["pos"]) + 0.001, ra + rb,
						"manor %d: marks %d and %d apart" % [cell, i, j])
	assert_true(seen_max and seen_one, "both a full cluster and a lone farmstead exist")
	assert_gt(flipped, 0, "some marks mirror")
	assert_gt(turned, 0, "some fields turn")
	var grain_cell := -1
	for cell: int in per_cell:
		if MapManors.focus_of(real, state, cell) == "grain" and int(per_cell[cell]["focus"]) > 0:
			grain_cell = cell
			break
	assert_gt(grain_cell, -1, "grain manors carry fields")
	var grain_row: Dictionary = {}
	for row: Dictionary in real.manor_decor:
		if String(row.get("focus_code", "")) == "grain":
			grain_row = row
	var grain_pop := float((people[grain_cell] as Dictionary)["total"])
	assert_lte(int(per_cell[grain_cell]["focus"]),
		clampi(roundi(grain_pop / float(grain_row["per_people"])), 1, int(float(grain_row["max_count"]))))
	assert_eq(MapObjects.manor_decor(real, state), marks, "the same every call")
	# A chosen focus moves the marks.
	assert_true(MapManors.set_focus(real, state, grain_cell, "stone", "test"))
	var stone_texture := ""
	for row: Dictionary in real.manor_decor:
		if String(row.get("focus_code", "")) == "stone":
			stone_texture = String(row["texture"])
	var fields := 0
	var spoil := 0
	for m: Dictionary in MapObjects.manor_decor(real, state):
		if int(m["cell"]) != grain_cell:
			continue
		if String(m["texture"]) == String(grain_row["texture"]):
			fields += 1
		elif String(m["texture"]) == stone_texture:
			spoil += 1
	assert_eq(fields, 0, "the fields are gone")
	assert_gt(spoil, 0, "a quarry's marks stand instead")

## Where the farmsteads stand (owner 2026-09-13): the centre of a plain; by
## the river or road when one runs through; back from the water on a coast;
## downhill on high ground — and always inside the cell.
func test_a_manors_site_follows_its_rivers_coast_and_heights() -> void:
	var plain := 0
	var river := 0
	var coast := 0
	var high := 0
	var on_bank := 0
	for id: int in real.manors:
		if MapManors.burg_of(real, id) != "":
			continue
		var cell: Dictionary = real.cells[id]
		var centre := MapTerrain.cell_center(real, cell)
		var radius := MapTerrain.cell_radius(real, cell)
		var site := MapObjects.manor_site(real, id)
		var anchor: Vector2 = site["anchor"]
		assert_true(Geometry2D.is_point_in_polygon(anchor, MapEconomy.cell_polygon(real, cell)) \
			or anchor == centre, "manor %d: the site is inside" % id)
		if bool(site["plain"]):
			assert_eq(anchor, centre, "manor %d: a plain's farmsteads sit in the middle" % id)
			plain += 1
			continue
		assert_lte(anchor.distance_to(centre), radius * 0.75 + 2.0 * real.bal("map_manor_site_bank_px") + 0.001)
		if bool(site["river"]) or bool(site["road"]):
			var bank := real.bal("map_manor_site_bank_px")
			var near := MapObjects.nearest_site_point(real, centre, radius * real.bal("map_manor_site_reach"))
			assert_false(near.is_empty())
			# A centre already within two banks of the water may be moved OUT
			# to clear ground instead; the pull shows on the rest.
			if not bool(site["coast"]) and not bool(site["high"]) \
					and centre.distance_to(near["point"]) > 2.0 * bank + 1.0:
				assert_lt(anchor.distance_to(near["point"]), centre.distance_to(near["point"]) + 0.001,
					"manor %d: drawn toward the water or the road" % id)
			# Not on the bank itself: nothing of the river or road within
			# bank px of the site — save the few cells a river cuts clean
			# through, which have no clear ground at all.
			if not MapObjects.nearest_site_point(real, anchor, bank - 0.5).is_empty():
				on_bank += 1
			river += 1
		if bool(site["coast"]):
			coast += 1
		if bool(site["high"]):
			high += 1
	assert_gt(plain, 0, "plains exist")
	assert_gt(river, 0, "riverside and roadside manors exist")
	assert_lt(float(on_bank), float(river) * 0.02, "%d of %d sites on the bank: all but a river-cut few are clear" % [on_bank, river])
	assert_gt(coast, 0, "coastal manors exist")
	assert_gt(high, 0, "hill manors exist")
