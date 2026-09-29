extends GutTest
## Supply lines (spec 2026-09-30-ledger-supply-design §3).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

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
	assert_eq(SupplySystem.loss_of(data, 0), 0)
	assert_eq(SupplySystem.loss_of(data, 100), 60)
	assert_eq(SupplySystem.loss_of(data, 250), 150)
	assert_eq(SupplySystem.loss_of(data, 5000), 600)

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
