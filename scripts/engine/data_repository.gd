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
## data/ui_table_palette.csv: key -> "#rrggbb[aa]" for the WAR TABLE chrome
## (paper ink, brass, wax, the tally board, the table's light; owner 2026-10-01).
var ui_table_palette: Dictionary = {}
## data/ui_fonts.csv: role -> the row (size_scale, title_case); the faces
## themselves are assets/fonts/roles/<role>.tres (owner 2026-10-02).
var ui_fonts: Dictionary = {}
## data/manor_card_sections.csv: the manor card's named sections in order,
## each {section, label, keys (Array), rates (bool), per_month (bool),
## drop_if_rates (Array)}.
var manor_card_sections: Array = []
## data/resource_icons.csv: key -> {label, icon, tooltip} for every resource
## and unit the UI shows as a glyph with a floating tooltip.
var resource_icons: Dictionary = {}
## data/map3d_settlements.csv rows keyed by burg group: the 3D MAP's
## placeholder marker for each settlement (Map3DView).
var map3d_settlements: Dictionary = {}
## data/map3d_houses.csv rows keyed by type: the 3D MAP's house types, their
## role, weight, size and roof colour (spec 2026-09-20 §2); the mesh each is
## drawn with is GameArt's HOUSE_MODELS.
var map3d_houses: Dictionary = {}
## data/map3d_tree_crowns.csv rows (cell, kind, ...): which cell of the woods'
## crown atlas shows which kind of tree (0 broadleaf, 1 conifer, 2 lone) —
## the photo cards of 2026-10-01 (tree_card.gdshader).
var map3d_tree_crowns: Array = []
## data/map3d_bake.csv as key -> number: the 3D build's own tuning. The bake
## (tools/map3d/bake_world.py) has always read this file; the runtime reads
## it too for the settlements' house clusters, so the two can never disagree
## about where a cluster ends.
var map3d_bake: Dictionary = {}
## data/graphics_quality.csv rows keyed by tier (low/medium/high/ultra): the
## 3D map's graphics tiers (Map3DQuality, spec 2026-09-20 §4).
var graphics_quality: Dictionary = {}
## data/army_art.csv: piece -> {piece, stand_deg, size, stride_m, rank_depth} —
## how a regiment's 3D piece stands and walks (MapObjects.army_piece); its
## model and its card's painting are GameArt's tables (owner 2026-10-02).
var army_art: Dictionary = {}
## data/army_terrain_biomes.csv: biome id -> the terrain a regiment on it
## stands on (ArmySystem.terrain_of, owner 2026-09-17).
var army_terrain_biomes: Dictionary = {}
## data/army_terrain.csv: "terrain|arm" -> {defend, attack} per mille.
var army_terrain: Dictionary = {}
## data/army_town_reach.csv: burg group -> km (float) a regiment stands IN a
## town of that group within (ArmySystem.town_of).
var army_town_reach: Dictionary = {}
## data/war_marks.csv: marker type -> {glyph, layer, note} — which marks the
## WAR ROOM inks, how, and on which layer (spec 2026-10-07-war-room-p2 §1.1).
var war_marks: Dictionary = {}
## data/war_mark_hazards.csv: marker type -> {reach_km, permille} — the marks
## that take a share of a supply line passing within their reach (§1.2).
var war_mark_hazards: Dictionary = {}
## data/war_works.csv: strategic good -> {family, glyph} — the goods that make
## a town a war works on the WAR ROOM's sheet, by family (spec 2026-10-07-war-room-p3 §1.1).
var war_works: Dictionary = {}
## data/hazard_kinds.csv: zone kind -> {label, months, public, wounds_permille,
## morale, supply_loss_permille, pace_permille, ink} (spec 2026-10-07-war-room-p2 §2.2).
var hazard_kinds: Dictionary = {}
## data/army_town_defence.csv: "works|arm" -> {defend, attack} per mille, works
## town / walls / citadel (ArmySystem.works_of).
var army_town_defence: Dictionary = {}
## data/army_ground_speed.csv: key -> per mille of a march's pace (road, trail,
## tier_<tier>, and each terrain of army_terrain_biomes).
var army_ground_speed: Dictionary = {}
## data/army_matchups.csv: arm -> [{vs, attack, defense}] per mille, in file order.
var army_matchups: Dictionary = {}
## data/army_training_grades.csv rows {above, label}, first match wins.
var army_training_grades: Array[Dictionary] = []
## data/army_orders.csv, IN ORDER: the rows of a regiment's right-click menu
## on the map, [{action_code, label, hint, params}] (ArmyOrderMenu); params is
## the row's `key=value|key=value` as a Dictionary of strings, sent with the
## regiment (ARMY_STANCE's stance). A list, not a dictionary, because the
## order of the entries is the order they are shown in.
var army_orders: Array = []
## data/army_route_orders.csv: key -> {label, hint} — the rows of the march's
## confirm menu (commit / cancel) and route menu (edit / halt), and the
## paused-only reason (owner 2026-09-27, ArmyOrderMenu).
var army_route_orders: Dictionary = {}
## data/army_carry_loads.csv: [{days, pace_permille, label}], days ascending
## (spec 2026-10-07-army-supply-lines §3.6).
var army_carry_loads: Array = []
## data/army_supply_orders.csv: key -> {label, hint} — the supply rows of the
## regiment's right-click menu (spec 2026-10-07-army-supply-lines §5.1).
var army_supply_orders: Dictionary = {}
## data/army_hostile_stances.csv: the stances whose regiments cut supply lines.
var army_hostile_stances: Array[String] = []
## data/battle_outcomes.csv (spec 2026-10-07-enemy-ai-and-battle §4.3): the five
## result tiers in ascending eff_min, {tier, eff_min, eff_max,
## attacker_loss_permille, defender_loss_permille, wounded_share_permille,
## attacker_morale, defender_morale, rout, siege} — whole numbers; rout is
## "attacker" / "defender" / "none"; siege (optional column) is what an
## assault's round of the tier does to the siege: "repulsed", "breach" or "".
var battle_outcomes: Array[Dictionary] = []
## data/battle_stances.csv (§4.4): stance -> {label, defence_permille,
## morale_decay_permille, retreat_odds_permille, retreats_on_contact (bool)}.
var battle_stances: Dictionary = {}
## data/ai_doctrines.csv (§3.3): host role -> {greed_permille, caution_permille,
## dist_cost, engage_odds_permille, retreat_morale, town_bonus}.
var ai_doctrines: Dictionary = {}
## The pack's military/raid_hosts.csv (§2) in file order: [{host_code,
## regiments (Array of regiment codes), appear_day, role, start_x, start_y}].
## Cleared by load_map.
var raid_hosts: Array[Dictionary] = []
## data/event_presenters.csv: an event id or an event category -> the council
## seat whose holder brings that event before the crown (owner 2026-10-02:
## every event waits on the table as a minister's matter); an id wins.
var event_presenters: Dictionary = {}
## data/army_formations.csv, by min_fit_permille: [{figures, min_fit_permille,
## slots: [Vector2]}] — how many figures a regiment's piece shows by its
## strength (Map3DFormation).
var army_formations: Array = []
## data/army_speed.csv: arm -> km a day (int), the arm's own march
## (owner 2026-09-19, ArmySystem.base_pace_km).
var army_speed: Dictionary = {}
## data/army_height_supply.csv: [{tier, min_height, supply_permille}],
## highest min_height first (Elevation.tier_of reads the first it reaches).
var army_height_supply: Array = []
## data/army_morale_words.csv: [{min_score, word}], highest min_score first
## (ArmySystem.morale_word reads the first it reaches; spec
## 2026-09-30-ledger-supply-design §4).
var army_morale_words: Array = []
## data/war_plan_kinds.csv: kind -> {label, tool_key, gesture, head, teeth,
## pen, name_default, cut} — the staff's stroke kinds (WAR ROOM plans, spec
## 2026-10-07-war-room-annotations-and-planning-pieces §2.1), in file order.
var war_plan_kinds: Dictionary = {}
## data/war_palette.csv: key -> Color (WAR ROOM, spec 2026-10-01 §5).
var war_palette: Dictionary = {}
## data/war_drills.csv, file order: [{key, clip, label, arms: PackedStringArray}].
var war_drills: Array = []
## data/war_equipment.csv, file order: [{arm, part, label, note}].
var war_equipment: Array = []
## data/war_folio_sections.csv, file order: [{key, label}].
var war_folio_sections: Array = []
## data/war_order_words.csv: order key (ArmySystem.ORDER_*) -> the folio's word for it.
var war_order_words: Dictionary = {}
## data/workshop_rates.csv: [{rate_permille, word, ledger_label}], lowest
## rate first — the rates WORKSHOP_RATE accepts and how each is said
## (WorkshopSystem; spec 2026-09-30-ledger-supply-design §2).
var workshop_rates: Array = []
## data/building_inputs.csv: building code -> [{good, units}] in file order,
## what one standing building eats a month (IndustrySystem; spec
## 2026-09-30-ledger-industry-trade-design M5). A building with no rows eats
## nothing.
var building_inputs: Dictionary = {}
## data/courier_kinds.csv: kind -> {speed_permille, fee_gold, offered}
## (spec 2026-09-27-courier-core §3).
var courier_kinds: Dictionary = {}
## The LEDGER's ontology (spec 2026-09-30-ledger-ontology-design §7.1):
## rows as read, in file order.
var ledger_lenses: Array = []
var ledger_types: Array = []
var ledger_links: Array = []
var ledger_actions: Array = []
var ledger_loops: Array = []
## data/ledger_clusters.csv, in file order: {cluster, label, colour (a
## ledger_palette.csv key), at (Vector3, the anchor), lens (the lens chip it
## answers to)}.
var ledger_clusters: Array = []
## key -> Color (data/ledger_palette.csv).
var ledger_palette: Dictionary = {}
## data/ledger_governance.csv: flow_type -> {seat, skill, base_permille,
## skill_mid, skill_step_permille, min_permille, max_permille, label, books,
## ledger_type} (LEDGER M3, Governance; spec 2026-09-30-ledger-governors-design
## §2). `books`: whether the flow keeps books an audit can read (LEDGER_AUDIT
## refuses one without, M5/M6 ruling); `ledger_type`: the LEDGER type its
## instances are drawn as (the flow's own name when empty; the works are
## drawn on the artisans).
var ledger_governance: Dictionary = {}
## data/ledger_static_nodes.csv (spec 2026-09-30-ledger-galaxy-design §3b):
## single nodes written down — {node_id, type_id, label, note}; the type's
## row names the instance list `static`.
var ledger_static_nodes: Array = []
## data/ledger_static_links.csv: single edges written down — {link_id, from,
## to, flow (-1 when blank), note}; the link type's row names the reader `static`.
var ledger_static_links: Array = []
## data/courier_art.csv: kind -> its row (size, stride_m); its model and its
## painting are GameArt's tables.
var courier_art: Dictionary = {}
## data/intel_facts.csv: key -> {label, round_to, tiers} (spec 2026-09-28 §1).
var intel_facts: Dictionary = {}
## data/spy_difficulty.csv: key -> per mille added to a spy's quality roll.
var spy_difficulty: Dictionary = {}
## data/road_speed.csv: key -> per mille (road, trail, offroad, sea, tier_<tier>).
var road_speed: Dictionary = {}
## data/weather.csv: kind -> {speed_permille, icon, label, and the look: overcast,
## wet, mud, snow, rainfall, snowfall (0..1)}, in the file's order.
var weather_kinds: Dictionary = {}
## data/weather_odds.csv: "season|tier" -> {kind: weight}, kinds in weather_kinds' order.
var weather_odds: Dictionary = {}
## data/landmark_names.csv: kind ("high"|"low") -> patterns in file order.
var landmark_names: Dictionary = {}
## data/manor_buildings.csv: building_code -> {label, cost_gold, civil_cost,
## build_days, tax_bonus, output_bonus, defence_bonus, church_bonus,
## *_per_tick, produce_good, produce_units} — what a manor can raise, what
## the work takes in civil goods, how long it takes and what it does once it
## stands.
var manor_buildings: Dictionary = {}
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
## the estate a manor is by its industry (focus_code) and its people (owner
## 2026-09-14) — the manor card's size; its painting is GameArt's.
var manor_estates: Array[Dictionary] = []
## data/goods_palette.csv: a good's first tag -> the colour its province wears
## in the ECONOMY view.
var goods_palette: Dictionary = {}
## data/terrain_palette.csv: key -> "#rrggbb" for the terrain the game draws
## itself (MapTerrain): land tints per biome, sea, lake, and line colours.
var terrain_palette: Dictionary = {}
var events: Array[Dictionary] = []
var events_by_id: Dictionary = {}
var event_choices: Array[Dictionary] = []
## The scripted chapters (data/chapter_events.csv). They are NOT in `events`
## — the random roll samples that pool by weight and a chapter beat must
## never be sampled; it is fired by id, off the chain. `events_by_id` holds
## both, because EventSystem._fire looks a beat up by id either way.
var chapter_events: Array[Dictionary] = []
var chapter_event_choices: Array[Dictionary] = []
## branch_id -> the ordered rules of data/chapter_branches.csv. The `branch:`
## effect op schedules the first rule whose `requires` holds.
var chapter_branches: Dictionary = {}
var world_rules: Dictionary = {}
var claim_types: Dictionary = {}
## event_id -> scene prose from RANDOM_EVENTS.md (see StorySource), with
## {player_realm}-style tokens filled from the loaded pack. Read this one.
var event_scenes: Dictionary = {}
## event_id -> the title from its heading in the story document, shown on the
## audience window's banner. Authored like the scene, never a template key.
var event_titles: Dictionary = {}
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
## arms key -> res:// path of the art it wears (maps/<id>/arms_bindings.csv,
## optional, hand-maintained): pins a kingdom or a house to a chosen coat of
## arms, from this pack or any other — HouseArms reads it before its own.
var arms_bindings: Dictionary = {}
## maps/<id>/political/manors.csv: cell_id (int) -> {manor_code, label,
## province_code, burg_code, culture_code} — one named manor per land cell,
## forged by the importer (ManorNames); maps/<id>/manor_name_overrides.csv
## (cell_id,label), hand-maintained, replaces labels last. MANOR_SYSTEM.md §1.
var manors: Dictionary = {}
## manor_code -> cell_id, and lower-cased label -> cell_id, for orders that
## name a manor ("buy Ashcombe").
var manor_by_code: Dictionary = {}
var manor_by_label: Dictionary = {}
## maps/<id>/landmark_name_overrides.csv (optional): cell id -> name.
var landmark_name_overrides: Dictionary = {}
## Every pack table by domain and area: world_tables[domain][area][code] -> row
## (spec 2026-09-09 §1). The named fields above (kingdoms, provinces, burgs,
## routes, rivers, markers, biomes) are the SAME Dictionary objects, so the
## old callers and the world ledger see one set of rows.
var world_tables: Dictionary = {}
## economy/deals.csv (LEDGER M6, spec 2026-09-30-ledger-industry-trade-design):
## the export's trade flows in FILE order, {seller_type, seller, buyer_type,
## buyer, good, units (float), price (float)} — a month's units, read by
## MarketSystem through live ownership. Cleared by load_map.
var deals: Array = []

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
## The default map pack's id straight from data/maps.csv (is_default = 1,
## else the first row) — for tools that run before any repository loads,
## so none of them names a pack.
static func default_pack_id(maps_csv: String = "res://data/maps.csv") -> String:
	var first := ""
	for row: Dictionary in parse_csv(maps_csv, ["map_id"]):
		if first == "":
			first = String(row["map_id"])
		if String(row.get("is_default", "")) == "1":
			return String(row["map_id"])
	return first

## Where pack `id`'s 3D build lives ("" = the loaded map): its maps.csv
## `map3d_dir`, else res://assets/3D/terrain/<id> (spec 2026-09-20 §3).
func map3d_dir(id: String = "") -> String:
	var key := id if id != "" else map_id
	var row: Dictionary = maps.get(key, {})
	var d := String(row.get("map3d_dir", ""))
	return d if d != "" else "res://assets/3D/terrain/%s" % key

## Where a pack's built 3D WORLD SCENE lives (owner 2026-10-04: every scene is
## under scenes/, assets/ holds art): scenes/map3d/worlds/<id>.tscn. The build
## writes it there; its data — the Terrain3D regions, textures, bake, layers,
## rivers and manifest — stays in map3d_dir (Map3DWorldLoader.data_dir).
const MAP3D_WORLDS := "res://scenes/map3d/worlds"


func map3d_scene(id: String = "") -> String:
	return map3d_scene_of(id if id != "" else map_id)


static func map3d_scene_of(pack_id: String) -> String:
	return MAP3D_WORLDS.path_join(pack_id + ".tscn")


## map3d_dir straight from data/maps.csv, for tools that run before any
## repository loads.
static func map3d_dir_of(pack_id: String, maps_csv: String = "res://data/maps.csv") -> String:
	for row: Dictionary in parse_csv(maps_csv, ["map_id"]):
		if String(row["map_id"]) == pack_id and String(row.get("map3d_dir", "")) != "":
			return String(row["map3d_dir"])
	return "res://assets/3D/terrain/%s" % pack_id

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

## Only what the interface's LOOK reads — balance, the palettes, the font
## roles' sizes, the resource icons' words — for the editor, where the Game
## autoload is a placeholder and the @tool look classes (the war table's
## paper, brass and seal, the icons) still draw their scenes. Null on failure.
static func load_look(dir: String) -> DataRepository:
	var repo := DataRepository.new()
	var bal_rows := DataRepository.parse_csv(dir + "/balance.csv", ["key", "value"])
	if bal_rows.is_empty():
		return null
	for r in bal_rows:
		repo.balance[r["key"]] = float(r["value"])
	if not repo._load_look_tables(dir):
		return null
	return repo

func _load_look_tables(dir: String) -> bool:
	if not _load_if_present(dir + "/political_palette.csv", ["key", "color"],
			func(r): palette[r["key"]] = r["color"]):
		return false
	if not _load_if_present(dir + "/chart_palette.csv", ["key", "color"],
			func(r): chart_palette[r["key"]] = r["color"]):
		return false
	if not _load_if_present(dir + "/ui_table_palette.csv", ["key", "color"],
			func(r): ui_table_palette[r["key"]] = r["color"]):
		return false
	if not _load_if_present(dir + "/ui_fonts.csv", ["role", "size_scale", "title_case"],
			func(r): ui_fonts[r["role"]] = r):
		return false
	if not _load_if_present(dir + "/resource_icons.csv", ["key", "label", "icon", "tooltip"],
			func(r): resource_icons[r["key"]] = r):
		return false
	return true

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
	if not _load_if_present(dir + "/chapter_events.csv",
			["event_id", "category", "trigger", "weight", "cooldown_ticks", "once",
			"voice", "title_key"],
			func(r): chapter_events.append(r)):
		return false
	for row in chapter_events:
		events_by_id[row["event_id"]] = row
	if not _load_if_present(dir + "/maps.csv",
			["map_id", "label", "index_texture", "data_dir"],
			func(r): maps[r["map_id"]] = r):
		return false
	# Event prose is authored, not generated: it comes from the story
	# documents, and templates.csv no longer carries a copy to drift from them.
	event_scenes_authored = StorySource.load_all_scenes()
	event_scenes = event_scenes_authored.duplicate()
	event_titles = StorySource.load_all_titles()
	if not _load_if_present(dir + "/event_choices.csv",
			["event_id", "choice_id", "label", "centralism", "militarism", "orthodoxy",
			"tax_incidence", "expansionism", "effects", "requires"],
			func(r): event_choices.append(r)):
		return false
	if not _load_if_present(dir + "/chapter_event_choices.csv",
			["event_id", "choice_id", "label", "centralism", "militarism", "orthodoxy",
			"tax_incidence", "expansionism", "effects", "requires"],
			func(r): chapter_event_choices.append(r)):
		return false
	if not _load_if_present(dir + "/chapter_branches.csv",
			["branch_id", "order", "requires", "event_id", "ticks"],
			func(r): (chapter_branches.get_or_add(r["branch_id"], []) as Array).append(r)):
		return false
	for id: String in chapter_branches:
		(chapter_branches[id] as Array).sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
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
	if not _load_look_tables(dir):
		return false
	if not _load_if_present(dir + "/manor_card_sections.csv", ["section", "label", "keys", "rates"],
			func(r): manor_card_sections.append({"section": String(r["section"]),
				"label": String(r["label"]), "keys": String(r["keys"]).split("|", false),
				"rates": int(float(r["rates"])) == 1,
				"per_month": int(float(r.get("per_month", "0"))) == 1,
				"drop_if_rates": String(r.get("drop_if_rates", "")).split("|", false)})):
		return false
	if not _load_if_present("res://data/goods_palette.csv", ["tag", "color"],
			func(r): goods_palette[String(r["tag"])] = String(r["color"])):
		return false
	if not _load_if_present("res://data/goods_economy.csv",
			["good_code", "pool", "price_gold", "growth_permille"],
			func(r): goods_economy[String(r["good_code"])] = r):
		return false
	if not _load_if_present("res://data/goods_economy_defaults.csv",
			["tag", "pool", "price_gold", "growth_permille"],
			func(r): goods_economy_defaults[String(r["tag"])] = r):
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
			["focus_code", "tier", "min_people"],
			func(r): manor_estates.append(r)):
		return false
	if not _load_if_present("res://data/map3d_settlements.csv",
			["group", "dot_px", "ring_px", "line_px", "color", "max_view_m"],
			func(r): map3d_settlements[String(r["group"])] = r):
		return false
	if not _load_if_present("res://data/map3d_houses.csv",
			["type", "role", "weight", "footprint_m", "height_m", "roof", "min_group"],
			func(r): map3d_houses[String(r["type"])] = r):
		return false
	if not _load_if_present("res://data/map3d_tree_crowns.csv", ["cell", "kind"],
			func(r): map3d_tree_crowns.append(r)):
		return false
	if not _load_if_present("res://data/map3d_bake.csv", ["key", "value"],
			func(r): map3d_bake[String(r["key"])] = float(r["value"])):
		return false
	if not _load_if_present("res://data/graphics_quality.csv", ["tier", "render_scale"],
			func(r): graphics_quality[String(r["tier"])] = r):
		return false
	if not _load_if_present(dir + "/army_art.csv", ["piece", "stand_deg"],
			func(r): army_art[String(r["piece"])] = r):
		return false
	if not _load_if_present(dir + "/army_terrain_biomes.csv", ["biome_id", "terrain"],
			func(r): army_terrain_biomes[int(r["biome_id"])] = String(r["terrain"])):
		return false
	if not _load_if_present(dir + "/army_terrain.csv", ["terrain", "arm", "defend_permille", "attack_permille"],
			func(r): army_terrain["%s|%s" % [r["terrain"], r["arm"]]] = {
				"defend": int(r["defend_permille"]), "attack": int(r["attack_permille"])}):
		return false
	if not _load_if_present(dir + "/army_town_reach.csv", ["group", "reach_km"],
			func(r): army_town_reach[String(r["group"])] = float(r["reach_km"])):
		return false
	if not _load_if_present(dir + "/war_marks.csv", ["type", "glyph", "layer", "note"],
			func(r): war_marks[String(r["type"])] = {"glyph": String(r["glyph"]), "layer": String(r["layer"]),
				"note": String(r["note"])}):
		return false
	if not _load_if_present(dir + "/war_plan_kinds.csv", ["kind", "label", "tool_key", "gesture", "head", "teeth",
			"pen", "name_default", "cut"],
			func(r): war_plan_kinds[String(r["kind"])] = {"label": String(r["label"]), "tool_key": String(r["tool_key"]),
				"gesture": String(r["gesture"]), "head": String(r["head"]) == "1", "teeth": String(r["teeth"]) == "1",
				"pen": String(r["pen"]) == "1", "name_default": String(r["name_default"]), "cut": int(r["cut"])}):
		return false
	if not _load_if_present(dir + "/war_mark_hazards.csv", ["type", "reach_km", "supply_loss_permille"],
			func(r): war_mark_hazards[String(r["type"])] = {"reach_km": float(r["reach_km"]),
				"permille": int(r["supply_loss_permille"])}):
		return false
	if not _load_if_present(dir + "/war_works.csv", ["good_code", "family", "glyph"],
			func(r): war_works[String(r["good_code"])] = {"family": String(r["family"]), "glyph": String(r["glyph"])}):
		return false
	if not _load_if_present(dir + "/hazard_kinds.csv", ["kind", "label", "months", "public", "wounds_permille",
			"morale", "supply_loss_permille", "pace_permille", "ink"],
			func(r): hazard_kinds[String(r["kind"])] = {"label": String(r["label"]), "months": int(r["months"]),
				"public": String(r["public"]) == "1", "wounds_permille": int(r["wounds_permille"]),
				"morale": int(r["morale"]), "supply_loss_permille": int(r["supply_loss_permille"]),
				"pace_permille": int(r["pace_permille"]), "ink": String(r["ink"])}):
		return false
	if not _load_if_present(dir + "/army_town_defence.csv", ["works", "arm", "defend_permille", "attack_permille"],
			func(r): army_town_defence["%s|%s" % [r["works"], r["arm"]]] = {
				"defend": int(r["defend_permille"]), "attack": int(r["attack_permille"])}):
		return false
	if not _load_if_present(dir + "/army_ground_speed.csv", ["key", "permille"],
			func(r): army_ground_speed[String(r["key"])] = int(r["permille"])):
		return false
	if not _load_if_present(dir + "/army_matchups.csv", ["arm", "vs_arm", "attack_permille", "defense_permille"],
			_add_matchup):
		return false
	if not _load_if_present(dir + "/army_training_grades.csv", ["above", "label"],
			func(r): army_training_grades.append({"above": int(r["above"]), "label": String(r["label"])})):
		return false
	if not _load_if_present(dir + "/army_speed.csv", ["arm", "km_per_day"],
			func(r): army_speed[String(r["arm"])] = int(r["km_per_day"])):
		return false
	if not _load_if_present(dir + "/courier_kinds.csv", ["kind", "speed_permille", "fee_gold", "offered"],
			func(r): courier_kinds[String(r["kind"])] = {"speed_permille": int(r["speed_permille"]),
				"fee_gold": int(r["fee_gold"]), "offered": int(r["offered"]) == 1}):
		return false
	if not _load_if_present(dir + "/ledger_lenses.csv", ["lens", "label", "instance_type"],
			func(r): ledger_lenses.append(r)):
		return false
	if not _load_if_present(dir + "/ledger_clusters.csv", ["cluster", "label", "colour", "x", "y", "z", "lens"],
			func(r): ledger_clusters.append({"cluster": String(r["cluster"]), "label": String(r["label"]),
				"colour": String(r["colour"]), "lens": String(r["lens"]),
				"at": Vector3(float(r["x"]), float(r["y"]), float(r["z"]))})):
		return false
	if not _load_if_present(dir + "/ledger_static_nodes.csv", ["node_id", "type_id", "label", "note"],
			func(r): ledger_static_nodes.append({"node_id": String(r["node_id"]), "type_id": String(r["type_id"]),
				"label": String(r["label"]), "note": String(r["note"])})):
		return false
	if not _load_if_present(dir + "/ledger_static_links.csv", ["link_id", "from", "to", "flow", "note"],
			func(r): ledger_static_links.append({"link_id": String(r["link_id"]), "from": String(r["from"]),
				"to": String(r["to"]), "flow": -1 if String(r["flow"]).strip_edges() == "" else int(r["flow"]),
				"note": String(r["note"])})):
		return false
	if not _load_if_present(dir + "/ledger_object_types.csv",
			["type_id", "layer", "lenses", "label", "icon", "x", "z", "instances", "status", "milestone",
				"cluster", "fold_to", "star"],
			func(r): ledger_types.append(r)):
		return false
	if not _load_if_present(dir + "/ledger_link_types.csv",
			["link_id", "from_type", "to_type", "verb", "lenses", "status", "resolver",
				"governor_seat", "governor_kind", "milestone", "planned_note", "look"],
			func(r): ledger_links.append(r)):
		return false
	if not _load_if_present(dir + "/ledger_actions.csv",
			["target", "action_code", "label", "params", "needs_map"],
			func(r): ledger_actions.append(r)):
		return false
	if not _load_if_present(dir + "/ledger_loops.csv", ["loop_id", "links", "kind", "running", "label"],
			func(r): ledger_loops.append(r)):
		return false
	if not _load_if_present(dir + "/ledger_palette.csv", ["key", "color"],
			func(r): ledger_palette[String(r["key"])] = Color(String(r["color"]))):
		return false
	if not _load_if_present(dir + "/ledger_governance.csv",
			["flow_type", "seat", "skill", "base_permille", "skill_mid", "skill_step_permille", "min_permille",
				"max_permille", "label", "books", "ledger_type"],
			func(r): ledger_governance[String(r["flow_type"])] = {"seat": String(r["seat"]),
				"skill": String(r["skill"]), "base_permille": int(r["base_permille"]),
				"skill_mid": int(r["skill_mid"]), "skill_step_permille": int(r["skill_step_permille"]),
				"min_permille": int(r["min_permille"]), "max_permille": int(r["max_permille"]),
				"label": String(r["label"]), "books": String(r["books"]) != "0",
				"ledger_type": String(r["flow_type"]) if String(r["ledger_type"]) == "" \
					else String(r["ledger_type"])}):
		return false
	if not _load_if_present(dir + "/courier_art.csv", ["kind", "size"],
			func(r): courier_art[String(r["kind"])] = r):
		return false
	if not _load_if_present(dir + "/road_speed.csv", ["key", "permille"],
			func(r): road_speed[String(r["key"])] = int(r["permille"])):
		return false
	if not _load_if_present(dir + "/weather.csv", ["kind", "speed_permille", "icon", "label"],
			func(r): weather_kinds[String(r["kind"])] = {"speed_permille": int(r["speed_permille"]),
				"icon": String(r["icon"]), "label": String(r["label"]),
				"overcast": float(r.get("overcast", 0)), "wet": float(r.get("wet", 0)),
				"mud": float(r.get("mud", 0)), "snow": float(r.get("snow", 0)),
				"rainfall": float(r.get("rainfall", 0)), "snowfall": float(r.get("snowfall", 0)),
				"gust": float(r.get("gust", 0))}):
		return false
	if not _load_if_present(dir + "/weather_odds.csv", ["season", "tier"], _add_weather_odds):
		return false
	if not _load_if_present(dir + "/intel_facts.csv", ["key", "label", "round_to", "tiers"],
			func(r): intel_facts[String(r["key"])] = {"label": String(r["label"]),
				"round_to": maxi(1, int(r["round_to"])),
				"tiers": String(r["tiers"]).split("|", false)}):
		return false
	if not _load_if_present(dir + "/spy_difficulty.csv", ["key", "permille"],
			func(r): spy_difficulty[String(r["key"])] = int(r["permille"])):
		return false
	if not _load_if_present(dir + "/army_orders.csv", ["action_code", "label", "hint"],
			func(r): army_orders.append({"action_code": String(r["action_code"]),
				"label": String(r["label"]), "hint": String(r["hint"]),
				"params": _order_params(String(r.get("params", "")))})):
		return false
	if not _load_if_present(dir + "/event_presenters.csv", ["key", "seat"],
			func(r): event_presenters[String(r["key"])] = String(r["seat"])):
		return false
	if not _load_if_present(dir + "/army_route_orders.csv", ["key", "label", "hint"],
			func(r): army_route_orders[String(r["key"])] = {"label": String(r["label"]),
				"hint": String(r["hint"])}):
		return false
	if not _load_if_present(dir + "/army_carry_loads.csv", ["days", "pace_permille", "label"],
			func(r): army_carry_loads.append({"days": int(r["days"]),
				"pace_permille": int(r["pace_permille"]), "label": String(r["label"])})):
		return false
	army_carry_loads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["days"]) < int(b["days"]))
	if not _load_if_present(dir + "/army_supply_orders.csv", ["key", "label", "hint"],
			func(r): army_supply_orders[String(r["key"])] = {"label": String(r["label"]),
				"hint": String(r["hint"])}):
		return false
	if not _load_if_present(dir + "/army_hostile_stances.csv", ["stance"],
			func(r): army_hostile_stances.append(String(r["stance"]))):
		return false
	if not _load_if_present(dir + "/battle_outcomes.csv",
			["tier", "eff_min", "eff_max", "attacker_loss_permille", "defender_loss_permille",
			"wounded_share_permille", "attacker_morale", "defender_morale", "rout"],
			func(r): battle_outcomes.append({"tier": String(r["tier"]),
				"eff_min": int(r["eff_min"]), "eff_max": int(r["eff_max"]),
				"attacker_loss_permille": int(r["attacker_loss_permille"]),
				"defender_loss_permille": int(r["defender_loss_permille"]),
				"wounded_share_permille": int(r["wounded_share_permille"]),
				"attacker_morale": int(r["attacker_morale"]),
				"defender_morale": int(r["defender_morale"]), "rout": String(r["rout"]),
				"siege": String(r.get("siege", ""))})):
		return false
	battle_outcomes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["eff_min"]) < int(b["eff_min"]))
	if not _load_if_present(dir + "/battle_stances.csv",
			["stance", "label", "defence_permille", "morale_decay_permille",
			"retreat_odds_permille", "retreats_on_contact"],
			func(r): battle_stances[String(r["stance"])] = {"label": String(r["label"]),
				"defence_permille": int(r["defence_permille"]),
				"morale_decay_permille": int(r["morale_decay_permille"]),
				"retreat_odds_permille": int(r["retreat_odds_permille"]),
				"retreats_on_contact": int(r["retreats_on_contact"]) == 1}):
		return false
	if not _load_if_present(dir + "/ai_doctrines.csv",
			["role", "greed_permille", "caution_permille", "dist_cost", "engage_odds_permille",
			"retreat_morale", "town_bonus"],
			func(r): ai_doctrines[String(r["role"])] = {"greed_permille": int(r["greed_permille"]),
				"caution_permille": int(r["caution_permille"]), "dist_cost": int(r["dist_cost"]),
				"engage_odds_permille": int(r["engage_odds_permille"]),
				"retreat_morale": int(r["retreat_morale"]), "town_bonus": int(r["town_bonus"])}):
		return false
	if not _load_if_present(dir + "/army_formations.csv", ["figures", "min_fit_permille", "slots"],
			func(r):
				var slots: Array = []
				for part: String in String(r["slots"]).split("|"):
					var xy := part.split(":")
					slots.append(Vector2(float(xy[0]), float(xy[1])))
				army_formations.append({"figures": int(r["figures"]),
					"min_fit_permille": int(r["min_fit_permille"]), "slots": slots})):
		return false
	army_formations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["min_fit_permille"]) < int(b["min_fit_permille"]))
	if not _load_if_present(dir + "/war_palette.csv", ["key", "color"],
			func(r): war_palette[String(r["key"])] = Color(String(r["color"]))):
		return false
	if not _load_if_present(dir + "/war_drills.csv", ["key", "clip", "label", "arms"],
			func(r): war_drills.append({"key": String(r["key"]), "clip": String(r["clip"]),
				"label": String(r["label"]), "arms": PackedStringArray(String(r["arms"]).split("|", false))})):
		return false
	# war_equipment.csv: one row per piece of kit the folio's exploded view names;
	# part = the object's name in assets/3D/units/<arm>/<arm>_parts.glb; note is
	# SHOWN to the player, so it is a plain description, never empty, never a design note.
	if not _load_if_present(dir + "/war_equipment.csv", ["arm", "part", "label", "note"],
			func(r): war_equipment.append({"arm": String(r["arm"]), "part": String(r["part"]),
				"label": String(r["label"]), "note": String(r["note"])})):
		return false
	if not _load_if_present(dir + "/war_folio_sections.csv", ["key", "label"],
			func(r): war_folio_sections.append({"key": String(r["key"]), "label": String(r["label"])})):
		return false
	if not _load_if_present(dir + "/war_order_words.csv", ["key", "word"],
			func(r): war_order_words[String(r["key"])] = String(r["word"])):
		return false
	if not _load_if_present(dir + "/army_height_supply.csv", ["tier", "min_height", "supply_permille"],
			func(r): army_height_supply.append({"tier": String(r["tier"]),
				"min_height": int(r["min_height"]), "supply_permille": int(r["supply_permille"])})):
		return false
	army_height_supply.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["min_height"]) > int(b["min_height"]))
	if not _load_if_present(dir + "/army_morale_words.csv", ["min_score", "word"],
			func(r): army_morale_words.append({"min_score": int(r["min_score"]), "word": String(r["word"])})):
		return false
	army_morale_words.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["min_score"]) > int(b["min_score"]))
	if not _load_if_present(dir + "/workshop_rates.csv", ["rate_permille", "word", "ledger_label"],
			func(r): workshop_rates.append({"rate_permille": int(r["rate_permille"]), "word": String(r["word"]),
				"ledger_label": String(r["ledger_label"])})):
		return false
	workshop_rates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["rate_permille"]) < int(b["rate_permille"]))
	if not _load_if_present(dir + "/building_inputs.csv", ["building_code", "good_code", "units"],
			func(r):
				var code := String(r["building_code"])
				if not building_inputs.has(code):
					building_inputs[code] = []
				(building_inputs[code] as Array).append({"good": String(r["good_code"]), "units": int(r["units"])})):
		return false
	if not _load_if_present(dir + "/landmark_names.csv", ["kind", "pattern"],
			func(r):
				var k := String(r["kind"])
				if not landmark_names.has(k):
					landmark_names[k] = []
				(landmark_names[k] as Array).append(String(r["pattern"]))):
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
	MapEconomy.forget()
	RealmEconomy.forget()
	ManorEconomy.forget()
	MapPalette.forget_colors()
	HouseArms.forget()
	Elevation.forget()
	Weather.forget()
	RoadGraph.forget()
	ArmySystem.forget_grids()
	WarSheets.forget()
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
	arms_bindings.clear()
	manors.clear()
	manor_by_code.clear()
	manor_by_label.clear()
	landmark_name_overrides.clear()
	world_tables.clear()
	deals.clear()
	raid_hosts.clear()
	MarketSystem.forget()
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
	if not _load_if_present(dir + "/economy/deals.csv",
			["seller_type", "seller", "buyer_type", "buyer", "good_code", "units", "price"],
			func(r: Dictionary) -> void:
				deals.append({"seller_type": String(r["seller_type"]), "seller": String(r["seller"]),
					"buyer_type": String(r["buyer_type"]), "buyer": String(r["buyer"]),
					"good": String(r["good_code"]), "units": float(r["units"]), "price": float(r["price"])})):
		return false
	if not _load_if_present(dir + "/military/raid_hosts.csv",
			["host_code", "regiments", "appear_day", "role", "start_x", "start_y"],
			func(r: Dictionary) -> void:
				raid_hosts.append({"host_code": String(r["host_code"]),
					"regiments": Array(String(r["regiments"]).split("|", false)),
					"appear_day": int(r["appear_day"]), "role": String(r["role"]),
					"start_x": int(float(r["start_x"])), "start_y": int(float(r["start_y"]))})):
		return false
	if not _load_if_present(dir + "/realm_bindings.csv", ["slot", "kingdom_code"],
			func(r): realm_bindings[r["slot"]] = r["kingdom_code"]):
		return false
	if not _load_if_present(dir + "/house_bindings.csv", ["family_name", "province_codes"],
			func(r: Dictionary) -> void:
				for pc in String(r["province_codes"]).split("|", false):
					house_bindings[pc] = String(r["family_name"])):
		return false
	if not _load_if_present(dir + "/arms_bindings.csv", ["key", "arms"],
			func(r: Dictionary) -> void:
				arms_bindings[String(r["key"])] = HouseArms.arms_path(String(r["arms"]))):
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
	if not _load_if_present(dir + "/landmark_name_overrides.csv", ["cell_id", "name"],
			func(r): landmark_name_overrides[int(r["cell_id"])] = String(r["name"])):
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
			event_choices, chapter_events, chapter_event_choices]:
		for r: Dictionary in rows:
			_fill_row_realms(r)
	# RANDOM_EVENTS.md scenes are loaded before any map is, so they are filled
	# here rather than at parse time — and from the authored copy, so swapping
	# packs mid-session re-fills rather than compounding.
	for id: String in event_scenes_authored:
		event_scenes[id] = fill_realms(String(event_scenes_authored[id]))

## Every choice the engine may resolve — the random pool's and the scripted
## chapters'. Concatenated on the spot rather than cached, so a test fixture
## that replaces `event_choices` wholesale is still the truth the engine reads.
func event_choices_all() -> Array[Dictionary]:
	return event_choices + chapter_event_choices


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

func _add_weather_odds(r: Dictionary) -> void:
	var w: Dictionary = {}
	for kind: String in weather_kinds:
		w[kind] = int(r.get(kind, "0"))
	weather_odds["%s|%s" % [String(r["season"]), String(r["tier"])]] = w

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

## An order row's `key=value|key=value` params as a Dictionary of strings.
static func _order_params(text: String) -> Dictionary:
	var out: Dictionary = {}
	for pair: String in text.split("|", false):
		var kv := pair.split("=", true, 1)
		if kv.size() == 2 and kv[0].strip_edges() != "":
			out[kv[0].strip_edges()] = kv[1].strip_edges()
	return out

func bal(key: String) -> float:
	assert(balance.has(key), "balance.csv missing key: " + key)
	return balance[key]
