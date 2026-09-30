# tests/engine/test_ledger_snapshot.gd
extends GutTest
## The picture the LEDGER draws (spec 2026-09-30 §6-§7): belief, not truth.

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	assert_not_null(data, DataRepository.last_error)
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	Intel.dev_all = false
	RealmEconomy.forget()

func _ids(snap: Dictionary) -> Array:
	return snap["nodes"].map(func(n: Dictionary) -> String: return String(n["id"]))

func _link(snap: Dictionary, type: String) -> Dictionary:
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == type:
			return l
	return {}

func test_the_type_level_draws_every_type_of_its_lens_built_or_not() -> void:
	var snap := Ledger.snapshot(data, s, "economy", {})
	assert_has(_ids(snap), "type:manor")
	for n: Dictionary in snap["nodes"]:
		assert_true(n.has("x") and n.has("z"), "a type sphere stands at its hand-set place")
	# M6 built the last economy type; the factions are still to come (PRD Step 5)
	var all := Ledger.snapshot(data, s, "all", {})
	assert_has(_ids(all), "type:faction", "a type not yet built is still drawn")
	var planned := _link(all, "faction_governs")
	assert_eq(String(planned["status"]), "planned")
	assert_null(planned["flow"])
	assert_eq(String(planned["planned_note"]), "lit when factions exist")

func test_no_link_joins_a_sphere_to_itself() -> void:
	for lens in ["economy", "war", "court", "intelligence", "all"]:
		for l: Dictionary in Ledger.snapshot(data, s, lens, {})["links"]:
			assert_ne(String(l["from"]), String(l["to"]), "%s: %s" % [lens, l["id"]])

func test_the_court_lens_is_the_web_of_the_court() -> void:
	var snap := Ledger.snapshot(data, s, "court", {})
	assert_eq(snap["nodes"].size(), s.characters.size())
	assert_eq(snap["links"].size(), s.relationships.size())
	var kin := _link(snap, "kin")
	assert_eq(int(kin["flow"]), absi(int(kin["sentiment"])))

func test_the_ego_network_of_a_regiment_touches_it() -> void:
	var reg: Dictionary = MapObjects.regiments_of(data, data.resolve_realm("player_realm"))[0]
	var id := "regiment:" + String(reg["regiment_code"])
	var snap := Ledger.snapshot(data, s, "all", {"id": id})
	assert_eq(String(snap["focus_id"]), id)
	assert_gt(snap["links"].size(), 0)
	for l: Dictionary in snap["links"]:
		assert_true(String(l["from"]) == id or String(l["to"]) == id)
	for n: Dictionary in snap["nodes"]:
		assert_false(n.has("x"), "an ego network is laid out, not placed by hand")

func test_a_vanished_focus_falls_back_to_the_type_level() -> void:
	var snap := Ledger.snapshot(data, s, "war", {"id": "courier:99999"})
	assert_true(snap["focus_lost"])
	assert_eq(String(snap["focus_id"]), "")
	assert_has(_ids(snap), "type:regiment")

func test_the_cap_folds_the_rest_into_one_more_sphere() -> void:
	data.balance["ledger_instance_cap"] = 2.0
	var home := MapManors.home_province(data, s)
	var n := MapManors.manors_of_province(data, home, s).size()
	assert_gt(n, 2, "the home province has more than two manors")
	var snap := Ledger.snapshot(data, s, "economy", {"id": "province:" + home})
	var parts := 0
	var more := ""
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == "part_of":
			parts += 1
			if String(l["from"]).begins_with("more:"):
				more = String(l["from"])
	assert_eq(parts, 3, "two manors and one +N more")
	assert_eq(LedgerResolvers.label_of(data, s, more), "+%d more" % (n - 2))

func test_a_fresh_reign_with_no_letters_still_draws() -> void:
	s.missives.clear()
	s.couriers.clear()
	var snap := Ledger.snapshot(data, s, "intelligence", {})
	assert_eq(int(_link(snap, "describes_province")["flow"]), 0)
	assert_eq(int(_link(snap, "carries")["flow"]), 0)

func test_the_intel_gate_blurs_what_the_crown_does_not_control() -> void:
	var realm := data.resolve_realm("player_realm")
	var mine := MapManors.controlled_provinces(data, s)
	var other := ""
	for code: String in MapOwnership.provinces_of(data, s, realm):
		if not code in mine:
			other = code
			break
	assert_ne(other, "", "the realm has a province the crown does not control")
	var cell := int(MapManors.manors_of_province(data, other, s)[0])
	var id := "manor:%d" % cell
	var acc: Dictionary = _link(Ledger.snapshot(data, s, "economy", {"id": id}), "yields_civil")["accounts"][0]
	assert_eq(String(acc["level"]), "general")
	assert_null(acc["value"], "words, not a figure")
	Intel.dev_all = true
	acc = _link(Ledger.snapshot(data, s, "economy", {"id": id}), "yields_civil")["accounts"][0]
	assert_eq(String(acc["level"]), "full")
	assert_eq(int(acc["value"]), int(RealmEconomy.line_of(data, s, cell)["civil"]))

func test_a_tie_is_never_a_belief_word() -> void:
	var realm := data.resolve_realm("player_realm")
	var mine := MapManors.controlled_provinces(data, s)
	var other := ""
	for code: String in MapOwnership.provinces_of(data, s, realm):
		if not code in mine:
			other = code
			break
	assert_ne(other, "", "the realm has a province the crown does not control")
	var cell := int(MapManors.manors_of_province(data, other, s)[0])
	var id := "manor:%d" % cell
	var snap := Ledger.snapshot(data, s, "economy", {"id": id})
	var acc: Dictionary = _link(snap, "part_of")["accounts"][0]
	assert_eq(String(acc["text"]), "")
	assert_eq(int(acc["value"]), -1)
	assert_eq(String(acc["level"]), "general")

func test_the_type_level_is_the_crowns_own_record() -> void:
	var acc: Dictionary = _link(Ledger.snapshot(data, s, "economy", {}), "taxed")["accounts"][0]
	assert_eq(String(acc["level"]), "full")
	assert_eq(String(acc["source"]), "own records")

func test_the_same_state_gives_the_same_picture() -> void:
	assert_eq_deep(Ledger.snapshot(data, s, "all", {}), Ledger.snapshot(data, s, "all", {}))

func test_a_loop_runs_by_its_condition() -> void:
	s.metrics["grain"] = 0.0
	var famine: Dictionary = Ledger.snapshot(data, s, "economy", {})["loops"][0]
	assert_eq(String(famine["id"]), "famine")
	assert_true(famine["running"])
	s.metrics["grain"] = 500.0
	assert_false(Ledger.snapshot(data, s, "economy", {})["loops"][0]["running"])

func test_a_loop_with_a_planned_link_never_runs() -> void:
	for lp: Dictionary in Ledger.snapshot(data, s, "all", {})["loops"]:
		if String(lp["id"]) == "war_chest":
			assert_false(lp["running"])

func test_orders_follow_the_node() -> void:
	var codes := func(id: String) -> Array:
		return Ledger.actions_for(data, id).map(func(a: Dictionary) -> String: return String(a["code"]))
	assert_has(codes.call("type:civil_goods"), "GOODS_BUY", "a pool is a singleton: the type sphere")
	assert_has(codes.call("manor:12"), "MANOR_BUILD")
	assert_false("MANOR_BUILD" in codes.call("type:manor"), "a type with instances takes orders per instance")
	assert_has(codes.call("trade_gold|type:gold|type:civil_goods"), "GOODS_BUY", "a thread's own orders")
	# owner 2026-09-30: a march garrisons on arrival, so no Garrison order is offered
	assert_false("ARMY_GARRISON" in codes.call("regiment:r7"), "no Garrison button")
	assert_eq(Ledger.params_of({"params": "regiment=@id"}, "regiment:r7"), {"regiment": "r7"})
	var buy: Dictionary = Ledger.actions_for(data, "type:civil_goods")[0]
	assert_eq(Ledger.params_of(buy, "type:civil_goods"), {"pool": "civil", "gold": 50})
	# final fix M2: a numeric id is a number, as an order's params expect
	assert_eq(Ledger.params_of({"params": "cell=@id|rate=0"}, "manor:12"), {"cell": 12, "rate": 0})

## Final fix M1: an order that spends a sum says so, and its fee apart.
func test_an_order_names_what_it_spends_and_its_fee() -> void:
	var buy: Dictionary = Ledger.actions_for(data, "type:civil_goods")[0]
	var gold := int(Ledger.params_of(buy, "type:civil_goods")["gold"])
	var fee := int(OrderCosts.gold_of(data, String(buy["code"])))
	var text := Ledger.order_text(data, buy, "type:civil_goods")
	assert_string_contains(text, "%d gold of civil goods" % gold)
	assert_string_contains(text, "+%d fee" % fee)
	for a: Dictionary in Ledger.actions_for(data, "regiment:r7"):
		assert_false(Ledger.order_text(data, a, "regiment:r7").contains("{"), "no placeholder left")

## Final fix I1: a spy's `tax` estimate reaches the LEDGER's `taxed` thread —
## the first report to reach a LEDGER thread. Shaped as SpySystem.report
## files one: a "spy" letter in the credible column about a manor subject of
## that cell, its tax as a span under the key `tax`.
func test_a_spy_report_on_a_manors_tax_reaches_its_taxed_thread() -> void:
	var realm := data.resolve_realm("player_realm")
	var mine := MapManors.controlled_provinces(data, s)
	var other := ""
	for code: String in MapOwnership.provinces_of(data, s, realm):
		if not code in mine:
			other = code
			break
	assert_ne(other, "", "the realm has a province the crown does not control")
	var cell := int(MapManors.manors_of_province(data, other, s)[0])
	var at := MapTerrain.cell_center(data, data.cells[cell])
	MissiveLog.add(data, s, MissiveLog.make("spy", "credible", s.absolute_day(),
		MissiveLog.subject("manor", MapManors.code_of(data, cell), cell, at), "A spy report",
		[MissiveLog.span("tax", "Tax", 40, 60)]))
	var acc: Dictionary = _link(Ledger.snapshot(data, s, "economy", {"id": "manor:%d" % cell}),
		"taxed")["accounts"][0]
	assert_eq(String(acc["source"]), "spy", "the report's own kind")
	assert_string_contains(String(acc["text"]), "40")
