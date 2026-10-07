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
	var inflow := TownStores.month_inflow(repo, s)
	var sum := 0
	for t: String in inflow:
		sum += int(inflow[t]["lord"]) + int(inflow[t]["crown"]) + int(inflow[t]["house"])
	assert_gt(sum, 0, "the realm's manors make strategic goods")
	var type_level := _run("stocks", "")
	assert_eq(int(type_level[0]["flow"]), sum)
	var catch := TownStores.catchment(repo, s)
	assert_false(catch.is_empty())
	var cells: Array = catch.keys()
	cells.sort()
	var cell: int = cells[0]
	var one := _run("stocks", "manor:%d" % cell)
	assert_eq(one.size(), 1)
	assert_eq(String(one[0]["to"]), "town:" + String(catch[cell]))
	assert_eq(int(one[0]["flow"]), int(RealmEconomy.line_of(repo, s, cell)["strategic"]))
	# a town reads every manor of its catchment, in cell order
	var mine: Array = cells.filter(func(c: int) -> bool: return String(catch[c]) == String(catch[cell]))
	var from_town := _run("stocks", "town:" + String(catch[cell]))
	assert_eq(from_town.map(func(l: Dictionary) -> String: return String(l["from"])),
		mine.map(func(c: int) -> String: return "manor:%d" % c))
	for l: Dictionary in from_town:
		assert_eq(int(l["flow"]), int(RealmEconomy.line_of(repo, s, int(String(l["from"]).substr(6)))["strategic"]))
	# the memoised index agrees with the plain one
	LedgerResolvers.begin_memo()
	var memo_town := _run("stocks", "town:" + String(catch[cell]))
	LedgerResolvers.end_memo()
	assert_eq(memo_town.size(), from_town.size())

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

func _a_family() -> String:
	for c: Character in s.characters.values():
		if c.family_name != "":
			return c.family_name
	return ""

func test_sells_to_counts_a_retired_lines_and_a_towns_topups() -> void:
	var fam := _a_family()
	# a regiment with no line: its entry's top-ups sell from the town it holds
	var held := ""
	for c in s.regiments.keys():
		var reg := ArmySystem.regiment(repo, String(c))
		if String(reg.get("is_naval", "0")) != "1" and ArmySystem.held_town_of(repo, reg, s) != "":
			code = String(c)
			held = ArmySystem.held_town_of(repo, reg, s)
			break
	assert_ne(held, "", "a land regiment stands in a town the realm holds")
	s.supply_lines.erase(code)
	s.regiments[code]["m_bought"] = {fam: 300}
	var links := _run("sells_to", "house:" + fam)
	assert_eq(links.size(), 1)
	assert_eq(String(links[0]["to"]), "town:" + held)
	assert_eq(int(links[0]["flow"]), TownStores.gold_of_units(repo, 300))
	# with a line, the entry's purchases go to the line's town, added to the line's own
	_flow()
	s.supply_lines[code]["m_bought"] = {fam: 100}
	links = _run("sells_to", "house:" + fam)
	assert_eq(links.size(), 1)
	assert_eq(String(links[0]["to"]), "town:" + town)
	assert_eq(int(links[0]["flow"]), TownStores.gold_of_units(repo, 400))
	assert_eq(int(_run("sells_to", "")[0]["flow"]), TownStores.gold_of_units(repo, 400))

func test_sells_to_skips_a_regiment_in_the_open_with_no_line() -> void:
	var fam := _a_family()
	for c in s.regiments.keys():
		var reg := ArmySystem.regiment(repo, String(c))
		if String(reg.get("is_naval", "0")) != "1" and ArmySystem.held_town_of(repo, reg, s) == "":
			s.regiments[c]["m_bought"] = {fam: 50}
			break
	assert_eq(_run("sells_to", ""), [])

func test_the_town_card_says_how_long_its_stores_last() -> void:
	_flow()
	s.town_stock[town] = {"crown": 600, "lord": 300, "house": 100}
	var draw := 0
	for row: Dictionary in SupplySystem.plan(repo, s):
		if String(row["town"]) == town:
			draw += int(row["need"])
	assert_gt(draw, 0)
	var rows := {}
	for f: Array in MapObjects.burg_card(repo, s, town)["fields"]:
		rows[String(f[0])] = String(f[1])
	assert_eq(rows["Stores last"], "%d days at today's draw" % (1000 * Calendar.DAYS_PER_TICK / draw))
	s.supply_lines.clear()
	rows = {}
	for f: Array in MapObjects.burg_card(repo, s, town)["fields"]:
		rows[String(f[0])] = String(f[1])
	assert_false(rows.has("Stores last"), "no draw, no line to read")
