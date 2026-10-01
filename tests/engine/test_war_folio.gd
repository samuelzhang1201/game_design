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
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, r) > 0:
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
	assert_eq(rows["Formation"], "9 figures — full strength")
	var infantry := int(float(reg.get("infantry", 0)))
	if infantry > 0:
		assert_eq(rows["Infantry"], WarRoom.group(infantry))


func test_morale_names_its_mark_and_the_months_drift() -> void:
	var st := ArmySystem.state_of(repo, state, code)
	var reg := ArmySystem.regiment(repo, code)
	var score := ArmySystem.supply_score(repo, int(st["supplies"]), ArmySystem.supply_use(repo, reg, state))
	var mark := ArmySystem.morale_mark(repo, score, false)
	var rows := _rows("morale")
	assert_eq(rows["Morale"], "%d / 100" % int(st["morale"]))
	assert_eq(rows["Heading for"], "%d — the ranks are %s" % [mark, ArmySystem.morale_word(repo, score)])
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
