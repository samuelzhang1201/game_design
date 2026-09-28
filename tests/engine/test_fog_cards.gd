extends GutTest
## The fog on the cards (spec 2026-09-28 §1 "Closing the leaks").

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
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


func test_dev_mode_lifts_the_fog() -> void:
	var s := GameState.new_campaign(repo, 7)
	Intel.dev_all = true
	assert_eq(String(MapObjects.manor_card(repo, s, _foreign_manor(s))["known"]), "full")
	Intel.dev_all = false
