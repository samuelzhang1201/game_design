extends GutTest
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM slip's facts (spec 2026-10-07-war-room-scale-hover §4.1): the
## ground under the pointer, read for the chosen regiment; never a foreign force.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)


func _land_code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _naval_code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_naval", "0")) == "1":
			return String(r["regiment_code"])
	return ""


func _land_point() -> Vector2:
	var code := _land_code()
	return ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))


func _sea_point() -> Vector2:
	for id: int in repo.cells:
		if MapTerrain.is_sea(repo.cells[id]):
			return MapTerrain.cell_center(repo, repo.cells[id])
	return Vector2(-1, -1)


func test_the_ground_alone_with_no_regiment_chosen() -> void:
	var at := _land_point()
	var r := WarGround.reading(repo, state, at, "")
	assert_false(bool(r["sea"]))
	assert_eq(r["terrain"], ArmySystem.terrain_at(repo, at))
	assert_eq(r["road"], ArmySystem.road_at(repo, at))
	assert_eq(r["metres"], Elevation.metres_of_cell(repo, MapEconomy.cell_at(repo, at)))
	assert_eq(r["place"], Intel.place_label(repo, state, at))
	assert_eq(r["regiment"], {})
	var kinds := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["kind"]))
	assert_false(kinds.has("rubric"), "no regiment section without a choice")


func test_the_sea_reads_as_open_sea() -> void:
	var at := _sea_point()
	var r := WarGround.reading(repo, state, at, "")
	assert_true(bool(r["sea"]))
	assert_eq(String(WarGround.lines(repo, r)[0]["text"]), "the open sea")


func test_a_chosen_regiment_reads_its_factors_against_open_plains() -> void:
	var code := _land_code()
	var at := _land_point() + Vector2(3, 3)
	var r := WarGround.reading(repo, state, at, code)
	var g: Dictionary = r["regiment"]
	var town := String(r["town"])
	# a town's works only for the unit on its seat, or one that would take an
	# empty seat (spec 2026-10-07-army-split-and-ground §4.1, §4.3)
	var seat := ArmyGround.seat_of(repo, state, town) if town != "" else ""
	var works := String(r["works"]) if town != "" and String(r["town_holder"]) == String(ArmySystem.regiment(repo, code)["kingdom_code"]) \
		and (seat == "" or seat == code) else ""
	var plains := ArmySystem.power_on(repo, state, code, "defend", "plains", "")
	@warning_ignore("integer_division")
	assert_eq(g["defend"], ArmySystem.power_on(repo, state, code, "defend", String(r["terrain"]), works) * 1000 / plains)
	assert_eq(g["ground"], ArmySystem.ground_permille(repo, ArmySystem.regiment(repo, code), at))
	assert_eq(g["height"], ArmySystem.height_factor(repo, int(g["delta_m"])))
	assert_gte(int(g["days"]), 1)


func test_a_fleet_cannot_go_ashore() -> void:
	var code := _naval_code()
	if code == "":
		pass_test("the realm has no fleet")
		return
	var r := WarGround.reading(repo, state, _land_point(), code)
	assert_true(bool(r["regiment"]["ashore"]))
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.has("A fleet cannot go ashore"))


func test_an_empty_banner_reads_no_power_no_pace_and_no_days() -> void:
	var code := _land_code()
	var at := _land_point() + Vector2(3, 3)
	var row: Dictionary = state.army_roster[code]
	for arm in ["infantry", "archers", "cavalry", "artillery", "fleet"]:
		row[arm] = "0"   # day_step_m is 0 only for an empty banner (base_pace_km 0)
	assert_false(Personnel.replace(repo, state, code, 0).has("error"))
	var r := WarGround.reading(repo, state, at, code)
	var g: Dictionary = r["regiment"]
	assert_eq(int(g["defend"]), 0)
	assert_eq(int(g["days"]), 0)
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.any(func(t: String) -> bool: return t.contains("cannot march")))


func test_a_foreign_town_never_shows_a_garrison() -> void:
	var mine := repo.resolve_realm("player_realm")
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		var at := Vector2(float(b["x"]), float(b["y"]))
		var holder := MapOwnership.owner_of(repo, state, String(b.get("province_code", "")))
		if holder == mine or holder == "":
			continue
		var r := WarGround.reading(repo, state, at, "")
		assert_eq(r["garrison"], [], "foreign town %s" % code)
		return
	pass_test("no foreign town on this pack")


## The capital, the unit on its seat and the units camped round it off the
## seat (spec 2026-10-07-army-split-and-ground §4.1).
func _capital_camp() -> Dictionary:
	var realm := repo.resolve_realm("player_realm")
	var town := String(repo.kingdoms[realm]["capital_burg"])
	var seat := ArmyGround.seat_of(repo, state, town)
	var camped: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, realm, state):
		var c := String(r["regiment_code"])
		if c != seat and ArmyGround.camped_by(repo, state, c) == town:
			camped.append(c)
	var b: Dictionary = repo.burgs[town]
	return {"town": town, "seat": seat, "camped": camped, "at": Vector2(float(b["x"]), float(b["y"]))}


## The garrison is the unit on the seat; the rest of the camp is a count, the
## outer rings' units in it and a column passing through not.
func test_the_garrison_is_the_seat_and_the_camp_a_count() -> void:
	var cap := _capital_camp()
	var seat := String(cap["seat"])
	assert_ne(seat, "", "premise: the capital's seat is held")
	var n := (cap["camped"] as Array).size()
	assert_gt(n, 1, "premise: several units camp round the capital")
	# a column passing through the capital holds no ground and is no garrison
	var through := String((cap["camped"] as Array)[0])
	ArmySystem.ensure(repo, state)
	ArmySystem.set_march(repo, state, through, (cap["at"] as Vector2) + Vector2(40.0, 0.0))
	state.regiments[through]["x_m"] = ArmySystem.pack_to_metres(repo, cap["at"]).x
	state.regiments[through]["y_m"] = ArmySystem.pack_to_metres(repo, cap["at"]).y
	var r := WarGround.reading(repo, state, cap["at"], "")
	var label := String(ArmySystem.regiment(repo, seat, state)["label"])
	assert_eq(r["garrison"], [label], "one name: the seat's")
	assert_eq(int(r["camped"]), n - 1, "the camp, less the column on the march")
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.has("Garrison: %s · %d camped round it" % [label, n - 1]), str(texts))


## The town's works go to the seat's unit alone (§4.1): a unit camped round
## the town reads the field's terrain; an empty seat is the next arrival's
## (§4.3), so then it reads the works too.
func test_only_the_seat_reads_the_towns_works() -> void:
	var cap := _capital_camp()
	var seat := String(cap["seat"])
	var camper := String((cap["camped"] as Array)[0])
	var at: Vector2 = cap["at"]
	var r := WarGround.reading(repo, state, at, "")
	var works := String(r["works"])
	var terrain := String(r["terrain"])
	assert_eq(works, ArmySystem.works_of(repo, ArmySystem.regiment(repo, seat, state), state), "premise: the seat's works")
	var factor := func(c: String, w: String) -> int:
		@warning_ignore("integer_division")
		return ArmySystem.power_on(repo, state, c, "defend", terrain, w) * 1000 \
			/ ArmySystem.power_on(repo, state, c, "defend", "plains", "")
	assert_eq(int(WarGround.reading(repo, state, at, seat)["regiment"]["defend"]), factor.call(seat, works))
	assert_ne(factor.call(camper, works), factor.call(camper, ""), "premise: the works would tell on the camper")
	assert_eq(int(WarGround.reading(repo, state, at, camper)["regiment"]["defend"]), factor.call(camper, ""),
		"a camp fights on the field's terrain")
	state.town_seat.erase(String(cap["town"]))
	assert_eq(int(WarGround.reading(repo, state, at, camper)["regiment"]["defend"]), factor.call(camper, works),
		"an empty seat is the next arrival's")


func test_raking_leaves_the_days_out() -> void:
	var r := WarGround.reading(repo, state, _land_point() + Vector2(3, 3), _land_code())
	var texts := WarGround.lines(repo, r, true).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_false(texts.any(func(t: String) -> bool: return t.contains("away")))


func test_a_reading_stays_inside_its_budget() -> void:
	var code := _land_code()
	var far := _land_point() + Vector2(60, 40)   # a long march
	WarGround.reading(repo, state, far, code)   # warm the grids
	var t0 := Time.get_ticks_usec()
	WarGround.reading(repo, state, far, code)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	assert_lt(ms, repo.bal("war_hover_budget_ms"), "%.2f ms" % ms)


func test_a_land_regiment_cannot_march_into_the_sea() -> void:
	var r := WarGround.reading(repo, state, _sea_point(), _land_code())
	assert_true(bool(r["regiment"]["afloat"]))
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.has("It cannot march into the sea"))
	assert_false(texts.any(func(t: String) -> bool: return t.contains("away") or t.contains("Defend")))


func test_the_slip_names_the_marks_near_the_pointer_nearest_first() -> void:
	var all := WarMarks.inked(repo, "")
	var m: Dictionary = all[0]
	var at: Vector2 = (m["at"] as Vector2) + Vector2(0.3, 0.0)
	var r := WarGround.reading(repo, state, at, "")
	var places: Array = r["places"]
	assert_gt(places.size(), 0)
	assert_lte(places.size(), int(repo.bal("war_mark_hover_max")))
	assert_eq(String(places[0]["code"]), String(m["code"]))
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with(String(m["label"]) + ",")))
	var legend := String(m["legend"]).substr(0, int(repo.bal("war_mark_legend_chars")))
	if legend != "":
		assert_true(texts.has(legend))


func test_a_brigand_mark_states_its_toll() -> void:
	for m: Dictionary in WarMarks.inked(repo, "sheet"):
		if String(m["type"]) != "brigands":
			continue
		var r := WarGround.reading(repo, state, m["at"], "")
		var hz: Dictionary = repo.war_mark_hazards["brigands"]
		var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
		@warning_ignore("integer_division")
		var toll := "Supply lines within %d\u00a0km lose %d%%" % [int(hz["reach_km"]), int(hz["permille"]) / 10]
		assert_true(texts.has(toll), "the toll on a line of its own, its figure and unit unbroken: " + toll)
		var head: Array = texts.filter(func(t: String) -> bool: return t.begins_with(String(m["label"]) + ","))
		assert_eq(head.size(), 1)
		assert_false(String(head[0]).contains(String(repo.war_marks["brigands"]["note"])), "no type words twice beside the legend")
		return
	pass_test("no brigands on this pack")


func test_no_marks_far_from_everything() -> void:
	var r := WarGround.reading(repo, state, _sea_point(), "")
	assert_lte((r["places"] as Array).size(), int(repo.bal("war_mark_hover_max")))
	for p: Dictionary in r["places"]:
		assert_lte(float(p["distance_km"]), repo.bal("war_mark_hover_km"))


func test_a_legend_is_plain_words_cut_at_a_word() -> void:
	var cap := int(repo.bal("war_mark_legend_chars"))
	for m: Dictionary in WarMarks.inked(repo, ""):
		var shown := WarGround.legend_of(repo, String(m["legend"]))
		assert_false(shown.contains("<") or shown.contains(">"), "%s: %s" % [m["code"], shown])
		assert_lte(shown.length(), cap + 1, String(m["code"]))
		if shown.ends_with("…"):
			assert_false(shown.trim_suffix("…").ends_with(" "), "cut before a space, not inside a word")


func test_a_pointer_inside_a_hazards_reach_names_it() -> void:
	for m: Dictionary in WarMarks.inked(repo, "sheet"):
		if String(m["type"]) != "brigands":
			continue
		var reach := float(repo.war_mark_hazards["brigands"]["reach_km"])
		var hover := repo.bal("war_mark_hover_km")
		if reach <= hover:
			pass_test("the hover reach already covers it")
			return
		var off := (hover + reach) * 0.5 / WarMarks.km_per_px(repo)
		var r := WarGround.reading(repo, state, (m["at"] as Vector2) + Vector2(off, 0.0), "")
		var codes: Array = (r["places"] as Array).map(func(p: Dictionary) -> String: return String(p["code"]))
		assert_true(codes.has(String(m["code"])), "inside the dotted ring, the brigands are named")
		return
	pass_test("no brigands on this pack")


func test_the_slip_names_a_known_hazard_with_its_months_and_effect() -> void:
	var at := _land_point()
	var cell := MapEconomy.cell_at(repo, at)
	Hazards.add(state, "pl", "Disease", "Test Plague", [cell], state.tick, state.tick + 7, "test")
	var r := WarGround.reading(repo, state, at, "")
	assert_true((r["hazards"] as Array).any(func(h: Dictionary) -> bool: return String(h["id"]) == "pl"))
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.any(func(t: String) -> bool:
		return t.begins_with("Test Plague") and t.contains("7 months left") and t.contains(WarGround.hazard_words(repo, "Disease"))))


func test_the_slip_never_names_an_unknown_hazard() -> void:
	var mine := repo.resolve_realm("player_realm")
	var ids: Array = repo.cells.keys()
	ids.sort()
	for c: int in ids:
		var holder := MapOwnership.owner_of(repo, state, MapManors.province_of(repo, c, state))
		if holder != "" and holder != mine and not MapTerrain.is_water(repo.cells[c]):
			Hazards.add(state, "sr", "Rebels", "Secret Rebels", [c], state.tick, -1, "test")
			var r := WarGround.reading(repo, state, MapTerrain.cell_center(repo, repo.cells[c]), "")
			var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
			assert_false(texts.any(func(t: String) -> bool: return t.contains("Secret Rebels")))
			return
	pass_test("no foreign land")


func test_hazard_words_by_kind() -> void:
	assert_string_contains(WarGround.hazard_words(repo, "Disease"), "a month")
	assert_string_contains(WarGround.hazard_words(repo, "Flood"), "×")
	assert_eq(WarGround.hazard_words(repo, "Fault"), "no effect on a march")


func _texts(r: Dictionary) -> Array:
	return WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))


func _town_point(code: String) -> Vector2:
	var b: Dictionary = repo.burgs[code]
	return Vector2(float(b["x"]), float(b["y"]))


func test_a_road_carrying_trade_names_it() -> void:
	var flows := WarEconomy.trade_flows(repo)
	var g := RoadGraph.of_pack(repo)
	var busiest := Vector2i(-1, -1)
	for seg: Vector2i in flows:
		if busiest.x < 0 or int(flows[seg]) > int(flows[busiest]):
			busiest = seg
	var at := ArmySystem.metres_to_pack(repo, Vector2i((Vector2(g.nodes[busiest.x]) + Vector2(g.nodes[busiest.y])) * 0.5))
	var r := WarGround.reading(repo, state, at, "")
	assert_eq(int(r["trade"]), WarEconomy.trade_at(repo, at))
	assert_true(_texts(r).any(func(t: String) -> bool: return t == "Trade: about %s gold a month passes" % Intel.num(int(r["trade"]))))


func test_a_work_names_its_goods_and_at_home_its_month() -> void:
	var realm := repo.resolve_realm("player_realm")
	var home := ""
	var abroad := ""
	var codes: Array = WarEconomy.works(repo).keys()
	codes.sort()
	for code: String in codes:
		var mine := MapOwnership.owner_of(repo, state, String(repo.burgs[code]["province_code"])) == realm
		if mine and home == "":
			home = code
		elif not mine and abroad == "":
			abroad = code
	assert_ne(abroad, "")
	var ra := WarGround.reading(repo, state, _town_point(abroad), "")
	var line_a: Array = _texts(ra).filter(func(t: String) -> bool: return t.begins_with("Works: "))
	assert_eq(line_a.size(), 1)
	assert_false(String(line_a[0]).contains("this month"), "a foreign works' month is not known")
	var w: Dictionary = WarEconomy.works(repo)[abroad]
	assert_true(String(line_a[0]).begins_with("Works: %s" % WarEconomy.good_label(repo, String(w["goods"][0]["good"])).to_lower()), String(line_a[0]))
	assert_false(String(line_a[0]).contains(" %d," % roundi(float(w["goods"][0]["units"]))), "no pack units")
	assert_string_contains(String(line_a[0]), "(%s gold a month)" % Intel.num(int(w["gold"])))
	if home != "":
		var rh := WarGround.reading(repo, state, _town_point(home), "")
		assert_true(_texts(rh).any(func(t: String) -> bool: return t.begins_with("Works: ") and t.contains("(this month: ")))


func test_a_market_town_names_its_market_and_food_price() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var r := WarGround.reading(repo, state, m["at"], "")
	var label := String(repo.burgs[String(m["burg"])]["label"])
	var price := String.num(float(WarEconomy.food_price_permille(repo, String(m["id"]))) / 1000.0, 2)
	assert_true(_texts(r).any(func(t: String) -> bool: return t.begins_with("Market of %s (" % label) and t.ends_with("— food at ×%s" % price)))


func test_a_market_won_reads_ours() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var prov := String(repo.burgs[String(m["burg"])]["province_code"])
	MapOwnership.set_owner(repo, state, prov, repo.resolve_realm("player_realm"), "test: the market's province is taken")
	var r := WarGround.reading(repo, state, m["at"], "")
	assert_true(_texts(r).any(func(t: String) -> bool: return t.begins_with("Market of ") and t.contains("(ours)")))


func test_the_open_sea_has_no_economy_lines() -> void:
	var texts := _texts(WarGround.reading(repo, state, _sea_point(), ""))
	for t: String in texts:
		assert_false(t.begins_with("Trade: ") or t.begins_with("Works: ") or t.begins_with("Market of "), t)
