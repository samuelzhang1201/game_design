extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const H := preload("res://tests/engine/conduct_helpers.gd")
## The lines of foraging and desertion (spec 2026-10-10-foraging-and-desertion
## §4): folio rows, the unit card, the hover slip, the kingdom card, the word
## of a province, the bare list, and the guards on data/army/conduct_words.csv.
## High summer, day 1, a province of 100 food units: 100 x 30 supplies a month
## x 1000 per mille = 3000, 100 a day.

var repo: DataRepository
var state: GameState
var code: String
var home: String
var foreign: String


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	code = H.land_unit(repo, state)
	home = H.home_province(repo, state)
	foreign = H.foreign_province(repo, state)
	for t in range(0, 12):
		state.tick = t
		if Forage.season_permille(repo, state) == 1000:
			break
	state.day = 1
	state.forage_stripped.clear()
	state.grievance.clear()
	H.set_food(repo, foreign, 100)
	H.set_food(repo, home, 100)


func _words(key: String) -> String:
	return String(repo.conduct_words[key])


func _supply_rows() -> Dictionary:
	for s: Dictionary in WarFolio.sections(repo, state, code):
		if String(s["key"]) == "supply":
			var out := {}
			for row: Dictionary in s["rows"]:
				out[String(row["label"])] = String(row["text"])
			return out
	return {}


func _brief_rows() -> Dictionary:
	var out := {}
	for row: Dictionary in WarFolio.brief(repo, state, code)["rows"]:
		out[String(row["label"])] = String(row["text"])
	return out


func _point_in(province: String) -> Vector2:
	var cells: Array = MapManors.manors_of_province(repo, province, state)
	assert_false(cells.is_empty())
	return MapTerrain.cell_center(repo, repo.cells[int(cells[0])])


func _slip(province: String, unit: String) -> Array:
	var lines: Array = WarGround.lines(repo, WarGround.reading(repo, state, _point_in(province), unit))
	return lines.map(func(l: Dictionary) -> String: return String(l["text"]))


# --- word_of

func test_word_of_at_its_thresholds() -> void:
	# a day is (3000 x (1000 - stripped) / 1000) / 30 of a full 100: x10 per mille
	var cases := {0: "rich", 250: "rich", 251: "fair", 600: "fair", 601: "thin", 990: "thin", 999: "stripped", 1000: "stripped"}
	for x: int in cases:
		state.forage_stripped[foreign] = x
		assert_eq(Forage.word_of(repo, state, foreign), cases[x], "stripped %d" % x)


func test_word_of_a_province_with_no_food_is_stripped() -> void:
	H.set_food(repo, foreign, 0)
	assert_eq(Forage.word_of(repo, state, foreign), "stripped")


func test_word_of_winter_is_thin() -> void:
	# winter 300 per mille of a full day: 30 of 100
	for t in range(0, 12):
		state.tick = t
		if Forage.season_permille(repo, state) == int(repo.bal("forage_winter_permille")):
			break
	assert_eq(Forage.word_of(repo, state, foreign), "thin")


# --- stripped_bare

func test_stripped_bare_list() -> void:
	var codes: Array = repo.provinces.keys()
	codes.sort()
	var a := String(codes[0])
	var b := String(codes[1])
	var c := String(codes[2])
	state.forage_stripped[c] = 901
	state.forage_stripped[a] = 1000
	state.forage_stripped[b] = 900   # at the line is not past it
	assert_eq(Forage.stripped_bare(repo, state), [a, c] if a < c else [c, a])
	state.forage_stripped.clear()
	assert_eq(Forage.stripped_bare(repo, state), [])


func test_the_intel_ink_names_a_stripped_province() -> void:
	WarSheets.forget()
	var sheet: Dictionary = {}
	var rows: Array = repo.provinces.keys()
	rows.sort()
	for p: String in rows:
		var row: Dictionary = repo.provinces[p]
		var c := Vector2(float(row.get("center_x", 0)), float(row.get("center_y", 0)))
		for sh: Dictionary in WarSheets.series(repo):
			if (sh["rect"] as Rect2).has_point(c):
				sheet = sh
				state.forage_stripped[p] = 950
				break
		if not sheet.is_empty():
			break
	assert_false(sheet.is_empty(), "a province on a sheet")
	var ink := WarIntelInk.strokes(repo, state, sheet, 1024)
	assert_gte((ink["stripped"] as Array).size(), 1)
	var names: Array = (ink["stripped"] as Array).map(func(x: Dictionary) -> String: return String(x["text"]))
	assert_has(names, _words("ink_stripped"))
	state.forage_stripped.clear()
	assert_eq((WarIntelInk.strokes(repo, state, sheet, 1024)["stripped"] as Array).size(), 0)


# --- the folio and the card

func test_folio_rows_only_when_set() -> void:
	assert_false(_supply_rows().has(_words("row_foraging")))
	assert_false(_supply_rows().has(_words("row_deserted")))
	assert_false(_brief_rows().has(_words("row_foraging")))
	state.regiments[code]["forage"] = "law"
	_desert(12)
	assert_eq(_supply_rows()[_words("row_foraging")], _words("state_law"))
	assert_eq(_supply_rows()[_words("row_deserted")], "12")
	assert_eq(_brief_rows()[_words("row_foraging")], _words("state_law"))
	state.regiments[code]["forage"] = "desperate"
	assert_eq(_supply_rows()[_words("row_foraging")], _words("state_desperate"))


func test_under_arms_excludes_the_deserted() -> void:
	var heads := ArmySystem.headcount(repo, ArmySystem.regiment(repo, code, state))
	assert_false(Personnel.move(repo, state, code, "fit", "dead", 10).has("error"))
	_desert(20)
	var want := WarRoom.group(heads - 30)
	assert_eq(_brief_rows()["Under arms"], want)
	var comp := {}
	for s: Dictionary in WarFolio.sections(repo, state, code):
		if String(s["key"]) == "composition":
			for row: Dictionary in s["rows"]:
				comp[String(row["label"])] = String(row["text"])
	assert_eq(comp["Under arms"], want)
	var card := MapObjects.army_card(repo, code, state)
	var shown := ""
	for f: Array in card["fields"]:
		if String(f[0]) == "Under arms":
			shown = String(f[1])
	assert_eq(shown, str(heads - 30))


func test_under_arms_never_below_nothing() -> void:
	_desert(ArmySystem.fit_count(repo, state, code))
	assert_true(Personnel.move(repo, state, code, "fit", "released", 1).has("error"), "cannot release more than remain")
	assert_eq(_brief_rows()["Under arms"], "0")


func test_the_card_names_the_state_and_the_deserted() -> void:
	var card := MapObjects.army_card(repo, code, state)
	var labels: Array = card["fields"].map(func(f: Array) -> String: return String(f[0]))
	assert_false(labels.has(_words("row_foraging")))
	assert_false(labels.has(_words("row_deserted")))
	state.regiments[code]["forage"] = "desperate"
	_desert(7)
	card = MapObjects.army_card(repo, code, state)
	assert_has(card["fields"], [_words("row_foraging"), _words("state_desperate")])
	assert_has(card["fields"], [_words("row_deserted"), "7"])


# --- the kingdom card

func _kingdom_lines(kingdom: String) -> Array:
	var row: Dictionary = repo.kingdoms[kingdom]
	return MapObjects.describe(repo, {"kind": "kingdom", "state_id": int(row["state_id"])}, state)["lines"]


func test_kingdom_card_grievance_only_when_above_nothing() -> void:
	var kingdom := MapOwnership.owner_of(repo, state, foreign)
	var label := _words("row_grievance")
	assert_false(_kingdom_lines(kingdom).any(func(l: String) -> bool: return l.begins_with(label)))
	state.grievance[kingdom] = 0
	assert_false(_kingdom_lines(kingdom).any(func(l: String) -> bool: return l.begins_with(label)))
	state.grievance[kingdom] = 9
	assert_has(_kingdom_lines(kingdom), label + ": 9")


# --- the hover slip

func test_slip_in_enemy_land() -> void:
	H.set_stance(repo, MapOwnership.owner_of(repo, state, foreign), "Enemy")
	assert_eq(Forage.land_kind(repo, state, foreign), Forage.ENEMY)
	assert_has(_slip(foreign, ""), _words("slip_forage") % ["rich", 100])
	state.forage_stripped[foreign] = 500   # c = 1500, 50 a day, 500 per mille: fair
	assert_has(_slip(foreign, ""), _words("slip_forage") % ["fair", 50])


func test_slip_in_grey_land() -> void:
	H.set_stance(repo, MapOwnership.owner_of(repo, state, foreign), "Neutral")
	assert_eq(Forage.land_kind(repo, state, foreign), Forage.GREY)
	assert_has(_slip(foreign, ""), _words("slip_forage") % ["rich", 100])


func test_slip_at_home() -> void:
	var lines := _slip(home, "")
	assert_has(lines, _words("slip_home"))
	assert_false(lines.any(func(l: String) -> bool: return l.begins_with("Forage")))


func test_slip_with_a_unit_chosen() -> void:
	H.set_stance(repo, MapOwnership.owner_of(repo, state, foreign), "Enemy")
	for c: String in state.regiments:
		(state.regiments[c] as Dictionary)["supplies"] = 0
	# a host whose need is far above the 100 a day: the whole day is its share
	var row: Dictionary = state.army_roster[code]
	for arm: String in repo.world_table("military", "unit_types"):
		if row.has(arm):
			row[arm] = "0"
	row["infantry"] = "900"
	repo.balance["army_supply_per_head_permille"] = 1000 # 900 × 1000‰ retains the old 9000 × 100‰ demand.
	assert_false(Personnel.replace(repo, state, code, 900).has("error"))
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code, state), state)
	assert_gt(Forage.need_of(repo, state, code), 100)
	assert_eq(Forage.cut_permille(repo, state, code), 1000)
	@warning_ignore("integer_division")
	var m := use / Calendar.DAYS_PER_TICK
	assert_has(_slip(foreign, code), _words("slip_feeds") % [100, m])


# --- the words

func test_words_all_used() -> void:
	var src := ""
	for path: String in _scripts("res://scripts"):
		src += FileAccess.get_file_as_string(path) + "\n"
	for k: String in repo.conduct_words:
		assert_true(src.contains('"%s"' % k), "conduct_words key %s is used in scripts/" % k)


func test_words_name_no_kingdom() -> void:
	for k: String in repo.conduct_words:
		var text := String(repo.conduct_words[k]).to_lower()
		for kingdom: Dictionary in repo.kingdoms.values():
			assert_false(text.contains(String(kingdom["label"]).to_lower()), "%s names %s" % [k, kingdom["label"]])


func _scripts(dir: String) -> Array:
	var out: Array = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out


func _desert(n: int) -> void:
	var result := MilitaryRoster.transfer_units(repo, state, "desertion:%d:%s" % [state.absolute_day(), code],
		[{"unit_code": code, "from": "fit", "to": "released", "count": n}], "Test desertion for displayed history")
	assert_false(result.has("error"), str(result))
