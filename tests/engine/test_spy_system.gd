extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Spies (spec 2026-09-28 §1). Rolls are forced through SpySystem.report's
## q and bias; observe's own draw is checked for determinism only
## (test_observe_draws_the_same_report_from_the_same_state).

var repo: DataRepository


## The pack's road graph is cached by map id and every test's repository
## carries the same routes and road speeds, so it is built once per script
## (and forgotten around it, so no other script's graph is read).
func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}


func after_all() -> void:
	RoadGraph.forget()


## burg_cells() is keyed by burg CODE (String) -> cell id (int), so a plain
## `.has(cell_id)` against it is always false. This is the set of cell ids
## that actually hold a town, built from the dictionary's VALUES.
func _town_cells() -> Dictionary:
	var out: Dictionary = {}
	for cell in MapEconomy.burg_cells(repo).values():
		out[int(cell)] = true
	return out


## A foreign manor with people and no town in it (no walls to shift the roll).
func _foreign_manor(s: GameState) -> int:
	var realm := repo.resolve_realm("player_realm")
	var towns := _town_cells()
	var ids := repo.manors.keys()
	ids.sort()
	for id: int in ids:
		if MapOwnership.owner_of(repo, s, MapManors.province_of(repo, id, s)) != realm \
				and not towns.has(id) and int(RealmEconomy.line_of(repo, s, id)["people"]) >= 500:
			return id
	return -1


## A manor of the crown's home province with no town in it.
func _home_plain(s: GameState) -> int:
	var towns := _town_cells()
	for id in MapManors.manors_of_province(repo, MapManors.home_province(repo, s)):
		if not towns.has(int(id)):
			return int(id)
	return -1


func _at(id: int) -> Vector2:
	return MapTerrain.cell_center(repo, repo.cells[id])


func _fact(m: Dictionary, key: String) -> Dictionary:
	for f: Dictionary in m["facts"]:
		if String(f["key"]) == key:
			return f
	return {}


func test_an_estimate_by_hand() -> void:
	# q 1000 -> half-width 100‰; q 0 -> 450‰ (spy_width_best/worst).
	assert_eq(SpySystem.estimate(repo, 3000, 1000, 0, 100), [2700, 3300])
	assert_eq(SpySystem.estimate(repo, 3000, 0, 0, 100), [1600, 4400], "450‰ of 3000 = 1350, rounded out")
	# q 500 -> 100 + 350*500/1000 = 275‰ -> half 825; bias +200‰ -> centre 3600;
	# 2775 floors to 2700, 4425 ceils to 4500.
	assert_eq(SpySystem.estimate(repo, 3000, 500, 200, 100), [2700, 4500])
	# q 0 -> 450‰ of 100 = 45; bias −300‰ -> centre 70; 25 floors to 0, 115 ceils to 200.
	assert_eq(SpySystem.estimate(repo, 100, 0, -300, 100), [0, 200], "never below zero")


func test_quality_follows_the_place() -> void:
	var s := SuiteData.campaign(repo, 7)
	var f := _foreign_manor(s)
	assert_eq(SpySystem.quality(repo, s, _at(f), 600), 600 + int(repo.spy_difficulty["foreign"]), "foreign, clear weather")
	assert_eq(SpySystem.quality(repo, s, _at(_home_plain(s)), 600), 600 + int(repo.spy_difficulty["home"]), "home")
	assert_eq(SpySystem.quality(repo, s, _at(f), 10), 0, "clamped at 0")


## A manor holding a walled/citadel town: quality picks up the extra
## spy_difficulty "walled" shift beside the home/foreign one (fix round 1 —
## the previous helpers never actually excluded towns, so this path was
## never exercised).
func test_quality_is_shifted_by_walls() -> void:
	var s := SuiteData.campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	var cells := MapEconomy.burg_cells(repo)
	var codes := repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var feats := String((repo.burgs[code] as Dictionary).get("features", "")).split("|")
		if not ("walls" in feats or "citadel" in feats):
			continue
		if not cells.has(code):
			continue
		var cell := int(cells[code])
		var prov := MapManors.province_of(repo, cell, s)
		var home := MapOwnership.owner_of(repo, s, prov) == realm
		var shift := int(repo.spy_difficulty.get("home" if home else "foreign", 0))
		var walled := int(repo.spy_difficulty.get("walled", 0))
		var expected := clampi(600 + shift + walled, 0, 999)
		assert_eq(SpySystem.quality(repo, s, _at(cell), 600), expected,
			"%s (%s, walled) at roll 600" % [code, "home" if home else "foreign"])
		return
	pass_test("no walled town on this pack")


func test_the_column_and_the_facts() -> void:
	var s := SuiteData.campaign(repo, 7)
	var f := _foreign_manor(s)
	var line := RealmEconomy.line_of(repo, s, f)
	var good := SpySystem.report(repo, s, _at(f), 800, 0)
	assert_eq(String(good["column"]), "credible")
	assert_eq(String(good["subject"]["kind"]), "manor")
	var p := _fact(good, "people")
	assert_true(int(p["lo"]) <= int(line["people"]) and int(line["people"]) <= int(p["hi"]), "true value inside")
	assert_eq(String(_fact(good, "holder")["text"]), "House " + MapManors.owner_of(repo, s, f))
	var bad := SpySystem.report(repo, s, _at(f), 200, 300)
	assert_eq(String(bad["column"]), "rumour")
	assert_eq(String(_fact(bad, "holder")["text"]), "unclear", "below spy_text_threshold")


func test_troops_near_the_point_split_own_and_foreign() -> void:
	var s := SuiteData.campaign(repo, 7)
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var at := ArmySystem.position_of(repo, s, reg)
	var m := SpySystem.report(repo, s, at, 1000, 0)
	var own := _fact(m, "troops_own")
	assert_true(int(own["hi"]) >= ArmySystem.headcount(repo, reg), "our own regiment is counted")


func test_a_spy_at_sea_reports_troops_only() -> void:
	var s := SuiteData.campaign(repo, 7)
	var wet := Vector2(1.0, 1.0)
	if MapEconomy.cell_at(repo, wet) >= 0:
		return
	var m := SpySystem.report(repo, s, wet, 700, 0)
	assert_eq(_fact(m, "people"), {})
	assert_false(_fact(m, "troops_foreign").is_empty())
	assert_string_contains(String(m["title"]), "open sea")


func test_two_spies_can_disagree() -> void:
	var s := SuiteData.campaign(repo, 7)
	var f := _foreign_manor(s)
	assert_ne(JSON.stringify(SpySystem.report(repo, s, _at(f), 900, 0)["facts"]),
		JSON.stringify(SpySystem.report(repo, s, _at(f), 150, -250)["facts"]))


func test_send_ride_arrive_file() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var f := _foreign_manor(s)
	var req := ActionRequest.make("SPY_SEND", {"x": _at(f).x, "y": _at(f).y})
	assert_eq(actions.validate(req, s), "")
	var before: float = s.metrics["treasury"]
	actions.execute(req, s)
	assert_eq(s.couriers.size(), 1)
	assert_eq(String(s.couriers[0]["kind"]), "spy")
	assert_lt(float(s.metrics["treasury"]), before)
	var got: Array = []
	for day in int(repo.bal("courier_max_days")):
		got.append_array(CourierSystem.ride_day(repo, s))
		if s.couriers.is_empty():
			break
	var reports := got.filter(func(e: Dictionary) -> bool: return String(e["type"]) == "spy_report")
	assert_eq(reports.size(), 1)
	var m := MissiveLog.find(s, int(reports[0]["missive"]))
	assert_eq(String(m["kind"]), "spy")
	assert_true(String(m["column"]) in ["credible", "rumour"])
	assert_string_contains(CourierSystem.headline(repo, reports[0]), "spy")


func test_a_thin_chest_cannot_send_a_spy() -> void:
	var s := SuiteData.campaign(repo, 7)
	var f := _foreign_manor(s)
	s.metrics["treasury"] = float(CourierSystem.fee_gold(repo, CourierSystem.SPY)) - 0.5
	assert_ne(ActionSystem.new(repo).validate(ActionRequest.make("SPY_SEND", {"x": _at(f).x, "y": _at(f).y}), s), "")


## M16 (final review): observe's own draws — the quality roll, then the
## bias — come from GameState.rng alone: two identical states file the
## identical report and leave the stream at the same place.
func test_observe_draws_the_same_report_from_the_same_state() -> void:
	var out: Array = []
	for i in 2:
		var s := SuiteData.campaign(repo, 7)
		var f := _foreign_manor(s)
		var c := CourierSystem.dispatch_spy(repo, s, _at(f))
		var aim := Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"]))
		c["x_m"] = aim.x
		c["y_m"] = aim.y
		var e := SpySystem.observe(repo, s, c)
		out.append([JSON.stringify(MissiveLog.find(s, int(e["missive"]))), s.rng.randi_range(0, 999999)])
	assert_eq(out[0][0], out[1][0], "the same report")
	assert_eq(out[0][1], out[1][1], "the stream left at the same place")


## M2 (final review): a spy's report names the manor's chief good and gives
## ITS units a month.
func test_the_report_names_the_chief_good() -> void:
	var s := SuiteData.campaign(repo, 7)
	var f := _foreign_manor(s)
	var line := RealmEconomy.line_of(repo, s, f)
	var chief := ManorEconomy.focus_units(repo, s, f, int(line["people"]), s.tick)
	assert_ne(String(chief["good"]), "", "the manor works a good")
	var good_label := String((repo.world_table("economy", "goods").get(String(chief["good"]), {}) as Dictionary).get("label", ""))
	var out := _fact(SpySystem.report(repo, s, _at(f), 1000, 0), "output")
	assert_eq(String(out["label"]), "%s a month" % good_label)
	assert_true(int(out["lo"]) <= int(chief["units"]) and int(chief["units"]) <= int(out["hi"]),
		"the chief good's own units inside the span")


## M1 (final review): a spy's news lines name his place — a spy rides for no
## regiment, so "The courier to  is held up" read with a hole in it.
func test_a_spys_news_lines_name_his_place() -> void:
	var s := SuiteData.campaign(repo, 7)
	var f := _foreign_manor(s)
	var c := CourierSystem.dispatch_spy(repo, s, _at(f))
	var place := Intel.place_label(repo, s, _at(f))
	c["days"] = int(repo.bal("courier_max_days"))
	var fuse: Array = CourierSystem.ride_day(repo, s).filter(
		func(e: Dictionary) -> bool: return String(e["type"]) == "fuse")
	assert_eq(fuse.size(), 1)
	var line := CourierSystem.headline(repo, fuse[0])
	assert_string_contains(line, place)
	assert_false(line.contains("to  "), line)
	var slow := CourierSystem.headline(repo, {"type": "slow", "courier": 1, "regiment": "",
		"place": place, "weather": "blizzard"})
	assert_string_contains(slow, place)
	assert_false(slow.contains("to  "), slow)
	# and the ride itself stamps the place on a slow day
	var s2 := SuiteData.campaign(repo, 7)
	Weather.forget()
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 0, "rain": 0, "mud": 0, "snow": 0, "blizzard": 1}
	CourierSystem.dispatch_spy(repo, s2, _at(f))
	var slows: Array = CourierSystem.ride_day(repo, s2).filter(
		func(e: Dictionary) -> bool: return String(e["type"]) == "slow")
	assert_eq(slows.size(), 1, "a blizzard holds him up")
	if not slows.is_empty():
		assert_eq(String(slows[0].get("place", "")), place)


## M15 (final review): a spy who could not reach the place before the fuse
## (courier_max_days) is refused with the reason, not paid for and lost.
func test_a_spy_is_refused_beyond_the_fuse() -> void:
	var s := SuiteData.campaign(repo, 7)
	var f := _foreign_manor(s)
	var req := ActionRequest.make("SPY_SEND", {"x": _at(f).x, "y": _at(f).y})
	var actions := ActionSystem.new(repo)
	assert_eq(actions.validate(req, s), "", "within reach")
	repo.balance["courier_max_days"] = 0.0
	var why := actions.validate(req, s)
	assert_string_contains(why, "days")


## Rebase onto main (2026-09-28): the map draws a courier riding his NEXT day
## through CourierSystem.ride_ahead, which runs the ride on a COPY with the
## real state. A spy rides for a point, not a regiment, so the preview must
## not drop him as "regiment gone" (he would be drawn a day behind, the
## owner's complaint of that morning) nor re-aim him, and it must never file
## his report: observe draws from GameState.rng and writes a letter.
func test_a_spys_next_day_is_previewed_and_the_preview_files_nothing() -> void:
	var s := SuiteData.campaign(repo, 7)
	var f := _foreign_manor(s)
	var c := CourierSystem.dispatch_spy(repo, s, _at(f))
	var aim := Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"]))
	# one short stretch of road left: the day ahead reaches the point
	c["x_m"] = aim.x - 1000
	c["y_m"] = aim.y
	c["path"] = [[aim.x, aim.y, "road"]]
	var before: Dictionary = c.duplicate(true)
	var rng_before: Dictionary = s.rng.to_dict()
	var letters := s.missives.size()
	var day := CourierSystem.ride_ahead(repo, s, c)
	assert_eq(day["points"], [aim, aim], "he is drawn riding onto his point")
	assert_lt(float(day["share"]), 1.0, "he arrives with some of the day to spare")
	assert_eq(c, before, "the spy is untouched")
	assert_eq(s.rng.to_dict(), rng_before, "the preview draws nothing from the engine's stream")
	assert_eq(s.missives.size(), letters, "the preview files no letter")
	assert_eq(s.couriers.size(), 1)
	var reports: Array = CourierSystem.ride_day(repo, s).filter(
		func(e: Dictionary) -> bool: return String(e["type"]) == "spy_report")
	assert_eq(reports.size(), 1, "the real day files the report")
