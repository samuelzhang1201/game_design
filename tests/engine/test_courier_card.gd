extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The courier's card (spec 2026-09-27-courier-core §2, invariant 10), and the
## weather now on the province and manor cards.

var repo: DataRepository


## The pack's road graph is cached by map id and every test's repository
## carries the same routes and road speeds, so it is built once per script
## (and forgotten around it, so no other script's graph is read).
func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _field(card: Dictionary, label: String) -> String:
	for f: Array in card["fields"]:
		if String(f[0]) == label:
			return String(f[1])
	return ""


func test_the_card_says_what_he_carries_and_when() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _code()
	var c := CourierSystem.dispatch(repo, s, "ordinary", code, {"action_code": "ARMY_GARRISON"})
	var card := CourierCard.card(repo, s, int(c["id"]))
	var label := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(String(card["title"]), "Courier to " + label)
	assert_eq(String(card["known"]), "courier")
	assert_eq(_field(card, "Carrying"), "Orders to stand", "short: the title names the regiment")
	assert_string_contains(String(card["title"]), label)
	assert_string_contains(_field(card, "Arrives"), "day")
	assert_ne(_field(card, "Weather"), "")
	assert_ne(_field(card, "Ground"), "")
	assert_eq(_field(card, "Ordered"), Calendar.date_string(s.tick, s.day))


## The card's values stay short in the fixed left column (fix round 1,
## 2026-09-28: "Rain (march and couriers ×0.85)" wrapped to five lines).
func test_the_weather_reads_short_on_his_card() -> void:
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 0, "rain": 1, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()
	var s := SuiteData.campaign(repo, 7)
	var c := CourierSystem.dispatch(repo, s, "ordinary", _code(), {"action_code": "ARMY_MARCH",
		"dest_x_m": 0, "dest_y_m": 0})
	var card := CourierCard.card(repo, s, int(c["id"]))
	assert_eq(_field(card, "Weather"), "Rain ×0.85")
	assert_eq(_field(card, "Carrying"), "Orders to march")
	assert_eq(CourierCard.weather_short(repo, "clear"), "Clear")
	assert_eq(CourierCard.weather_short(repo, "blizzard"), "Blizzard ×0.40")


func test_a_gone_courier_has_no_card() -> void:
	var s := SuiteData.campaign(repo, 7)
	assert_eq(CourierCard.card(repo, s, 99), {})


func test_province_and_manor_cards_carry_the_weather() -> void:
	var s := SuiteData.campaign(repo, 7)
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


func test_the_card_wears_its_kinds_painting_or_the_foul_weather_one() -> void:
	var own := GameArt.path(GameArt.COURIER_PAINTINGS, "ordinary")
	var foul := GameArt.path(GameArt.COURIER_PAINTINGS, "foul")
	assert_ne(own, "")
	assert_ne(foul, "")
	assert_eq(CourierCard.painting_for(repo, "ordinary", "clear"), own)
	assert_eq(CourierCard.painting_for(repo, "ordinary", "rain"), own, "850 is above the line")
	assert_eq(CourierCard.painting_for(repo, "ordinary", "mud"), foul, "700 is at the line")
	assert_eq(CourierCard.painting_for(repo, "ordinary", "blizzard"), foul)
	assert_eq(CourierCard.painting_for(repo, "ordinary", "no_such_weather"), own)


## Every kind of courier, and the foul-weather and delivered scenes, wears a
## painting (courier_paintings.tres, picked in the inspector).
func test_every_courier_painting_is_installed() -> void:
	var t := GameArt.table(GameArt.COURIER_PAINTINGS)
	for key: String in (repo.courier_art.keys() + ["foul", "delivered"]):
		assert_true(t.of(key) is Texture2D, key)
