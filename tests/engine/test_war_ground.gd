extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM slip's facts (spec 2026-10-07-war-room-scale-hover §4.1): the
## ground under the pointer, read for the chosen regiment; never a foreign force.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)


func _land_code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _naval_code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
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
	var works := String(r["works"]) if town != "" and String(r["town_holder"]) == String(ArmySystem.regiment(repo, code)["kingdom_code"]) else ""
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
	var row: Dictionary = repo.world_table("military", "regiments")[code]
	for arm in ["infantry", "archers", "cavalry", "artillery", "fleet"]:
		row[arm] = "0"   # day_step_m is 0 only for an empty banner (base_pace_km 0)
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
