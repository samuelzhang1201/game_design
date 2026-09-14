extends GutTest
## Map packs (data/maps.csv + data/maps/<id>/). Authored content names realm
## SLOTS, never the kingdom codes a particular Azgaar export generated, so a
## new map is a data drop rather than a content rewrite.

func _fresh() -> DataRepository:
	var repo := DataRepository.load_all("res://data")
	assert_not_null(repo, "data load failed: " + DataRepository.last_error)
	return repo

func test_default_pack_loads_with_its_world_and_art() -> void:
	var repo := _fresh()
	assert_eq(repo.map_id, repo.default_map_id(), "opens on the default pack")
	assert_false(repo.kingdoms.is_empty(), "pack supplies kingdoms")
	assert_false(repo.provinces.is_empty(), "pack supplies provinces")
	assert_false(repo.burgs.is_empty(), "pack supplies burgs")
	assert_true(ResourceLoader.exists(repo.index_texture_path),
		"hit-test bitmap exists: " + repo.index_texture_path)
	# The sea's distance field (2026-09-13) is baked by the importer beside
	# the index bitmaps, at the canvas size, so the bands line up with the land.
	assert_true(ResourceLoader.exists(repo.sea_texture_path),
		"sea distance field exists: " + repo.sea_texture_path)
	var field: Image = (load(repo.sea_texture_path) as Texture2D).get_image()
	assert_eq(field.get_width(), int(repo.map_info["width"]), "field is canvas-wide")
	assert_eq(field.get_height(), int(repo.map_info["height"]), "field is canvas-high")

func test_every_binding_points_at_a_kingdom_this_pack_has() -> void:
	var repo := _fresh()
	assert_false(repo.realm_bindings.is_empty(), "pack binds its realm slots")
	for slot: String in repo.realm_bindings:
		var code := String(repo.realm_bindings[slot])
		assert_true(repo.kingdoms.has(code),
			"slot '%s' binds to '%s', which must exist on this map" % [slot, code])

## The point of the whole exercise: authored rows carry a slot, and what the
## engine sees downstream is a concrete kingdom_code from the loaded pack.
func test_authored_realms_resolve_through_the_pack() -> void:
	var repo := _fresh()
	var player := {}
	for r in repo.roles:
		if String(r["id"]) == "you":
			player = r
	assert_false(player.is_empty(), "roles.csv has the player")
	assert_eq(String(player["kingdom_slot"]), "player_realm",
		"the authored value is a slot, not a map's kingdom code")
	assert_eq(String(player["kingdom"]), repo.resolve_realm("player_realm"),
		"what the engine reads is the resolved code")
	assert_true(repo.kingdoms.has(String(player["kingdom"])),
		"and that code is a real kingdom on this map")

## Regression guard. If someone re-introduces a literal kingdom code into an
## authored CSV, swapping maps silently orphans that row — catch it here.
func test_no_authored_csv_names_a_map_kingdom_directly() -> void:
	var repo := _fresh()
	for spec in [["res://data/roles.csv", "kingdom"],
			["res://data/founding_council.csv", "kingdom"],
			["res://data/facts.csv", "subject"]]:
		var rows := DataRepository.parse_csv(String(spec[0]), [String(spec[1])])
		for r in rows:
			var v := String(r[String(spec[1])])
			assert_false(repo.kingdoms.has(v),
				"%s: '%s' is a raw kingdom code from this map — use a realm slot"
					% [String(spec[0]).get_file(), v])

## Re-resolving must read the pristine authored slot, never a code a previous
## map already resolved, or the second map swap would silently keep map one's
## realms.
func test_reloading_a_pack_re_resolves_from_the_authored_slot() -> void:
	var repo := _fresh()
	assert_true(repo.load_map(repo.map_id), "same pack reloads")
	var player := {}
	for r in repo.roles:
		if String(r["id"]) == "you":
			player = r
	assert_eq(String(player["kingdom_slot"]), "player_realm",
		"the slot survives resolution and stays re-resolvable")
	assert_true(repo.kingdoms.has(String(player["kingdom"])),
		"and still resolves to a real kingdom")

## Prose says {raider_realm}, never a kingdom's name, so a re-export that
## renames the world touches realm_bindings.csv and nothing else.
func test_realm_tokens_in_prose_fill_from_the_pack() -> void:
	var repo := _fresh()
	var raider := repo.realm_label("raider_realm")
	assert_ne(raider, "raider_realm", "the slot resolves to a real label")
	assert_eq(repo.fill_realms("{raider_realm} musters."), "%s musters." % raider)
	assert_eq(repo.fill_realms("no tokens here"), "no tokens here",
		"text without tokens is returned untouched")
	assert_eq(repo.fill_realms("It is {season} of year {year}."),
		"It is {season} of year {year}.",
		"non-realm placeholders are left for their own formatter")
	assert_eq(repo.fill_realms("{not_a_slot}"), "{not_a_slot}",
		"an unknown token is left alone rather than blanked")

## The muster fact is authored with a token; what the engine hands the UI is
## the bound kingdom's name.
func test_authored_prose_reaches_the_engine_already_filled() -> void:
	var repo := _fresh()
	var muster := {}
	for r in repo.facts:
		if String(r["fact_code"]) == "fact_raider_muster":
			muster = r
	assert_false(muster.is_empty(), "facts.csv still carries the muster fact")
	assert_string_contains(String(muster["_authored"]["text"]), "{raider_realm}")
	assert_string_contains(String(muster["text"]), repo.realm_label("raider_realm"))
	assert_false(String(muster["text"]).contains("{"), "no token survives to the UI")

## Filling must start from the authored text every time, or a second pack
## would substitute into map one's already-substituted prose.
func test_reloading_a_pack_refills_prose_from_the_authored_text() -> void:
	var repo := _fresh()
	assert_true(repo.load_map(repo.map_id), "same pack reloads")
	for r in repo.facts:
		if String(r["fact_code"]) == "fact_raider_muster":
			assert_eq(String(r["text"]), "%s is massing for a raid eastward."
				% repo.realm_label("raider_realm"))

## maps.csv carries a free-text notes column; an unquoted comma in it once
## shifted every column after it, silently reading the notes tail as the
## next column. Every row must parse to the full header width.
func test_maps_csv_rows_parse_to_the_full_header() -> void:
	var f := FileAccess.open("res://data/maps.csv", FileAccess.READ)
	assert_not_null(f, "maps.csv opens")
	var header := f.get_csv_line()
	var seen := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() == 1 and String(row[0]).strip_edges() == "":
			continue
		seen += 1
		assert_eq(row.size(), header.size(),
			"row '%s' has %d fields for %d columns — quote any field with a comma"
				% [row[0], row.size(), header.size()])
	assert_gt(seen, 0, "maps.csv lists at least one pack")

func test_unknown_map_fails_loudly() -> void:
	var repo := _fresh()
	var before := repo.map_id
	assert_false(repo.load_map("no_such_map"), "refuses an uninstalled pack")
	assert_ne(DataRepository.last_error, "", "and says why")
	assert_eq(repo.map_id, before, "leaving the loaded pack untouched")

## The save names its world (SAVE_VERSION 2): reloading must restore the same
## map, not whichever one happens to be default.
func test_save_carries_the_map_id() -> void:
	Game.start_campaign(42)
	assert_eq(Game.state.map_id, Game.data.map_id, "a campaign records its map")
	var round_tripped := GameState.from_dict(Game.state.to_dict())
	assert_eq(round_tripped.map_id, Game.state.map_id, "and it survives the save")

## The manor system (MANOR_SYSTEM.md §1): the pack names every land cell
## once, codes and labels are unique, a burg's cell carries the burg's name,
## and the cell index returns each land cell's id under its centre.
func test_the_pack_names_every_land_cell_as_a_manor() -> void:
	var repo := _fresh()
	var land := 0
	for id: int in repo.cells:
		if not MapTerrain.is_water(repo.cells[id]):
			land += 1
			assert_true(repo.manors.has(id), "cell %d has a manor row" % id)
	assert_eq(repo.manors.size(), land, "one manor per land cell, none for water")
	var labels: Dictionary = {}
	for id: int in repo.manors:
		var row: Dictionary = repo.manors[id]
		var label := String(row["label"]).to_lower()
		assert_false(labels.has(label), "unique label: " + label)
		labels[label] = true
		assert_eq(repo.manor_by_code[String(row["manor_code"])], id)
		assert_eq(repo.manor_by_label[label], id)
		var burg := String(row["burg_code"])
		if burg != "":
			assert_true(String(row["label"]).begins_with(String(repo.burgs[burg]["label"])),
				"%s is named after its burg" % row["label"])
	assert_eq(repo.manor_by_code.size(), repo.manors.size(), "codes are unique")

func test_the_cell_index_finds_each_land_cell_under_its_centre() -> void:
	var repo := _fresh()
	assert_true(ResourceLoader.exists(repo.cell_texture_path), "cell index exists: " + repo.cell_texture_path)
	var img: Image = (load(repo.cell_texture_path) as Texture2D).get_image()
	assert_eq(img.get_width(), int(repo.map_info["width"]))
	assert_eq(img.get_height(), int(repo.map_info["height"]))
	var checked := 0
	var hits := 0
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell):
			continue
		checked += 1
		if MapIndex.id_at(img, Vector2i(MapTerrain.cell_center(repo, cell).floor())) == id:
			hits += 1
	# A centroid can fall outside a very concave cell; nearly all land in.
	assert_gt(float(hits) / float(checked), 0.97, "%d of %d centres decode to their cell" % [hits, checked])

## The crown starts with the capital's province and nothing more (owner
## 2026-09-13): the king rules the realm, the crown holds one province.
func test_the_crown_starts_with_the_capitals_province_only() -> void:
	var repo := _fresh()
	var state := GameState.new_campaign(repo, 42)
	var realm: Dictionary = repo.kingdoms[repo.resolve_realm("player_realm")]
	var capital_province := String(repo.burgs[String(realm["capital_burg"])]["province_code"])
	assert_eq(MapManors.controlled_provinces(repo, state), [capital_province])
	assert_gt(MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")).size(), 1,
		"the realm itself is larger")
	assert_gt(state.metrics["treasury"], 0.0, "seeded from the capital province's towns")
	assert_almost_eq(state.metrics["treasury"],
		roundf(WorldLedger.crown_town_treasury(repo, state) * repo.bal("pack_treasury_scale")), 0.001)

## data/manor_focus.csv (owner 2026-09-13): every focus names a good the
## pack trades and biomes the pack has, and every manor of the capital's
## province can work something.
func test_the_manor_focus_table_fits_the_pack() -> void:
	var repo := _fresh()
	assert_gt(repo.manor_focus.size(), 5, "a real choice of chief goods")
	for code: String in repo.manor_focus:
		var row: Dictionary = repo.manor_focus[code]
		assert_false(repo.world_row("economy", "goods", String(row["good_code"])).is_empty(),
			"%s: the pack trades %s" % [code, String(row["good_code"])])
		var biomes := String(row["biomes"])
		if biomes != "any":
			for b: String in biomes.split("|"):
				assert_true(repo.biomes.has(int(b)), "%s: biome %s exists" % [code, b])
		assert_gt(float(row["yield_per_1000"]), 0.0)
	var state := GameState.new_campaign(repo, 42)
	for province: String in MapManors.controlled_provinces(repo, state):
		for cell: int in MapManors.manors_of_province(repo, province):
			assert_ne(MapManors.default_focus(repo, cell), "", "%s works something" % MapManors.label_of(repo, cell))

## On the real pack (owner 2026-09-14) the defaults spread the industries:
## the coast fishes, the hot desert grows dates, the heights quarry, the
## grassland lowlands run cattle — and no manor is left without a focus.
func test_default_focuses_follow_the_packs_terrain() -> void:
	var repo := _fresh()
	var counts: Dictionary = {}
	for id: int in repo.manors:
		var f := MapManors.default_focus(repo, id)
		assert_ne(f, "", "%s works something" % MapManors.label_of(repo, id))
		counts[f] = int(counts.get(f, 0)) + 1
		var cell: Dictionary = repo.cells[id]
		if MapManors.is_coastal(repo, id):
			assert_eq(f, "fish", "the coast fishes")
		elif float(cell["height"]) >= repo.bal("manor_focus_peak_height") and MapManors.focus_allowed(repo, id, "iron"):
			assert_eq(f, "iron")
		elif float(cell["height"]) >= repo.bal("manor_focus_high_height"):
			assert_eq(f, "stone")
		elif int(cell["biome_id"]) == 1:
			assert_eq(f, "dates")
		elif int(cell["biome_id"]) == 4:
			assert_eq(f, "cattle")
	assert_gte(counts.size(), 6, "six or more industries at the start: %s" % str(counts))
