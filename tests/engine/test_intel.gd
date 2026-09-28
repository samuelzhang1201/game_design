extends GutTest
## The knowledge gate (spec 2026-09-28 §1).

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	Intel.dev_all = false


func after_each() -> void:
	Intel.dev_all = false


func _province_where(pred: Callable, s: GameState) -> String:
	var codes := repo.provinces.keys()
	codes.sort()
	for c: String in codes:
		if pred.call(c, s):
			return c
	return ""


func _foreign(s: GameState) -> String:
	return _province_where(func(c: String, st: GameState) -> bool:
		return MapOwnership.owner_of(repo, st, c) != repo.resolve_realm("player_realm"), s)


func _ours_uncontrolled(s: GameState) -> String:
	return _province_where(func(c: String, st: GameState) -> bool:
		return MapOwnership.owner_of(repo, st, c) == repo.resolve_realm("player_realm") \
			and not c in MapManors.controlled_provinces(repo, st), s)


func _subj(code: String) -> Dictionary:
	var p: Dictionary = repo.provinces[code]
	return MissiveLog.subject("province", code, -1, Vector2(float(p["center_x"]), float(p["center_y"])))


func test_three_levels() -> void:
	var s := GameState.new_campaign(repo, 7)
	var home := MapManors.home_province(repo, s)
	assert_eq(Intel.level(repo, s, _subj(home)), "full")
	var ours := _ours_uncontrolled(s)
	if ours != "":
		assert_eq(Intel.level(repo, s, _subj(ours)), "general")
	assert_eq(Intel.level(repo, s, _subj(_foreign(s))), "basic")
	Intel.dev_all = true
	assert_eq(Intel.level(repo, s, _subj(_foreign(s))), "full", "DEV MODE sees everything")


func test_basic_says_little_and_general_says_words() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _subj(_foreign(s))
	assert_eq(String(Intel.fact(repo, s, f, "people", 2837)["text"]), "—")
	assert_eq(String(Intel.fact(repo, s, f, "holder", "House Vane")["text"]), "House Vane")
	assert_eq(String(Intel.fact(repo, s, f, "wealth", 2)["text"]), "rich")
	var ours := _ours_uncontrolled(s)
	if ours != "":
		assert_eq(String(Intel.fact(repo, s, _subj(ours), "people", 2837)["text"]), "thousands")


func test_the_newest_report_wins_and_says_where_it_came_from() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _foreign(s)
	var f := _subj(code)
	MissiveLog.add(repo, s, MissiveLog.make("spy", "rumour", 5, f, "old", [MissiveLog.span("people", "People", 1000, 2000)]))
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 9, f, "new", [MissiveLog.span("people", "People", 2800, 3200)]))
	var got := Intel.fact(repo, s, f, "people", 2837)
	assert_eq(String(got["text"]), "≈ 2,800–3,200")
	assert_eq(String(got["column"]), "credible")
	assert_eq(int(got["day"]), 9)
	assert_eq(String(got["source"]), "spy")


func test_a_report_counts_by_distance_for_a_nearby_point() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _subj(_foreign(s))
	var near := MissiveLog.subject("point", "", -1, Vector2(float(f["x"]) + 3.0, float(f["y"])))
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 4, near, "near", [MissiveLog.span("people", "People", 500, 700)]))
	assert_eq(String(Intel.fact(repo, s, f, "people", 600)["text"]), "≈ 500–700")


func test_full_knowledge_beats_a_report() -> void:
	var s := GameState.new_campaign(repo, 7)
	var h := _subj(MapManors.home_province(repo, s))
	MissiveLog.add(repo, s, MissiveLog.make("spy", "rumour", 4, h, "x", [MissiveLog.span("people", "People", 1, 2)]))
	var got := Intel.fact(repo, s, h, "people", 2837)
	assert_eq(String(got["text"]), "2,837")
	assert_eq(String(got["column"]), "truth")


func test_words_and_numbers() -> void:
	assert_eq(Intel.num(2837), "2,837")
	assert_eq(Intel.num(512), "512")
	assert_eq(Intel.magnitude(repo, 50), "a handful")
	assert_eq(Intel.magnitude(repo, 500), "hundreds")
	assert_eq(Intel.magnitude(repo, 2500), "thousands")
	assert_eq(Intel.magnitude(repo, 9000), "many thousands")
	assert_eq(Intel.wealth_word(repo, 0), "poor")


func test_the_stance_comes_from_the_packs_diplomacy() -> void:
	var realm := repo.resolve_realm("player_realm")
	assert_eq(Intel.stance_of(repo, realm), "Our realm")
	for key: String in repo.world_table("political", "diplomacy"):
		if key.begins_with(realm + ">"):
			var row: Dictionary = repo.world_table("political", "diplomacy")[key]
			assert_eq(Intel.stance_of(repo, String(row["other_code"])), String(row["stance"]))
			return
