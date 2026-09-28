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


## A manor of a foreign province, else -1.
func _foreign_manor_cell(s: GameState) -> int:
	var code := _foreign(s)
	var cells := MapManors.manors_of_province(repo, code, s)
	return int(cells[0]) if not cells.is_empty() else -1


## T3 (final review): the positive tier-1 case — a report on a manor answers
## a query about that same manor.
func test_a_manor_report_answers_the_same_manor() -> void:
	var s := GameState.new_campaign(repo, 7)
	var cell := _foreign_manor_cell(s)
	assert_gt(cell, -1, "a foreign manor exists on this pack")
	var a := _manor_subj(cell)
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 4, a, "x",
		[MissiveLog.span("people", "People", 500, 700)]))
	var got := Intel.fact(repo, s, a, "people", 600)
	assert_eq(String(got["text"]), "≈ 500–700")
	assert_eq(String(got["source"]), "spy")


## T3: tier 3 alone — a POINT report near a manor, in its province, answers
## a query about that manor (tier 1 needs a manor report, tier 2 a province
## query, so only the distance rule can match here).
func test_a_point_report_answers_a_manor_query_by_distance_alone() -> void:
	var s := GameState.new_campaign(repo, 7)
	var cell := _foreign_manor_cell(s)
	var a := _manor_subj(cell)
	var near := MissiveLog.subject("point", "", -1, Vector2(float(a["x"]) + 0.5, float(a["y"])))
	assert_eq(Intel.province_of(repo, s, near), Intel.province_of(repo, s, a), "the point lies in the same province")
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 4, near, "near",
		[MissiveLog.span("troops_foreign", "Foreign troops nearby", 100, 300)]))
	assert_eq(String(Intel.fact(repo, s, a, "troops_foreign", 200)["text"]), "≈ 100–300")
	var far := MissiveLog.subject("point", "", -1, Vector2(float(a["x"]) + _reach() * 50.0, float(a["y"])))
	var s2 := GameState.new_campaign(repo, 7)
	MissiveLog.add(repo, s2, MissiveLog.make("spy", "credible", 4, far, "far",
		[MissiveLog.span("troops_foreign", "Foreign troops nearby", 100, 300)]))
	assert_ne(String(Intel.fact(repo, s2, a, "troops_foreign", 200)["source"]), "spy",
		"out of reach, a point report says nothing of the manor")


## I1 / Ruling 11: a manor report answers its PROVINCE only in the
## province's own words (stance, wealth) — never with that one manor's
## people, tax, output or holder, which would read at province scale.
func test_a_manor_report_answers_its_province_only_for_stance_and_wealth() -> void:
	var s := GameState.new_campaign(repo, 7)
	var cell := _foreign_manor_cell(s)
	var code := MapManors.province_of(repo, cell, s)
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 4, _manor_subj(cell), "x", [
		MissiveLog.span("people", "People", 500, 700),
		MissiveLog.span("tax", "Tax a month", 10, 20),
		MissiveLog.span("output", "Goods a month", 30, 40),
		MissiveLog.words("holder", "Held by", "House Spyglass"),
		MissiveLog.words("stance", "Stance", "Wary"),
		MissiveLog.words("wealth", "Wealth", "rich")]))
	var p := _subj(code)
	var stance := Intel.fact(repo, s, p, "stance", "Neutral")
	assert_eq(String(stance["text"]), "Wary", "the province's stance comes from the report")
	assert_eq(String(stance["source"]), "spy")
	assert_eq(String(Intel.fact(repo, s, p, "wealth", 0)["text"]), "rich")
	for key in ["people", "tax", "output", "holder"]:
		assert_ne(String(Intel.fact(repo, s, p, key, 15000)["source"]), "spy",
			"one manor's %s never answers for its whole province" % key)
	# and the same manor still reads all of it
	assert_eq(String(Intel.fact(repo, s, _manor_subj(cell), "people", 600)["text"]), "≈ 500–700")
	assert_eq(String(Intel.fact(repo, s, _manor_subj(cell), "holder", "x")["text"]), "House Spyglass")


## I3 / Ruling 13: holder, stance and wealth are always given — a poor
## report's "unclear" never overrides them on a card (the letter still
## says "unclear").
func test_an_unclear_word_never_overrides_what_is_always_given() -> void:
	var s := GameState.new_campaign(repo, 7)
	var cell := _foreign_manor_cell(s)
	var m := _manor_subj(cell)
	MissiveLog.add(repo, s, MissiveLog.make("spy", "rumour", 4, m, "x", [
		MissiveLog.words("holder", "Held by", "unclear"),
		MissiveLog.words("stance", "Stance", "unclear"),
		MissiveLog.words("wealth", "Wealth", "unclear")]))
	assert_eq(String(Intel.fact(repo, s, m, "holder", "House Vane")["text"]), "House Vane")
	assert_eq(String(Intel.fact(repo, s, m, "stance", "Neutral")["text"]), "Neutral")
	var w := Intel.fact(repo, s, m, "wealth", 2)
	assert_eq(String(w["text"]), "rich")
	assert_eq(String(w["source"]), "common knowledge")
	# an older CLEAR word still stands behind a newer unclear one
	var s2 := GameState.new_campaign(repo, 7)
	MissiveLog.add(repo, s2, MissiveLog.make("spy", "credible", 3, m, "old",
		[MissiveLog.words("stance", "Stance", "Wary")]))
	MissiveLog.add(repo, s2, MissiveLog.make("spy", "rumour", 5, m, "new",
		[MissiveLog.words("stance", "Stance", "unclear")]))
	assert_eq(String(Intel.fact(repo, s2, m, "stance", "Neutral")["text"]), "Wary")


## The province wealth tiers computed by hand from a state as it stands
## (the per-person tax against every province's terciles).
func _tiers_by_hand(s: GameState) -> Dictionary:
	var rates: Array = []
	var per: Dictionary = {}
	var codes := repo.provinces.keys()
	codes.sort()
	for c: String in codes:
		var people := RealmEconomy._figure(repo, s, "economy.provinces.%s.rural_population" % c) \
			+ RealmEconomy._figure(repo, s, "economy.provinces.%s.urban_population" % c)
		if people <= 0:
			continue
		@warning_ignore("integer_division")
		var rate := int(RealmEconomy.province(repo, s, c)["tax"]) * 1000 / people
		per[c] = rate
		rates.append(rate)
	rates.sort()
	var out: Dictionary = {}
	for c: String in per:
		out[c] = Intel.tercile_of(rates, int(per[c]))
	return out


## A change within the month that moves provinces' tax per head apart: the
## tariff lands only on towns, so town-heavy provinces climb the terciles.
func _mid_month_change(s: GameState) -> void:
	s.metrics["tariff_rate"] = 10.0
	s.metrics["tax_rate"] = 1.0


## I5 / Ruling 15 (final review): the wealth tiers are STATE, settled with
## the month — never filled on demand at a moment the UI chooses. Two
## identical states take the same mid-month change; on one a card is opened
## BEFORE the change (and the game is then reloaded, as a player may), on
## the other nothing is opened. Their spies must file identical reports.
func test_opening_a_card_mid_month_never_changes_a_report() -> void:
	var a := GameState.new_campaign(repo, 7)
	var b := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	# a foreign province whose tier this change moves, with a manor to spy on
	var probe := GameState.new_campaign(repo, 7)
	var pre := _tiers_by_hand(probe)
	_mid_month_change(probe)
	var post := _tiers_by_hand(probe)
	var cell := -1
	var codes := repo.provinces.keys()
	codes.sort()
	for c: String in codes:
		if MapOwnership.owner_of(repo, probe, c) == realm or int(pre.get(c, 1)) == int(post.get(c, 1)):
			continue
		var cells := MapManors.manors_of_province(repo, c, probe)
		if not cells.is_empty():
			cell = int(cells[0])
			break
	assert_gt(cell, -1, "a foreign province whose tier the change moves")
	if cell < 0:
		return
	var at := MapTerrain.cell_center(repo, repo.cells[cell])
	var prov := MapManors.province_of(repo, cell, a)
	MapObjects.province_card(repo, a, prov)  # the player looks, early in the month
	_mid_month_change(a)
	var report_a := JSON.stringify(SpySystem.report(repo, a, at, 900, 0))
	repo.load_map(repo.map_id)  # the game is reloaded mid-month
	_mid_month_change(b)
	var report_b := JSON.stringify(SpySystem.report(repo, b, at, 900, 0))
	assert_eq(report_a, report_b, "what a spy files never depends on when a card was opened")


## Ruling 15: the tick settles the tiers into the state right after the
## month's economy, and they survive a save.
func test_the_tick_settles_the_wealth_tiers_into_the_state() -> void:
	var s := GameState.new_campaign(repo, 7)
	assert_eq(s.wealth_tiers, _tiers_by_hand(s), "a new campaign starts with the tiers of its own state")
	_mid_month_change(s)
	var moved := _tiers_by_hand(s)
	assert_ne(s.wealth_tiers, moved, "the change moves some tier, but not until the month is settled")
	var engine := TickEngine.new(repo)
	engine.advance(s)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.wealth_tiers, s.wealth_tiers, "the tiers are saved")
	var home := MapManors.home_province(repo, s)
	assert_eq(Intel.wealth_tier(repo, s, home), int(s.wealth_tiers.get(home, 1)), "readers read the state")


## Ruling 15: a save written before the tiers existed computes them once,
## from the loaded state.
func test_an_old_save_computes_its_wealth_tiers_once_on_load() -> void:
	var s := GameState.new_campaign(repo, 7)
	var d := s.to_dict()
	d.erase("wealth_tiers")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(back.wealth_tiers, {}, "the old save carries none")
	Intel.ensure_wealth_tiers(repo, back)
	assert_eq(back.wealth_tiers, _tiers_by_hand(back))


## M13 (final review): a manor with no province (the wildlands) is named
## without empty parentheses.
func test_place_label_drops_empty_parentheses() -> void:
	var s := GameState.new_campaign(repo, 7)
	var ids := repo.manors.keys()
	ids.sort()
	for id: int in ids:
		if MapManors.province_of(repo, id, s) != "":
			continue
		var got := Intel.place_label(repo, s, MapTerrain.cell_center(repo, repo.cells[id]))
		assert_false(got.contains("()"), got)
		assert_eq(got, MapManors.label_of(repo, id))
		return
	pending("no manor outside every province on this pack")


## M2 (final review): a foreign kingdom's card gives its wealth tier — the
## mean of its provinces' settled tiers, rounded — in words.
func test_a_foreign_kingdoms_card_gives_its_wealth() -> void:
	var s := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	var codes := repo.kingdoms.keys()
	codes.sort()
	for k: String in codes:
		if k == realm or MapOwnership.provinces_of(repo, s, k).is_empty():
			continue
		var lines := MapObjects._kingdom_lines(repo, repo.kingdoms[k], s)
		assert_has(lines, "Wealth: " + Intel.wealth_word(repo, Intel.kingdom_wealth_tier(repo, s, k)))
		return
