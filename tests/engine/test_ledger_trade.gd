# tests/engine/test_ledger_trade.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The LEDGER lights industry and trade (spec 2026-09-30-ledger-industry-trade-design).

var data: DataRepository
var s: GameState
var sys: ActionSystem

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
	sys = ActionSystem.new(data)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func _link(snap: Dictionary, type: String) -> Dictionary:
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == type:
			return l
	return {}

func _links(snap: Dictionary, type: String) -> Array:
	return (snap["links"] as Array).filter(func(l: Dictionary) -> bool: return String(l["type"]) == type)

## The steward runs the tolls in full and honestly (carry 7).
func _able_honest_steward() -> Character:
	var c: Character = s.characters[String(s.council["steward"])]
	c.skills["sk_steward"] = 16
	c.opinion = 50
	c.traits = []
	c.attributes["integrity"] = 50
	return c

func _first_route() -> Dictionary:
	return MarketSystem.routes(data, s)[0]

## A type is built exactly when something reads it: no live link reaches a
## planned type, and every live type is an end of some live link.
func test_a_type_is_live_exactly_when_a_live_link_reads_it() -> void:
	var live := {}
	for r: Dictionary in data.ledger_types:
		live[String(r["type_id"])] = String(r["status"]) == "live"
	var touched := {}
	for r: Dictionary in data.ledger_links:
		if String(r["status"]) != "live":
			continue
		for end in ["from_type", "to_type"]:
			assert_true(live.get(String(r[end]), false), "%s reaches a planned type %s" % [r["link_id"], r[end]])
			touched[String(r[end])] = true
	for id: String in live:
		if live[id]:
			assert_true(touched.has(id), "%s is live with nothing reading it" % id)

func test_a_route_is_its_toll() -> void:
	var r := _first_route()
	var ego := Ledger.snapshot(data, s, "economy", {"id": "trade_route:" + String(r["kingdom"])})
	assert_eq(_link(ego, "routes")["flow"], int(r["claimed"]))
	assert_eq(String(_link(ego, "routes")["to"]), "type:gold")

func test_the_type_level_route_is_every_toll() -> void:
	var said := 0
	for r: Dictionary in MarketSystem.routes(data, s):
		said += int(r["claimed"])
	assert_eq(int(_link(Ledger.snapshot(data, s, "economy", {}), "routes")["flow"]), said)

func test_an_honest_stewards_route_is_one_account_naming_both_sources() -> void:
	_able_honest_steward()
	var r := _first_route()
	var l := _link(Ledger.snapshot(data, s, "economy", {"id": "trade_route:" + String(r["kingdom"])}), "routes")
	assert_eq(l["accounts"].size(), 1)
	assert_string_contains(String(l["accounts"][0]["source"]), "the treasury's own count")
	assert_string_contains(String(l["accounts"][0]["source"]), "Steward")

func test_a_venal_steward_splits_the_route() -> void:
	var st := _able_honest_steward()
	st.traits = ["venal"]
	var r := _first_route()
	assert_gt(int(r["skimmed"]), 0, "a venal steward skims this route")
	var l := _link(Ledger.snapshot(data, s, "economy", {"id": "trade_route:" + String(r["kingdom"])}), "routes")
	assert_eq(l["accounts"].size(), 2, "his word and the treasury's count")
	assert_eq(int(l["accounts"][0]["value"]), int(r["claimed"]))
	assert_eq(int(l["accounts"][1]["value"]), int(r["toll"]))

func test_a_same_month_audit_stands_beside_the_venal_stewards_word() -> void:
	var st := _able_honest_steward()
	st.traits = ["venal"]
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "trade_route"}), s)
	var r := _first_route()
	var l := _link(Ledger.snapshot(data, s, "economy", {"id": "trade_route:" + String(r["kingdom"])}), "routes")
	assert_eq(l["accounts"].size(), 2, "the audit agrees with the treasury and merges into it")
	assert_string_contains(String(l["accounts"][1]["source"]), "the audit of")

func test_the_audit_letter_has_one_fact_per_route_and_the_total() -> void:
	var facts := AuditWriter.facts(data, s, "trade_route")
	var routes := MarketSystem.routes(data, s)
	assert_eq(facts.size(), routes.size() + 1)
	for i in routes.size():
		assert_eq(String(facts[i]["key"]), "trade_route:" + String(routes[i]["kingdom"]))
		assert_eq(int(facts[i]["exact"]), int(routes[i]["toll"]))
		assert_eq(int(facts[i]["claimed"]), int(routes[i]["claimed"]))
	assert_eq(String(facts[-1]["key"]), "total")

func test_a_caught_steward_skims_the_trade_on_his_ego() -> void:
	var st := _able_honest_steward()
	st.traits = ["venal"]
	s.skims[st.id] = {"trade_route": 12}
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "trade_route"}), s)
	var skims := _link(Ledger.snapshot(data, s, "economy", {"id": "character:" + st.id}), "skims_trade")
	assert_false(skims.is_empty(), "caught, his skim is drawn")
	assert_eq(String(skims["to"]), "type:trade_route")
	assert_eq(int(skims["flow"]), 12)

func test_the_steward_governs_every_route() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	var ties := _links(Ledger.snapshot(data, s, "economy", {"id": "character:" + st.id}), "governs_trade")
	assert_eq(ties.size(), MarketSystem.routes(data, s).size())
	var e := LedgerCards.entry(data, s, "character:" + st.id,
		Ledger.snapshot(data, s, "economy", {"id": "character:" + st.id}))
	assert_true((e["lines"] as Array).any(func(t: String) -> bool: return t.begins_with("governs the trade tolls (")),
		str(e["lines"]))

func test_closing_and_reopening_a_route() -> void:
	var k := String(_first_route()["kingdom"])
	var close := ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": 0})
	assert_eq(sys.validate(close, s), "")
	sys.execute(close, s)
	assert_true(k in s.closed_routes)
	assert_ne(sys.validate(close, s), "", "already closed")
	sys.execute(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": 1}), s)
	assert_false(k in s.closed_routes)

func test_a_route_that_is_not_there_or_a_bad_flag_is_refused() -> void:
	var k := String(_first_route()["kingdom"])
	assert_ne(sys.validate(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": "atlantis", "open": 0}), s), "")
	assert_ne(sys.validate(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": 2}), s), "")
	assert_string_contains(sys.validate(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": 1}), s),
		"already open")
	# Final fix wave, I2b: a missing or unknown kingdom is refused on its
	# own, with player wording — never "no trade route to " with nothing
	# after it (an empty label reads as a hole in the sentence).
	var missing := sys.validate(ActionRequest.make("TRADE_ROUTE_SET", {"open": 0}), s)
	assert_ne(missing, "")
	assert_false(missing.contains(" to "), missing)
	var unknown := sys.validate(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": "atlantis", "open": 0}), s)
	assert_false(unknown.contains(" to "), unknown)
	# open must be exactly 0/1 or "0"/"1" (final fix wave, I2b): int("abc")
	# is silently 0 in GDScript, which must never read as a real CLOSE
	# order — a string "0"/"1" is still accepted, since that is how a
	# player-typed or LLM-proposed order can arrive.
	assert_ne(sys.validate(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": "abc"}), s), "")
	assert_eq(sys.validate(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": "0"}), s), "",
		"a string \"0\" is still a real close order")

func test_closing_a_route_angers_the_guildmaster_with_a_reason() -> void:
	var k := String(_first_route()["kingdom"])
	var g: Character = s.characters[ActionSystem.GUILDMASTER]
	var was := g.opinion
	sys.execute(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": 0}), s)
	assert_eq(g.opinion, was + int(data.bal("trade_close_opinion")))
	var label := MarketSystem.label_of(data, k)
	assert_true(g.opinion_log.any(func(e: Dictionary) -> bool:
		return String(e["reason"]) == "the crown closed the trade with " + label), str(g.opinion_log))

func test_a_closed_route_pays_nothing_on_the_ledger() -> void:
	var k := String(_first_route()["kingdom"])
	sys.execute(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": 0}), s)
	var l := _link(Ledger.snapshot(data, s, "economy", {"id": "trade_route:" + k}), "routes")
	assert_eq(int(l["flow"]), 0)
	var e := LedgerCards.entry(data, s, "trade_route:" + k, Ledger.snapshot(data, s, "economy", {"id": "trade_route:" + k}))
	assert_string_contains(String(e["lines"][0]), "Closed")

func test_the_route_offers_close_audit_and_give() -> void:
	var k := String(_first_route()["kingdom"])
	var codes: Array = Ledger.actions_for(data, "trade_route:" + k, s).map(
		func(a: Dictionary) -> String: return String(a["code"]))
	assert_has(codes, "TRADE_ROUTE_SET")
	var row: Dictionary = Ledger.actions_for(data, "trade_route:" + k, s)[0]
	var params := Ledger.params_of(row, "trade_route:" + k)
	assert_eq(String(params["kingdom"]), k, "a kingdom code stays a String")
	var thread := "routes|trade_route:%s|type:gold" % k
	var on_thread: Array = Ledger.actions_for(data, thread, s).map(
		func(a: Dictionary) -> String: return String(a["code"]))
	assert_has(on_thread, "LEDGER_AUDIT")
	assert_has(on_thread, "GOVERNOR_SET")

## Final fix wave, Minor5: the CLOSE order's own tooltip says closing only
## stops the tolls — there is no diplomacy yet — so the player is not left
## thinking it touches a relationship the game does not track. The OPEN
## order needs no such caveat.
func test_closing_a_route_says_it_only_stops_the_tolls() -> void:
	var k := String(_first_route()["kingdom"])
	var rows: Array = Ledger.actions_for(data, "trade_route:" + k, s)
	var close := {}
	var open := {}
	for a: Dictionary in rows:
		if String(a["label"]) == "Close the route":
			close = a
		elif String(a["label"]) == "Open the route":
			open = a
	assert_false(close.is_empty())
	assert_false(open.is_empty())
	assert_string_contains(String(close["hint"]), "no diplomacy yet")
	assert_eq(String(open["hint"]), "")

func test_a_route_and_a_market_are_named_by_the_live_labels() -> void:
	var k := String(_first_route()["kingdom"])
	assert_eq(LedgerResolvers.label_of(data, s, "trade_route:" + k), "Trade with " + MarketSystem.label_of(data, k))
	assert_eq(LedgerResolvers.label_of(data, s, "trade_route:atlantis"), "", "no such route")
	var m := String(MarketSystem.realm_markets(data, s)[0])
	var town := String(data.world_table("economy", "markets")[m]["center_burg"])
	assert_eq(LedgerResolvers.label_of(data, s, "market:" + m),
		"Market of " + String(data.burgs[town]["label"]))

func test_a_market_trades_its_value() -> void:
	var m := String(MarketSystem.realm_markets(data, s)[0])
	var ego := Ledger.snapshot(data, s, "economy", {"id": "market:" + m})
	assert_eq(int(_link(ego, "trades")["flow"]), MarketSystem.market_value(data, m, "civil"))
	assert_eq(int(_link(ego, "trades_strategic")["flow"]), MarketSystem.market_value(data, m, "strategic"))

func test_a_market_offers_buying_and_not_selling_there() -> void:
	var m := String(MarketSystem.realm_markets(data, s)[0])
	var rows := Ledger.actions_for(data, "market:" + m, s)
	var buy: Array = rows.filter(func(a: Dictionary) -> bool: return String(a["code"]) == "GOODS_BUY")
	assert_eq(buy.size(), 2, "civil and strategic")
	assert_eq(rows.filter(func(a: Dictionary) -> bool: return String(a["code"]) == "GOODS_SELL").size(), 0,
		"selling at a market never beats the factor: not offered (Task 3 review ruling)")
	var req := ActionRequest.make("GOODS_BUY", Ledger.params_of(buy[0], "market:" + m))
	assert_eq(sys.validate(req, s), "", "the int market id from the LEDGER is accepted")

func test_a_forge_eats_on_the_ledger() -> void:
	var cell := int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, "smithy", "a test forge")
	var ego := Ledger.snapshot(data, s, "economy", {"id": "building:%d:smithy" % cell})
	assert_false(_link(ego, "consumes_strategic").is_empty(), "iron is a strategic good")
	var gold := 0
	for row: Dictionary in IndustrySystem.plan(data, s):
		if int(row["cell"]) == cell and String(row["code"]) == "smithy":
			gold += int(row["gold"])
	assert_eq(int(_link(ego, "consumes_strategic")["flow"]), gold)
	assert_true(_link(ego, "consumes").is_empty(), "a forge eats no civil goods")

func test_the_artisans_build_their_provinces_buildings() -> void:
	var home := MapManors.home_province(data, s)
	var cell := int(MapManors.manors_of_province(data, home, s)[0])
	MapManors.build(data, s, cell, "smithy", "a test forge")
	var ego := Ledger.snapshot(data, s, "economy", {"id": "artisans:" + home})
	var b := _link(ego, "builds")
	assert_eq(String(b["to"]), "building:%d:smithy" % cell)
	assert_eq(int(b["flow"]), MapManors.work_speed_permille(data, s, home) - 1000)
	assert_eq(LedgerResolvers.label_of(data, s, "artisans:" + home),
		"Artisans of " + String(data.provinces[home]["label"]))

## Final fix wave, Minor2: an artisans card for a province the crown does
## not control carries no "Works go N% faster" head — it matches
## work_speed_permille's own plain 1000‰ there and label_of's "".
func test_an_uncontrolled_provinces_artisans_have_no_card_head() -> void:
	var home := MapManors.home_province(data, s)
	var foreign := ""
	for p: String in data.provinces:
		if p != home and not MapManors.controlled_provinces(data, s).has(p):
			foreign = p
			break
	assert_ne(foreign, "", "the pack has an uncontrolled province")
	var id := "artisans:" + foreign
	var e := LedgerCards.entry(data, s, id, Ledger.snapshot(data, s, "economy", {"id": id}))
	for line: String in (e["lines"] as Array):
		assert_false(String(line).begins_with("Works go"), str(e["lines"]))

func test_a_work_in_hand_is_a_building_the_artisans_raise() -> void:
	var home := MapManors.home_province(data, s)
	var cell := int(MapManors.manors_of_province(data, home, s)[0])
	assert_true(MapManors.start_work(data, s, cell, "chapel", "a test work"))
	var id := "building:%d:chapel" % cell
	assert_ne(LedgerResolvers.label_of(data, s, id), "", "a work in hand is named")
	var ego := Ledger.snapshot(data, s, "economy", {"id": id})
	assert_false(_link(ego, "builds").is_empty())

## The master of works governs the artisans' flow (the `works` Governance
## flow); a fresh campaign seats none, so the type level draws a vacant tie.
func test_the_works_are_governed_and_vacant_at_the_start() -> void:
	var gov := _link(Ledger.snapshot(data, s, "economy", {}), "governs_works")
	assert_false(gov.is_empty())
	assert_true(bool(gov["vacant"]))
	var st := String(s.council["steward"])
	sys.execute(ActionRequest.make("GOVERNOR_SET", {"flow": "works", "character": st}), s)
	var ties := _links(Ledger.snapshot(data, s, "economy", {"id": "character:" + st}), "governs_works")
	assert_eq(ties.size(), MapManors.controlled_provinces(data, s).size())
	assert_eq(String(_link(Ledger.snapshot(data, s, "economy", {}), "builds")["governor"]), st,
		"the builds thread names the man given the works")

## The `books` ruling (Task 2 review): the building works keep no books.
func test_the_works_keep_no_books_to_audit() -> void:
	var st := String(s.council["steward"])
	sys.execute(ActionRequest.make("GOVERNOR_SET", {"flow": "works", "character": st}), s)
	assert_eq(sys.validate(ActionRequest.make("LEDGER_AUDIT", {"flow": "works"}), s),
		"The building works keeps no books to audit")
	assert_eq(sys.validate(ActionRequest.make("LEDGER_AUDIT", {"flow": "trade_route"}), s), "")
	assert_true(bool(data.ledger_governance["trade_route"]["books"]))
	assert_false(bool(data.ledger_governance["works"]["books"]))

func test_the_works_offer_no_audit() -> void:
	var codes: Array = Ledger.actions_for(data, "builds|type:artisans|type:building", s).map(
		func(a: Dictionary) -> String: return String(a["code"]))
	assert_does_not_have(codes, "LEDGER_AUDIT")
	assert_has(codes, "GOVERNOR_SET")

func test_the_instances_are_listed() -> void:
	var routes := LedgerResolvers.instances("trade_routes", data, s)
	assert_eq(routes.size(), MarketSystem.routes(data, s).size())
	assert_eq(LedgerResolvers.instances("markets", data, s).size(), MarketSystem.realm_markets(data, s).size())
	assert_eq(LedgerResolvers.instances("artisans", data, s).size(),
		MapManors.controlled_provinces(data, s).size())

## A snapshot reads the industry plan and the routes once (the memo).
func test_the_plans_are_memoised_for_one_snapshot_only() -> void:
	LedgerResolvers.begin_memo()
	var a := LedgerResolvers._industry_plan(data, s)
	var r := LedgerResolvers._routes(data, s)
	assert_true(is_same(a, LedgerResolvers._industry_plan(data, s)))
	assert_true(is_same(r, LedgerResolvers._routes(data, s)))
	LedgerResolvers.end_memo()
	assert_false(LedgerResolvers.memo_active())

func test_the_order_has_its_catalogue_rows() -> void:
	assert_true(data.actions.has("TRADE_ROUTE_SET"))
	assert_true(data.order_costs.has("TRADE_ROUTE_SET"), "invariant 8")
	assert_false(OpinionDrift.signature_for(data, "TRADE_ROUTE_SET", {}).is_empty())
