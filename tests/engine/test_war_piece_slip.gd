extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The slip over a WAR ROOM piece (owner 2026-10-07: 棋子的tooltip显示基本战斗数据).

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)


func _land() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func test_a_regiments_reading_is_its_own_figures_and_days_in_hand() -> void:
	var code := _land()
	var reg := ArmySystem.regiment(repo, code)
	ArmySystem.ensure(repo, state)
	state.regiments[code]["supplies"] = 600
	state.regiments[code]["wounded"] = 10
	var r: Dictionary = WarPieceSlip.reading(repo, state, [code])[0]
	var use := ArmySystem.supply_use(repo, reg, state)
	assert_gt(use, 0)
	assert_eq(int(r["supplies"]), 600)
	@warning_ignore("integer_division")
	assert_eq(int(r["days"]), 600 * 30 / use, "units x 30 / the month's use, whole days")
	assert_eq(int(r["heads"]), ArmySystem.headcount(repo, reg))
	assert_eq(int(r["fit"]), ArmySystem.headcount(repo, reg) - 10)
	assert_eq(int(r["defend"]), ArmySystem.power(repo, state, code, "defend"), "on the ground where it stands")
	assert_eq(int(r["attack"]), ArmySystem.power(repo, state, code, "attack"))
	assert_eq(int(r["readiness"]), ArmySystem.bars_of(repo, state, code).x)


func test_supplies_are_a_figure_with_the_days_in_brackets() -> void:
	assert_eq(WarPieceSlip.supplies_text({"supplies": 1240, "days": 18}), "Supplies 1,240 (≈\u00a018\u00a0days)")
	assert_eq(WarPieceSlip.supplies_text({"supplies": 40, "days": 1}), "Supplies 40 (≈\u00a01\u00a0day)")
	assert_eq(WarPieceSlip.supplies_text({"supplies": 0, "days": -1}), "Supplies 0", "a banner that eats nothing has no days")


func test_one_regiments_slip_names_it_and_says_its_figures() -> void:
	var code := _land()
	var lines := WarPieceSlip.lines(repo, WarPieceSlip.reading(repo, state, [code]))
	assert_eq(String(lines[0]["text"]), String(ArmySystem.regiment(repo, code)["label"]))
	assert_eq(String(lines[0]["kind"]), "title")
	var texts: Array = lines.map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("Defend ")), str(texts))
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("Readiness ")), str(texts))
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("Supplies ")), str(texts))


func test_a_garrisons_slip_lists_each_regiment_briefly() -> void:
	var codes: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and codes.size() < 2:
			codes.append(String(r["regiment_code"]))
	var town := String(repo.burgs.keys()[0])
	var lines := WarPieceSlip.lines(repo, WarPieceSlip.reading(repo, state, codes), town)
	assert_eq(String(lines[0]["text"]), "Garrison of %s" % String(repo.burgs[town]["label"]))
	assert_eq(lines.filter(func(l: Dictionary) -> bool: return String(l["kind"]) == "rubric").size(), 2, "a heading per regiment")
	assert_eq(lines.filter(func(l: Dictionary) -> bool: return String(l["text"]).contains("Supplies ")).size(), 2)
