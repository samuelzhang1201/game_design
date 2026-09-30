extends GutTest
## Buildings eat (spec 2026-09-30-ledger-industry-trade-design, M5): a
## standing input building is fed from its own manor's units first
## (ManorEconomy.line_of nets them — still the only rounding), the rest is
## bought from the lord's pool of the good at its price at the month's end
## (IndustrySystem.settle_month), and a building the pool cannot pay for
## stands IDLE the next month, making and eating nothing.

var data: DataRepository
var s: GameState
## A home-province manor that makes no iron of its own: its forge buys all 3.
var cell := -1

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()
	cell = _home_manor(func(c: int) -> bool:
		return not (ManorEconomy.line_of(data, s, c, s.tick)["units"] as Dictionary).has("iron"))

func after_each() -> void:
	RealmEconomy.forget()

## The first manor of the home province (cell order) that `ok` accepts.
func _home_manor(ok: Callable, skip: int = -1) -> int:
	var cells: Array = MapManors.manors_of_province(data, MapManors.home_province(data, s), s).duplicate()
	cells.sort()
	for c: int in cells:
		if c != skip and bool(ok.call(c)):
			return c
	return -1

func _smithy(at: int = -1) -> void:
	assert_true(MapManors.build(data, s, cell if at < 0 else at, "smithy", "a test forge"))

func test_the_inputs_table() -> void:
	assert_eq(data.building_inputs["smithy"], [{"good": "iron", "units": 3}])
	assert_eq(data.building_inputs["armoury"], [{"good": "tools", "units": 1}, {"good": "iron", "units": 2}],
		"file order kept")
	assert_eq(data.building_inputs["shipwright"].size(), 2)
	assert_false(data.building_inputs.has("war_workshop"), "a war workshop converts pools, not units")

func test_a_fed_smithy_makes_tools() -> void:
	assert_ne(cell, -1, "a home manor without iron of its own")
	_smithy()
	var line := ManorEconomy.line_of(data, s, cell, s.tick)
	assert_gt(int((line["units"] as Dictionary).get("tools", 0)), 0)
	assert_eq(line["fed"], {"smithy": {"iron": 0}}, "no iron of its own: it eats none of the manor's")

func test_its_own_iron_feeds_it_first() -> void:
	var miner := _home_manor(func(c: int) -> bool: return MapManors.focus_allowed(data, c, "iron"))
	if miner == -1:
		pending("no home manor may work iron on this pack")
		return
	# A focus set long ago has settled in whole (MapManors.focus_ramp).
	s.manor_focus[str(miner)] = {"focus": "iron", "since": -1000}
	_smithy(miner)
	# The same manor with its forge idle: the forge's output bonus (5%) still
	# stands, but it makes and eats nothing — the line to compare against.
	s.idle_buildings[str(miner)] = ["smithy"]
	var bare := ManorEconomy.line_of(data, s, miner, s.tick)
	s.idle_buildings.clear()
	var iron := int((bare["units"] as Dictionary).get("iron", 0))
	assert_gt(iron, 0, "a manor working iron makes iron")
	var line := ManorEconomy.line_of(data, s, miner, s.tick)
	var own := int((line["fed"]["smithy"] as Dictionary).get("iron", 0))
	assert_eq(own, mini(iron, 3), "a manor working iron feeds its own forge first")
	assert_eq(int((line["units"] as Dictionary).get("iron", 0)), iron - own, "what it ate is not shipped")
	# Hand-computed: the strategic pool loses the eaten iron (4 gold a unit)
	# and gains the forge's tools (12 gold a unit); nothing else moved.
	var tools := int((line["units"] as Dictionary).get("tools", 0))
	assert_eq(tools, 3, "3 tools a month at growth index 1000")
	assert_eq(int(line["strategic"]), int(bare["strategic"]) - own * 4 + tools * 12)
	assert_eq(int(line["tax"]), int(bare["tax"]), "eating moves no tax")
	var rows := IndustrySystem.plan(data, s).filter(func(r: Dictionary) -> bool: return int(r["cell"]) == miner)
	assert_eq(rows.size(), 1)
	assert_eq(int(rows[0]["own"]), own)
	assert_eq(int(rows[0]["buy"]), 3 - own)
	assert_eq(int(rows[0]["gold"]), (3 - own) * 4)

func test_the_plan_row() -> void:
	_smithy()
	assert_eq(IndustrySystem.plan(data, s), [{"cell": cell, "code": "smithy", "good": "iron", "need": 3,
		"own": 0, "buy": 3, "gold": 12, "pool": "strategic"}])

func test_the_rest_is_bought_from_the_lords_stores() -> void:
	_smithy()
	s.metrics["lord_strategic"] = 1000.0
	var lines := IndustrySystem.settle_month(data, s)
	assert_eq(lines, [{"metric": "lord_strategic", "delta": -12,
		"reason": "the lord's workshops buy their inputs"}], "3 iron × 4 gold")
	assert_false(MapManors.is_idle(s, cell, "smithy"))
	assert_eq(s.idle_buildings, {})

func test_unfed_it_idles_and_eats_and_makes_nothing() -> void:
	_smithy()
	s.metrics["lord_strategic"] = 0.0
	assert_eq(IndustrySystem.settle_month(data, s), [])
	assert_true(MapManors.is_idle(s, cell, "smithy"))
	RealmEconomy.forget()
	var line := ManorEconomy.line_of(data, s, cell, s.tick)
	assert_eq(int((line["units"] as Dictionary).get("tools", 0)), 0, "an idle forge makes nothing")
	assert_false((line["fed"] as Dictionary).has("smithy"), "and eats nothing")
	assert_eq(MapManors.building_output_of(data, s, cell), {})

func test_a_short_pool_feeds_the_first_forge_in_cell_order() -> void:
	var other := _home_manor(func(c: int) -> bool:
		return not (ManorEconomy.line_of(data, s, c, s.tick)["units"] as Dictionary).has("iron"), cell)
	assert_ne(other, -1)
	_smithy()
	_smithy(other)
	s.metrics["lord_strategic"] = 20.0
	var lines := IndustrySystem.settle_month(data, s)
	assert_eq(lines, [{"metric": "lord_strategic", "delta": -12,
		"reason": "the lord's workshops buy their inputs"}], "20 gold pays for one forge's 12, not two")
	var first := mini(cell, other)
	var second := maxi(cell, other)
	assert_false(MapManors.is_idle(s, first, "smithy"))
	assert_eq(s.idle_buildings, {str(second): ["smithy"]})

func test_a_paid_month_wakes_an_idle_forge() -> void:
	_smithy()
	s.idle_buildings[str(cell)] = ["smithy"]
	s.metrics["lord_strategic"] = 100.0
	var lines := IndustrySystem.settle_month(data, s)
	assert_eq(lines, [{"metric": "lord_strategic", "delta": -12,
		"reason": "the lord's workshops buy their inputs"}], "an idle forge still buys its whole need")
	assert_eq(s.idle_buildings, {}, "rewritten whole every settlement")

func test_a_civil_input_is_bought_from_the_civil_stores() -> void:
	var dry := _home_manor(func(c: int) -> bool:
		return not (ManorEconomy.line_of(data, s, c, s.tick)["units"] as Dictionary).has("grain"))
	if dry == -1:
		pending("every home manor makes grain on this pack")
		return
	assert_true(MapManors.build(data, s, dry, "brewery", "a test brewery"))
	s.metrics["lord_civil"] = 1000.0
	s.metrics["lord_strategic"] = 0.0
	assert_eq(IndustrySystem.settle_month(data, s), [{"metric": "lord_civil", "delta": -4,
		"reason": "the lord's workshops buy their inputs"}], "4 grain × 1 gold")

func test_idling_a_building_moves_the_province_sums() -> void:
	_smithy()
	var home := MapManors.home_province(data, s)
	var before := RealmEconomy.province(data, s, home)
	var key_before := RealmEconomy.province_key(data, s, home)
	s.idle_buildings[str(cell)] = ["smithy"]
	assert_ne(RealmEconomy.province_key(data, s, home), key_before, "the key sees the idle forge")
	var after := RealmEconomy.province(data, s, home)
	assert_lt(int(after["strategic"]), int(before["strategic"]), "the cache saw the idle forge")
	assert_eq(RealmEconomy.check_full(data, s), [], "the cache agrees with a fresh count")

func test_the_realm_signature_sees_idling() -> void:
	var sig := RealmEconomy.realm_signature(s)
	s.idle_buildings[str(cell)] = ["smithy"]
	assert_ne(RealmEconomy.realm_signature(s), sig)

func test_the_tick_buys_after_the_economy_and_idles_the_unpaid() -> void:
	_smithy()
	s.metrics["lord_strategic"] = -1000000.0
	var tick := TickEngine.new(data)
	tick.advance(s)
	assert_true(MapManors.is_idle(s, cell, "smithy"), "no stores: the forge idles next month")
	s.metrics["lord_strategic"] = 1000000.0
	var r := tick.advance(s)
	assert_false(MapManors.is_idle(s, cell, "smithy"), "paid: it works again")
	var reasons: Array = r.metric_deltas.map(func(d: Dictionary) -> String: return String(d["reason"]))
	var bought := reasons.find("the lord's workshops buy their inputs")
	assert_ne(bought, -1, "the purchase is a ledger line")
	assert_eq(float(r.metric_deltas[bought]["delta"]), -12.0, "an idle forge buys its whole 3 iron")
	assert_eq(String(r.metric_deltas[bought]["metric"]), "lord_strategic")
	assert_gt(bought, reasons.find("your own provinces' strategic goods"), "after the month's economy")

func test_the_plan_is_deterministic() -> void:
	_smithy()
	assert_eq(IndustrySystem.plan(data, s), IndustrySystem.plan(data, s))
	assert_eq(IndustrySystem.buildings(s), [[cell, "smithy"]])

func test_idle_state_survives_a_save() -> void:
	s.idle_buildings[str(cell)] = ["smithy"]
	assert_eq(GameState.from_dict(s.to_dict()).idle_buildings, s.idle_buildings)
	var json: Variant = JSON.parse_string(JSON.stringify(s.to_dict()))
	assert_eq(GameState.from_dict(json).idle_buildings, s.idle_buildings, "through JSON too")
	var old := s.to_dict()
	old.erase("idle_buildings")
	assert_eq(GameState.from_dict(old).idle_buildings, {}, "an old save: nothing idle")

func test_a_demolished_building_leaves_no_idle_mark() -> void:
	_smithy()
	s.idle_buildings[str(cell)] = ["smithy"]
	assert_gt(MapManors.demolish(data, s, cell, "smithy", "a test clearance"), -1.0)
	assert_eq(s.idle_buildings, {})
