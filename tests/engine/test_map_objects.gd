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
		"map_pick_radius_px": 6.0, "map_line_pick_px": 4.0}
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

func test_marker_beats_a_burg_at_the_same_spot() -> void:
	var hit := _at(_tiny(), Vector2(1.5, 2.5), 0)
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
	for want in ["Group", "Type", "Culture", "Population", "Climate", "Elevation"]:
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
