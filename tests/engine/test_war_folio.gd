# tests/engine/test_war_folio.gd
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The folio's right page and its drill tabs (spec 2026-10-01-war-room-design §4).

var repo: DataRepository
var state: GameState
var code := ""


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, r) > 0 \
				and int(float(r.get("infantry", 0))) > 0:
			code = String(r["regiment_code"])
			break


func _rows(key: String) -> Dictionary:
	for s: Dictionary in WarFolio.sections(repo, state, code):
		if String(s["key"]) == key:
			var out := {}
			for row: Dictionary in s["rows"]:
				out[String(row["label"])] = String(row["text"])
			return out
	return {}


func test_every_section_in_the_table_has_a_builder() -> void:
	for row: Dictionary in repo.war_folio_sections:
		assert_true(WarFolio.has_builder(String(row["key"])), String(row["key"]))


func test_the_page_carries_the_six_sections_in_order() -> void:
	var keys: Array = WarFolio.sections(repo, state, code).map(func(s: Dictionary) -> String: return String(s["key"]))
	assert_eq(keys, ["composition", "arms", "morale", "supply", "ground", "march"])


func test_composition_counts_each_arm_and_the_figures() -> void:
	var reg := ArmySystem.regiment(repo, code)
	var rows := _rows("composition")
	assert_eq(rows["Under arms"], WarRoom.group(ArmySystem.headcount(repo, reg)))
	assert_eq(rows["Wounded"], "0", "a new campaign has none")
	assert_eq(rows["Fit"], WarRoom.group(ArmySystem.headcount(repo, reg)), "fit = headcount less the wounded")
	assert_eq(rows["Formation"], "9 figures — full strength")
	var infantry := int(float(reg.get("infantry", 0)))
	assert_gt(infantry, 0, "the fixture regiment has infantry")
	assert_eq(rows["Infantry"], WarRoom.group(infantry))


func test_morale_names_its_mark_and_the_months_drift() -> void:
	var st := ArmySystem.state_of(repo, state, code)
	var reg := ArmySystem.regiment(repo, code)
	var score := ArmySystem.supply_score(repo, int(st["supplies"]), ArmySystem.supply_use(repo, reg, state))
	# the seat's unit heads for the garrison's mark (spec 2026-10-07-army-split-and-ground §4.1)
	var mark := ArmySystem.morale_mark(repo, score, ArmyGround.seated_in(repo, state, code) != "")
	var rows := _rows("morale")
	assert_eq(rows["Morale"], "%d / 100" % int(st["morale"]))
	assert_eq(rows["Heading for (by today's stores)"], "%d — the ranks are %s" % [mark, ArmySystem.morale_word(repo, score)])
	assert_eq(rows["Drift"], "%d a month" % int(repo.bal("army_morale_drift_per_month")))


func test_ground_gives_the_grid_reference() -> void:
	var at := WarRoom.believed_position(repo, state, ArmySystem.regiment(repo, code))
	var sheet: Dictionary = WarSheets.series(repo)[WarSheets.sheet_of(repo, at)]
	assert_eq(_rows("ground")["Place"], WarSheets.grid_ref(repo, sheet, at))


func test_a_foreign_regiment_gets_only_its_headcount_word() -> void:
	var foreign := _foreign()
	var secs := WarFolio.sections(repo, state, foreign)
	assert_eq(secs.size(), 1)
	assert_eq(String(secs[0]["key"]), "composition")
	assert_eq(String(secs[0]["rows"][0]["text"]),
		Intel.magnitude(repo, ArmySystem.headcount(repo, ArmySystem.regiment(repo, foreign))))


func test_drills_are_only_the_clips_the_model_has() -> void:
	var clips := PackedStringArray(["Armature|MARCH", "Armature|GARRISON"])
	var drills := WarFolio.drills_for(repo, "infantry", clips)
	var keys: Array = drills.map(func(d: Dictionary) -> String: return String(d["key"]))
	assert_eq(keys, ["march", "garrison"], "no STANDBY or ATTACK clip, no tab")
	assert_eq(String(drills[0]["clip_name"]), "Armature|MARCH")
	assert_eq(WarFolio.current_drill(drills, ArmySystem.ORDER_GARRISON), 1)
	assert_eq(WarFolio.current_drill(drills, ArmySystem.ORDER_STANDBY), 0, "no STANDBY tab: the first")


func test_a_defend_clip_gets_its_own_tab() -> void:
	var clips := PackedStringArray(["Armature|MARCH", "Armature|DEFEND"])
	var drills := WarFolio.drills_for(repo, "archers", clips)
	var keys: Array = drills.map(func(d: Dictionary) -> String: return String(d["key"]))
	assert_eq(keys, ["march", "defend"])
	assert_eq(String(drills[1]["clip_name"]), "Armature|DEFEND")


func test_figures_follow_the_strength_tiers() -> void:
	assert_eq(WarFolio.figures(repo, state, code), 9)
	ArmySystem.ensure(repo, state)
	var heads := ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))
	@warning_ignore("integer_division")
	state.regiments[code]["wounded"] = heads / 2   # 500 fit per mille -> depleted
	assert_eq(WarFolio.figures(repo, state, code), 6)
	state.regiments[code]["wounded"] = heads - heads / 10   # ~100 -> remnants
	assert_eq(WarFolio.figures(repo, state, code), 3)


func _foreign() -> String:
	var army := ArmySystem.roster(repo, state)
	var codes := army.keys()
	codes.sort()
	for c: String in codes:
		if String(army[c]["kingdom_code"]) != repo.resolve_realm("player_realm"):
			return c
	return ""


func test_dev_mode_foreign_regiment_gets_all_six_sections() -> void:
	var was := Intel.dev_all
	Intel.dev_all = true
	var secs := WarFolio.sections(repo, state, _foreign())
	Intel.dev_all = was
	var keys: Array = secs.map(func(s: Dictionary) -> String: return String(s["key"]))
	assert_eq(keys, ["composition", "arms", "morale", "supply", "ground", "march"])


func test_supply_gives_stores_and_line() -> void:
	var rows := _rows("supply")
	assert_true(rows.has("In hand"))
	assert_true(rows.has("Line"), "a regiment with state has a supply line row")
	assert_true(rows.has("Governed by"))


func test_march_under_orders_names_destination_and_arrival() -> void:
	var reg := ArmySystem.regiment(repo, code)
	var from := ArmySystem.position_of(repo, state, reg)
	ArmySystem.set_march(repo, state, code, from + Vector2(30, 0))
	var rows := _rows("march")
	var dest := ArmySystem.destination_of(repo, state, code)
	var sheet: Dictionary = WarSheets.series(repo)[WarSheets.sheet_of(repo, dest)]
	assert_eq(rows["Bound for"], WarSheets.grid_ref(repo, sheet, dest))
	assert_true(rows.has("Arrives"))
	assert_true(rows.has("Readiness weights"))
	assert_false(rows["Readiness weights"].contains("(weights)"))
	assert_eq(rows["Order"], "On the march", "a word, never the raw id")


func test_garrison_adds_its_morale_row() -> void:
	var held := ""   # the unit holding the seat of a town the crown holds
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		var c := String(r["regiment_code"])
		if ArmyGround.seated_in(repo, state, c) != "":
			held = c
			break
	assert_ne(held, "", "the pack has a land unit on a crown town's seat")
	var morale := {}
	var supply := {}
	for sec: Dictionary in WarFolio.sections(repo, state, held):
		var out := {}
		for row: Dictionary in sec["rows"]:
			out[String(row["label"])] = String(row["text"])
		if String(sec["key"]) == "morale":
			morale = out
		elif String(sec["key"]) == "supply":
			supply = out
	assert_true(morale.has("In garrison"))
	assert_eq(morale["In garrison"], "+%d" % int(repo.bal("army_morale_garrison_bonus")))
	assert_true(String(supply["Line"]).contains(" tops it up"), supply["Line"])


## Final review 6: a unit camped round its realm town (not on the seat) is
## topped up by it, and the folio says so.
func test_a_standing_regiment_reads_the_town_that_tops_it_up() -> void:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		var c := String(r["regiment_code"])
		var held := SupplyLines.home_town(repo, state, c)
		if held == "" or ArmyGround.seated_in(repo, state, c) != "":
			continue
		for sec: Dictionary in WarFolio.sections(repo, state, c):
			if String(sec["key"]) != "supply":
				continue
			for row: Dictionary in sec["rows"]:
				if String(row["label"]) == "Line":
					assert_string_contains(String(row["text"]), "%s tops it up" % String(repo.burgs[held]["label"]))
					return
	fail_test("no standing regiment in a realm town, or no Line row")


## The Order row (spec 2026-10-07-army-split-and-ground §4.1): only the unit
## on a town's seat is its garrison; a unit camped round the town reads as
## camped by it, one halted in the open as encamped in the field.
func test_the_order_row_tells_the_seat_from_the_camp_and_the_field() -> void:
	var seated := ""
	var camped := ""
	ArmySystem.ensure(repo, state)
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		var c := String(r["regiment_code"])
		if String(r.get("is_naval", "0")) == "1":
			continue
		state.regiments[c]["order"] = ArmySystem.ORDER_GARRISON   # as an arrival leaves it
		if seated == "" and ArmyGround.seated_in(repo, state, c) != "":
			seated = c
		elif camped == "" and ArmyGround.seated_in(repo, state, c) == "" and ArmyGround.camped_by(repo, state, c) != "":
			camped = c
	assert_ne(seated, "", "premise: a unit on a seat")
	assert_ne(camped, "", "premise: a unit camped off the seat")
	code = seated
	assert_eq(_rows("march")["Order"], "In garrison")
	code = camped
	assert_eq(_rows("march")["Order"], "Camped by the town")
	state.regiments[camped]["camp_town"] = ""   # settled in the open
	assert_eq(_rows("march")["Order"], "Encamped in the field")


func test_matchups_are_named_per_arm() -> void:
	var rows := _rows("arms")
	assert_true(rows.has("Matchups — Infantry"))


func test_a_piece_of_kit_two_arms_share_is_shown_once() -> void:
	var seen := {}
	for s: Dictionary in WarFolio.sections(repo, state, code):
		if String(s["key"]) != "arms":
			continue
		for row: Dictionary in s["rows"]:
			var label := String(row["label"])
			assert_false(seen.has(label), "%s listed twice" % label)
			seen[label] = true


func test_the_readiness_row_gives_its_four_parts_and_hides_training() -> void:
	var st := ArmySystem.state_of(repo, state, code)
	var reg := ArmySystem.regiment(repo, code)
	var score := ArmySystem.supply_score(repo, int(st["supplies"]), ArmySystem.supply_use(repo, reg, state))
	var rows := _rows("march")
	@warning_ignore("integer_division")
	var pct := score / 10
	assert_eq(rows["Readiness parts"], "arm 100%%, supplies %d%%, morale %d%%, training %s" % [
		pct, int(st["morale"]), ArmySystem.training_grade(repo, int(st["training"]))])
	assert_eq(rows["Supplies score"], "%d%%" % pct, "a percentage, not per mille")
	assert_false(rows["Readiness parts"].contains(str(int(st["training"])) + "%"), "training stays a word")


func test_every_order_has_a_word() -> void:
	for order: String in [ArmySystem.ORDER_MARCH, ArmySystem.ORDER_GARRISON, ArmySystem.ORDER_STANDBY]:
		assert_true(repo.war_order_words.has(order), order)
	assert_eq(WarFolio.order_word(repo, ArmySystem.ORDER_GARRISON), "In garrison")
	assert_eq(WarFolio.order_word(repo, ArmySystem.ORDER_STANDBY), "Standing by")


func test_the_line_row_names_its_supply_point() -> void:
	state.supply_lines.erase(code)
	var none := String(_rows("supply")["Line"])
	var refill := SupplyLines.refill_words(repo, state, code)
	assert_eq(none, "no supply point" + ("" if refill == "" else "; " + refill))
	var town: String = TownStores.realm_towns(repo, state)[0]
	state.supply_lines[code] = SupplyLines._new_record(town, 1500, 1)
	state.supply_lines[code]["state"] = SupplyLines.FLOWING
	var line := String(_rows("supply")["Line"])
	assert_true(line.begins_with("flowing from %s, 1.5×" % String(repo.burgs[town]["label"])), line)
	assert_true(line.contains(" km, "), line)


func test_in_hand_reads_days_of_the_carry() -> void:
	var st := ArmySystem.state_of(repo, state, code)
	var text := String(_rows("supply")["In hand"])
	assert_true(text.ends_with(" days of %d)" % ArmySystem.carry_of(repo, st)), text)


func test_the_archers_kit_is_not_hidden_by_the_infantrys_names() -> void:
	var inf: Array = WarFolio.kit_of(repo, "infantry").map(func(r: Dictionary) -> String: return String(r["label"]))
	for r: Dictionary in WarFolio.kit_of(repo, "archers"):
		assert_false(String(r["label"]) in inf, "archers' %s shares the infantry's name" % r["part"])


func test_the_supply_row_names_a_brigand_on_the_road() -> void:
	# a flowing line from the first eligible realm town with a road to the column
	var e := SupplyLines.eligibility(repo, state, code)
	var towns: Array = e.keys()
	towns.sort()
	for t: String in towns:
		if String(e[t]) == "" and SupplyLines.road_px(repo, state, code, t).size() >= 2:
			state.supply_lines[code] = SupplyLines._new_record(t, 1000, 1)
			state.supply_lines[code]["state"] = SupplyLines.FLOWING
			break
	var route := SupplySystem.route_px(repo, state, code)
	if route.size() < 2:
		pass_test("no realm town in reach of this regiment")
		return
	var mid := route[route.size() / 2]
	var codes: Array = repo.markers.keys()
	codes.sort()
	for c: String in codes:
		if String(repo.markers[c]["type"]) == "brigands":
			repo.markers[c]["x"] = str(mid.x)
			repo.markers[c]["y"] = str(mid.y)
			assert_string_contains(_rows("supply")["Line"], "to the %s" % repo.markers[c]["label"])
			return
	pass_test("no brigands on this pack")
