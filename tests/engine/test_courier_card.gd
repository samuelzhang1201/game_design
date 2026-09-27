extends GutTest
## The courier's card (spec 2026-09-27-courier-core §2, invariant 10), and the
## weather now on the province and manor cards.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _field(card: Dictionary, name: String) -> String:
	for f: Array in card["fields"]:
		if String(f[0]) == name:
			return String(f[1])
	return ""


func test_the_card_says_what_he_carries_and_when() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _code()
	var c := CourierSystem.dispatch(repo, s, "ordinary", code, {"action_code": "ARMY_GARRISON"})
	var card := CourierCard.card(repo, s, int(c["id"]))
	var label := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(String(card["title"]), "Courier to " + label)
	assert_eq(String(card["known"]), "courier")
	assert_eq(_field(card, "Carrying"), "Orders to stand for " + label)
	assert_string_contains(_field(card, "Arrives"), "day")
	assert_ne(_field(card, "Weather"), "")
	assert_ne(_field(card, "Ground"), "")
	assert_eq(_field(card, "Rode out"), Calendar.date_string(s.tick, s.day))


func test_a_gone_courier_has_no_card() -> void:
	var s := GameState.new_campaign(repo, 7)
	assert_eq(CourierCard.card(repo, s, 99), {})


func test_province_and_manor_cards_carry_the_weather() -> void:
	var s := GameState.new_campaign(repo, 7)
	var codes := repo.provinces.keys()
	codes.sort()
	var p := String(codes[0])
	var names: Array = []
	for f: Array in MapObjects.province_card(repo, s, p)["fields"]:
		names.append(String(f[0]))
	assert_has(names, "Weather", "even a foreign province: the sky is no secret")
	var cell := int(MapManors.manors_of_province(repo, p)[0])
	var keys: Array = []
	for st: Dictionary in MapObjects.manor_card(repo, s, cell)["stats"]:
		keys.append(String(st["key"]))
	assert_has(keys, "weather_" + Weather.of(repo, s, p, s.absolute_day()))


func test_every_weather_icon_has_a_row() -> void:
	for kind: String in repo.weather_kinds:
		assert_true(repo.resource_icons.has(String(repo.weather_kinds[kind]["icon"])), kind)
