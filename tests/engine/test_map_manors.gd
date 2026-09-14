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

## Neighbouring provinces get different shade levels (owner 2026-09-13):
## cells 1 (p) and 4 (q) do not touch, so p and q may share a level; make
## them touch and they must not. shade() moves a colour by level.
func test_provinces_that_touch_take_different_shades() -> void:
	var r := _repo()
	assert_eq(MapManors.province_neighbours(r), {}, "p and q do not touch")
	var apart := MapManors.province_shades(r, 5)
	assert_eq(int(apart["p"]), 0)
	assert_eq(int(apart["q"]), 0, "apart, both take the first level")
	MapManors.invalidate()
	r.cells[2]["neighbor_ids"] = PackedInt32Array([1, 4])
	r.cells[4]["neighbor_ids"] = PackedInt32Array([2])
	var touching := MapManors.province_neighbours(r)
	assert_eq(touching["p"], ["q"])
	assert_eq(touching["q"], ["p"])
	var shades := MapManors.province_shades(r, 5)
	assert_ne(int(shades["p"]), int(shades["q"]), "touching, they differ")
	var base := Color(0.5, 0.5, 0.5, 0.8)
	assert_eq(MapManors.shade(base, 0, 0.1), base)
	assert_almost_eq(MapManors.shade(base, 1, 0.1).r, 0.55, 0.001, "1: a step lighter")
	assert_almost_eq(MapManors.shade(base, 2, 0.1).r, 0.45, 0.001, "2: a step darker")
	assert_almost_eq(MapManors.shade(base, 3, 0.1).r, 0.6, 0.001, "3: two steps lighter")
	assert_almost_eq(MapManors.shade(base, 2, 0.1).a, 0.8, 0.001, "alpha kept")

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

## Control (owner 2026-09-13): the house with the most manors in a province
## controls it; a tie goes to the province's own house. Buying one manor of
## two ties; buying both takes the province.
func test_the_house_with_most_manors_controls_the_province() -> void:
	var r := _repo()
	var s := _state()
	assert_eq(MapManors.controller_of(r, s, "p"), "Valorin")
	assert_eq(MapManors.controller_of(r, s, "q"), "Wick")
	assert_false(MapManors.crown_controls(r, s, "p"))
	assert_eq(MapManors.controlled_provinces(r, s), [])
	assert_true(MapManors.set_owner(r, s, 1, "Rex", "bought"))
	assert_eq(MapManors.controller_of(r, s, "p"), "Valorin", "one each: the province's own house keeps it")
	assert_true(MapManors.set_owner(r, s, 2, "Rex", "bought"))
	assert_eq(MapManors.controller_of(r, s, "p"), "Rex")
	assert_true(MapManors.crown_controls(r, s, "p"))
	assert_eq(MapManors.controlled_provinces(r, s), ["p"])
	assert_true(MapManors.set_owner(r, s, 1, "Wick", "sold"))
	assert_eq(MapManors.controller_of(r, s, "p"), "Rex",
		"a tie between strangers: the first by name")
	assert_true(MapManors.set_owner(r, s, 2, "Wick", "sold"))
	assert_eq(MapManors.controller_of(r, s, "p"), "Wick")
	assert_eq(MapManors.controlled_provinces(r, s), [], "and the crown lost it")

## The chief good (owner 2026-09-13). Focus rows are added here so the
## hand-computed prices and rents above stay as they were. Cell 1 (biome 1,
## touching the sea cell 3, 1 500 people, land 0.8) may work grain or fish;
## cell 2 (biome 2, inland) grain or ore; the default is the first allowed.
## Grain: 1.5 x 10 x 0.8 = 12 units. Switched to fish at tick 3 with two
## ticks to settle: 0 at tick 3, half of 1.5 x 8 x 0.8 = 9.6 at tick 4, all
## at tick 5. Rent on cell 2 (1.0 base) with grain's 0.1 bonus is 1.1.
func test_a_manor_works_a_chief_good_its_land_allows() -> void:
	var r := _repo()
	r.balance["manor_focus_yield_scale"] = 1.0
	r.manor_focus = {
		"grain": {"focus_code": "grain", "label": "Grain fields", "good_code": "grain", "biomes": "1|2",
			"coast": "0", "yield_per_1000": "10", "rent_bonus": "0.1", "switch_cost_gold": "20",
			"transition_ticks": "2"},
		"fish": {"focus_code": "fish", "label": "Fisheries", "good_code": "fish", "biomes": "any",
			"coast": "1", "yield_per_1000": "8", "rent_bonus": "0.05", "switch_cost_gold": "15",
			"transition_ticks": "2"},
		"ore": {"focus_code": "ore", "label": "Iron workings", "good_code": "iron", "biomes": "2",
			"coast": "0", "yield_per_1000": "2", "rent_bonus": "0.2", "switch_cost_gold": "60",
			"transition_ticks": "0"},
	}
	var s := _state()
	assert_true(MapManors.is_coastal(r, 1))
	assert_false(MapManors.is_coastal(r, 2))
	assert_eq(MapManors.focuses_for(r, 1), ["grain", "fish"])
	assert_eq(MapManors.focuses_for(r, 2), ["grain", "ore"])
	assert_eq(MapManors.focuses_for(r, 3), [], "the sea works nothing")
	assert_eq(MapManors.default_focus(r, 1), "grain")
	assert_eq(MapManors.focus_of(r, s, 1), "grain")
	var grain := MapManors.focus_output_of(r, s, 1)
	assert_eq(String(grain["good"]), "grain")
	assert_almost_eq(float(grain["units"]), 12.0, 0.001)
	assert_almost_eq(MapManors.rent_of(r, s, 2), 1.1, 0.0001, "grain adds a tenth to the rent")
	assert_almost_eq(MapManors.base_value_of(r, s, 1), (60.0 + 12.0 * 2.0) * 1.18, 0.001,
		"the yield counts in the value like town trade does")
	assert_false(MapManors.set_focus(r, s, 2, "fish", "turned"), "no sea at cell 2")
	assert_false(MapManors.set_focus(r, s, 1, "grain", "turned"), "already works it")
	assert_false(MapManors.set_focus(r, s, 1, "fish", ""), "no reason")
	assert_true(MapManors.set_focus(r, s, 1, "fish", "turned to the sea"))
	assert_eq(s.manor_focus, {"1": {"focus": "fish", "since": 3}})
	assert_eq(String(s.manor_log[0]["focus"]), "fish")
	assert_almost_eq(MapManors.focus_ramp(r, s, 1), 0.0, 0.001, "nothing on the tick it turns")
	assert_almost_eq(float(MapManors.focus_output_of(r, s, 1)["units"]), 0.0, 0.001)
	s.tick = 4
	assert_almost_eq(float(MapManors.focus_output_of(r, s, 1)["units"]), 4.8, 0.001, "half settled")
	s.tick = 5
	assert_almost_eq(float(MapManors.focus_output_of(r, s, 1)["units"]), 9.6, 0.001)
	assert_eq(String(MapManors.focus_output_of(r, s, 1)["good"]), "fish")
	assert_true(MapManors.set_focus(r, s, 2, "ore", "dug"))
	assert_almost_eq(MapManors.focus_ramp(r, s, 2), 1.0, 0.001, "no transition: at once")
	assert_almost_eq(MapManors.rent_of(r, s, 2), 1.2, 0.0001)
	# The crown's column: cell 1's fish and cell 2's ore, no town trade in
	# this fixture.
	var column := MapEconomy.output_of_provinces(r, ["p"], s)
	assert_eq(column.size(), 2)
	assert_eq(String(column[0]["good"]), "fish")
	assert_almost_eq(float(column[1]["units"]), 2.5 * 2.0 * 0.4, 0.001, "ore: 2 500 people, poor land")
	assert_eq(MapEconomy.output_of_provinces(r, ["p"]).size(), 0, "without a state, town trade only")
	# It survives a save.
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(String(back.manor_focus["1"]["focus"]), "fish")
	assert_eq(int(back.manor_focus["1"]["since"]), 3)
	assert_eq(MapManors.focus_of(r, back, 1), "fish")

## Building takes time and room (owner 2026-09-13): a manor has
## manor_slots_base slots (one more with a town), a work takes build_days
## from the day it begins, and a building or a work can be pulled down for
## manor_demolish_refund of its cost. Cell 2 holds Shole, so 3 slots; cell 1
## has 2. The fixture's tick 3 is absolute day 31..45.
func test_works_take_days_and_slots_and_can_be_pulled_down() -> void:
	var r := _repo()
	r.balance["manor_slots_base"] = 2.0
	r.balance["manor_slots_burg_bonus"] = 1.0
	r.balance["manor_demolish_refund"] = 0.5
	r.manor_buildings["mill"]["build_days"] = "4"
	r.manor_buildings["palisade"]["build_days"] = "0"
	r.manor_buildings["chapel"] = {"building_code": "chapel", "label": "Chapel", "cost_gold": "30",
		"build_days": "10", "tax_bonus": "0", "output_bonus": "0", "defence_bonus": "0", "church_bonus": "0.3"}
	var s := _state()
	s.day = 1
	assert_eq(MapManors.slots_of(r, 1), 2)
	assert_eq(MapManors.slots_of(r, 2), 3, "a town adds a slot")
	assert_eq(s.absolute_day(), 61)
	assert_false(MapManors.start_work(r, s, 1, "castle", "no such"), "no such building")
	assert_false(MapManors.start_work(r, s, 1, "mill", ""), "no reason")
	assert_true(MapManors.start_work(r, s, 1, "mill", "begun"))
	assert_false(MapManors.start_work(r, s, 1, "mill", "begun"), "one mill, begun or standing")
	assert_true(MapManors.is_building(s, 1, "mill"))
	assert_eq(MapManors.buildings_of(s, 1), [], "not standing yet")
	assert_eq(MapManors.free_slots(r, s, 1), 1)
	assert_eq(MapManors.work_days_left(s, 1, "mill"), 4)
	assert_almost_eq(MapManors.work_progress(s, 1, "mill"), 0.0, 0.001)
	assert_true(MapManors.start_work(r, s, 1, "chapel", "begun"))
	assert_eq(MapManors.free_slots(r, s, 1), 0)
	assert_false(MapManors.start_work(r, s, 1, "palisade", "begun"), "no room")
	assert_eq(int(s.manor_log[0]["begun"]), 4)
	# Two days on: half a mill.
	s.day = 3
	assert_eq(MapManors.advance_works(r, s), [], "nothing done yet")
	assert_almost_eq(MapManors.work_progress(s, 1, "mill"), 0.5, 0.001)
	assert_eq(MapManors.work_days_left(s, 1, "mill"), 2)
	s.day = 5
	assert_eq(MapManors.advance_works(r, s), [{"cell": 1, "building": "mill"}])
	assert_eq(MapManors.buildings_of(s, 1), ["mill"])
	assert_false(MapManors.is_building(s, 1, "mill"))
	assert_true(MapManors.is_building(s, 1, "chapel"), "the chapel still rises")
	assert_string_contains(String(s.manor_log[2]["reason"]), "finished after 4 days")
	# A work with no days stands the day it is begun.
	assert_true(MapManors.start_work(r, s, 2, "palisade", "dug"))
	assert_eq(MapManors.advance_works(r, s), [{"cell": 2, "building": "palisade"}])
	# Pull the mill down: half its 40 back; stop the chapel: half its 30.
	assert_almost_eq(MapManors.demolish(r, s, 1, "castle", "x"), -1.0, 0.001, "no such building")
	assert_almost_eq(MapManors.demolish(r, s, 1, "palisade", "x"), -1.0, 0.001, "nothing there")
	assert_almost_eq(MapManors.demolish(r, s, 1, "mill", "pulled down"), 20.0, 0.001)
	assert_eq(MapManors.buildings_of(s, 1), [])
	assert_almost_eq(MapManors.demolish(r, s, 1, "chapel", "stopped"), 15.0, 0.001)
	assert_eq(MapManors.works_of(s, 1), [])
	assert_eq(MapManors.free_slots(r, s, 1), 2)
	assert_almost_eq(float(s.manor_log[-1]["demolished"]), 15.0, 0.001)
	# It all survives a save.
	assert_true(MapManors.start_work(r, s, 1, "chapel", "begun again"))
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.day, 5)
	assert_eq(back.manor_works.keys(), ["1"])
	assert_eq(String(back.manor_works["1"][0]["building"]), "chapel")
	assert_eq(int(back.manor_works["1"][0]["start"]), 65)
	assert_eq(MapManors.work_days_left(back, 1, "chapel"), 10)

## What buildings do each tick (owner 2026-09-13): the *_per_tick columns
## summed over the crown's finished buildings, works not counting.
func test_finished_buildings_add_to_the_crowns_metrics_each_tick() -> void:
	var r := _repo()
	r.manor_buildings["market"] = {"building_code": "market", "label": "Market", "cost_gold": "50",
		"build_days": "0", "tax_bonus": "0.15", "output_bonus": "0", "defence_bonus": "0",
		"church_bonus": "0", "gold_per_tick": "3", "grain_per_tick": "0", "contentment_per_tick": "0",
		"unrest_per_tick": "0", "produce_good": "cloth", "produce_units": "1"}
	r.manor_buildings["mill"]["grain_per_tick"] = "2"
	r.manor_buildings["mill"]["build_days"] = "9"
	r.balance["manor_slots_base"] = 3.0
	r.balance["manor_slots_burg_bonus"] = 1.0
	var s := _state()
	assert_true(MapManors.set_owner(r, s, 1, "Rex", "bought"))
	assert_true(MapManors.build(r, s, 1, "market", "raised"))
	assert_true(MapManors.start_work(r, s, 1, "mill", "begun"))
	var fx := MapManors.building_effects(r, s, [1, 2])
	assert_almost_eq(float(fx["treasury"]), 3.0, 0.001, "the market's tolls")
	assert_almost_eq(float(fx["grain"]), 0.0, 0.001, "the mill is not built yet")
	assert_eq(MapManors.building_output_of(r, s, 1), {"cloth": 1.0})
	assert_eq(MapManors.building_output_of(r, s, 2), {})
	s.day = 10
	MapManors.advance_works(r, s)
	assert_almost_eq(float(MapManors.building_effects(r, s, [1])["grain"]), 2.0, 0.001, "and now it is")
	# Only the crown's: cell 2 is Valorin's, so its palisade counts for nothing.
	assert_true(MapManors.build(r, s, 2, "palisade", "dug"))
	r.manor_buildings["palisade"]["unrest_per_tick"] = "-0.1"
	r.provinces["p"]["kingdom_code"] = "k"
	r.realm_bindings = {"player_realm": "k"}
	var crown := MapManors.crown_building_effects(r, s)
	assert_almost_eq(float(crown["treasury"]), 3.0, 0.001)
	assert_almost_eq(float(crown["unrest"]), 0.0, 0.001, "another house's wall")

## The default focus follows the terrain (owner 2026-09-14): default_on
## rows claim cells — coast, high, peak, biomes — in file order, provided
## the land allows the focus; an unclaimed cell works the first it allows.
## Fixture rows: grain (biomes 1|2, no claim), fish (any, coast, claims
## coast), ore (biome 2, claims high). Cell 1: biome 1, coastal -> fish.
## Cell 2: biome 2, inland, height 30 -> nothing claims it -> grain; raise
## it to 60 -> ore claims high ground.
func test_the_default_focus_follows_the_terrain() -> void:
	var r := _repo()
	r.balance["manor_focus_high_height"] = 52.0
	r.balance["manor_focus_peak_height"] = 63.0
	r.manor_focus = {
		"grain": {"focus_code": "grain", "label": "Grain fields", "good_code": "grain", "biomes": "1|2|3",
			"coast": "0", "yield_per_1000": "10", "rent_bonus": "0.1", "switch_cost_gold": "20",
			"transition_ticks": "2", "default_on": ""},
		"fish": {"focus_code": "fish", "label": "Fisheries", "good_code": "fish", "biomes": "any",
			"coast": "1", "yield_per_1000": "8", "rent_bonus": "0.05", "switch_cost_gold": "15",
			"transition_ticks": "2", "default_on": "coast"},
		"ore": {"focus_code": "ore", "label": "Iron workings", "good_code": "iron", "biomes": "2",
			"coast": "0", "yield_per_1000": "2", "rent_bonus": "0.2", "switch_cost_gold": "60",
			"transition_ticks": "0", "default_on": "high|3"},
	}
	assert_eq(MapManors.default_focus(r, 1), "fish", "a coastal manor fishes")
	assert_eq(MapManors.default_focus(r, 2), "grain", "inland lowland: the first allowed")
	MapManors.invalidate()
	r.cells[2]["height"] = 60.0
	assert_eq(MapManors.default_focus(r, 2), "ore", "high ground: the claim wins")
	MapManors.invalidate()
	r.cells[2]["height"] = 30.0
	r.cells[2]["biome_id"] = 3
	assert_eq(MapManors.default_focus(r, 2), "grain", "biome 3 is claimed by ore but ore is not allowed there")

## Integer people (spec §4.1): largest remainder, ties to the lower id.
func test_apportion_hands_the_remainder_to_the_largest_fractions() -> void:
	var out := MapManors.apportion([1, 2, 3], PackedFloat64Array([1.0, 1.0, 1.0]), 1000)
	assert_eq(out, {1: 334, 2: 333, 3: 333})
	assert_eq(MapManors.apportion([7, 9], PackedFloat64Array([3.0, 1.0]), 10), {7: 8, 9: 2}, "7.5 and 2.5: the tie goes to the lower id")
	assert_eq(MapManors.apportion([], PackedFloat64Array(), 5), {})
	assert_eq(MapManors.apportion([4], PackedFloat64Array([0.0]), 5), {4: 0}, "no weight, no people")

## Province p: 3 000 country folk over weights 80 and 80, and Shole's 1 000
## townsfolk to cell 2 -> 1 500 and 2 500, summing to the province's 4 000.
func test_people_sum_exactly_to_the_province() -> void:
	var r := _repo()
	var s := _state()
	var t := MapManors.people_table(r, s, "p")
	assert_eq(t, {1: 1500, 2: 2500})
	assert_eq(MapManors.people_of(r, s, 1), 1500)
	assert_eq(MapManors.people_of(r, s, 2), 2500)
	assert_eq(MapManors.people_of(r, s, 4), 800, "q's 800 go to its one manor")
	WorldLedger.apply(r, s, "economy.provinces.p.rural_population", 1, "test: one more", "test")
	assert_eq(MapManors.people_table(r, s, "p"), {1: 1501, 2: 2500}, "an odd one goes to the lower id; the cache keys on the figure")
