# tests/engine/test_war_folio.gd
extends GutTest
## The folio's right page and its drill tabs (spec 2026-10-01-war-room-design §4).

var repo: DataRepository
var state: GameState
var code := ""


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	state = GameState.new_campaign(repo, 42)
	WarSheets.forget()
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
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
	var mark := ArmySystem.morale_mark(repo, score, false)
	var rows := _rows("morale")
	assert_eq(rows["Morale"], "%d / 100" % int(st["morale"]))
	assert_eq(rows["Heading for (by today's stores)"], "%d — the ranks are %s" % [mark, ArmySystem.morale_word(repo, score)])
	assert_eq(rows["Drift"], "%d a month" % int(repo.bal("army_morale_drift_per_month")))


func test_ground_gives_the_grid_reference() -> void:
	var at := WarRoom.believed_position(repo, state, ArmySystem.regiment(repo, code))
	var sheet: Dictionary = WarSheets.series(repo)[WarSheets.sheet_of(repo, at)]
	assert_eq(_rows("ground")["Place"], WarSheets.grid_ref(repo, sheet, at))


func test_a_foreign_regiment_gets_only_its_headcount_word() -> void:
	var foreign := ""
	for r: Dictionary in repo.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) != repo.resolve_realm("player_realm"):
			foreign = String(r["regiment_code"])
			break
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
	for r: Dictionary in repo.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) != repo.resolve_realm("player_realm"):
			return String(r["regiment_code"])
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
	var held := ""   # a land regiment standing in a town of a province the crown controls
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		var c := String(r["regiment_code"])
		if String(r.get("is_naval", "0")) != "1" and SupplySystem.stronghold_of(repo, state, c) != "":
			held = c
			break
	assert_ne(held, "", "the pack has a land regiment at a crown town")
	ArmySystem.set_garrison(repo, state, held)
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
	assert_true(String(supply["Line"]).begins_with("in garrison at "))


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


func test_the_line_names_the_depot_town() -> void:
	var name := WarFolio.depot_name(repo, state)
	assert_ne(name, "the depot", "the capital is a town")
	var realm := repo.resolve_realm("player_realm")
	var cap := String(repo.kingdoms[realm]["capital_burg"])
	assert_eq(name, String(repo.burgs[cap]["label"]))
	# a regiment out on the road reads its line from that town
	var reg := ArmySystem.regiment(repo, code)
	var from := ArmySystem.position_of(repo, state, reg)
	ArmySystem.set_march(repo, state, code, from + Vector2(30, 0))
	var line := String(_rows("supply").get("Line", ""))
	if line.contains(" km from "):
		assert_true(line.contains(name), line)


func test_the_archers_kit_is_not_hidden_by_the_infantrys_names() -> void:
	var inf: Array = WarFolio.kit_of(repo, "infantry").map(func(r: Dictionary) -> String: return String(r["label"]))
	for r: Dictionary in WarFolio.kit_of(repo, "archers"):
		assert_false(String(r["label"]) in inf, "archers' %s shares the infantry's name" % r["part"])
