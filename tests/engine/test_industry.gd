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
	# The same manor with its forge working but eating nothing (this test's
	# own repository, its inputs row set aside): the line to compare against.
	var inputs: Array = data.building_inputs["smithy"]
	data.building_inputs.erase("smithy")
	var bare := ManorEconomy.line_of(data, s, miner, s.tick)
	data.building_inputs["smithy"] = inputs
	var iron := int((bare["units"] as Dictionary).get("iron", 0))
	assert_gt(iron, 0, "a manor working iron makes iron")
	var line := ManorEconomy.line_of(data, s, miner, s.tick)
	var own := int((line["fed"]["smithy"] as Dictionary).get("iron", 0))
	assert_eq(own, mini(iron, 3), "a manor working iron feeds its own forge first")
	assert_eq(int((line["units"] as Dictionary).get("iron", 0)), iron - own, "what it ate is not shipped")
	# Hand-computed: the strategic pool loses the eaten iron (4 gold a unit);
	# the tools are made either way; nothing else moved.
	assert_eq(int((line["units"] as Dictionary).get("tools", 0)), 3, "3 tools a month at growth index 1000")
	assert_eq(int(line["strategic"]), int(bare["strategic"]) - own * 4)
	assert_eq(int(line["tax"]), int(bare["tax"]), "eating moves no tax")
	assert_eq(IndustrySystem.missing_of(data, s, miner, "smithy"), [] if own == 3 else ["iron"])
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

## Final fix wave, Minor1: two DIFFERENT buildings on ONE manor wanting the
## SAME good (armoury and smithy both eat iron) idle TOGETHER when the pool
## cannot pay either, and wake together once it can pay both — each bills
## its own whole need, in the plan's own cell-then-code order.
func test_two_buildings_on_one_manor_wanting_the_same_good_idle_and_wake_together() -> void:
	_smithy()
	assert_true(MapManors.build(data, s, cell, "armoury", "a test armoury"))
	s.metrics["lord_strategic"] = 0.0
	assert_eq(IndustrySystem.settle_month(data, s), [])
	assert_true(MapManors.is_idle(s, cell, "smithy"), "no iron of its own, no gold: idle")
	assert_true(MapManors.is_idle(s, cell, "armoury"), "wants the SAME iron: idle too")
	assert_eq(s.idle_buildings, {str(cell): ["armoury", "smithy"]})
	# armoury: 2 iron + 1 tools = 8 + 12 = 20; smithy: 3 iron = 12; 32 pays
	# both whole bills (neither manor makes iron or tools of its own).
	s.metrics["lord_strategic"] = 32.0
	var lines := IndustrySystem.settle_month(data, s)
	assert_eq(lines, [{"metric": "lord_strategic", "delta": -32,
		"reason": "the lord's workshops buy their inputs"}], "both whole bills paid at once")
	assert_false(MapManors.is_idle(s, cell, "smithy"))
	assert_false(MapManors.is_idle(s, cell, "armoury"))
	assert_eq(s.idle_buildings, {}, "both woke")

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
	assert_eq(IndustrySystem.buildings(data, s), [[cell, "smithy"]])

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

# ---- controller rulings after review (2026-09-30): an idle building gives
# NOTHING — no goods and no bonus — and it says why, once ----------------

func test_an_idle_smithy_lifts_nothing() -> void:
	var bare := ManorEconomy.line_of(data, s, cell, s.tick)
	_smithy()
	var working := ManorEconomy.line_of(data, s, cell, s.tick)
	s.idle_buildings[str(cell)] = ["smithy"]
	var idle := ManorEconomy.line_of(data, s, cell, s.tick)
	assert_eq(idle["units"], bare["units"], "its output bonus no longer lifts the manor's goods")
	assert_eq(int(idle["strategic"]), int(bare["strategic"]))
	assert_eq(int(idle["civil"]), int(bare["civil"]))
	assert_eq(int(idle["tax"]), int(bare["tax"]))
	assert_eq(idle["fed"], {})
	assert_gt(int(working["strategic"]), int(idle["strategic"]), "working, it did lift the line")

func test_an_idle_armoury_does_not_defend() -> void:
	var base := MapManors.defence_of(data, s, cell)
	assert_true(MapManors.build(data, s, cell, "armoury", "a test armoury"))
	assert_eq(MapManors.defence_of(data, s, cell), base + 10.0)
	s.idle_buildings[str(cell)] = ["armoury"]
	assert_eq(MapManors.defence_of(data, s, cell), base, "idle, its defence bonus lapses")

func test_an_idle_brewery_cheers_no_one() -> void:
	assert_true(MapManors.build(data, s, cell, "brewery", "a test brewery"))
	assert_almost_eq(float(MapManors.building_effects(data, s, [cell])["peasant_contentment"]), 0.1, 0.0001)
	s.idle_buildings[str(cell)] = ["brewery"]
	assert_eq(float(MapManors.building_effects(data, s, [cell])["peasant_contentment"]), 0.0,
		"idle, its monthly effect lapses")

func test_what_an_idle_building_lacks() -> void:
	_smithy()
	assert_eq(IndustrySystem.missing_of(data, s, cell, "smithy"), ["iron"], "no iron of its own")
	assert_eq(IndustrySystem.missing_of(data, s, cell, "mill"), [], "a mill eats nothing")
	assert_eq(IndustrySystem.idle_text(data, s, cell, "smithy"), "idle: no iron")

func test_the_card_says_a_building_is_idle() -> void:
	_smithy()
	assert_eq(MapObjects.manor_card(data, s, cell).get("idle", {}), {}, "a working forge is not idle")
	s.idle_buildings[str(cell)] = ["smithy"]
	var card := MapObjects.manor_card(data, s, cell)
	assert_eq(card["idle"], {"smithy": "idle: no iron"})
	var buildings := ""
	for f: Array in card["fields"]:
		if String(f[0]) == "Buildings":
			buildings = String(f[1])
	assert_string_contains(buildings, "Smithy (idle: no iron)")

func test_the_tick_names_a_newly_idle_building_once() -> void:
	_smithy()
	var tick := TickEngine.new(data)
	s.metrics["lord_strategic"] = -1000000.0
	tick.advance(s)
	assert_eq(tick.newly_idle, [{"cell": cell, "building": "smithy", "missing": ["iron"]}],
		"the month it first goes idle")
	s.metrics["lord_strategic"] = -1000000.0
	tick.advance(s)
	assert_true(MapManors.is_idle(s, cell, "smithy"), "still idle")
	assert_eq(tick.newly_idle, [], "said once, not every month")
	s.metrics["lord_strategic"] = 1000000.0
	tick.advance(s)
	assert_eq(tick.newly_idle, [], "paid: nothing new stands idle")
	s.metrics["lord_strategic"] = -1000000.0
	tick.advance(s)
	assert_eq(tick.newly_idle.size(), 1, "idle again after working: news again")

# ---- fix round 1 (task review, controller rulings 2026-09-30) -----------

func _iron_manor() -> int:
	var miner := _home_manor(func(c: int) -> bool: return MapManors.focus_allowed(data, c, "iron"))
	if miner != -1:
		s.manor_focus[str(miner)] = {"focus": "iron", "since": -1000}
	return miner

func test_a_waking_forge_pays_only_what_its_manor_cannot_give() -> void:
	var miner := _iron_manor()
	if miner == -1:
		pending("no home manor may work iron on this pack")
		return
	_smithy(miner)
	s.idle_buildings[str(miner)] = ["smithy"]
	# Idle, it ate nothing: the manor's whole iron is its own supply.
	var iron := int((ManorEconomy.line_of(data, s, miner, s.tick)["units"] as Dictionary).get("iron", 0))
	var own := mini(iron, 3)
	var row: Dictionary = IndustrySystem.plan(data, s).filter(
		func(r: Dictionary) -> bool: return int(r["cell"]) == miner)[0]
	assert_eq(int(row["own"]), own, "an idle forge's own is what its manor could give it")
	assert_eq(int(row["buy"]), 3 - own, "only the shortfall is bought")
	s.metrics["lord_strategic"] = 100.0
	var want: Array = [] if own == 3 else [{"metric": "lord_strategic", "delta": -(3 - own) * 4,
		"reason": "the lord's workshops buy their inputs"}]
	assert_eq(IndustrySystem.settle_month(data, s), want, "its own iron is not bought back")
	assert_false(MapManors.is_idle(s, miner, "smithy"), "it wakes")

func test_an_iron_manor_forge_wakes_on_empty_stores() -> void:
	var miner := _iron_manor()
	if miner == -1:
		pending("no home manor may work iron on this pack")
		return
	var iron := int((ManorEconomy.line_of(data, s, miner, s.tick)["units"] as Dictionary).get("iron", 0))
	if iron < 3:
		pending("this pack's iron manor makes under 3 iron")
		return
	_smithy(miner)
	s.idle_buildings[str(miner)] = ["smithy"]
	s.metrics["lord_strategic"] = 0.0
	assert_eq(IndustrySystem.settle_month(data, s), [], "a bill of 0")
	assert_eq(s.idle_buildings, {}, "a forge its own manor feeds never needs the lord's stores")

## A house the player's is not: another province's own house.
func _other_house() -> String:
	var home := MapManors.home_province(data, s)
	var codes: Array = data.provinces.keys()
	codes.sort()
	for code: String in codes:
		var house := MapObjects.house_name_of(data, code)
		if code != home and house != "" and house != MapManors.crown(s):
			return house
	return ""

func test_only_the_crowns_manors_buy_through_the_lord() -> void:
	_smithy()
	s.idle_buildings[str(cell)] = ["smithy"]
	var house := _other_house()
	assert_ne(house, "")
	assert_true(MapManors.set_owner(data, s, cell, house, "test: sold away"))
	assert_eq(IndustrySystem.buildings(data, s), [], "not the lord's building any more")
	assert_eq(IndustrySystem.plan(data, s), [])
	s.metrics["lord_strategic"] = 1000.0
	assert_eq(IndustrySystem.settle_month(data, s), [], "the lord is charged nothing")
	assert_eq(s.idle_buildings, {}, "and nothing is idle for it")
	var line := ManorEconomy.line_of(data, s, cell, s.tick)
	assert_gt(int((line["units"] as Dictionary).get("tools", 0)), 0, "it keeps working as the pack counts it")

func test_the_idle_words() -> void:
	assert_eq(IndustrySystem.idle_words([]), "idle")
	assert_eq(IndustrySystem.idle_words(["iron"]), "idle: no iron")
	assert_eq(IndustrySystem.idle_words(["tools", "iron"]), "idle: no tools and iron")
