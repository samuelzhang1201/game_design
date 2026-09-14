extends GutTest
## ManorEconomy (spec §4): one manor's month in whole gold, hand-computed.
## Province p (rural 3 000, urban 1 000): cell 1 is 10x10 on land 0.8 and
## works grain; cell 2 is 20x10 on land 0.4, holds Shole (1 000 townsfolk)
## which makes 7 wood and 2 iron a month, and works nothing. Balance: 20
## gold a month per 1 000 people at tax level 5; tariff 2 per level per
## hundred.

func _repo() -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"manor_tax_per_1000": 20.0, "tax_rate_base": 5.0, "tariff_per_sales_tax": 2.0,
		"manor_focus_high_height": 52.0, "manor_focus_peak_height": 63.0}
	r.biomes = {1: {"habitability": "80"}, 2: {"habitability": "40"}}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 10), 3: Vector2(0, 10),
		4: Vector2(30, 0), 5: Vector2(30, 10)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 30.0, "biome_id": 1,
			"water": "", "neighbor_ids": PackedInt32Array([2])},
		2: {"vertex_ids": PackedInt32Array([1, 4, 5, 2]), "height": 30.0, "biome_id": 2,
			"water": "", "neighbor_ids": PackedInt32Array([1])},
	}
	r.manors = {
		1: {"cell_id": 1, "manor_code": "ashcombe", "label": "Ashcombe", "province_code": "p",
			"burg_code": "", "culture_code": "c"},
		2: {"cell_id": 2, "manor_code": "shole_manor", "label": "Shole Manor", "province_code": "p",
			"burg_code": "shole", "culture_code": "c"},
	}
	for id: int in r.manors:
		r.manor_by_code[String(r.manors[id]["manor_code"])] = id
		r.manor_by_label[String(r.manors[id]["label"]).to_lower()] = id
	r.provinces = {"p": {"province_code": "p", "label": "Prov", "kingdom_code": "k", "capital_burg": "shole"}}
	r.burgs = {"shole": {"burg_code": "shole", "label": "Shole", "province_code": "p",
		"population": "1000", "x": "20", "y": "5"}}
	r.house_bindings = {"p": "Valorin"}
	r.manor_buildings = {
		"mill": {"building_code": "mill", "label": "Mill", "cost_gold": "40", "tax_bonus": "0.05",
			"output_bonus": "0.15", "defence_bonus": "0", "church_bonus": "0", "produce_good": "", "produce_units": "0"},
		"market": {"building_code": "market", "label": "Market", "cost_gold": "50", "tax_bonus": "0",
			"output_bonus": "0", "defence_bonus": "0", "church_bonus": "0", "produce_good": "iron", "produce_units": "30"},
	}
	r.manor_focus = {"grain": {"focus_code": "grain", "label": "Grain fields", "good_code": "grain",
		"biomes": "1", "coast": "0", "yield_per_1000": "12",
		"switch_cost_gold": "20", "transition_ticks": "2", "default_on": "1"}}
	r.goods_economy = {
		"grain": {"good_code": "grain", "pool": "civil", "price_gold": "1", "growth_permille": "2"},
		"wood": {"good_code": "wood", "pool": "civil", "price_gold": "1", "growth_permille": "3"},
		"iron": {"good_code": "iron", "pool": "strategic", "price_gold": "4", "growth_permille": "3"},
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
		"p": {"province_code": "p", "rural_population": "3000", "urban_population": "1000"}})
	r._register_table("economy", "goods", {
		"grain": {"good_code": "grain", "label": "Grain", "tags": "food"},
		"wood": {"good_code": "wood", "label": "Wood", "tags": "construction|fuel"},
		"iron": {"good_code": "iron", "label": "Iron", "tags": "ore|military"}})
	r._register_table("economy", "production", {
		"shole:wood": {"burg_code": "shole", "good_code": "wood", "units": "7"},
		"shole:iron": {"burg_code": "shole", "good_code": "iron", "units": "2"}})
	MapManors.invalidate()
	MapEconomy.forget()
	ManorEconomy.forget()
	return r

func _state() -> GameState:
	var s := GameState.new()
	s.rng = Rng.new(1)
	s.tick = 0
	s.metrics = {"tax_rate": 5.0, "tariff_rate": 3.0}
	s.player_setup = {"first_name": "Anne", "family_name": "Rex", "flag": ""}
	return s

## 1000 per mille at tick 0; 2 per mille compounding in integers: every
## month adds round(prev x 2 / 1000) = 2, so tick 12 is 1024 (the float
## 1.002^12 is 1.0243); a good with no growth stays 1000.
func test_growth_is_an_integer_table() -> void:
	var r := _repo()
	assert_eq(ManorEconomy.growth_index(r, "grain", 0), 1000)
	assert_eq(ManorEconomy.growth_index(r, "grain", 1), 1002)
	assert_eq(ManorEconomy.growth_index(r, "grain", 12), 1024)
	assert_eq(ManorEconomy.growth_index(r, "nothing", 40), 1000)
	assert_eq(ManorEconomy.growth_index(r, "grain", 12), 1024, "the same the second time")

## Cell 1: 1 500 people -> tax round(1.5 x 20 x 5/5) = 30; grain units
## round(1.5 x 12 x 0.8 x ramp 1 x growth 1) = round(14.4) = 14 -> 14 gold
## of civil goods, no town, no tariff, no strategic.
func test_a_country_manor_pays_tax_and_grows_its_chief_good() -> void:
	var r := _repo()
	var s := _state()
	var line := ManorEconomy.line_of(r, s, 1, 0)
	assert_eq(line["people"], 1500)
	assert_eq(line["tax"], 30)
	assert_eq(line["tariff"], 0)
	assert_eq(line["units"], {"grain": 14})
	assert_eq(line["civil"], 14)
	assert_eq(line["strategic"], 0)

## Cell 2: 2 500 people -> 50 tax; the town's 7 wood (1 gold) and 2 iron
## (4 gold) are 15 gold of goods -> tariff round(15 x 3 x 2 / 100) = 1, so
## tax 51; wood is civil (7), iron strategic (8). Its land allows no focus.
func test_a_town_manor_earns_its_towns_lines_and_a_tariff() -> void:
	var r := _repo()
	var s := _state()
	var line := ManorEconomy.line_of(r, s, 2, 0)
	assert_eq(line["people"], 2500)
	assert_eq(line["tariff"], 1)
	assert_eq(line["tax"], 51)
	assert_eq(line["units"], {"iron": 2, "wood": 7})
	assert_eq(line["civil"], 7)
	assert_eq(line["strategic"], 8)

## At tick 12 grain has grown to 1024 per mille: round(14.4 x 1.024) =
## round(14.7456) = 15. A mill's output_bonus 0.15 on cell 1 at tick 0:
## round(14.4 x 1.15) = round(16.56) = 17; its tax_bonus 0.05: round(31.5) = 32.
func test_growth_and_buildings_raise_the_line() -> void:
	var r := _repo()
	var s := _state()
	assert_eq(ManorEconomy.line_of(r, s, 1, 12)["units"], {"grain": 15})
	s.manor_buildings["1"] = ["mill"]
	var line := ManorEconomy.line_of(r, s, 1, 0)
	assert_eq(line["units"], {"grain": 17})
	assert_eq(line["tax"], 32)

## A building's produce_good grows but takes no output_bonus (unlike the
## chief good and the town's lines): with mill + market on cell 1 at tick 0,
## the mill's 0.15 raises grain 14.4 -> 16.56 -> 17 and its 0.05 raises tax
## round(1.5 x 20 x 1.05) = 32, but the market's 30 iron stays 30 (growth
## 1000, no output_bonus) -> strategic 30 x 4 = 120, civil 17. With market
## alone at tick 12, iron's growth (3 per mille, compounding in integers)
## reads 1036 at tick 12 -> round(30 x 1.036) = round(31.08) = 31; grain
## (no mill now) at growth 1024 -> round(14.4 x 1.024) = round(14.7456) =
## 15 -> units {"grain": 15, "iron": 31}, strategic 31 x 4 = 124.
func test_a_buildings_produce_grows_but_takes_no_output_bonus() -> void:
	var r := _repo()
	var s := _state()
	s.manor_buildings["1"] = ["mill", "market"]
	var line := ManorEconomy.line_of(r, s, 1, 0)
	assert_eq(line["units"], {"grain": 17, "iron": 30})
	assert_eq(line["strategic"], 120)
	assert_eq(line["civil"], 17)
	assert_eq(line["tax"], 32)
	s.manor_buildings["1"] = ["market"]
	var later := ManorEconomy.line_of(r, s, 1, 12)
	assert_eq(later["units"], {"grain": 15, "iron": 31})
	assert_eq(later["strategic"], 124)

## The poll tax scales the tax: level 10 doubles, level 1 fifths; the
## sales tax scales the tariff: level 0 is none.
func test_the_tax_levels_scale_the_lines() -> void:
	var r := _repo()
	var s := _state()
	s.metrics["tax_rate"] = 10.0
	assert_eq(ManorEconomy.line_of(r, s, 1, 0)["tax"], 60)
	s.metrics["tax_rate"] = 1.0
	assert_eq(ManorEconomy.line_of(r, s, 1, 0)["tax"], 6)
	s.metrics["tariff_rate"] = 0.0
	assert_eq(ManorEconomy.line_of(r, s, 2, 0)["tariff"], 0)
