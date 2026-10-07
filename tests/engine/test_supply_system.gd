extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The supply helpers (spec 2026-10-07-army-supply-lines): the road's loss,
## a regiment's line as the cards read it, the garrison test. The day's
## supply itself is tests/engine/test_supply_day.gd.

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
	_able_honest_governors()
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

## An able, honest governor: efficiency 1000, no skim — so the figures stay
## the plain arithmetic they were written against (M3 Task 2).
func _able_honest_governors() -> void:
	for pair in [["steward", "sk_steward"], ["marshal", "sk_admin"]]:
		var c: Character = s.characters[String(s.council[pair[0]])]
		c.skills[pair[1]] = 16
		c.opinion = 50
		c.traits = []
		c.attributes["integrity"] = 50

func _land_codes() -> Array:
	var out: Array = []
	for c in s.regiments.keys():
		if String(ArmySystem.regiment(data, String(c)).get("is_naval", "0")) != "1":
			out.append(String(c))
	out.sort()
	return out

func _place(code: String, px: Vector2) -> void:
	var m := ArmySystem.pack_to_metres(data, px)
	s.regiments[code]["x_m"] = m.x
	s.regiments[code]["y_m"] = m.y
	s.regiments[code]["dest_x_m"] = m.x
	s.regiments[code]["dest_y_m"] = m.y

## Stands a regiment IN the crown's home province's capital town (a garrison
## is only one inside a town, spec 2026-10-06-army-location-and-town-defence §4).
func _stand_at_home(code: String, order: String) -> Dictionary:
	var home := MapManors.home_province(data, s)
	var p: Dictionary = data.provinces[home]
	var b: Dictionary = data.burgs[String(p["capital_burg"])]
	_place(code, Vector2(float(b["x"]), float(b["y"])))
	s.regiments[code]["order"] = order
	return p

func _card_stat(code: String, key: String) -> Dictionary:
	for st: Dictionary in MapObjects.army_card(data, code, s)["stats"]:
		if String(st["key"]) == key:
			return st
	return {}

func test_the_loss_grows_with_the_road_and_is_capped() -> void:
	var per := int(data.bal("army_supply_loss_permille_per_100km"))
	var cap := int(data.bal("army_supply_loss_cap_permille"))
	assert_gt(per, 0)
	assert_eq(SupplySystem.loss_of(data, 0), 0)
	assert_eq(SupplySystem.loss_of(data, 100), per)
	@warning_ignore("integer_division")
	assert_eq(SupplySystem.loss_of(data, 250), mini(per * 5 / 2, cap))
	@warning_ignore("integer_division")
	assert_eq(SupplySystem.loss_of(data, cap * 100 / per + 1000), cap, "the cap holds a long road")

func test_line_of_reads_the_line() -> void:
	var code := String(_land_codes()[0])
	assert_eq(String(SupplySystem.line_of(data, s, code)["town"]), "", "no line yet")
	assert_eq(SupplySystem.route_px(data, s, code).size(), 0, "no line, no road")
	var town: String = TownStores.realm_towns(data, s)[0]
	s.supply_lines[code] = SupplyLines._new_record(town, 800, 1)
	var line := SupplySystem.line_of(data, s, code)
	assert_eq(String(line["town"]), town)
	assert_eq(int(line["rate"]), 800)
	assert_eq(String(line["state"]), SupplyLines.ORDERED)
	assert_eq(int(line["loss_permille"]), SupplySystem.loss_of(data, int(line["length_km"])))
	assert_eq(SupplySystem.route_px(data, s, code), SupplyLines.road_px(data, s, code, town))

func test_a_garrison_in_a_crown_town_reads_its_town() -> void:
	var code: String = _land_codes()[0]
	var p := _stand_at_home(code, ArmySystem.ORDER_GARRISON)
	var line := SupplySystem.line_of(data, s, code)
	assert_true(line["garrison"])
	assert_eq(String(line["garrison_town"]), String(p["capital_burg"]))

func test_a_garrison_reads_in_garrison_at_its_town() -> void:
	var code: String = _land_codes()[0]
	var p := _stand_at_home(code, ArmySystem.ORDER_GARRISON)
	var town := String(data.burgs[String(p["capital_burg"])]["label"])
	assert_true(SupplySystem.line_of(data, s, code)["garrison"])
	assert_eq(String(_card_stat(code, "army_supply_line")["text"]), "none", "no line ordered")
	assert_string_contains(String(_card_stat(code, "army_supply_line")["tooltip"]).to_lower(),
		(town + " tops it up").to_lower())

## Final review 6: a regiment merely STANDING in its realm town (no garrison
## order) is topped up by it all the same, and the card says so.
func test_a_standing_regiment_reads_that_its_town_tops_it_up() -> void:
	var code: String = _land_codes()[0]
	var p := _stand_at_home(code, ArmySystem.ORDER_STANDBY)
	var town := String(data.burgs[String(p["capital_burg"])]["label"])
	assert_false(SupplySystem.line_of(data, s, code)["garrison"], "no garrison order")
	var tip := String(_card_stat(code, "army_supply_line")["tooltip"])
	assert_string_contains(tip.to_lower(), (town + " tops it up").to_lower())

## Final review 1: a regiment whose own town has run dry reads the depot
## that feeds it.
func test_a_regiment_whose_town_is_dry_reads_the_depot_that_feeds_it() -> void:
	var dep := TownStores.depot(data, s)
	for code: String in _land_codes():
		var held := SupplyLines.home_town(data, s, code)
		if held == "" or held == dep:
			continue
		s.regiments[code]["supply_dry"] = held
		var tip := String(_card_stat(code, "army_supply_line")["tooltip"])
		assert_string_contains(tip, "%s's stores are empty" % String(data.burgs[held]["label"]))
		assert_string_contains(tip, "fed from %s" % String(data.burgs[dep]["label"]))
		return
	pending("no regiment stands in a realm town other than the depot")

## A regiment quartered in a realm town with stores to spare is topped up
## every day to its carried load (spec 2026-10-07-army-supply-lines §3.2):
## a month on, its ranks are well fed.
func test_a_month_in_a_stocked_town_leaves_the_ranks_well_fed() -> void:
	var code: String = _land_codes()[0]
	var p := _stand_at_home(code, ArmySystem.ORDER_GARRISON)
	s.regiments[code]["supplies"] = 0
	s.town_stock[String(p["capital_burg"])] = {"crown": 1000000, "lord": 0, "house": 0}
	TownStores.sync_metrics(data, s)
	var engine := TickEngine.new(data)
	for d in Calendar.DAYS_PER_TICK - 1:
		engine.advance_day(s)
	engine.advance(s)
	var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, code), s)
	var score := ArmySystem.supply_score(data, int(s.regiments[code]["supplies"]), use)
	assert_eq(score, 1000, "a full train after the month")
	assert_eq(ArmySystem.morale_word(data, score), "well fed")
	assert_string_contains(String(_card_stat(code, "army_morale")["tooltip"]), "well fed")

## Supply use and the card's height row read the ground the regiment stands
## on NOW.
func _mountain_cell() -> int:
	var ids: Array = data.cells.keys()
	ids.sort()
	for id: int in ids:
		var cell: Dictionary = data.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		if not String(Elevation.tier_of(data, float(cell["height"]))["tier"]) in ["mountains", "peak"]:
			continue
		if MapEconomy.cell_at(data, MapTerrain.cell_center(data, cell)) == id:
			return id
	return -1

func test_a_regiment_on_the_mountains_uses_more_than_at_home() -> void:
	var code: String = _land_codes()[0]
	var reg := ArmySystem.regiment(data, code)
	var at_home := ArmySystem.supply_use(data, reg, s)
	var home_tier := ArmySystem.height_tier(data, reg, s)
	var id := _mountain_cell()
	assert_gte(id, 0, "the pack has mountains")
	_place(code, MapTerrain.cell_center(data, data.cells[id]))
	var there := ArmySystem.height_tier(data, reg, s)
	assert_gt(int(there["supply_permille"]), int(home_tier["supply_permille"]), "the mountains cost more than home")
	var up_there := ArmySystem.supply_use(data, reg, s)
	assert_gt(up_there, at_home)
	assert_eq(ArmySystem.supply_use(data, reg), at_home, "no state: the pack's own quarters")
	var height_text := ""
	for st: Dictionary in MapObjects.army_card(data, code, s)["stats"]:
		if String(st["key"]) == "army_height":
			height_text = String(st["tooltip"])
	assert_string_contains(height_text, String(there["tier"]))

## Only a GARRISON order earns the garrison's morale.
func test_only_a_garrison_order_earns_the_garrison_morale() -> void:
	var codes := _land_codes()
	var standing: String = codes[0]
	var holding: String = codes[1]
	var fed := int(data.bal("army_morale_fed"))
	var bonus := int(data.bal("army_morale_garrison_bonus"))
	var drift := int(data.bal("army_morale_drift_per_month"))
	assert_gt(bonus, 0)
	assert_gt(drift, 1, "the drift reaches past the fed mark")
	for pair: Array in [[standing, ArmySystem.ORDER_STANDBY], [holding, ArmySystem.ORDER_GARRISON]]:
		var c: String = pair[0]
		_stand_at_home(c, String(pair[1]))
		s.regiments[c]["morale"] = fed - 1
		s.regiments[c]["supplies"] = ArmySystem.supply_use(data, ArmySystem.regiment(data, c), s) * 4
	ArmySystem.settle_month(data, s)
	assert_eq(int(s.regiments[standing]["morale"]), fed, "standing by at home: the fed mark")
	assert_eq(int(s.regiments[holding]["morale"]), mini(fed + bonus, fed - 1 + drift),
		"in garrison: toward the fed mark and the bonus")
