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


func _manor_subj(cell: int) -> Dictionary:
	return MissiveLog.subject("manor", MapManors.code_of(repo, cell), cell,
		MapTerrain.cell_center(repo, repo.cells[cell]))


func _reach() -> float:
	return repo.bal("intel_match_km") * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))


## Two distinct provinces whose centers sit within intel_match_km of each
## other (the reviewer found 8 such pairs on the shipped `beria` pack, e.g.
## winkwarne/altnesbury at 6.72px), else [].
func _nearby_province_pair() -> Array:
	var reach := _reach()
	var codes := repo.provinces.keys()
	codes.sort()
	for i in codes.size():
		var a: Dictionary = repo.provinces[codes[i]]
		var pa := Vector2(float(a["center_x"]), float(a["center_y"]))
		for j in range(i + 1, codes.size()):
			var b: Dictionary = repo.provinces[codes[j]]
			var pb := Vector2(float(b["center_x"]), float(b["center_y"]))
			if pa.distance_to(pb) <= reach:
				return [String(codes[i]), String(codes[j])]
	return []


## Two distinct manor cells sharing one province, else [].
func _two_manors_one_province(s: GameState) -> Array:
	var codes := repo.provinces.keys()
	codes.sort()
	for c: String in codes:
		var cells := MapManors.manors_of_province(repo, c, s)
		if cells.size() >= 2:
			return [int(cells[0]), int(cells[1])]
	return []


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


func test_estimate_wraps_latest_and_text_of() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _subj(_foreign(s))
	assert_eq(Intel.estimate(repo, s, f, "people"), {}, "no report yet")
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 9, f, "new",
		[MissiveLog.span("people", "People", 2800, 3200)]))
	var got := Intel.estimate(repo, s, f, "people")
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


func test_a_report_never_answers_a_different_nearby_province() -> void:
	var s := GameState.new_campaign(repo, 7)
	var pair := _nearby_province_pair()
	if pair.is_empty():
		pending("no two provinces within intel_match_km on this pack")
		return
	var a := _subj(String(pair[0]))
	var b := _subj(String(pair[1]))
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 4, a, "x", [MissiveLog.span("people", "People", 500, 700)]))
	var got := Intel.fact(repo, s, b, "people", 999)
	assert_ne(String(got["text"]), "≈ 500–700", "a's report must never answer for its neighbour b")
	assert_ne(String(got["source"]), "spy")


func test_a_report_never_answers_a_different_manor_of_the_same_province() -> void:
	var s := GameState.new_campaign(repo, 7)
	var pair := _two_manors_one_province(s)
	if pair.size() < 2:
		pending("no province with two manors on this pack")
		return
	var a := _manor_subj(int(pair[0]))
	var b := _manor_subj(int(pair[1]))
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 4, a, "x", [MissiveLog.span("people", "People", 500, 700)]))
	var got := Intel.fact(repo, s, b, "people", 999)
	assert_ne(String(got["text"]), "≈ 500–700", "a's report must never answer for manor b, same province or not")
	assert_ne(String(got["source"]), "spy")


func test_a_point_report_in_the_same_province_within_reach_still_answers() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _subj(_foreign(s))
	var near := MissiveLog.subject("point", "", -1, Vector2(float(f["x"]) + 3.0, float(f["y"])))
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 4, near, "near", [MissiveLog.span("people", "People", 500, 700)]))
	assert_eq(String(Intel.fact(repo, s, f, "people", 600)["text"]), "≈ 500–700")


func test_wealth_tier_cache_key_includes_the_seed_and_forget_clears_it() -> void:
	var s := GameState.new_campaign(repo, 7)
	var home := MapManors.home_province(repo, s)
	Intel.wealth_tier(repo, s, home)
	assert_true(String(Intel._tiers_key).find("|7|") != -1, "the cache key carries the campaign's seed")
	Intel.forget()
	assert_eq(String(Intel._tiers_key), "", "forget() clears the cache")


func test_tercile_of_ties_take_the_middle_rank() -> void:
	var rates := [1, 1, 1, 1, 1, 2, 2, 2, 3]
	assert_eq(Intel.tercile_of(rates, 1), 0)
	assert_eq(Intel.tercile_of(rates, 2), 2)
	assert_eq(Intel.tercile_of(rates, 3), 2)
	var stepped := [1, 2, 3, 4, 5, 6]
	assert_eq(Intel.tercile_of(stepped, 1), 0)
	assert_eq(Intel.tercile_of(stepped, 2), 0)
	assert_eq(Intel.tercile_of(stepped, 3), 1)
	assert_eq(Intel.tercile_of(stepped, 4), 1)
	assert_eq(Intel.tercile_of(stepped, 5), 2)
	assert_eq(Intel.tercile_of(stepped, 6), 2)


func test_place_label_names_the_manor_and_its_province() -> void:
	var s := GameState.new_campaign(repo, 7)
	var home := MapManors.home_province(repo, s)
	var cells := MapManors.manors_of_province(repo, home, s)
	if cells.is_empty():
		pending("home province has no manors on this pack")
		return
	var cell: int = int(cells[0])
	var px := MapTerrain.cell_center(repo, repo.cells[cell])
	var want := "%s (%s)" % [MapManors.label_of(repo, cell), String(repo.provinces[home].get("label", home))]
	assert_eq(Intel.place_label(repo, s, px), want)


func test_place_label_names_the_open_sea() -> void:
	var s := GameState.new_campaign(repo, 7)
	assert_eq(Intel.place_label(repo, s, Vector2(-999999.0, -999999.0)), "the open sea")


## Task 10's look check (2026-09-28): a spy who counted nobody read
## "≈ 0–0". An estimate with no width is one number, and nothing is "none".
func test_an_estimate_with_no_width_reads_as_one_number() -> void:
	assert_eq(Intel.text_of({"lo": 0, "hi": 0}), "none")
	assert_eq(Intel.text_of({"lo": 1500, "hi": 1500}), "≈ " + Intel.num(1500))
	assert_eq(Intel.text_of({"lo": 1500, "hi": 3100}), "≈ %s–%s" % [Intel.num(1500), Intel.num(3100)])
