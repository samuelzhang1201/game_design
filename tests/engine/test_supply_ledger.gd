extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The LEDGER's supply chain (spec 2026-10-07-army-supply-lines §2.3).

var repo: DataRepository
var s: GameState
var code := ""
var town := ""

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			code = String(c)
			break
	town = TownStores.realm_towns(repo, s)[0]

func _flow() -> void:
	s.supply_lines[code] = SupplyLines._new_record(town, 1200, 1)
	s.supply_lines[code]["state"] = SupplyLines.FLOWING

func _run(link_id: String, id: String) -> Array:
	for row: Dictionary in repo.ledger_links:
		if String(row["link_id"]) == link_id:
			return LedgerResolvers.run(row, repo, s, {"id": id} if id != "" else {})
	return []

func test_no_line_no_plan_row() -> void:
	assert_eq(SupplySystem.plan(repo, s), [])

func test_a_line_is_one_row_projecting_its_month() -> void:
	_flow()
	var rows := SupplySystem.plan(repo, s)
	assert_eq(rows.size(), 1)
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), s)
	assert_eq(int(rows[0]["need"]), use * 1200 / 1000)
	assert_eq(int(rows[0]["paid"]), TownStores.gold_of_units(repo, use * 1200 / 1000))
	assert_eq(String(rows[0]["town"]), town)

func test_the_link_types_are_the_new_chain() -> void:
	var live: Array = []
	for row: Dictionary in repo.ledger_links:
		if String(row["status"]) == "live":
			live.append(String(row["link_id"]))
	for id in ["stocks", "dispatches", "sells_to", "supplies_out"]:
		assert_true(live.has(id), id)
	assert_false(live.has("supplies_in"))

func test_the_regiment_card_names_the_supply_point() -> void:
	s.supply_lines[code] = SupplyLines._new_record(town, 800, 1)
	s.supply_lines[code]["state"] = SupplyLines.FLOWING
	var card := MapObjects.army_card(repo, code, s)
	var stat: Dictionary = (card["stats"] as Array).filter(func(x: Dictionary) -> bool:
		return String(x["key"]) == "army_supply_line")[0]
	assert_true(String(stat["tooltip"]).contains(String(repo.burgs[town]["label"])))

func test_dispatches_runs_town_to_line() -> void:
	_flow()
	var row: Dictionary = SupplySystem.plan(repo, s)[0]
	var type_level := _run("dispatches", "")
	assert_eq(type_level.size(), 1)
	assert_eq(int(type_level[0]["flow"]), int(row["paid"]))
	var links := _run("dispatches", "supply_line:" + code)
	assert_eq(links.size(), 1)
	assert_eq(String(links[0]["from"]), "town:" + town)
	assert_eq(String(links[0]["to"]), "supply_line:" + code)
	assert_eq(_run("dispatches", "town:" + town).size(), 1)

func test_stocks_runs_manor_to_town() -> void:
	var links := _run("stocks", "town:" + town)
	for l: Dictionary in links:
		assert_eq(String(l["to"]), "town:" + town)
		assert_true(String(l["from"]).begins_with("manor:"))
	var any: Dictionary = {}
	var catch := TownStores.catchment(repo, s)
	for cell in catch:
		any = {"cell": cell, "town": String(catch[cell])}
		break
	if not any.is_empty():
		var one := _run("stocks", "manor:%d" % int(any["cell"]))
		assert_eq(one.size(), 1)
		assert_eq(String(one[0]["to"]), "town:" + String(any["town"]))

func test_sells_to_reads_the_month_counters() -> void:
	_flow()
	var fam := ""
	for c: Character in s.characters.values():
		if c.family_name != "":
			fam = c.family_name
			break
	s.supply_lines[code]["m_bought"] = {fam: 400}
	var links := _run("sells_to", "house:" + fam)
	assert_eq(links.size(), 1)
	assert_eq(String(links[0]["to"]), "town:" + town)
	assert_eq(int(links[0]["flow"]), TownStores.gold_of_units(repo, 400))
	assert_eq(_run("sells_to", "").size(), 1)

func test_the_supply_line_is_named_from_its_town() -> void:
	assert_eq(LedgerResolvers.label_of(repo, s, "supply_line:" + code), "", "no line, no node")
	_flow()
	var label := LedgerResolvers.label_of(repo, s, "supply_line:" + code)
	assert_true(label.contains(String(repo.burgs[town]["label"])), label)
	assert_true(label.contains(String(ArmySystem.regiment(repo, code)["label"])), label)

func test_the_town_card_shows_its_stores() -> void:
	_flow()
	var card := MapObjects.burg_card(repo, s, town)
	var rows := {}
	for f: Array in card["fields"]:
		rows[String(f[0])] = String(f[1])
	assert_true(rows.has("Strategic stores"), "a realm town reads its stores")
	assert_eq(rows["Supply lines"], "1 from here")

func test_no_card_or_node_still_names_a_stronghold() -> void:
	_flow()
	assert_false(SupplySystem.line_of(repo, s, code).has("stronghold"))
