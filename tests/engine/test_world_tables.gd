extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The Azgaar export's economic, military, political, and social data, imported
## into domain folders under the pack (spec 2026-09-09 §1). Nothing here names
## a kingdom: everything hangs off the realm the pack binds player_realm to.

var repo: DataRepository

func before_all() -> void:
	repo = SuiteData.repo()
	assert_not_null(repo, DataRepository.last_error)

func _player() -> String:
	return repo.resolve_realm("player_realm")

func test_every_domain_table_loads() -> void:
	for spec in [["geography", "biomes"], ["geography", "rivers"], ["geography", "markers"],
			["geography", "routes"], ["political", "kingdoms"], ["political", "provinces"],
			["political", "burgs"], ["political", "diplomacy"], ["political", "campaigns"],
			["economy", "kingdoms"], ["economy", "provinces"], ["economy", "burgs"],
			["economy", "goods"], ["economy", "markets"], ["economy", "market_goods"],
			["economy", "production"], ["military", "kingdoms"], ["military", "regiments"],
			["military", "unit_types"], ["society", "cultures"], ["society", "religions"],
			["society", "zones"]]:
		assert_gt(repo.world_table(spec[0], spec[1]).size(), 0,
			"%s/%s.csv loaded" % [spec[0], spec[1]])

## The old named fields and the domain store are one set of rows, not copies.
func test_named_tables_share_rows_with_world_tables() -> void:
	assert_true(is_same(repo.world_table("political", "kingdoms"), repo.kingdoms))
	assert_true(is_same(repo.world_table("political", "provinces"), repo.provinces))
	assert_true(is_same(repo.world_table("political", "burgs"), repo.burgs))
	assert_true(is_same(repo.world_table("geography", "routes"), repo.routes))
	assert_true(is_same(repo.world_table("geography", "rivers"), repo.rivers))
	assert_true(is_same(repo.world_table("geography", "markers"), repo.markers))
	assert_true(is_same(repo.world_table("geography", "biomes"), repo.biomes))

func test_kingdoms_carry_form_culture_and_religion() -> void:
	var k: Dictionary = repo.kingdoms[_player()]
	assert_ne(String(k["form"]), "", "government form")
	assert_ne(String(k["form_name"]), "", "form name")
	assert_true(repo.world_table("society", "cultures").has(String(k["culture_code"])),
		"culture resolves")
	assert_true(repo.world_table("society", "religions").has(String(k["religion_code"])),
		"majority religion resolves")

func test_economy_rows_reference_real_places() -> void:
	for code: String in repo.world_table("economy", "kingdoms"):
		assert_true(repo.kingdoms.has(code), "economy kingdom %s" % code)
	for code: String in repo.world_table("economy", "provinces"):
		assert_true(repo.provinces.has(code), "economy province %s" % code)
	for code: String in repo.world_table("economy", "burgs"):
		assert_true(repo.burgs.has(code), "economy burg %s" % code)
	var goods: Dictionary = repo.world_table("economy", "goods")
	for key: String in repo.world_table("economy", "production"):
		var row: Dictionary = repo.world_table("economy", "production")[key]
		assert_true(repo.burgs.has(String(row["burg_code"])), "production burg %s" % key)
		assert_true(goods.has(String(row["good_code"])), "production good %s" % key)
	for key: String in repo.world_table("economy", "market_goods"):
		var row: Dictionary = repo.world_table("economy", "market_goods")[key]
		assert_true(repo.world_table("economy", "markets").has(String(row["market_id"])),
			"market %s" % key)
		assert_true(goods.has(String(row["good_code"])), "market good %s" % key)

func test_player_realm_has_economy_and_military_rows() -> void:
	var e: Dictionary = repo.world_row("economy", "kingdoms", _player())
	assert_false(e.is_empty(), "economy row")
	assert_gt(float(e["treasury"]), 0.0)
	assert_gt(float(e["poll_tax"]), 0.0)
	assert_gt(int(e["rural_population"]), 0)
	var m: Dictionary = repo.world_row("military", "kingdoms", _player())
	assert_false(m.is_empty(), "military row")
	assert_gt(int(m["regiments"]), 0)
	assert_gt(float(m["strength"]), 0.0)

func test_military_totals_equal_the_sum_of_regiments() -> void:
	var units: Array = repo.world_table("military", "unit_types").keys()
	assert_gt(units.size(), 0, "unit types imported")
	for code: String in repo.world_table("military", "kingdoms"):
		var row: Dictionary = repo.world_row("military", "kingdoms", code)
		var sums: Dictionary = {}
		var n := 0
		for rc: String in repo.world_table("military", "regiments"):
			var r: Dictionary = repo.world_row("military", "regiments", rc)
			if String(r["kingdom_code"]) != code:
				continue
			n += 1
			for u: String in units:
				sums[u] = int(sums.get(u, 0)) + int(r[u])
		assert_eq(int(row["regiments"]), n, "%s regiment count" % code)
		for u: String in units:
			assert_eq(int(row[u]), int(sums.get(u, 0)), "%s %s" % [code, u])

func test_diplomacy_lists_every_ordered_pair_once() -> void:
	var dip: Dictionary = repo.world_table("political", "diplomacy")
	var n := repo.kingdoms.size()
	assert_eq(dip.size(), n * (n - 1), "every ordered pair of kingdoms")
	for key: String in dip:
		var row: Dictionary = dip[key]
		assert_true(repo.kingdoms.has(String(row["kingdom_code"])))
		assert_true(repo.kingdoms.has(String(row["other_code"])))
		assert_ne(String(row["kingdom_code"]), String(row["other_code"]))
		assert_ne(String(row["stance"]), "")

func test_zones_name_real_provinces_and_kingdoms() -> void:
	for code: String in repo.world_table("society", "zones"):
		var z: Dictionary = repo.world_row("society", "zones", code)
		for p: String in String(z["province_codes"]).split("|", false):
			assert_true(repo.provinces.has(p), "zone %s province %s" % [code, p])
		for k: String in String(z["kingdom_codes"]).split("|", false):
			assert_true(repo.kingdoms.has(k), "zone %s kingdom %s" % [code, k])

func test_burgs_carry_group_and_culture() -> void:
	var realm: Dictionary = repo.kingdoms[_player()]
	var k: Dictionary = repo.burgs[String(realm["capital_burg"])]
	assert_eq(String(k["group"]), "capital")
	assert_true(repo.world_table("society", "cultures").has(String(k["culture_code"])))

func test_absent_table_reads_as_empty() -> void:
	assert_eq(repo.world_table("economy", "no_such_area"), {})
	assert_eq(repo.world_row("economy", "kingdoms", "no_such_kingdom"), {})

## house_bindings.csv binds the court's houses to provinces of the player's
## realm (spec addendum 2026-09-09): every code must be real and start in the
## player's realm, every house must be a house of the roster.
func test_house_bindings_name_real_land_of_the_realm_and_real_houses() -> void:
	assert_false(repo.house_bindings.is_empty(), "the pack binds houses")
	var houses: Dictionary = {}
	for role in repo.roles:
		houses[String(role.get("family_name", ""))] = true
	for code: String in repo.house_bindings:
		assert_true(repo.provinces.has(code), "%s is a province" % code)
		assert_eq(String(repo.provinces[code]["kingdom_code"]), _player(),
			"%s starts in the player's realm" % code)
		assert_true(houses.has(String(repo.house_bindings[code])),
			"%s is a house of the roster" % String(repo.house_bindings[code]))

func test_regiments_stand_in_a_province_of_their_kingdom() -> void:
	for code: String in repo.world_table("military", "regiments"):
		var r: Dictionary = repo.world_row("military", "regiments", code)
		var pc := String(r.get("province_code", ""))
		assert_true(repo.provinces.has(pc), "%s stands in a province" % code)
		assert_eq(String(repo.provinces[pc]["kingdom_code"]), String(r["kingdom_code"]),
			"%s stands on its own kingdom's land" % code)

func test_provinces_carry_a_majority_biome() -> void:
	for code: String in repo.provinces:
		var bid := int(float(repo.provinces[code].get("biome_id", "0")))
		assert_true(repo.biomes.has(bid), "%s has a named biome" % code)
