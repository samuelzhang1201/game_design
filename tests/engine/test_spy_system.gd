extends GutTest
## Spies (spec 2026-09-28 §1). Rolls are forced through SpySystem.report's
## q and bias; observe's own draw is checked for determinism only.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
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
	var s := GameState.new_campaign(repo, 7)
	var f := _foreign_manor(s)
	assert_eq(SpySystem.quality(repo, s, _at(f), 600), 450, "foreign −150, clear weather")
	assert_eq(SpySystem.quality(repo, s, _at(_home_plain(s)), 600), 750, "home +150")
	assert_eq(SpySystem.quality(repo, s, _at(f), 10), 0, "clamped at 0")


## A manor holding a walled/citadel town: quality picks up the extra
## spy_difficulty "walled" shift beside the home/foreign one (fix round 1 —
## the previous helpers never actually excluded towns, so this path was
## never exercised).
func test_quality_is_shifted_by_walls() -> void:
	var s := GameState.new_campaign(repo, 7)
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
	var s := GameState.new_campaign(repo, 7)
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
	var s := GameState.new_campaign(repo, 7)
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var at := ArmySystem.position_of(repo, s, reg)
	var m := SpySystem.report(repo, s, at, 1000, 0)
	var own := _fact(m, "troops_own")
	assert_true(int(own["hi"]) >= ArmySystem.headcount(repo, reg), "our own regiment is counted")


func test_a_spy_at_sea_reports_troops_only() -> void:
	var s := GameState.new_campaign(repo, 7)
	var wet := Vector2(1.0, 1.0)
	if MapEconomy.cell_at(repo, wet) >= 0:
		return
	var m := SpySystem.report(repo, s, wet, 700, 0)
	assert_eq(_fact(m, "people"), {})
	assert_false(_fact(m, "troops_foreign").is_empty())
	assert_string_contains(String(m["title"]), "open sea")


func test_two_spies_can_disagree() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _foreign_manor(s)
	assert_ne(JSON.stringify(SpySystem.report(repo, s, _at(f), 900, 0)["facts"]),
		JSON.stringify(SpySystem.report(repo, s, _at(f), 150, -250)["facts"]))


func test_send_ride_arrive_file() -> void:
	var s := GameState.new_campaign(repo, 7)
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
	var s := GameState.new_campaign(repo, 7)
	var f := _foreign_manor(s)
	s.metrics["treasury"] = float(CourierSystem.fee_gold(repo, CourierSystem.SPY)) - 0.5
	assert_ne(ActionSystem.new(repo).validate(ActionRequest.make("SPY_SEND", {"x": _at(f).x, "y": _at(f).y}), s), "")
