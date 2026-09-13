extends GutTest
## MapManors (MANOR_SYSTEM.md): manors as units — held by a house, their
## people a share of their province's, buildings, rent and a price — with
## hand-computed values over a tiny fixture pack.
##
## Two land squares in province "p" (bound to House Valorin, seat Shole):
## cell 1 is 10x10 on rich land (value 0.8, weight 80), cell 2 is 20x10 on
## poor land (value 0.4, weight 80) and holds the burg Shole (1 000 people).
## Cell 3 is sea. Cell 4 is a manor in province "q", which is unbound, so
## its house is named after q's seat, the burg Wick.

func _repo() -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"manor_rent_per_1000": 0.4, "manor_price_per_1000": 40.0,
		"manor_price_per_unit": 2.0, "manor_price_building_ratio": 0.5,
		"manor_price_land_swing": 0.6, "manor_markup_max": 0.5, "manor_sell_ratio": 0.7,
		"manor_defence_base": 10.0}
	r.biomes = {1: {"habitability": "80"}, 2: {"habitability": "40"}}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 10), 3: Vector2(0, 10),
		4: Vector2(30, 0), 5: Vector2(30, 10), 6: Vector2(0, 20), 7: Vector2(10, 20),
		8: Vector2(50, 0), 9: Vector2(60, 0), 10: Vector2(60, 10), 11: Vector2(50, 10)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 30.0, "biome_id": 1,
			"water": "", "neighbor_ids": PackedInt32Array([2, 3])},
		2: {"vertex_ids": PackedInt32Array([1, 4, 5, 2]), "height": 30.0, "biome_id": 2,
			"water": "", "neighbor_ids": PackedInt32Array([1])},
		3: {"vertex_ids": PackedInt32Array([3, 2, 7, 6]), "height": 5.0, "biome_id": 0,
			"water": "ocean", "neighbor_ids": PackedInt32Array([1])},
		4: {"vertex_ids": PackedInt32Array([8, 9, 10, 11]), "height": 30.0, "biome_id": 1,
			"water": "", "neighbor_ids": PackedInt32Array()},
	}
	r.manors = {
		1: {"cell_id": 1, "manor_code": "ashcombe", "label": "Ashcombe", "province_code": "p",
			"burg_code": "", "culture_code": "c"},
		2: {"cell_id": 2, "manor_code": "shole_manor", "label": "Shole Manor", "province_code": "p",
			"burg_code": "shole", "culture_code": "c"},
		4: {"cell_id": 4, "manor_code": "farholt", "label": "Farholt", "province_code": "q",
			"burg_code": "", "culture_code": "c"},
	}
	for id: int in r.manors:
		r.manor_by_code[String(r.manors[id]["manor_code"])] = id
		r.manor_by_label[String(r.manors[id]["label"]).to_lower()] = id
	r.provinces = {
		"p": {"province_code": "p", "label": "Prov", "kingdom_code": "k", "capital_burg": "shole"},
		"q": {"province_code": "q", "label": "Quay", "kingdom_code": "k2", "capital_burg": "wick"},
	}
	r.burgs = {
		"shole": {"burg_code": "shole", "label": "Shole", "province_code": "p", "population": "1000"},
		"wick": {"burg_code": "wick", "label": "Wick", "province_code": "q", "population": "500"},
	}
	r.house_bindings = {"p": "Valorin"}
	r.manor_buildings = {
		"mill": {"building_code": "mill", "label": "Mill", "cost_gold": "40", "tax_bonus": "0.05",
			"output_bonus": "0.15", "defence_bonus": "0", "church_bonus": "0"},
		"palisade": {"building_code": "palisade", "label": "Palisade", "cost_gold": "45",
			"tax_bonus": "0", "output_bonus": "0", "defence_bonus": "10", "church_bonus": "0"},
	}
	r.world_schema = [
		{"path": "economy.provinces.*.rural_population", "type": "int", "min": "0",
			"max": "100000000", "enum_values": "", "good_direction": "1", "llm_cap": "2000",
			"alias_to": "", "alias_scale_key": ""},
		{"path": "economy.provinces.*.urban_population", "type": "int", "min": "0",
			"max": "100000000", "enum_values": "", "good_direction": "1", "llm_cap": "1000",
			"alias_to": "", "alias_scale_key": ""},
	]
	r._register_table("economy", "provinces", {
		"p": {"province_code": "p", "rural_population": "3000", "urban_population": "1000"},
		"q": {"province_code": "q", "rural_population": "800", "urban_population": "0"},
	})
	r._register_table("economy", "production", {})
	MapManors.invalidate()
	MapEconomy.forget()
	return r

func _state() -> GameState:
	var s := GameState.new()
	s.rng = Rng.new(1)
	s.tick = 3
	s.player_setup = {"first_name": "Anne", "family_name": "Rex", "flag": ""}
	var steward := Character.new()
	steward.id = "steward"
	steward.family_name = "Valorin"
	steward.opinion = 40
	s.characters["steward"] = steward
	s.council = {"steward": "steward"}
	var cousin := Character.new()
	cousin.id = "cousin"
	cousin.family_name = "Valorin"
	cousin.opinion = -80
	s.characters["cousin"] = cousin
	return s

func test_a_manor_is_named_and_placed_by_the_pack() -> void:
	var r := _repo()
	assert_true(MapManors.is_manor(r, 1))
	assert_false(MapManors.is_manor(r, 3), "the sea is no manor")
	assert_eq(MapManors.label_of(r, 1), "Ashcombe")
	assert_eq(MapManors.code_of(r, 2), "shole_manor")
	assert_eq(MapManors.province_of(r, 2), "p")
	assert_eq(MapManors.burg_of(r, 2), "shole")
	assert_eq(MapManors.manors_of_province(r, "p"), [1, 2])
	assert_eq(MapManors.manors_of_province(r, "none"), [])

func test_find_takes_a_code_a_label_or_a_number() -> void:
	var r := _repo()
	assert_eq(MapManors.find(r, "ashcombe"), 1, "code")
	assert_eq(MapManors.find(r, "Ashcombe"), 1, "label")
	assert_eq(MapManors.find(r, " ASHCOMBE manor "), 1, "any case, with the word")
	assert_eq(MapManors.find(r, "Shole"), 2, "a burg manor by its town's name")
	assert_eq(MapManors.find(r, "shole manor"), 2)
	assert_eq(MapManors.find(r, "2"), 2, "a cell id")
	assert_eq(MapManors.find(r, "Nowhere"), -1)
	assert_eq(MapManors.find(r, ""), -1)

func test_an_unmoved_manor_belongs_to_its_provinces_house() -> void:
	var r := _repo()
	var s := _state()
	assert_eq(MapManors.owner_of(r, s, 1), "Valorin", "the bound house")
	assert_eq(MapManors.owner_of(r, s, 4), "Wick", "an unbound province: the house of its seat")
	assert_eq(MapManors.crown(s), "Rex")
	assert_false(MapManors.is_crowns(r, s, 1))
	assert_eq(MapManors.holdings_of_province(r, s, "p"), {"Valorin": 2})

func test_set_owner_needs_a_manor_a_known_house_a_change_and_a_reason() -> void:
	var r := _repo()
	var s := _state()
	assert_false(MapManors.set_owner(r, s, 3, "Rex", "bought"), "the sea")
	assert_false(MapManors.set_owner(r, s, 1, "Nobody", "bought"), "an unknown house")
	assert_false(MapManors.set_owner(r, s, 1, "Valorin", "bought"), "already theirs")
	assert_false(MapManors.set_owner(r, s, 1, "Rex", "   "), "no reason")
	assert_true(s.manor_owner.is_empty(), "nothing moved")
	assert_true(MapManors.set_owner(r, s, 1, "Rex", "bought from House Valorin for 81 gold"))
	assert_eq(MapManors.owner_of(r, s, 1), "Rex")
	assert_true(MapManors.is_crowns(r, s, 1))
	assert_eq(s.manor_owner, {"1": "Rex"}, "sparse: only the moved manor")
	assert_eq(s.manor_log.size(), 1)
	assert_eq(s.manor_log[0], {"tick": 3, "cell": 1, "from": "Valorin", "to": "Rex",
		"reason": "bought from House Valorin for 81 gold"})
	assert_eq(MapManors.holdings_of_province(r, s, "p"), {"Valorin": 1, "Rex": 1})
	assert_eq(MapManors.manors_of_house(r, s, "Rex"), [1])
	assert_eq(MapManors.manors_of_house(r, s, "Rex", "k2"), [], "none in the other realm")
	assert_true(MapManors.set_owner(r, s, 1, "Wick", "sold on"), "a seat's house is known")
	assert_true(MapManors.is_known_house(r, s, "Valorin"))
	assert_false(MapManors.is_known_house(r, s, ""))

## Character creation renames the royal house; the pack still binds the
## demesne to the old name, so those manors are the crown's under the new.
func test_a_renamed_royal_house_keeps_its_manors() -> void:
	var r := _repo()
	var s := _state()
	s.player_setup["house_was"] = "Valorin"
	assert_eq(MapManors.owner_of(r, s, 1), "Rex", "bound to Valorin, which the crown was")
	assert_true(MapManors.is_crowns(r, s, 1))
	assert_eq(MapManors.owner_of(r, s, 4), "Wick", "another house is untouched")
	var you := Character.new()
	you.id = "you"
	you.family_name = "Regis"
	s.characters["you"] = you
	assert_eq(MapManors.crown(s), "Regis", "the player character's live name wins")

## Province p: 3 000 country folk split by weight (both 80 -> 1 500 each),
## 1 000 townsfolk to the one burg cell. The manors sum to the province.
func test_people_are_the_provinces_shared_by_land_and_town() -> void:
	var r := _repo()
	var s := _state()
	assert_almost_eq(MapManors.area_of(r, 1), 100.0, 0.001)
	assert_almost_eq(MapManors.area_of(r, 2), 200.0, 0.001)
	assert_almost_eq(MapManors.weight_of(r, 1), 80.0, 0.001)
	assert_almost_eq(MapManors.weight_of(r, 2), 80.0, 0.001)
	var a := MapManors.population_of(r, s, 1)
	var b := MapManors.population_of(r, s, 2)
	assert_almost_eq(float(a["rural"]), 1500.0, 0.001)
	assert_almost_eq(float(a["urban"]), 0.0, 0.001)
	assert_almost_eq(float(b["rural"]), 1500.0, 0.001)
	assert_almost_eq(float(b["urban"]), 1000.0, 0.001, "the burg's cell holds the town")
	assert_almost_eq(float(a["total"]) + float(b["total"]), 4000.0, 0.001, "the province entire")
	assert_almost_eq(float(MapManors.population_of(r, s, 4)["total"]), 800.0, 0.001)
	# The table reads each province once and agrees with the single reading.
	var table := MapManors.population_table(r, s, [1, 2, 4])
	assert_almost_eq(float(table[1]["rural"]), 1500.0, 0.001)
	assert_almost_eq(float(table[2]["urban"]), 1000.0, 0.001)
	assert_almost_eq(float(table[4]["total"]), 800.0, 0.001)
	assert_almost_eq(MapManors.rent_of(r, s, 2, 2500.0), MapManors.rent_of(r, s, 2), 0.0001,
		"a count handed in gives the same rent")
	# A ledger move on the province reaches its manors with nothing stored.
	WorldLedger.apply(r, s, "economy.provinces.p.rural_population", -1000.0, "plague", "test")
	assert_almost_eq(float(MapManors.population_of(r, s, 1)["rural"]), 1000.0, 0.001)

## Rent: 2 500 people / 1 000 x 0.4 = 1.0 a tick; a mill's 0.05 makes 1.05.
## Defence: 10 base, 20 with a palisade.
func test_buildings_rent_and_defence() -> void:
	var r := _repo()
	var s := _state()
	assert_almost_eq(MapManors.rent_of(r, s, 2), 1.0, 0.0001)
	assert_false(MapManors.build(r, s, 2, "castle", "raised"), "no such building")
	assert_false(MapManors.build(r, s, 2, "mill", ""), "no reason")
	assert_true(MapManors.build(r, s, 2, "mill", "raised a mill"))
	assert_false(MapManors.build(r, s, 2, "mill", "raised a mill"), "one mill per manor")
	assert_eq(MapManors.buildings_of(s, 2), ["mill"])
	assert_almost_eq(MapManors.rent_of(r, s, 2), 1.05, 0.0001)
	assert_almost_eq(MapManors.building_cost(r, s, 2), 40.0, 0.0001)
	assert_almost_eq(MapManors.defence_of(r, s, 2), 10.0, 0.0001)
	assert_true(MapManors.build(r, s, 2, "palisade", "dug in"))
	assert_almost_eq(MapManors.defence_of(r, s, 2), 20.0, 0.0001)
	assert_eq(s.manor_buildings, {"2": ["mill", "palisade"]})
	assert_eq(s.manor_log.size(), 2)
	assert_eq(String(s.manor_log[0]["building"]), "mill")

## Ashcombe: 1 500 people -> 60; no output, no buildings; land 0.8 ->
## x 1.18 = 70.8. House Valorin's steward sits on the council with opinion
## 40 (the cousin's -80 does not count while a councillor speaks for the
## house): coolness (100 - 40) / 200 = 0.3, markup 1.15 -> 81.42 -> 81.
## Selling back: 70.8 x 0.7 = 49.56 -> 50.
func test_the_price_is_the_value_marked_up_by_the_houses_coolness() -> void:
	var r := _repo()
	var s := _state()
	assert_eq(MapManors.house_opinion(r, s, "Valorin"), 40, "the councillor speaks for the house")
	assert_eq(MapManors.house_opinion(r, s, "Wick"), 0, "a house with no voice is neutral")
	assert_almost_eq(MapManors.base_value_of(r, s, 1), 70.8, 0.001)
	assert_almost_eq(MapManors.price_of(r, s, 1), 81.0, 0.001)
	assert_almost_eq(MapManors.sell_price_of(r, s, 1), 50.0, 0.001)
	# A hostile house asks the full markup: opinion -100 -> coolness 1 -> x 1.5.
	(s.characters["steward"] as Character).opinion = -100
	assert_almost_eq(MapManors.price_of(r, s, 1), 106.0, 0.001, "70.8 x 1.5 = 106.2")
	# Buildings raise the value by half their cost: a mill (40) adds 20 to
	# the base before the land factor.
	assert_true(MapManors.build(r, s, 1, "mill", "raised"))
	assert_almost_eq(MapManors.base_value_of(r, s, 1), (60.0 + 20.0) * 1.18, 0.001)

func test_manor_state_survives_a_save() -> void:
	var r := _repo()
	var s := _state()
	assert_true(MapManors.set_owner(r, s, 1, "Rex", "bought"))
	assert_true(MapManors.build(r, s, 1, "mill", "raised"))
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.manor_owner, {"1": "Rex"})
	assert_eq(back.manor_buildings, {"1": ["mill"]})
	assert_eq(back.manor_log.size(), 2)
	assert_eq(int(back.manor_log[0]["cell"]), 1)
	assert_eq(MapManors.owner_of(r, back, 1), "Rex")
	var before := s.to_dict()
	before.erase("manor_owner")
	before.erase("manor_buildings")
	before.erase("manor_log")
	var old := GameState.from_dict(JSON.parse_string(JSON.stringify(before)))
	assert_true(old.manor_owner.is_empty(), "a save without manors loads as nothing moved")
	assert_true(old.manor_log.is_empty())
