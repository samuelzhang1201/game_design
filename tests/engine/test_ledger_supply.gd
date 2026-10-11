# tests/engine/test_ledger_supply.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The LEDGER reads the supply chain from its one plan each (spec
## 2026-09-30-ledger-supply-design §5), and a sphere carries its gauges
## (spec 2026-09-30-ledger-ontology-design §6.3, "a property").

var data: DataRepository
var s: GameState
var cell := -1

func before_each() -> void:
	# its marches are short hops between the capital and its towns, which the
	# pack's bay and scarps would bend: walked straight (spec 2026-10-10-march-slope-detour)
	data = SuiteData.open_country(SuiteData.repo())
	assert_not_null(data, DataRepository.last_error)
	s = SuiteData.campaign(data, 42)
	_able_honest_governors()
	RealmEconomy.forget()
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop")
	s.metrics["lord_civil"] = 100.0
	# the supply lines are the regiments' own now: the first land regiment
	# runs one (spec 2026-10-07-army-supply-lines)
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(data, String(c)).get("is_naval", "0")) != "1":
			s.supply_lines[c] = SupplyLines._new_record(TownStores.realm_towns(data, s)[0], 1000, 1)
			s.supply_lines[c]["state"] = SupplyLines.FLOWING
			break

func after_each() -> void:
	Intel.dev_all = false
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

func _link(snap: Dictionary, type: String) -> Dictionary:
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == type:
			return l
	return {}

func _node(snap: Dictionary, id: String) -> Dictionary:
	for n: Dictionary in snap["nodes"]:
		if String(n["id"]) == id:
			return n
	return {}

func _prop(node: Dictionary, key: String) -> Dictionary:
	for p: Dictionary in node.get("props", []):
		if String(p["key"]) == key:
			return p
	return {}

func test_the_workshop_threads_carry_its_plan() -> void:
	var snap := Ledger.snapshot(data, s, "economy", {})
	assert_eq(int(_link(snap, "converts_in")["flow"]), 40)
	assert_eq(int(_link(snap, "converts_out")["flow"]), 28)
	var ego := Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell})
	assert_eq(String(_link(ego, "converts_in")["from"]), "type:civil_goods")
	assert_eq(String(_link(ego, "converts_out")["to"]), "type:strategic_goods")

func test_a_regiments_supply_line_is_its_plan() -> void:
	var row: Dictionary = SupplySystem.plan(data, s)[0]
	var code := String(row["code"])
	var ego := Ledger.snapshot(data, s, "war", {"id": "regiment:" + code})
	var out := _link(ego, "supplies_out")
	assert_eq(String(out["from"]), "supply_line:" + code)
	assert_eq(out["flow"], int(row["delivered"]))
	var line := Ledger.snapshot(data, s, "war", {"id": "supply_line:" + code})
	assert_eq(_link(line, "dispatches")["flow"], int(row["paid"]))

func test_a_garrison_stands_in_its_town() -> void:
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	var home := MapManors.home_province(data, s)
	var p: Dictionary = data.provinces[home]
	# the garrison is the unit holding the seat of a town its kingdom holds
	# (spec 2026-10-07-army-split-and-ground §4.1): it marches in and, the
	# seat empty, takes it on arrival
	var town := String(p["capital_burg"])
	var b: Dictionary = data.burgs[town]
	var at := Vector2(float(b["x"]), float(b["y"]))
	ArmySystem.set_march(data, s, code, at)
	s.town_seat.erase(town)
	var m := ArmySystem.pack_to_metres(data, at)
	s.regiments[code]["x_m"] = m.x
	s.regiments[code]["y_m"] = m.y
	ArmySystem.march_day(data, s)
	var g := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + code}), "garrisons")
	assert_eq(String(g["to"]), "town:" + String(p["capital_burg"]))

func test_a_workshop_takes_its_rate_orders() -> void:
	var codes := Ledger.actions_for(data, "workshop:%d" % cell).map(func(a: Dictionary) -> String: return String(a["label"]))
	assert_eq(codes, ["Let it go cold", "Run it at half", "Run it in full"])
	var cold: Dictionary = Ledger.actions_for(data, "workshop:%d" % cell)[0]
	assert_eq(Ledger.params_of(cold, "workshop:%d" % cell), {"cell": cell, "rate": 0})

func test_the_hungry_host_loop_runs_when_the_ranks_go_hungry() -> void:
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0
	var running := false
	for lp: Dictionary in Ledger.snapshot(data, s, "war", {})["loops"]:
		if String(lp["id"]) == "hungry_host":
			running = bool(lp["running"])
	assert_true(running)

func test_labels() -> void:
	assert_string_contains(LedgerResolvers.label_of(data, s, "workshop:%d" % cell), "War workshop at")
	assert_eq(LedgerResolvers.label_of(data, s, "workshop:999999999"), "")
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	assert_string_contains(LedgerResolvers.label_of(data, s, "supply_line:" + code), "Supply line from")

func test_the_instances_are_the_plans_rows() -> void:
	var ws := LedgerResolvers.instances("workshops", data, s)
	assert_eq(ws.map(func(r: Dictionary) -> String: return String(r["id"])), ["workshop:%d" % cell])
	var lines := LedgerResolvers.instances("supply_lines", data, s)
	assert_eq(lines.size(), SupplySystem.plan(data, s).size())

# --- gauges (§6.3 "a property") ----------------------------------------------

func test_a_regiment_carries_its_supplies_and_morale() -> void:
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	s.regiments[code]["morale"] = 42
	var snap := Ledger.snapshot(data, s, "war", {"id": "regiment:" + code})
	var node := _node(snap, "regiment:" + code)
	var sup := _prop(node, "supplies")
	assert_eq(int(sup["value"]), ArmySystem.bars_of(data, s, code).y)
	assert_eq(int(sup["max"]), 1000)
	assert_eq(String(sup["label"]), "Supplies")
	var mor := _prop(node, "morale")
	assert_eq(int(mor["value"]), 42)
	assert_eq(int(mor["max"]), 100)

func test_a_pool_carries_its_stock_against_a_year_of_intake() -> void:
	s.metrics["grain"] = 30.0
	s.metrics["lord_civil"] = 70.0
	s.metrics["strategic"] = 5.0
	s.metrics["lord_strategic"] = 6.0
	var snap := Ledger.snapshot(data, s, "economy", {})
	var months := int(data.bal("ledger_gauge_stock_months"))
	var civ := _prop(_node(snap, "type:civil_goods"), "stock")
	assert_eq(int(civ["value"]), 100)
	var intake := LedgerResolvers.intake_of(data, s)
	assert_eq(int(civ["max"]), maxi(int(intake["civil"]) * months, 1))
	var strat := _prop(_node(snap, "type:strategic_goods"), "stock")
	assert_eq(int(strat["value"]), 11)
	assert_eq(int(strat["max"]), maxi(int(intake["strategic"]) * months, 1))

func test_a_sphere_without_a_property_carries_none() -> void:
	var snap := Ledger.snapshot(data, s, "economy", {})
	assert_eq(_node(snap, "type:manor")["props"], [])
	assert_eq(_node(snap, "type:regiment").get("props", []), [], "a TYPE of regiment is no one regiment")

func test_a_foreign_regiment_shows_no_gauge_unless_in_dev_mode() -> void:
	var realm := data.resolve_realm("player_realm")
	var foreign := ""
	var codes: Array = ArmySystem.roster(data, s).keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(data, String(c), s).get("kingdom_code", "")) != realm:
			foreign = String(c)
			break
	if foreign == "":
		pass_test("the pack has no foreign regiment")
		return
	assert_eq(LedgerResolvers.props_of(data, s, "regiment:" + foreign), [])
	Intel.dev_all = true
	assert_eq(LedgerResolvers.props_of(data, s, "regiment:" + foreign).size(), 2)

# --- cards (final review Minor5) ---------------------------------------------

func test_a_supply_lines_card_states_its_road() -> void:
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	s.regiments[code]["order"] = ArmySystem.ORDER_MARCH
	var id := "supply_line:" + code
	var line := SupplySystem.line_of(data, s, code)
	var card := LedgerCards.entry(data, s, id, Ledger.snapshot(data, s, "war", {"id": id}))
	var from := String(data.burgs[String(line["town"])]["label"])
	@warning_ignore("integer_division")
	assert_eq(String(card["lines"][0]), "from %s, %d km, %d%% lost on the way — %s" % [from,
		int(line["length_km"]), int(line["loss_permille"]) / 10, String(line["state"])])

func test_a_workshops_card_names_its_rate() -> void:
	var id := "workshop:%d" % cell
	var card := LedgerCards.entry(data, s, id, Ledger.snapshot(data, s, "economy", {"id": id}))
	assert_eq(String(card["lines"][0]), "Runs in full")
	WorkshopSystem.set_rate(s, cell, 500)
	card = LedgerCards.entry(data, s, id, Ledger.snapshot(data, s, "economy", {"id": id}))
	assert_eq(String(card["lines"][0]), "Runs at half")
	WorkshopSystem.set_rate(s, cell, 0)
	card = LedgerCards.entry(data, s, id, Ledger.snapshot(data, s, "economy", {"id": id}))
	assert_eq(String(card["lines"][0]), "Runs cold")
