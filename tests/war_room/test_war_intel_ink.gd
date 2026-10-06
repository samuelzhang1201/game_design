extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## What we KNOW, inked over the laid sheet once a day (spec 2026-10-02-war-room-v2
## §2.4): our supply lines, our couriers, the weather, spy reports that came in.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()


func _sheet_of_first_regiment() -> Dictionary:
	var p: Dictionary = WarRoom.pieces(repo, state)[0]
	return WarSheets.series(repo)[int(p["sheet"])]


func test_only_our_own_supply_lines_are_inked() -> void:
	var ours: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")).map(
		func(r: Dictionary) -> String: return String(r["regiment_code"]))
	# every land regiment of ours runs a supply line (spec 2026-10-07-army-supply-lines)
	for c in state.regiments.keys():
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			state.supply_lines[c] = SupplyLines._new_record(TownStores.realm_towns(repo, state)[0], 1000, 1)
			state.supply_lines[c]["state"] = SupplyLines.FLOWING
	var inked := 0
	for s: Dictionary in WarSheets.series(repo):
		for line: Dictionary in WarIntelInk.strokes(repo, state, s, 1024)["supply"]:
			assert_true(String(line["code"]) in ours, "a foreign regiment's supply line is not ours to know")
			assert_gte((line["poly"] as PackedVector2Array).size(), 2)
			inked += 1
	assert_gt(inked, 0, "our lines are inked")


func test_a_spy_still_riding_is_a_courier_and_files_no_report_yet() -> void:
	var s := _sheet_of_first_regiment()
	var at: Vector2 = (s["cell"] as Rect2).get_center()
	CourierSystem.dispatch_spy(repo, state, at)
	var ink := WarIntelInk.strokes(repo, state, s, 1024)
	assert_eq((ink["spies"] as Array).size(), 0, "no report until it has come in")
	var riding: Array = (ink["couriers"] as Array).filter(func(x: Dictionary) -> bool: return bool(x["spy"]))
	assert_lte(riding.size(), 1, "the spy rides as a courier, once")


func test_an_arrived_spy_report_is_a_ring_with_its_estimate() -> void:
	var s := _sheet_of_first_regiment()
	var at: Vector2 = (s["cell"] as Rect2).get_center()
	MissiveLog.add(repo, state, MissiveLog.make("spy", "credible", state.absolute_day(),
		MissiveLog.subject("point", "", -1, at), "A report", [MissiveLog.span("people", "People", 2800, 3200)]))
	var ink := WarIntelInk.strokes(repo, state, s, 1024)
	assert_eq((ink["spies"] as Array).size(), 1)
	assert_string_contains(String(ink["spies"][0]["text"]), "2,800")
	assert_gt(float(ink["spies"][0]["radius"]), repo.bal("war_intel_spy_ring_px"), "a spread estimate rings wider")


func test_fair_weather_is_not_news() -> void:
	for s: Dictionary in WarSheets.series(repo):
		for w: Dictionary in WarIntelInk.strokes(repo, state, s, 1024)["weather"]:
			assert_true(float(w["rain"]) > 0.0 or float(w["snow"]) > 0.0 or float(w["overcast"]) >= 0.5)


func test_the_key_turns_with_the_day() -> void:
	var a := WarIntelInk.cache_key(state, 0)
	state.day += 1
	assert_ne(WarIntelInk.cache_key(state, 0), a)


func test_the_key_turns_with_land_and_letters_too() -> void:
	var a := WarIntelInk.cache_key(state, 0)
	state.manor_owner["1"] = "someone"
	var b := WarIntelInk.cache_key(state, 0)
	assert_ne(b, a, "a manor changing hands can move a supply road")
	state.next_missive_id += 1
	assert_ne(WarIntelInk.cache_key(state, 0), b, "a letter replaced at the column's cap")


func test_a_spy_ring_names_its_source() -> void:
	var s := _sheet_of_first_regiment()
	var at: Vector2 = (s["cell"] as Rect2).get_center()
	MissiveLog.add(repo, state, MissiveLog.make("spy", "rumour", state.absolute_day(),
		MissiveLog.subject("point", "", -1, at), "A report", [MissiveLog.span("people", "People", 2800, 3200)]))
	var ink := WarIntelInk.strokes(repo, state, s, 1024)
	assert_string_contains(String(ink["spies"][0]["text"]).to_lower(), "rumour")
