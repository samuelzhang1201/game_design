extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The numbered map series (spec 2026-10-01-war-room-design §2).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()
	WarSheets.forget()


func test_beria_cuts_into_four_by_two_held_to_the_edges() -> void:
	# 2560 x 929, sheets 670 x 485, overlap 40: stride 630 / 445.
	# cols ceil((2560-40)/630) = 4 -> 0, 630, 1260, then min(1890, 2560-670=1890)
	# rows ceil((929-40)/445) = 2 -> 0, then min(445, 929-485=444) = 444
	var rects := WarSheets.layout(2560.0, 929.0, 670.0, 485.0, 40.0)
	assert_eq(rects.size(), 8)
	assert_eq(rects[0], Rect2(0, 0, 670, 485))
	assert_eq(rects[3], Rect2(1890, 0, 670, 485))
	assert_eq(rects[4], Rect2(0, 444, 670, 485))
	assert_eq(rects[7], Rect2(1890, 444, 670, 485))


func test_a_map_smaller_than_a_sheet_is_one_sheet_at_the_origin() -> void:
	var rects := WarSheets.layout(300.0, 200.0, 670.0, 485.0, 40.0)
	assert_eq(rects, [Rect2(0, 0, 670, 485)])


func test_roman_numerals() -> void:
	assert_eq(WarSheets.roman(1), "I")
	assert_eq(WarSheets.roman(4), "IV")
	assert_eq(WarSheets.roman(9), "IX")
	assert_eq(WarSheets.roman(14), "XIV")


func test_the_series_keeps_only_sheets_with_land_numbered_in_order() -> void:
	var series := WarSheets.series(repo)
	assert_between(series.size(), 1, 8)
	for i in series.size():
		var s: Dictionary = series[i]
		assert_eq(int(s["index"]), i)
		assert_eq(String(s["numeral"]), WarSheets.roman(i + 1))
		assert_ne(String(s["name"]), "", "named after the kingdom with most land on it")
		assert_true(repo.kingdoms.has(String(s["kingdom"])))


func test_a_place_reads_as_sheet_column_letter_and_row_number() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var r: Rect2 = s["rect"]
	# 105 px east (40 per square -> third column, C), 130 px south (fourth row)
	var px := r.position + Vector2(105.0, 130.0) * WarSheets.px_per_unit(repo)
	assert_eq(WarSheets.grid_ref(repo, s, px), "%s · C4" % s["numeral"])
	assert_eq(WarSheets.grid_ref(repo, s, r.position + Vector2(1.0, 1.0)), "%s · A1" % s["numeral"])


func test_a_point_finds_its_sheet_and_a_point_off_the_map_the_nearest() -> void:
	var series := WarSheets.series(repo)
	var s: Dictionary = series[0]
	var inside: Vector2 = (s["rect"] as Rect2).get_center()
	assert_eq(WarSheets.sheet_of(repo, inside), 0)
	var far := Vector2(-5000.0, -5000.0)
	var got := WarSheets.sheet_of(repo, far)
	assert_between(got, 0, series.size() - 1, "nothing is off every sheet: the nearest takes it")
	assert_eq(got, 0, "the north-west corner is nearest the first sheet")


func test_neighbours_are_symmetric() -> void:
	var series := WarSheets.series(repo)
	for s: Dictionary in series:
		var nb := WarSheets.neighbours(repo, int(s["index"]))
		var back := {"n": "s", "s": "n", "e": "w", "w": "e"}
		for d: String in nb:
			assert_eq(int(WarSheets.neighbours(repo, int(nb[d])).get(back[d], -1)), int(s["index"]))


func test_a_hole_in_the_grid_leaves_no_neighbour_and_no_diagonal() -> void:
	# a 2 x 2 grid whose (1, 0) was all sea and skipped
	var cells := {Vector2i(0, 0): 0, Vector2i(0, 1): 1, Vector2i(1, 1): 2}
	assert_eq(WarSheets.grid_neighbours(cells, Vector2i(0, 0)), {"s": 1})
	assert_eq(WarSheets.grid_neighbours(cells, Vector2i(1, 1)), {"w": 1})
	assert_false(WarSheets.grid_neighbours(cells, Vector2i(1, 1)).has("n"))
	assert_eq(WarSheets.grid_neighbours(cells, Vector2i(0, 1)), {"n": 0, "e": 2})


func test_the_series_records_each_sheets_grid_place() -> void:
	for s: Dictionary in WarSheets.series(repo):
		assert_true(int(s["col"]) >= 0 and int(s["row"]) >= 0)


func test_load_map_forgets_the_series() -> void:
	var first: Array = WarSheets.series(repo)
	(first[0] as Dictionary)["name"] = "stale"
	repo.load_map(repo.default_pack_id())
	assert_ne(String((WarSheets.series(repo)[0] as Dictionary)["name"]), "stale", "rebuilt after the pack was swapped")
