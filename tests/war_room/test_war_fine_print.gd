extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The fine print a leaning officer reads (spec 2026-10-07-war-room-scale-hover §3).

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()


func test_figures_lie_on_their_contour_and_keep_apart() -> void:
	# a ramp rising 100 m a column over 21 columns: the 500 m contour at x = 5,
	# the 1000 m at x = 10, the 1500 m at 15, the 2000 m at 20
	var nx := 21
	var nz := 11
	var h := PackedFloat32Array()
	for z in nz:
		for x in nx:
			h.append(float(x) * 100.0)
	var size := Vector2(2000, 1000)   # 100 px a column
	var figs := WarFinePrint.contour_figures(h, nx, nz, size, 500.0, 400.0)
	assert_gt(figs.size(), 0)
	for f: Dictionary in figs:
		var m := int(f["metres"])
		assert_eq(m % 500, 0)
		assert_almost_eq((f["at"] as Vector2).x, float(m) / 100.0 * 100.0, 1.0, "on its contour")
		assert_almost_eq(absf(float(f["angle"])), PI * 0.5, 0.01, "turned along a north-south contour")
	for i in figs.size():
		for j in range(i + 1, figs.size()):
			if int(figs[i]["metres"]) == int(figs[j]["metres"]):
				assert_gte((figs[i]["at"] as Vector2).distance_to(figs[j]["at"]), 400.0)


func test_flat_ground_has_no_figures() -> void:
	var h := PackedFloat32Array()
	h.resize(100)
	h.fill(120.0)
	assert_eq(WarFinePrint.contour_figures(h, 10, 10, Vector2(1000, 1000), 500.0, 100.0), [])


func test_a_town_note_says_size_works_souls_and_height() -> void:
	var sheet: Dictionary = WarSheets.series(repo)[WarSheets.sheet_of(repo, ArmySystem.position_of(repo, state,
		ArmySystem.regiment(repo, MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]["regiment_code"])))]
	var fine := WarFinePrint.strokes(repo, state, sheet, int(repo.bal("war_sheet_texture_px")), null)
	var r: Rect2 = sheet["rect"]
	var expected: Array = []
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if r.has_point(Vector2(float(b["x"]), float(b["y"]))):
			expected.append(WarFinePrint.town_note(b))
	var notes: Array = (fine["notes"] as Array).map(func(n: Dictionary) -> String: return String(n["text"]))
	for t: String in notes:
		assert_true(expected.has(t))
	assert_eq(WarFinePrint.town_note({"group": "city", "features": "walls|citadel", "population": "14061", "elevation_m": "961"}),
		"city · citadel · 14,061 souls · 961 m")
	assert_eq(WarFinePrint.town_note({"group": "village", "features": "", "population": "1644", "elevation_m": "729"}),
		"village · open · 1,644 souls · 729 m")


func test_route_names_are_never_upside_down() -> void:
	for s: Dictionary in WarSheets.series(repo):
		var fine := WarFinePrint.strokes(repo, state, s, int(repo.bal("war_sheet_texture_px")), null)
		for rt: Dictionary in fine["routes"]:
			assert_between(float(rt["angle"]), -PI * 0.5 - 0.001, PI * 0.5 + 0.001, String(rt["text"]))
		if not (fine["routes"] as Array).is_empty():
			return
	fail_test("no sheet has a named route")


func test_fine_boxes_never_touch_a_town_name() -> void:
	for s: Dictionary in WarSheets.series(repo).slice(0, 12):
		var k := float(int(repo.bal("war_sheet_texture_px"))) / (s["rect"] as Rect2).size.x
		var ink := WarSheetInk.strokes(repo, state, s, int(repo.bal("war_sheet_texture_px")))
		var fine := WarFinePrint.strokes(repo, state, s, int(repo.bal("war_sheet_texture_px")), null)
		var towns: Array = (ink["towns"] as Array).map(func(t: Dictionary) -> Rect2: return WarSheetInk.town_label_box(repo, t))
		for m: Dictionary in fine["marks"]:
			for box: Rect2 in towns:
				assert_false(box.has_point(m["at"]), "a mark sits in a town's name box")
		assert_gt(k, 0.0)
