class_name DataRepository
extends RefCounted

static var last_error: String = ""

var balance: Dictionary = {}
var traits: Dictionary = {}
var seats: Dictionary = {}
var actions: Dictionary = {}
var founding: Array[Dictionary] = []
var roles: Array[Dictionary] = []
var relationships: Array[Dictionary] = []
var regions: Dictionary = {}
var locations: Dictionary = {}
var templates: Array[Dictionary] = []
var signatures: Array[Dictionary] = []
## data/world_schema.csv: every field the world ledger can address, its type,
## range, polarity, and the cap the model may move it by (WorldLedger).
var world_schema: Array[Dictionary] = []
## path -> the world_schema row governing it, memoised by
## WorldLedger.schema_for (2026-09-14: matching a path walked the whole
## table, splitting and realm-resolving every row, on EVERY ledger read —
## 75 of the 87 us a manor's month cost). Pure of game state: the pack's
## schema and realm bindings are loaded once and never rewritten. Code
## that does rewrite `world_schema` after load must clear this.
var schema_cache: Dictionary = {}
## data/metric_polarity.csv: metric -> which direction is good for the crown
## (1, -1, or 0 for neutral rates). OrderCosts reads it to tell a cost from a gain.
var metric_polarity: Dictionary = {}
## data/order_costs.csv: action_code -> {cost (EventEffects ops), always, notes}.
var order_costs: Dictionary = {}
## data/political_palette.csv: key -> "#rrggbb". Realm slots, other_N for the
## unbound kingdoms, and the named line colours (MapPalette). The render is
## terrain only; the game paints every political colour from this table.
var palette: Dictionary = {}
## data/chart_palette.csv: key -> "#rrggbb" for the dashboard's charts
## (cat_1.. in fixed order, sequential, track); validated CVD-safe.
var chart_palette: Dictionary = {}
## data/resource_icons.csv: key -> {label, icon, tooltip} for every resource
## and unit the UI shows as a glyph with a floating tooltip.
var resource_icons: Dictionary = {}
## data/settlement_art.csv rows: which settlement drawing a burg group (and
## whether it has walls) is shown with on the map (MapObjects.settlement_art).
var settlement_art: Array[Dictionary] = []
## data/army_art.csv: piece -> {piece, texture, painting} — the painted 3D
## counter a regiment is drawn with and the painting heading its card
## (MapObjects.army_piece / army_card, owner 2026-09-15).
var army_art: Dictionary = {}
## data/army_terrain_biomes.csv: biome id -> the terrain a regiment on it
## stands on (ArmySystem.terrain_of, owner 2026-09-17).
var army_terrain_biomes: Dictionary = {}
## data/army_terrain.csv: "terrain|arm" -> {defend, attack} per mille.
var army_terrain: Dictionary = {}
## data/army_matchups.csv: arm -> [{vs, attack, defense}] per mille, in file order.
var army_matchups: Dictionary = {}
## data/army_training_grades.csv rows {above, label}, first match wins.
var army_training_grades: Array[Dictionary] = []
## data/settlement_growth.csv rows: how a settlement's drawing grows with its
## manor — a tier promoted past min_people, or once a listed building stands
## (MapObjects.settlement_look, owner 2026-09-15).
var settlement_growth: Array[Dictionary] = []
## data/terrain_art.csv rows: which symbol a land cell is decorated with, by
## height band or biome, and how thickly (MapObjects.terrain_decor).
var terrain_art: Array[Dictionary] = []
## BIOMES LAYER (experiment 2026-09-14): data/biome_art.csv rows — the
## seamless ground tile each biome's land wears (MapBiomes.layers).
var biome_art: Array[Dictionary] = []
## data/sea_art.csv rows: the ships and whales printed on the open sea
## (MapObjects.sea_decor): texture, weight, height_px, min_shore_px from the coast.
var sea_art: Array[Dictionary] = []
## data/manor_buildings.csv: building_code -> {label, cost_gold, civil_cost,
## build_days, tax_bonus, output_bonus, defence_bonus, church_bonus,
## *_per_tick, produce_good, produce_units} — what a manor can raise, what
## the work takes in civil goods, how long it takes and what it does once it
## stands.
var manor_buildings: Dictionary = {}
## data/goods_art.csv: good_code -> the produce icon the ECONOMY view draws.
var goods_art: Dictionary = {}
## data/goods_art.csv `icon`: good_code -> the COLOUR icon the manor card's
## output rows show (owner 2026-09-14, the painting style); "" for none.
var goods_icons: Dictionary = {}
## data/goods_economy.csv: good_code -> {pool, price_gold, growth_permille}
## (spec 2026-09-14 §3); goods_economy_defaults.csv: tag -> the same, for a
## good the table does not name.
var goods_economy: Dictionary = {}
var goods_economy_defaults: Dictionary = {}
## data/manor_focus.csv: focus_code -> {label, good_code, biomes, coast,
## yield_per_1000, switch_cost_gold, transition_ticks} — the
## chief goods a manor may work at (owner 2026-09-13), in file order.
var manor_focus: Dictionary = {}
## data/manor_estates.csv rows, in file order then ascending by min_people:
## the estate drawing a manor wears in the MANORS view by its industry
## (focus_code) and its people (owner 2026-09-14).
var manor_estates: Array[Dictionary] = []
## data/goods_palette.csv: a good's first tag -> the colour its province wears
## in the ECONOMY view.
var goods_palette: Dictionary = {}
## data/marker_art.csv: marker type -> {texture, notes}, the point-of-interest
## icon drawn for that type on the map (MapObjects.marker_art).
var marker_art: Dictionary = {}
## data/terrain_palette.csv: key -> "#rrggbb" for the terrain the game draws
## itself (MapTerrain): land tints per biome, sea, lake, and line colours.
var terrain_palette: Dictionary = {}
var events: Array[Dictionary] = []
var events_by_id: Dictionary = {}
var event_choices: Array[Dictionary] = []
var world_rules: Dictionary = {}
var claim_types: Dictionary = {}
## event_id -> scene prose from RANDOM_EVENTS.md (see StorySource), with
## {player_realm}-style tokens filled from the loaded pack. Read this one.
var event_scenes: Dictionary = {}
## The same scenes exactly as authored, tokens unfilled — the source every
## re-fill starts from, so loading a second pack cannot compound substitutions.
var event_scenes_authored: Dictionary = {}
var facts: Array[Dictionary] = []
## Azgaar world import (tools/import_azgaar.gd), keyed by *_code. These
## belong to the LOADED MAP PACK, not to data/ — see load_map.
var kingdoms: Dictionary = {}
var provinces: Dictionary = {}
var burgs: Dictionary = {}
## kingdom_code -> Array of PackedVector2Array: each kingdom's closed border
## loops in native map coordinates (borders.csv, drawn by WorldMapView on
## hover).
var borders: Dictionary = {}
## province_code -> Array[PackedVector2Array]: each province's own outline.
## A kingdom's CURRENT border is the merge of the ones it holds — see
## MapOwnership. `borders` above stays the pack's starting kingdom outlines.
var province_borders: Dictionary = {}
## Azgaar province_id (int) -> the same row as `provinces`. Hit-testing reads
## a province id out of the index bitmap on every mouse move, so this saves
## a linear scan there.
var provinces_by_id: Dictionary = {}
## Map objects (spec 2026-09-08), keyed by *_code. Route and river rows carry
## two derived fields set at load: polyline (PackedVector2Array) and bbox
## (Rect2), so hit-testing never re-parses text.
var routes: Dictionary = {}
var rivers: Dictionary = {}
var markers: Dictionary = {}
## biome_id (int) -> row.
var biomes: Dictionary = {}
## width/height/distance_unit/distance_scale/population_rate as strings.
var map_info: Dictionary = {}
## The pack's terrain geometry (spec 2026-09-11, geography/vertices.csv and
## cells.csv): vertex_id -> Vector2, and cell_id -> row with vertex_ids and
## neighbor_ids as PackedInt32Array, height as float, biome_id as int, water
## as "" (land) / "ocean" / "lake". MapTerrain builds the mesh from these.
var vertices: Dictionary = {}
var cells: Dictionary = {}
## geography/coasts.csv rows (kind land|lake, feature_id, loop, points) with
## polyline and bbox set at load, like routes and rivers.
var coasts: Array[Dictionary] = []
## Available map packs from data/maps.csv, keyed by map_id.
var maps: Dictionary = {}
## The currently loaded pack (load_map).
var map_id: String = ""
var index_texture_path: String = ""
var province_texture_path: String = ""
var biome_texture_path: String = ""
## data/maps.csv sea_texture: world_sea_distance.png, every pixel its
## distance to land in native px (MapIndex.bake_sea_distance); SeaLayer.
var sea_texture_path: String = ""
## BIOMES LAYER (experiment 2026-09-14). data/maps.csv biome_weights: the
## base path of world_biome_weights_N.png, each biome's blurred share of
## the land (MapIndex.bake_biome_weights); BiomeLayer. "" when unbaked.
var biome_weights_path: String = ""

## BIOMES LAYER (owner 2026-09-17, choice B). data/maps.csv relief_texture:
## the pack's baked height field (MapIndex.bake_relief, tools/bake_relief.gd);
## biome_tiles.gdshader lights the ground by its slope. "" when unbaked.
var relief_path: String = ""
## data/maps.csv settlement_texture: world_settlement_distance.png, every
## pixel its distance in km to the nearest settlement's worked ground
## (tools/bake_settlements.gd). The ground shader fades to bare earth near
## a town so its art rises out of worked land instead of off green forest
## (owner 2026-09-17).
var settlement_path: String = ""
## data/maps.csv cell_texture: world_cell_index.png, R | G<<8 = the land
## cell under a pixel (white = water) — how a click finds its manor.
var cell_texture_path: String = ""
## realm slot -> this map's kingdom_code (maps/<id>/realm_bindings.csv).
var realm_bindings: Dictionary = {}
## province_code -> the authored house holding it (maps/<id>/house_bindings.csv,
## hand-maintained like realm_bindings). Unbound provinces are held by a house
## named after their capital town — see MapObjects.house_of.
var house_bindings: Dictionary = {}
## maps/<id>/political/manors.csv: cell_id (int) -> {manor_code, label,
## province_code, burg_code, culture_code} — one named manor per land cell,
## forged by the importer (ManorNames); maps/<id>/manor_name_overrides.csv
## (cell_id,label), hand-maintained, replaces labels last. MANOR_SYSTEM.md §1.
var manors: Dictionary = {}
## manor_code -> cell_id, and lower-cased label -> cell_id, for orders that
## name a manor ("buy Ashcombe").
var manor_by_code: Dictionary = {}
var manor_by_label: Dictionary = {}
## Every pack table by domain and area: world_tables[domain][area][code] -> row
## (spec 2026-09-09 §1). The named fields above (kingdoms, provinces, burgs,
## routes, rivers, markers, biomes) are the SAME Dictionary objects, so the
## old callers and the world ledger see one set of rows.
var world_tables: Dictionary = {}

## [domain, area, required columns, key columns, key separator]. A table absent
## from a pack simply loads as {} (the ledger reads null for its paths).
const WORLD_TABLE_SPECS := [
	["political", "diplomacy", ["kingdom_code", "other_code", "stance"], ["kingdom_code", "other_code"], ">"],
	["political", "campaigns", ["kingdom_code", "label"], ["kingdom_code", "label"], ":"],
	["economy", "kingdoms", ["kingdom_code", "treasury", "sales_tax", "poll_tax"], ["kingdom_code"], ""],
	["economy", "provinces", ["province_code"], ["province_code"], ""],
	["economy", "burgs", ["burg_code"], ["burg_code"], ""],
	["economy", "goods", ["good_code", "label"], ["good_code"], ""],
	["economy", "markets", ["market_id", "center_burg"], ["market_id"], ""],
	["economy", "market_goods", ["market_id", "good_code"], ["market_id", "good_code"], ":"],
	["economy", "production", ["burg_code", "good_code"], ["burg_code", "good_code"], ":"],
	["military", "kingdoms", ["kingdom_code"], ["kingdom_code"], ""],
	["military", "regiments", ["regiment_code", "kingdom_code"], ["regiment_code"], ""],
	["military", "unit_types", ["unit_code"], ["unit_code"], ""],
	["society", "cultures", ["culture_code", "label"], ["culture_code"], ""],
	["society", "religions", ["religion_code", "label"], ["religion_code"], ""],
	["society", "zones", ["zone_code", "label", "type"], ["zone_code"], ""],
]

func world_table(domain: String, area: String) -> Dictionary:
	return (world_tables.get(domain, {}) as Dictionary).get(area, {})

func world_row(domain: String, area: String, code: String) -> Dictionary:
	return world_table(domain, area).get(code, {})

## A good's pool, whole-gold price and monthly growth per mille: its own
## row, else its first tag's default row, else civil at 1 gold growing 0.
func goods_economy_of(good_code: String) -> Dictionary:
	var row: Dictionary = goods_economy.get(good_code, {})
	if row.is_empty():
		var tags := String(world_row("economy", "goods", good_code).get("tags", "")).split("|", false)
		if not tags.is_empty():
			row = goods_economy_defaults.get(String(tags[0]), {})
	if row.is_empty():
		return {"pool": "civil", "price_gold": 1, "growth_permille": 0}
	return {"pool": String(row.get("pool", "civil")),
		"price_gold": int(float(row.get("price_gold", 1))),
		"growth_permille": int(float(row.get("growth_permille", 0)))}

func _register_table(domain: String, area: String, table: Dictionary) -> void:
	if not world_tables.has(domain):
		world_tables[domain] = {}
	world_tables[domain][area] = table

## Parses a CSV with a header row into an Array of row Dictionaries.
## Returns [] and sets last_error if any row is shorter than required_cols
## or a file error occurs. Extra columns are kept; empty trailing lines skipped.
static func parse_csv(path: String, required_cols: Array) -> Array[Dictionary]:
	last_error = ""
	var out: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "cannot open %s" % path
		return []
	var header := f.get_csv_line()
	var row_num := 1
	while not f.eof_reached():
		var line := f.get_csv_line()
		row_num += 1
		if line.size() == 1 and line[0].strip_edges() == "":
			continue
		if line.size() < required_cols.size():
			last_error = "%s row %d: expected at least %d columns, got %d" % [
				path.get_file(), row_num, required_cols.size(), line.size()]
			return []
		var row := {}
		for i in header.size():
			row[header[i]] = line[i] if i < line.size() else ""
		out.append(row)
	return out

static func load_all(dir: String) -> DataRepository:
	var repo := DataRepository.new()
	if not repo._load(dir):
		return null
	return repo

func _load(dir: String) -> bool:
	var bal_rows := DataRepository.parse_csv(dir + "/balance.csv", ["key", "value"])
	if bal_rows.is_empty():
		return false
	for r in bal_rows:
		balance[r["key"]] = float(r["value"])
	var trait_rows := DataRepository.parse_csv(dir + "/character_traits.csv", ["trait_code"])
	if trait_rows.is_empty():
		return false
	for r in trait_rows:
		traits[r["trait_code"]] = r
	var seat_rows := DataRepository.parse_csv(dir + "/council_seats.csv", ["seat_code"])
	if seat_rows.is_empty():
		return false
	for r in seat_rows:
		seats[r["seat_code"]] = r
	var court_rows := DataRepository.parse_csv(dir + "/policy_actions_court_additions.csv", ["action_code"])
	if court_rows.is_empty():
		return false
	for r in court_rows:
		actions[r["action_code"]] = r
	if not _load_if_present(dir + "/policy_actions_domain.csv", ["action_code"],
			func(r): actions[r["action_code"]] = r):
		return false
	if not _load_if_present(dir + "/founding_council.csv", ["id", "display_name", "seat"],
			func(r): founding.append(r)):
		return false
	if not _load_if_present(dir + "/roles.csv", ["id", "display_name", "seat"],
			func(r): roles.append(r)):
		return false
	if not _load_if_present(dir + "/relationships.csv",
			["from_id", "to_id", "rel_type", "sentiment", "reason"],
			func(r): relationships.append(r)):
		return false
	if not _load_if_present(dir + "/world_rules.csv",
			["rule_code", "kind", "verdict"],
			func(r): world_rules[r["rule_code"]] = r):
		return false
	if not _load_if_present(dir + "/claim_types.csv", ["claim_type", "label"],
			func(r): claim_types[r["claim_type"]] = r):
		return false
	if not _load_if_present(dir + "/facts.csv",
			["fact_code", "kind", "subject", "claim_type", "text", "truth"],
			func(r): facts.append(r)):
		return false
	if not _load_if_present(dir + "/regions.csv", ["region_code", "label"],
			func(r): regions[r["region_code"]] = r):
		return false
	if not _load_if_present(dir + "/locations.csv",
			["location_code", "region_code", "label", "kind", "occupants"],
			func(r): locations[r["location_code"]] = r):
		return false
	if not _load_if_present(dir + "/templates.csv", ["key", "trait", "text"],
			func(r): templates.append(r)):
		return false
	if not _load_if_present(dir + "/action_signatures.csv",
			["action_code", "variant", "centralism", "militarism", "orthodoxy",
			"tax_incidence", "expansionism"],
			func(r): signatures.append(r)):
		return false
	if not _load_if_present(dir + "/events.csv",
			["event_id", "category", "trigger", "weight", "cooldown_ticks", "once",
			"voice", "title_key"],
			func(r): events.append(r)):
		return false
	for row in events:
		events_by_id[row["event_id"]] = row
	if not _load_if_present(dir + "/maps.csv",
			["map_id", "label", "index_texture", "data_dir"],
			func(r): maps[r["map_id"]] = r):
		return false
	# Event prose is authored, not generated: it comes from the story
	# document, and templates.csv no longer carries a copy to drift from it.
	event_scenes_authored = StorySource.load_scenes()
	event_scenes = event_scenes_authored.duplicate()
	if not _load_if_present(dir + "/event_choices.csv",
			["event_id", "choice_id", "label", "centralism", "militarism", "orthodoxy",
			"tax_incidence", "expansionism", "effects", "requires"],
			func(r): event_choices.append(r)):
		return false
	if not _load_if_present(dir + "/world_schema.csv",
			["path", "type", "good_direction", "llm_cap"],
			func(r): world_schema.append(r)):
		return false
	if not _load_if_present(dir + "/metric_polarity.csv", ["metric", "good_direction"],
			func(r): metric_polarity[r["metric"]] = int(float(r["good_direction"]))):
		return false
	if not _load_if_present(dir + "/order_costs.csv", ["action_code", "cost", "always"],
			func(r): order_costs[r["action_code"]] = r):
		return false
	if not _load_if_present(dir + "/political_palette.csv", ["key", "color"],
			func(r): palette[r["key"]] = r["color"]):
		return false
	if not _load_if_present(dir + "/chart_palette.csv", ["key", "color"],
			func(r): chart_palette[r["key"]] = r["color"]):
		return false
	if not _load_if_present(dir + "/resource_icons.csv", ["key", "label", "icon", "tooltip"],
			func(r): resource_icons[r["key"]] = r):
		return false
	if not _load_if_present("res://data/goods_palette.csv", ["tag", "color"],
			func(r): goods_palette[String(r["tag"])] = String(r["color"])):
		return false
	if not _load_if_present("res://data/goods_art.csv", ["good_code", "texture"],
			func(r):
				if String(r["texture"]) != "":
					goods_art[String(r["good_code"])] = String(r["texture"])
				if String(r.get("icon", "")) != "":
					goods_icons[String(r["good_code"])] = String(r["icon"])):
		return false
	if not _load_if_present("res://data/goods_economy.csv",
			["good_code", "pool", "price_gold", "growth_permille"],
			func(r): goods_economy[String(r["good_code"])] = r):
		return false
	if not _load_if_present("res://data/goods_economy_defaults.csv",
			["tag", "pool", "price_gold", "growth_permille"],
			func(r): goods_economy_defaults[String(r["tag"])] = r):
		return false
	if not _load_if_present("res://data/terrain_art.csv",
			["key", "biome_id", "min_height", "max_height", "texture", "density",
			"height_px", "clump", "spread"],
			func(r): terrain_art.append(r)):
		return false
	if not _load_if_present("res://data/manor_buildings.csv",
			["building_code", "label", "cost_gold", "civil_cost", "build_days", "tax_bonus", "output_bonus",
			"defence_bonus", "church_bonus", "gold_per_tick", "grain_per_tick",
			"contentment_per_tick", "unrest_per_tick", "produce_good", "produce_units"],
			func(r): manor_buildings[String(r["building_code"])] = r):
		return false
	if not _load_if_present("res://data/manor_focus.csv",
			["focus_code", "label", "good_code", "biomes", "coast", "yield_per_1000",
			"switch_cost_gold", "transition_ticks"],
			func(r): manor_focus[String(r["focus_code"])] = r):
		return false
	if not _load_if_present("res://data/manor_estates.csv",
			["focus_code", "tier", "min_people", "texture"],
			func(r): manor_estates.append(r)):
		return false
	# BIOMES LAYER (experiment 2026-09-14).
	if not _load_if_present("res://data/biome_art.csv", ["biome_id", "key", "texture"],
			func(r): biome_art.append(r)):
		return false
	if not _load_if_present("res://data/sea_art.csv",
			["key", "texture", "weight", "height_px", "min_shore_px"],
			func(r): sea_art.append(r)):
		return false
	if not _load_if_present(dir + "/settlement_art.csv", ["group", "walled", "tier", "texture", "size"],
			func(r): settlement_art.append(r)):
		return false
	if not _load_if_present(dir + "/army_art.csv", ["piece", "texture", "painting"],
			func(r): army_art[String(r["piece"])] = r):
		return false
	if not _load_if_present(dir + "/army_terrain_biomes.csv", ["biome_id", "terrain"],
			func(r): army_terrain_biomes[int(r["biome_id"])] = String(r["terrain"])):
		return false
	if not _load_if_present(dir + "/army_terrain.csv", ["terrain", "arm", "defend_permille", "attack_permille"],
			func(r): army_terrain["%s|%s" % [r["terrain"], r["arm"]]] = {
				"defend": int(r["defend_permille"]), "attack": int(r["attack_permille"])}):
		return false
	if not _load_if_present(dir + "/army_matchups.csv", ["arm", "vs_arm", "attack_permille", "defense_permille"],
			_add_matchup):
		return false
	if not _load_if_present(dir + "/army_training_grades.csv", ["above", "label"],
			func(r): army_training_grades.append({"above": int(r["above"]), "label": String(r["label"])})):
		return false
	if not _load_if_present(dir + "/settlement_growth.csv", ["from_tier", "to_tier", "min_people", "building"],
			func(r): settlement_growth.append(r)):
		return false
	if not _load_if_present(dir + "/marker_art.csv", ["type", "texture"],
			func(r): marker_art[r["type"]] = r):
		return false
	if not _load_if_present(dir + "/terrain_palette.csv", ["key", "color"],
			func(r): terrain_palette[r["key"]] = r["color"]):
		return false
	# A campaign always has a world under it; which one is data, not code.
	if not maps.is_empty() and not load_map(default_map_id()):
		return false
	return true

## The map a fresh campaign opens on: the is_default row, else the first
## row in file order (Dictionary keeps insertion order, so this is stable).
func default_map_id() -> String:
	for id: String in maps:
		if String(maps[id].get("is_default", "")) == "1":
			return id
	return String(maps.keys()[0]) if not maps.is_empty() else ""

## Swaps in a map pack: its world tables and its realm bindings. Safe to
## call again to change maps — slot resolution reads the pristine authored
## slot each time, never a code a previous map already resolved.
func load_map(id: String) -> bool:
	if not maps.has(id):
		last_error = "unknown map_id: " + id
		return false
	var m: Dictionary = maps[id]
	var dir := String(m["data_dir"])
	kingdoms.clear()
	provinces.clear()
	burgs.clear()
	borders.clear()
	province_borders.clear()
	provinces_by_id.clear()
	MapOwnership.invalidate()
	MapTerrain.invalidate()
	MapObjects.forget_decor()
	MapEconomy.forget()
	RealmEconomy.forget()
	ManorEconomy.forget()
	MapPalette.forget_colors()
	HouseArms.forget()
	routes.clear()
	rivers.clear()
	markers.clear()
	biomes.clear()
	map_info.clear()
	vertices.clear()
	cells.clear()
	coasts.clear()
	realm_bindings.clear()
	house_bindings.clear()
	manors.clear()
	manor_by_code.clear()
	manor_by_label.clear()
	world_tables.clear()
	if not _load_if_present(dir + "/political/kingdoms.csv",
			["kingdom_code", "state_id", "label", "capital_burg"],
			func(r): kingdoms[r["kingdom_code"]] = r):
		return false
	if not _load_if_present(dir + "/political/provinces.csv",
			["province_code", "label", "kingdom_code"],
			func(r): _add_province(r)):
		return false
	if not _load_if_present(dir + "/political/burgs.csv",
			["burg_code", "label", "province_code", "kingdom_code"],
			func(r): burgs[r["burg_code"]] = r):
		return false
	if not _load_if_present(dir + "/political/borders.csv", ["kingdom_code", "loop", "points"],
			func(r): _add_border_loop(r)):
		return false
	if not _load_if_present(dir + "/political/province_borders.csv",
			["province_code", "loop", "points"],
			func(r): _add_province_border_loop(r)):
		return false
	if not _load_if_present(dir + "/geography/routes.csv",
			["route_code", "label", "group", "from_burg", "to_burg", "length", "points"],
			func(r): routes[r["route_code"]] = _with_polyline(r)):
		return false
	if not _load_if_present(dir + "/geography/rivers.csv",
			["river_code", "label", "type", "length", "discharge", "kingdom_codes", "points"],
			func(r): rivers[r["river_code"]] = _with_polyline(r)):
		return false
	if not _load_if_present(dir + "/geography/markers.csv",
			["marker_code", "label", "type", "x", "y", "legend"],
			func(r): markers[r["marker_code"]] = r):
		return false
	if not _load_if_present(dir + "/geography/biomes.csv", ["biome_id", "label"],
			func(r): biomes[int(r["biome_id"])] = r):
		return false
	if not _load_if_present(dir + "/geography/vertices.csv", ["vertex_id", "x", "y"],
			func(r): vertices[int(r["vertex_id"])] = Vector2(float(r["x"]), float(r["y"]))):
		return false
	if not _load_if_present(dir + "/geography/cells.csv",
			["cell_id", "vertex_ids", "height", "biome_id", "water", "neighbor_ids"],
			func(r): cells[int(r["cell_id"])] = _typed_cell(r)):
		return false
	if not _load_if_present(dir + "/geography/coasts.csv",
			["kind", "feature_id", "loop", "points"],
			func(r): coasts.append(_with_polyline(r))):
		return false
	if not _load_if_present(dir + "/map_info.csv", ["key", "value"],
			func(r): map_info[r["key"]] = r["value"]):
		return false
	# The named tables above and the domain store are one set of rows.
	_register_table("political", "kingdoms", kingdoms)
	_register_table("political", "provinces", provinces)
	_register_table("political", "burgs", burgs)
	_register_table("geography", "routes", routes)
	_register_table("geography", "rivers", rivers)
	_register_table("geography", "markers", markers)
	_register_table("geography", "biomes", biomes)
	for spec in WORLD_TABLE_SPECS:
		var table: Dictionary = {}
		var key_cols: Array = spec[3]
		var sep := String(spec[4])
		if not _load_if_present("%s/%s/%s.csv" % [dir, spec[0], spec[1]], spec[2],
				func(r: Dictionary) -> void:
					var parts: Array[String] = []
					for k in key_cols:
						parts.append(String(r[k]))
					table[sep.join(parts)] = r):
			return false
		_register_table(String(spec[0]), String(spec[1]), table)
	if not _load_if_present(dir + "/realm_bindings.csv", ["slot", "kingdom_code"],
			func(r): realm_bindings[r["slot"]] = r["kingdom_code"]):
		return false
	if not _load_if_present(dir + "/house_bindings.csv", ["family_name", "province_codes"],
			func(r: Dictionary) -> void:
				for pc in String(r["province_codes"]).split("|", false):
					house_bindings[pc] = String(r["family_name"])):
		return false
	if not _load_if_present(dir + "/political/manors.csv",
			["cell_id", "manor_code", "label", "province_code", "burg_code", "culture_code"],
			func(r: Dictionary) -> void:
				r["cell_id"] = int(r["cell_id"])
				manors[int(r["cell_id"])] = r):
		return false
	if not _load_if_present(dir + "/manor_name_overrides.csv", ["cell_id", "label"],
			func(r: Dictionary) -> void:
				var cell := int(r["cell_id"])
				if manors.has(cell):
					manors[cell]["label"] = String(r["label"])):
		return false
	for cell: int in manors:
		var row: Dictionary = manors[cell]
		manor_by_code[String(row["manor_code"])] = cell
		manor_by_label[String(row["label"]).to_lower()] = cell
	map_id = id
	index_texture_path = String(m["index_texture"])
	province_texture_path = String(m.get("province_texture", ""))
	biome_texture_path = String(m.get("biome_texture", ""))
	sea_texture_path = String(m.get("sea_texture", ""))
	biome_weights_path = String(m.get("biome_weights", ""))  # BIOMES LAYER (experiment 2026-09-14)
	relief_path = String(m.get("relief_texture", ""))  # BIOMES LAYER (owner 2026-09-17)
	settlement_path = String(m.get("settlement_texture", ""))  # SETTLEMENT EARTH HALO
	cell_texture_path = String(m.get("cell_texture", ""))
	_resolve_realm_slots()
	return true

## province_code -> Array[PackedVector2Array], the same shape as `borders`.
## MapOwnership merges the loops of the provinces a kingdom holds into its
## live outline, so this is what makes a border able to move.
## The province row carrying this Azgaar province_id, or {}. Rebuilds the
## index when it has fallen out of step with `provinces` — a repo assembled
## by hand (test fixtures, a future mod loader) sets `provinces` wholesale
## and would otherwise silently look empty here.
func province_by_id(pid: int) -> Dictionary:
	if provinces_by_id.size() != provinces.size():
		provinces_by_id.clear()
		for row: Dictionary in provinces.values():
			provinces_by_id[int(row.get("province_id", -1))] = row
	return provinces_by_id.get(pid, {})

func _add_province(r: Dictionary) -> void:
	provinces[r["province_code"]] = r
	provinces_by_id[int(r.get("province_id", -1))] = r

func _add_province_border_loop(r: Dictionary) -> void:
	var code := String(r["province_code"])
	if not province_borders.has(code):
		province_borders[code] = []
	(province_borders[code] as Array).append(MapGeometry.parse_points(String(r["points"])))

func _add_border_loop(r: Dictionary) -> void:
	var code := String(r["kingdom_code"])
	if not borders.has(code):
		borders[code] = []
	(borders[code] as Array).append(MapGeometry.parse_points(String(r["points"])))

func _with_polyline(r: Dictionary) -> Dictionary:
	var pts := MapGeometry.parse_points(String(r["points"]))
	r["polyline"] = pts
	r["bbox"] = MapGeometry.bounds(pts)
	return r

## A cells.csv row with its id lists and numbers parsed once, so the mesh
## builder never re-splits text.
func _typed_cell(r: Dictionary) -> Dictionary:
	r["vertex_ids"] = _id_list(String(r["vertex_ids"]))
	r["neighbor_ids"] = _id_list(String(r["neighbor_ids"]))
	r["height"] = float(r["height"])
	r["biome_id"] = int(r["biome_id"])
	return r

static func _id_list(text: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for part in text.split("|", false):
		out.append(int(part))
	return out

## A realm slot resolved through the loaded map. Anything that is not a slot
## passes through unchanged — a literal kingdom_code, or facts.csv subjects
## like "world"/"realm"/a character id.
func resolve_realm(slot: String) -> String:
	return String(realm_bindings.get(slot, slot))

## The display name of the kingdom a slot binds to — "player_realm" ->
## "Kelvarn". Falls back to the kingdom_code, then to the slot itself, so an
## unbound slot degrades to something readable instead of blank.
func realm_label(slot: String) -> String:
	var code := resolve_realm(slot)
	var row: Dictionary = kingdoms.get(code, {})
	var label := String(row.get("label", ""))
	if label != "":
		return label
	return code if code != "" else slot

## Substitutes {player_realm}, {raider_realm}, ... in authored prose with the
## bound kingdom's label. Authored text never spells a kingdom's name, so a
## re-export that renames the world only touches realm_bindings.csv. Follows
## the {season}/{year} convention templates.csv already uses. Unknown tokens
## are left alone — nothing here can fail on a typo.
func fill_realms(text: String) -> String:
	if text.find("{") < 0:
		return text
	var out := text
	for slot: String in realm_bindings:
		out = out.replace("{%s}" % slot, realm_label(slot))
	return out

## The realm labels as format() vars, for template text that already goes
## through String.format (see TemplateVoicer).
func realm_vars() -> Dictionary:
	var out: Dictionary = {}
	for slot: String in realm_bindings:
		out[slot] = realm_label(slot)
	return out


## Authored content names slots (player_realm, raider_realm, ...) rather than
## the codes a particular Azgaar export happened to generate. Resolving once
## here keeps every consumer downstream seeing a concrete kingdom_code. The
## authored slot is kept alongside so re-resolving against a different map
## still works.
func _resolve_realm_slots() -> void:
	for r in roles:
		r["kingdom_slot"] = r.get("kingdom_slot", r.get("kingdom", ""))
		r["kingdom"] = resolve_realm(String(r["kingdom_slot"]))
	for r in founding:
		r["kingdom_slot"] = r.get("kingdom_slot", r.get("kingdom", ""))
		r["kingdom"] = resolve_realm(String(r["kingdom_slot"]))
	for r in facts:
		r["subject_slot"] = r.get("subject_slot", r.get("subject", ""))
		r["subject"] = resolve_realm(String(r["subject_slot"]))
	# Any authored cell may name a realm by slot, so fill every table that
	# reaches the player rather than listing columns — a new prose column
	# should not have to be remembered here. Cells with no "{" are untouched,
	# so ids and numbers cannot be caught by this.
	for rows in [roles, founding, facts, relationships, templates, events,
			event_choices]:
		for r: Dictionary in rows:
			_fill_row_realms(r)
	# RANDOM_EVENTS.md scenes are loaded before any map is, so they are filled
	# here rather than at parse time — and from the authored copy, so swapping
	# packs mid-session re-fills rather than compounding.
	for id: String in event_scenes_authored:
		event_scenes[id] = fill_realms(String(event_scenes_authored[id]))

## Fills realm tokens in every string cell of one row, keeping the authored
## text under "_authored" so a second load_map re-fills from the original
## rather than substituting into already-substituted text.
func _fill_row_realms(r: Dictionary) -> void:
	var authored: Dictionary = r.get("_authored", {})
	if authored.is_empty():
		for col: String in r:
			if col == "_authored" or not (r[col] is String):
				continue
			if String(r[col]).find("{") >= 0:
				authored[col] = String(r[col])
		if authored.is_empty():
			return
		r["_authored"] = authored
	for col: String in authored:
		r[col] = fill_realms(String(authored[col]))

## Sink for data/army_matchups.csv: appends one {vs, attack, defense} row
## under its arm in army_matchups, in file order.
func _add_matchup(r: Dictionary) -> void:
	if not army_matchups.has(String(r["arm"])):
		army_matchups[String(r["arm"])] = []
	(army_matchups[String(r["arm"])] as Array).append({"vs": String(r["vs_arm"]),
		"attack": int(r["attack_permille"]), "defense": int(r["defense_permille"])})

## Loads a live-gameplay CSV that is nonetheless allowed to be genuinely
## absent (future saves/mods may not ship it yet). A missing file is not an
## error. A present-but-malformed file is: unlike the old _load_optional,
## this cannot silently swallow a parse failure — it fails loud through
## parse_csv's required_cols/last_error contract, same as the always-required
## files above.
func _load_if_present(path: String, required_cols: Array, sink: Callable) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var rows := DataRepository.parse_csv(path, required_cols)
	if DataRepository.last_error != "":
		return false
	for r in rows:
		sink.call(r)
	return true

func bal(key: String) -> float:
	assert(balance.has(key), "balance.csv missing key: " + key)
	return balance[key]
