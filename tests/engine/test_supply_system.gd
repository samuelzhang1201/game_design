extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Supply lines (spec 2026-09-30-ledger-supply-design §3).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
	_able_honest_governors()
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

## An able, honest governor: efficiency 1000, no skim — so the M1/M2
## figures stay the plain arithmetic they were written against (M3 Task 2).
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

func test_what_is_shipped_covers_what_the_road_loses() -> void:
	assert_eq(SupplySystem.ship_for(90, 100), 100)
	assert_eq(SupplySystem.ship_for(0, 300), 0)
	assert_eq(SupplySystem.ship_for(7, 0), 7)

func test_a_short_pool_is_shared_by_need() -> void:
	assert_eq(SupplySystem.share(50, [60, 40]), [30, 20])
	assert_eq(SupplySystem.share(0, [60, 40]), [0, 0])
	assert_eq(SupplySystem.share(500, [60, 40]), [60, 40], "enough for all: each paid in full")

func test_a_regiment_at_the_depot_loses_nothing() -> void:
	var code: String = _land_codes()[0]
	_place(code, CourierSystem.origin(data, s))
	var line := SupplySystem.line_of(data, s, code)
	assert_eq(int(line["length_km"]), 0)
	assert_eq(int(line["loss_permille"]), 0)

## A hand-checked multi-waypoint line: pins the CONVENTION (walk every leg
## from the depot, path_between's own waypoints included), not the
## implementation — the expected length is summed here straight off
## CourierSystem.path_between's output, independently of SupplySystem.
func test_the_road_length_sums_every_leg_from_the_depot() -> void:
	var code: String = _land_codes()[0]
	var from_px := CourierSystem.origin(data, s)
	var codes: Array = data.burgs.keys()
	codes.sort()
	var path: Array = []
	var to_px := Vector2.ZERO
	for bcode: String in codes:
		var b: Dictionary = data.burgs[bcode]
		var candidate := Vector2(float(b["x"]), float(b["y"]))
		var p := CourierSystem.path_between(data, from_px, candidate)
		if p.size() >= 2:
			path = p
			to_px = candidate
			break
	assert_false(path.is_empty(), "the pack has a burg whose road from the depot has more than one waypoint")
	var origin_m := ArmySystem.pack_to_metres(data, from_px)
	var here := Vector2(origin_m)
	var metres := 0.0
	for wp: Array in path:
		var to_wp := Vector2(float(wp[0]), float(wp[1]))
		metres += here.distance_to(to_wp)
		here = to_wp
	var expect_km := int(metres / 1000.0)
	_place(code, to_px)
	var line := SupplySystem.line_of(data, s, code)
	assert_eq(int(line["length_km"]), expect_km)

func test_a_garrison_in_the_crowns_province_draws_on_its_town() -> void:
	var code: String = _land_codes()[0]
	var home := MapManors.home_province(data, s)
	var p: Dictionary = data.provinces[home]
	_place(code, Vector2(float(p["center_x"]), float(p["center_y"])))
	s.regiments[code]["order"] = ArmySystem.ORDER_GARRISON
	var line := SupplySystem.line_of(data, s, code)
	assert_true(line["garrison"])
	assert_eq(String(line["stronghold"]), String(p["capital_burg"]))
	assert_eq(int(line["loss_permille"]), 0)

func test_a_hungry_regiment_is_refilled_to_its_target() -> void:
	var code: String = _land_codes()[0]
	s.regiments[code]["supplies"] = 0
	s.metrics["strategic"] = 1000000.0
	var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, code))
	var target := use * int(data.bal("army_supply_target_months"))
	var before := int(s.metrics["strategic"])
	var lines := SupplySystem.settle_month(data, s)
	assert_eq(int(s.regiments[code]["supplies"]), target)
	var paid := 0
	for l: Dictionary in lines:
		if String(l["metric"]) == "strategic":
			paid = -int(l["delta"])
	assert_gt(paid, 0)
	assert_eq(int(s.metrics["strategic"]), before, "settle_month returns lines; the tick applies them")

func test_empty_pools_ship_nothing() -> void:
	s.metrics["strategic"] = 0.0
	s.metrics["lord_strategic"] = 0.0
	var code: String = _land_codes()[0]
	s.regiments[code]["supplies"] = 0
	assert_eq(SupplySystem.settle_month(data, s), [])
	assert_eq(int(s.regiments[code]["supplies"]), 0)

func test_the_crown_pays_first_then_the_lord() -> void:
	for c in _land_codes():
		s.regiments[c]["supplies"] = 0
	s.metrics["strategic"] = 10.0
	s.metrics["lord_strategic"] = 1000000.0
	var lines := SupplySystem.settle_month(data, s)
	assert_eq(lines[0], {"metric": "strategic", "delta": -10, "reason": "supplies sent to the host"})
	assert_eq(String(lines[1]["metric"]), "lord_strategic")

func test_fleets_are_never_supplied() -> void:
	for row: Dictionary in SupplySystem.plan(data, s):
		assert_ne(String(ArmySystem.regiment(data, String(row["code"])).get("is_naval", "0")), "1")

func test_the_plan_is_deterministic() -> void:
	assert_eq_deep(SupplySystem.plan(data, s), SupplySystem.plan(data, s))

func test_full_supply_costs_about_half_the_crowns_strategic_intake() -> void:
	# The calibration of army_supply_gold_permille (spec §3): refilling every
	# land regiment's month of use, road losses included, against what the
	# crown and the lord take in strategic goods a month.
	var monthly := 0
	for code: String in _land_codes():
		var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, code))
		var ship := SupplySystem.ship_for(use, int(SupplySystem.line_of(data, s, code)["loss_permille"]))
		monthly += SupplySystem.gold_for(data, ship)
	var p := RealmEconomy.purses(data, s)
	var intake := int(p["lord"]["strategic"]) + int(p["realm_share"]["strategic"])
	gut.p("full supply %d gold a month against a strategic intake of %d" % [monthly, intake])
	assert_between(float(monthly) / float(maxi(intake, 1)), 0.3, 0.7)

## I1 (final review): refilled to army_supply_target_months, a regiment
## still holds a full supply score once its month is spent — the target is
## the full mark plus one month of use.
func test_after_a_month_with_ample_pools_the_ranks_are_well_fed() -> void:
	assert_eq(int(data.bal("army_supply_target_months")),
		int(data.bal("army_speed_supply_full_months")) + 1, "full, plus the month about to be eaten")
	for c in _land_codes():
		s.regiments[c]["supplies"] = 0
	s.metrics["strategic"] = 1000000.0
	s.metrics["lord_strategic"] = 1000000.0
	TickEngine.new(data).advance(s)
	for c: String in _land_codes():
		var score := ArmySystem.supply_score(data, int(s.regiments[c]["supplies"]),
			ArmySystem.supply_use(data, ArmySystem.regiment(data, c), s))
		assert_eq(score, 1000, "%s holds a full train after the month" % c)
		assert_eq(ArmySystem.morale_word(data, score), "well fed")
	var code: String = _land_codes()[0]
	var morale_tip := ""
	for st: Dictionary in MapObjects.army_card(data, code, s)["stats"]:
		if String(st["key"]) == "army_morale":
			morale_tip = String(st["tooltip"])
	assert_string_contains(morale_tip, "well fed")

## I2 (final review): supply use, the card's height row and the supply plan
## read the ground the regiment stands on NOW.
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
	s.regiments[code]["supplies"] = 0
	for row: Dictionary in SupplySystem.plan(data, s):
		if String(row["code"]) == code:
			assert_eq(int(row["need"]), up_there * int(data.bal("army_supply_target_months")))
	var height_text := ""
	for st: Dictionary in MapObjects.army_card(data, code, s)["stats"]:
		if String(st["key"]) == "army_height":
			height_text = String(st["tooltip"])
	assert_string_contains(height_text, String(there["tier"]))

## Minor3 (controller ruling): a regiment STANDING in a province the crown
## controls draws through its capital town, loss-free; only a GARRISON
## order earns the garrison's morale.
func _stand_at_home(code: String, order: String) -> Dictionary:
	var home := MapManors.home_province(data, s)
	var p: Dictionary = data.provinces[home]
	_place(code, Vector2(float(p["center_x"]), float(p["center_y"])))
	s.regiments[code]["order"] = order
	return p

func _card_stat(code: String, key: String) -> Dictionary:
	for st: Dictionary in MapObjects.army_card(data, code, s)["stats"]:
		if String(st["key"]) == key:
			return st
	return {}

func test_a_regiment_standing_at_home_draws_through_its_town() -> void:
	var code: String = _land_codes()[0]
	var p := _stand_at_home(code, ArmySystem.ORDER_STANDBY)
	var line := SupplySystem.line_of(data, s, code)
	assert_eq(String(line["stronghold"]), String(p["capital_burg"]))
	assert_eq(int(line["loss_permille"]), 0)
	assert_eq(int(line["length_km"]), 0)
	assert_false(line["garrison"], "standing by is not a garrison")
	var town := String(data.burgs[String(p["capital_burg"])]["label"])
	assert_eq(String(_card_stat(code, "army_supply_line")["text"]), "at home")
	assert_string_contains(String(_card_stat(code, "army_supply_line")["tooltip"]).to_lower(),
		("at home, supplied through " + town).to_lower())

func test_a_garrison_reads_in_garrison_at_its_town() -> void:
	var code: String = _land_codes()[0]
	var p := _stand_at_home(code, ArmySystem.ORDER_GARRISON)
	var town := String(data.burgs[String(p["capital_burg"])]["label"])
	assert_true(SupplySystem.line_of(data, s, code)["garrison"])
	assert_eq(String(_card_stat(code, "army_supply_line")["text"]), "in garrison")
	assert_string_contains(String(_card_stat(code, "army_supply_line")["tooltip"]).to_lower(),
		("in garrison at " + town).to_lower())

func test_a_marching_regiment_in_the_same_province_is_on_the_road() -> void:
	var code: String = _land_codes()[0]
	_stand_at_home(code, ArmySystem.ORDER_MARCH)
	s.regiments[code]["dest_x_m"] = int(s.regiments[code]["x_m"]) + 5000
	var line := SupplySystem.line_of(data, s, code)
	assert_eq(String(line["stronghold"]), "")
	assert_false(line["garrison"])
	var km := int(line["length_km"])
	assert_eq(int(line["loss_permille"]), SupplySystem.loss_of(data, km), "the road's own loss")

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


func test_a_route_runs_from_the_depot_to_the_regiment() -> void:
	for code: String in s.regiments:
		var reg := ArmySystem.regiment(data, code)
		if String(reg.get("is_naval", "0")) == "1" or SupplySystem.stronghold_of(data, s, code) != "":
			continue
		var route := SupplySystem.route_px(data, s, code)
		assert_gte(route.size(), 2)
		assert_almost_eq(route[route.size() - 1].distance_to(ArmySystem.position_of(data, s, reg)), 0.0, 0.01)
		return
	pending("no regiment stands away from a stronghold in this fixture")


func test_a_regiment_supplied_through_a_stronghold_has_no_route() -> void:
	for code: String in s.regiments:
		if SupplySystem.stronghold_of(data, s, code) != "":
			assert_eq(SupplySystem.route_px(data, s, code).size(), 0)
			return
	pending("no regiment stands in a stronghold in this fixture")
