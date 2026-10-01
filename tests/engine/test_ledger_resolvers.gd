# tests/engine/test_ledger_resolvers.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The LEDGER's readers return the truth the real systems hold (spec
## 2026-09-30 §7.2); Ledger turns it into belief (Task 4).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	assert_not_null(data, DataRepository.last_error)
	s = SuiteData.campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func _row(link_id: String) -> Dictionary:
	for r: Dictionary in data.ledger_links:
		if String(r["link_id"]) == link_id:
			return r
	return {}

func _home_manor() -> int:
	var home := MapManors.home_province(data, s)
	return int(MapManors.manors_of_province(data, home, s)[0])

func test_every_live_link_has_a_reader_that_runs_at_type_level() -> void:
	for r: Dictionary in data.ledger_links:
		if String(r["status"]) != "live":
			continue
		assert_true(LedgerResolvers.has(String(r["resolver"])), String(r["link_id"]))
		assert_true(LedgerResolvers.run(r, data, s, {}) is Array)

func test_type_level_yields_are_the_crowns_own_intake() -> void:
	var p := RealmEconomy.purses(data, s)
	var civil := int(p["lord"]["civil"]) + int(p["realm_share"]["civil"])
	var got := LedgerResolvers.run(_row("yields_civil"), data, s, {})
	assert_eq(got.size(), 1)
	assert_eq(String(got[0]["from"]), "type:manor")
	assert_eq(String(got[0]["to"]), "type:civil_goods")
	assert_eq(int(got[0]["flow"]), civil)
	assert_true((got[0]["subj"] as Dictionary).is_empty(), "the crown's own records")

func test_the_ration_reader_is_the_ticks_ration() -> void:
	var people := TickEngine.court_people(data, s)
	var expect := int(roundf(float(people) / 1000.0 * data.bal("ration_gold_per_1000")))
	assert_eq(TickEngine.ration_of(data, s), expect)
	s.metrics["grain_ration"] = 1.0
	var half := int(float(expect) / 2.0)
	assert_eq(TickEngine.ration_of(data, s), half, "halved under the ration order")
	assert_eq(int(LedgerResolvers.run(_row("rations"), data, s, {})[0]["flow"]), half)

func test_a_manor_yields_its_own_line() -> void:
	var cell := _home_manor()
	var line := RealmEconomy.line_of(data, s, cell)
	var got := LedgerResolvers.run(_row("yields_civil"), data, s, {"id": "manor:%d" % cell})
	assert_eq(got.size(), 1)
	assert_eq(String(got[0]["to"]), "type:civil_goods")
	assert_eq(int(got[0]["flow"]), int(line["civil"]))
	assert_eq(String((got[0]["subj"] as Dictionary)["kind"]), "manor")

func test_a_province_lists_its_manors() -> void:
	var home := MapManors.home_province(data, s)
	var got := LedgerResolvers.run(_row("part_of"), data, s, {"id": "province:" + home})
	assert_eq(got.size(), MapManors.manors_of_province(data, home, s).size())
	assert_eq(String(got[0]["to"]), "province:" + home)

func test_the_court_relations_are_every_edge_of_their_type() -> void:
	var n := 0
	for e: Dictionary in s.relationships:
		if String(e["type"]) == "rival":
			n += 1
	var got := LedgerResolvers.run(_row("rival"), data, s, {"all": true})
	assert_eq(got.size(), n)
	for l: Dictionary in got:
		assert_eq(int(l["flow"]), absi(int(l["sentiment"])))

func test_a_characters_ties_touch_him() -> void:
	for l: Dictionary in LedgerResolvers.run(_row("kin"), data, s, {"id": "character:you"}):
		assert_true(String(l["from"]) == "character:you" or String(l["to"]) == "character:you")

func test_a_regiment_stands_in_the_province_it_has_reached() -> void:
	var reg: Dictionary = MapObjects.regiments_of(data, data.resolve_realm("player_realm"))[0]
	var code := String(reg["regiment_code"])
	var got := LedgerResolvers.run(_row("based_in"), data, s, {"id": "regiment:" + code})
	assert_eq(got.size(), 1)
	assert_eq(int(got[0]["flow"]), ArmySystem.headcount(data, reg))
	assert_true(String(got[0]["to"]).begins_with("province:"))

func test_trade_is_a_lever_with_no_magnitude() -> void:
	assert_eq(int(LedgerResolvers.run(_row("trade_gold"), data, s, {})[0]["flow"]), -1)

func test_instances_come_most_strained_first() -> void:
	var rows := LedgerResolvers.instances("regiments", data, s)
	assert_gt(rows.size(), 0)
	for i in range(1, rows.size()):
		assert_true(int(rows[i - 1]["strain"]) >= int(rows[i]["strain"]))
	assert_ne(String(rows[0]["label"]), "")

func test_what_is_gone_has_no_label() -> void:
	assert_eq(LedgerResolvers.label_of(data, s, "manor:999999999"), "")
	assert_eq(LedgerResolvers.label_of(data, s, "character:nobody"), "")
	assert_eq(LedgerResolvers.label_of(data, s, "courier:424242"), "")
	assert_eq(LedgerResolvers.label_of(data, s, "type:regiment"), "Regiments")

## Final fix, deferred #4: a demolished building's node names nothing, so a
## focus on it falls back to the type level.
func test_a_building_that_no_longer_stands_has_no_name() -> void:
	var cell := _home_manor()
	var code := ""
	for c: String in data.manor_buildings:
		if MapManors.build(data, s, cell, c, "a test building"):
			code = c
			break
	assert_ne(code, "", "some building stands on the home manor")
	var id := "building:%d:%s" % [cell, code]
	assert_ne(LedgerResolvers.label_of(data, s, id), "")
	(s.manor_buildings[str(cell)] as Array).erase(code)
	assert_eq(LedgerResolvers.label_of(data, s, id), "", "demolished: it names nothing")
	assert_true(Ledger.snapshot(data, s, "economy", {"id": id})["focus_lost"])

## Final fix wave, I2a: an artisans node for a province the crown does not
## control names nothing (Minor2: work_speed_permille gives that province
## the plain 1000‰ too — the artisans are the LEDGER's own), and a market
## node for a market that is not the crown's own kingdom's names nothing
## (Task 4's ruled minors) — both fall back to the type level, like the
## demolished building above.
func test_artisans_and_a_foreign_market_have_no_name() -> void:
	var home := MapManors.home_province(data, s)
	var foreign_province := ""
	for p: String in data.provinces:
		if p != home:
			foreign_province = p
			break
	assert_ne(foreign_province, "", "the pack has more than one province")
	assert_ne(LedgerResolvers.label_of(data, s, "artisans:" + home), "",
		"the crown's own province names its artisans")
	assert_eq(LedgerResolvers.label_of(data, s, "artisans:" + foreign_province), "",
		"not controlled: no name")
	var realm_market := String(MarketSystem.realm_markets(data, s)[0])
	var foreign_market := ""
	for id: String in data.world_table("economy", "markets"):
		if not MarketSystem.is_realm_market(data, s, id):
			foreign_market = id
			break
	assert_ne(foreign_market, "", "the pack has a market that is not the realm's")
	assert_ne(LedgerResolvers.label_of(data, s, "market:" + realm_market), "")
	assert_eq(LedgerResolvers.label_of(data, s, "market:" + foreign_market), "", "not the realm's: no name")


## Final review minors: the memoised burg_province is the uncached scan,
## a town annexed into another province included.
func test_the_memoised_burg_province_is_the_scan() -> void:
	var moved := ""
	for cell: int in data.manors:
		var burg := MapManors.burg_of(data, cell)
		if burg == "":
			continue
		for code: String in data.provinces:
			if code != String(data.burgs[burg]["province_code"]):
				s.manor_province[str(cell)] = code
				moved = burg
				break
		break
	assert_ne(moved, "", "a town's cell was annexed")
	var memo := {}
	LedgerResolvers.begin_memo()
	for burg: String in data.burgs:
		memo[burg] = LedgerResolvers.burg_province(data, s, burg)
		assert_eq(LedgerResolvers.burg_province(data, s, burg), memo[burg], "the cache answers the same: " + burg)
	LedgerResolvers.end_memo()
	for burg: String in data.burgs:
		assert_eq(memo[burg], MarketSystem.province_of_burg(data, s, burg), burg)
	assert_eq(memo[moved], String(s.manor_province.values()[0]), "the annexed town's new province")
