extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The marks the WAR ROOM inks (spec 2026-10-07-war-room-p2-tactical-layer §1.1).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_every_inked_type_is_an_admitted_marker_type_with_a_known_glyph() -> void:
	var admitted := FileAccess.get_file_as_string("res://data/marker_types.csv")
	assert_gt(repo.war_marks.size(), 0)
	for type: String in repo.war_marks:
		assert_true(admitted.contains("\n%s," % type), "%s is not in marker_types.csv" % type)
		var row: Dictionary = repo.war_marks[type]
		assert_true(WarMarks.GLYPHS.has(String(row["glyph"])), "%s's glyph %s is not drawn" % [type, row["glyph"]])
		assert_true(["sheet", "fine"].has(String(row["layer"])), type)
	for type: String in repo.war_mark_hazards:
		assert_true(repo.war_marks.has(type), "a hazard %s that is not inked" % type)


func test_inked_marks_by_layer_in_code_order() -> void:
	var sheet := WarMarks.inked(repo, "sheet")
	var fine := WarMarks.inked(repo, "fine")
	assert_gt(sheet.size(), 0)
	for m: Dictionary in sheet:
		assert_eq(String(repo.war_marks[m["type"]]["layer"]), "sheet")
	for m: Dictionary in fine:
		assert_eq(String(repo.war_marks[m["type"]]["layer"]), "fine")
	var codes: Array = sheet.map(func(m: Dictionary) -> String: return String(m["code"]))
	var sorted := codes.duplicate()
	sorted.sort()
	assert_eq(codes, sorted)
	assert_eq(WarMarks.inked(repo, "").size(), sheet.size() + fine.size())


func test_a_type_not_in_the_table_is_never_inked() -> void:
	var code: String = repo.markers.keys()[0]
	repo.markers[code]["type"] = "not_a_type"
	for m: Dictionary in WarMarks.inked(repo, ""):
		assert_ne(String(m["code"]), code)


func test_near_is_nearest_first_and_capped() -> void:
	var all := WarMarks.inked(repo, "")
	var m: Dictionary = all[0]
	var at: Vector2 = m["at"]
	var near := WarMarks.near(repo, at + Vector2(0.5, 0.0), 5000.0, 3)
	assert_eq(near.size(), 3)
	assert_eq(String(near[0]["code"]), String(m["code"]))
	assert_lte(float(near[0]["distance_km"]), float(near[1]["distance_km"]))
	assert_lte(float(near[1]["distance_km"]), float(near[2]["distance_km"]))
	assert_eq(WarMarks.near(repo, at, 0.0001, 3).size(), 1, "only the one standing there")


func test_the_slips_words_are_for_the_player_not_the_designer() -> void:
	for type: String in repo.war_marks:
		var note := String(repo.war_marks[type]["note"])
		assert_false(note.contains("spec") or note.contains("WAR ROOM") or note.contains("("), "%s: %s" % [type, note])
