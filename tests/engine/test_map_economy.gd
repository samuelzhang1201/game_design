extends GutTest
## MapEconomy: production summed per province and per realm, over tiny
## fixture repos with hand-countable numbers.

func _repo() -> DataRepository:
	var r := DataRepository.new()
	r.burgs = {
		"a": {"burg_code": "a", "province_code": "p1"},
		"b": {"burg_code": "b", "province_code": "p1"},
		"c": {"burg_code": "c", "province_code": "p2"},
		"orphan": {"burg_code": "orphan", "province_code": ""},
	}
	r.provinces = {
		"p1": {"province_code": "p1", "kingdom_code": "k"},
		"p2": {"province_code": "p2", "kingdom_code": "k"},
	}
	# set_owner refuses a kingdom the pack does not know, so the fixture has
	# somewhere for the conquered province to go.
	r.kingdoms = {"k": {"kingdom_code": "k", "state_id": "1"},
		"other": {"kingdom_code": "other", "state_id": "2"}}
	r.world_tables = {"economy": {
		"goods": {
			"grain": {"good_code": "grain", "label": "Grain", "tags": "food"},
			"iron": {"good_code": "iron", "label": "Iron", "tags": "ore|military"},
			"wine": {"good_code": "wine", "label": "Wine", "tags": "food|luxury"},
		},
		"production": {
			"a:grain": {"burg_code": "a", "good_code": "grain", "units": "10"},
			"b:grain": {"burg_code": "b", "good_code": "grain", "units": "5"},
			"a:iron": {"burg_code": "a", "good_code": "iron", "units": "4"},
			"c:wine": {"burg_code": "c", "good_code": "wine", "units": "7"},
			"orphan:iron": {"burg_code": "orphan", "good_code": "iron", "units": "99"},
			"ghost:iron": {"burg_code": "ghost", "good_code": "iron", "units": "99"},
		},
	}}
	MapEconomy.forget()
	return r

func test_a_province_sums_the_burgs_inside_it() -> void:
	var out := MapEconomy.province_output(_repo())
	assert_eq(out["p1"]["grain"], 15.0, "10 from a, 5 from b")
	assert_eq(out["p1"]["iron"], 4.0)
	assert_eq(out["p2"]["wine"], 7.0)

func test_production_from_a_burg_with_no_province_is_dropped() -> void:
	var out := MapEconomy.province_output(_repo())
	for province: String in out:
		assert_false(out[province].has("iron") and out[province]["iron"] > 50.0,
			"the orphan's 99 iron went nowhere, and so did the unknown burg's")

func test_the_dominant_good_carries_its_share_of_the_province() -> void:
	var repo := _repo()
	var d := MapEconomy.dominant(repo, "p1")
	assert_eq(String(d["good"]), "grain")
	assert_eq(d["units"], 15.0)
	assert_almost_eq(float(d["share"]), 15.0 / 19.0, 0.0001, "15 of the 19 p1 makes")
	assert_eq(MapEconomy.dominant(repo, "nowhere"), {}, "a province that makes nothing")

func test_a_realm_sums_the_provinces_it_holds_now() -> void:
	var repo := _repo()
	var state := GameState.new()
	var out := MapEconomy.realm_output(repo, state, "k")
	assert_eq(out.size(), 3)
	assert_eq(String(out[0]["good"]), "grain", "biggest first")
	assert_eq(out[0]["units"], 15.0)
	assert_eq(String(out[0]["label"]), "Grain", "labelled from the goods table")
	# Lose p1 and the grain and iron go with it.
	MapOwnership.set_owner(repo, state, "p1", "other", "a test conquest")
	var after := MapEconomy.realm_output(repo, state, "k")
	assert_eq(after.size(), 1, "only p2's wine is left")
	assert_eq(String(after[0]["good"]), "wine")

func test_a_good_is_filed_under_its_first_tag() -> void:
	var repo := _repo()
	assert_eq(MapEconomy.good_tag(repo, "iron"), "ore")
	assert_eq(MapEconomy.good_tag(repo, "grain"), "food")
	assert_eq(MapEconomy.good_tag(repo, "nothing"), "")

## --- Manors ---------------------------------------------------------------
## Two 10x10 land squares side by side and a water square east of them:
##   cell 0 [0..10] forest (habitability 100), cell 1 [10..20] grassland (30),
##   cell 2 [20..30] ocean.
## a (2,3) and b (8,7) stand in cell 0, c (15,5) in cell 1, and the orphan at
## (21,5) just off the shore, in the water.
func _cell(ids: Array, biome: int, water: String) -> Dictionary:
	return {"vertex_ids": PackedInt32Array(ids), "neighbor_ids": PackedInt32Array(),
		"height": 5.0 if water != "" else 40.0, "biome_id": biome, "water": water}

func _manor_repo() -> DataRepository:
	var r := _repo()
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 10), 3: Vector2(0, 10),
		4: Vector2(20, 0), 5: Vector2(20, 10), 6: Vector2(30, 0), 7: Vector2(30, 10)}
	r.cells = {
		0: _cell([0, 1, 2, 3], 6, ""),
		1: _cell([1, 4, 5, 2], 4, ""),
		2: _cell([4, 6, 7, 5], 0, "ocean"),
	}
	r.biomes = {6: {"habitability": "100"}, 4: {"habitability": "30"}, 0: {"habitability": "0"}}
	for pos: Array in [["a", 2, 3], ["b", 8, 7], ["c", 15, 5], ["orphan", 21, 5]]:
		(r.burgs[pos[0]] as Dictionary).merge({"x": str(pos[1]), "y": str(pos[2])})
	return r

func test_a_burg_stands_in_the_land_cell_that_holds_its_point() -> void:
	var cells := MapEconomy.burg_cells(_manor_repo())
	assert_eq(cells["a"], 0)
	assert_eq(cells["b"], 0)
	assert_eq(cells["c"], 1)
	assert_eq(cells["orphan"], 1,
		"a burg just off the shore belongs to the nearest land cell, never the water")

func test_a_manor_gathers_what_its_settlements_make() -> void:
	var manors := MapEconomy.manors(_manor_repo())
	assert_eq(manors.size(), 2, "two working manors; the water cell has none")
	var home: Dictionary = manors[0]
	assert_eq(home["burgs"], ["a", "b"])
	assert_eq(home["goods"]["grain"], 15.0, "10 from a, 5 from b")
	assert_eq(String(home["good"]), "grain", "its chief good")
	assert_eq(home["units"], 15.0)
	assert_eq(home["total"], 19.0, "15 grain and 4 iron")
	var east: Dictionary = manors[1]
	assert_eq(String(east["good"]), "iron", "the orphan's 99 iron outweighs c's 7 wine")
	assert_eq(east["total"], 106.0)

func test_a_manors_land_value_is_its_biomes_habitability() -> void:
	var repo := _manor_repo()
	assert_almost_eq(MapEconomy.land_value(repo, repo.cells[0]), 1.0, 0.0001)
	assert_almost_eq(MapEconomy.land_value(repo, repo.cells[1]), 0.3, 0.0001)
	assert_eq(MapEconomy.land_value(repo, {"biome_id": 99}), 0.0, "an unknown biome is worthless")
