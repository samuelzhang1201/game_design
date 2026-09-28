extends GutTest
## The fog on the cards (spec 2026-09-28 §1 "Closing the leaks").

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	Intel.dev_all = false


## M9 (final review): DEV MODE is a static — never let one test's switch
## outlive it, even when the test aborts before its own last line.
func after_each() -> void:
	Intel.dev_all = false


func _foreign_manor(s: GameState) -> int:
	var realm := repo.resolve_realm("player_realm")
	var ids := repo.manors.keys()
	ids.sort()
	for id: int in ids:
		if MapOwnership.owner_of(repo, s, MapManors.province_of(repo, id, s)) != realm \
				and int(RealmEconomy.line_of(repo, s, id)["people"]) >= 500:
			return id
	return -1


func _foreign_regiment() -> String:
	var realm := repo.resolve_realm("player_realm")
	var codes := repo.world_table("military", "regiments").keys()
	codes.sort()
	for code: String in codes:
		var r: Dictionary = repo.world_table("military", "regiments")[code]
		if String(r["kingdom_code"]) != realm and int(MapObjects.regiment_size(repo, r)) >= 100:
			return code
	return ""


## Every string anywhere in a card, flattened.
func _texts(v: Variant) -> String:
	if v is Dictionary:
		var out := ""
		for k in v:
			out += " " + _texts(v[k])
		return out
	if v is Array:
		var out := ""
		for x in v:
			out += " " + _texts(x)
		return out
	return str(v)


func _leaks(text: String, n: int) -> bool:
	return n >= 100 and (text.contains(str(n)) or text.contains(Intel.num(n)))


func test_a_foreign_manor_card_shows_no_true_figures() -> void:
	var s := GameState.new_campaign(repo, 7)
	var cell := _foreign_manor(s)
	var line := RealmEconomy.line_of(repo, s, cell)
	var card := MapObjects.manor_card(repo, s, cell)
	assert_eq(String(card["known"]), "basic")
	var t := _texts(card)
	assert_false(_leaks(t, int(line["people"])), "people")
	assert_false(card.has("intel") and _leaks(_texts(card["intel"]), int(line["tax"])), "tax")
	assert_true(card.has("intel"))


func test_a_foreign_burg_card_is_fogged() -> void:
	var s := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if MapOwnership.owner_of(repo, s, String(b["province_code"])) == realm:
			continue
		var card := MapObjects.burg_card(repo, s, code)
		assert_ne(String(card["known"]), "full")
		assert_false(_leaks(_texts(card), int(float(b.get("population", 0)))), "population of " + code)
		assert_eq(float(card.get("wealth", 0.0)), 0.0)
		assert_eq(float(card.get("treasury", 0.0)), 0.0)
		return


func test_a_foreign_regiments_army_card_carries_no_exact_headcount() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _foreign_regiment()
	var r: Dictionary = repo.world_table("military", "regiments")[code]
	var total := int(MapObjects.regiment_size(repo, r))
	var card := MapObjects.army_card(repo, code, s)
	assert_false(_leaks(_texts(card), total), "headcount")


func test_a_report_shows_up_on_the_card_with_its_tag() -> void:
	var s := GameState.new_campaign(repo, 7)
	var cell := _foreign_manor(s)
	var at := MapTerrain.cell_center(repo, repo.cells[cell])
	MissiveLog.add(repo, s, SpySystem.report(repo, s, at, 900, 0))
	var card := MapObjects.manor_card(repo, s, cell)
	var people: Dictionary = (card["intel"] as Array).filter(
		func(r: Dictionary) -> bool: return String(r["label"]) == "People")[0]
	assert_string_contains(String(people["text"]), "≈")
	assert_string_contains(String(people["tag"]), "spy")
	assert_eq(String(people["column"]), "credible")


func test_our_own_land_is_still_exact() -> void:
	var s := GameState.new_campaign(repo, 7)
	var home := MapManors.home_province(repo, s)
	var cell := int(MapManors.manors_of_province(repo, home)[0])
	assert_eq(String(MapObjects.manor_card(repo, s, cell)["known"]), "full")
	assert_eq(String(MapObjects.province_card(repo, s, home)["known"]), "full")


func test_a_foreign_kingdoms_population_is_a_word() -> void:
	var s := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	for k: String in repo.kingdoms:
		if k == realm:
			continue
		var lines := "\n".join(MapObjects._kingdom_lines(repo, repo.kingdoms[k], s))
		var pop := int(float(repo.kingdoms[k].get("population", 0)))
		assert_false(_leaks(lines, pop), k)
		return


## Task 10's look check (2026-09-28): our own kingdom's exact population read
## as a raw run of digits ("4102026") on the hovered country card.
func test_our_own_kingdoms_population_is_grouped() -> void:
	var s := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	var pop := int(float(repo.kingdoms[realm].get("population", 0)))
	var lines := MapObjects._kingdom_lines(repo, repo.kingdoms[realm], s)
	assert_has(lines, "Population: " + Intel.num(pop))


func test_dev_mode_lifts_the_fog() -> void:
	var s := GameState.new_campaign(repo, 7)
	Intel.dev_all = true
	assert_eq(String(MapObjects.manor_card(repo, s, _foreign_manor(s))["known"]), "full")
	Intel.dev_all = false


## I2 / Ruling 12 (final review): "Send a spy" from a town card must change
## that card. A spy is sent to a foreign town through the real order, rides,
## files his report — which carries the TOWN's own people as its own
## estimate — and the town card reads that, never the manor's people.
func test_a_spy_sent_to_a_town_answers_its_card() -> void:
	RoadGraph.forget()
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var realm := repo.resolve_realm("player_realm")
	var cells := MapEconomy.burg_cells(repo)
	var codes := repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		if MapOwnership.owner_of(repo, s, String(b["province_code"])) == realm or not cells.has(code):
			continue
		var at := Vector2(float(b["x"]), float(b["y"]))
		var req := ActionRequest.make("SPY_SEND", {"x": at.x, "y": at.y})
		if actions.validate(req, s) != "":
			continue
		var before := MapObjects.burg_card(repo, s, code)
		var row0: Dictionary = (before["intel"] as Array).filter(
			func(r: Dictionary) -> bool: return String(r["label"]) == "People")[0]
		assert_eq(String(row0["tag"]), "", "no report yet: common knowledge only")
		actions.execute(req, s)
		var got: Array = []
		for day in int(repo.bal("courier_max_days")):
			got.append_array(CourierSystem.ride_day(repo, s))
			if s.couriers.is_empty():
				break
		var reports := got.filter(func(e: Dictionary) -> bool: return String(e["type"]) == "spy_report")
		assert_eq(reports.size(), 1, "the spy reached %s and reported" % code)
		if reports.is_empty():
			return
		var m := MissiveLog.find(s, int(reports[0]["missive"]))
		var town_people: Dictionary = {}
		for f: Dictionary in m["facts"]:
			if String(f["key"]) == "town_people":
				town_people = f
		assert_false(town_people.is_empty(), "a report from a town's cell carries the town's people")
		var card := MapObjects.burg_card(repo, s, code)
		var row: Dictionary = (card["intel"] as Array).filter(
			func(r: Dictionary) -> bool: return String(r["label"]) == "People")[0]
		assert_eq(String(row["text"]), Intel.text_of(town_people), "the card reads the town's own estimate")
		assert_string_contains(String(row["tag"]), "spy")
		assert_false(_leaks(_texts(card), int(float(b.get("population", 0)))), "still no true figure")
		return
	fail_test("no foreign town a spy can reach on this pack")


## M5 (final review): a fogged town card says its population once — the
## intel row, which carries its source — not also as a plain field.
func test_a_fogged_town_card_shows_its_population_once() -> void:
	var s := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	var codes := repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		if MapOwnership.owner_of(repo, s, String(repo.burgs[code]["province_code"])) == realm:
			continue
		var card := MapObjects.burg_card(repo, s, code)
		var n := 0
		for f: Array in card["fields"]:
			if String(f[0]) in ["Population", "People"]:
				n += 1
		for r: Dictionary in card["intel"]:
			if String(r["label"]) in ["Population", "People"]:
				n += 1
		assert_eq(n, 1, "population once on " + code)
		return
