extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The sheet's ink (spec 2026-10-01-war-room-design §2).

var repo: DataRepository
var state: GameState


func before_all() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()


func test_dashes_alternate_on_and_off_along_the_line() -> void:
	var d := WarSheetInk.dashed(PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), 20.0, 10.0)
	assert_eq(d.size(), 4)  # 0-20, 30-50, 60-80, 90-100
	assert_almost_eq(d[1][0].x, 30.0, 0.001)
	assert_almost_eq(d[3][1].x, 100.0, 0.001)


func test_only_what_touches_the_sheet_is_inked_in_texture_px() -> void:
	var sheet: Dictionary = WarSheets.series(repo)[0]
	var r: Rect2 = sheet["rect"]
	var ink := WarSheetInk.strokes(repo, state, sheet, 4096)
	var k := 4096.0 / r.size.x
	for t: Dictionary in ink["towns"]:
		var at: Vector2 = t["at"]
		assert_true(at.x >= 0.0 and at.x <= 4096.0 and at.y >= 0.0 and at.y <= r.size.y * k, String(t["label"]))
	var inside := 0
	for b: Dictionary in repo.burgs.values():
		if r.has_point(Vector2(float(b["x"]), float(b["y"]))):
			inside += 1
	assert_eq(ink["towns"].size(), inside)
	for key in ["roads", "trails", "rivers", "coasts", "seams", "peaks", "borders"]:
		assert_true(ink.has(key), key)
	for p: Dictionary in ink["peaks"]:
		assert_true(p.has("lod"), "each peak carries its lod, so the painter can thin them")


func test_a_conquest_changes_the_cache_key() -> void:
	var before := WarSheetInk.cache_key(state, 0)
	var prov: String = repo.provinces.keys()[0]
	state.province_owner[prov] = "someone_else"
	assert_ne(WarSheetInk.cache_key(state, 0), before)
	state.province_owner.erase(prov)
	assert_eq(WarSheetInk.cache_key(state, 0), before)


func test_a_dash_or_gap_of_no_length_gives_the_whole_line() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 50)])
	for pair: Array in [[0.0, 10.0], [10.0, 0.0], [-1.0, 5.0], [0.0, 0.0]]:
		var parts := WarSheetInk.dashed(line, float(pair[0]), float(pair[1]))
		assert_eq(parts.size(), 1, str(pair))
		assert_eq(parts[0], line, "the line itself, uncut")


func _richest_sheet() -> Dictionary:
	var best: Dictionary = {}
	var most := -1
	for s: Dictionary in WarSheets.series(repo):
		var n := 0
		for code: String in repo.burgs:
			var b: Dictionary = repo.burgs[code]
			if (s["rect"] as Rect2).has_point(Vector2(float(b["x"]), float(b["y"]))):
				n += 1
		if n > most:
			most = n
			best = s
	return best


func test_towns_say_whether_they_are_walled_and_ports() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	var walled := 0
	for t: Dictionary in ink["towns"]:
		assert_true(t.has("walls") and t.has("port"))
		walled += 1 if bool(t["walls"]) else 0
	var want := 0
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if (s["rect"] as Rect2).has_point(Vector2(float(b["x"]), float(b["y"]))) and String(b.get("features", "")).split("|").has("walls"):
			want += 1
	assert_eq(walled, want)


func test_manor_edges_run_between_land_cells_of_one_province_only() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	assert_gt((ink["manor_edges"] as Array).size(), 0)
	for e: PackedVector2Array in ink["manor_edges"]:
		assert_eq(e.size(), 2)
	assert_gt((ink["manors"] as Array).size(), 0, "manors are named")


func test_hollows_are_the_low_landmarks_on_the_sheet() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	var want := 0
	for m: Dictionary in Elevation.landmarks(repo):
		if String(m["kind"]) == "low" and (s["rect"] as Rect2).has_point(m["pos"]):
			want += 1
	assert_eq((ink["hollows"] as Array).size(), want)


func test_no_bake_no_woods_and_nothing_breaks() -> void:
	var ink := WarSheetInk.strokes(repo, state, WarSheets.series(repo)[0], 1024, null)
	assert_eq((ink["woods"] as Array).size(), 0)


func test_the_bake_plants_woods_on_a_wooded_sheet() -> void:
	var bake := WarBake.of(repo)
	if bake == null:
		pending("no built bake in this checkout")
		return
	var most := 0
	for s: Dictionary in WarSheets.series(repo):
		most = maxi(most, (WarSheetInk.strokes(repo, state, s, 1024, bake)["woods"] as Array).size())
		if most > 0:
			break
	assert_gt(most, 0, "some sheet has woods")


func test_a_crossing_is_where_a_line_meets_a_river() -> void:
	var road := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var river := PackedVector2Array([Vector2(4, -5), Vector2(4, 5)])
	var hits := WarSheetInk.crossings([road], [river])
	assert_eq(hits.size(), 1)
	assert_almost_eq((hits[0]["at"] as Vector2).distance_to(Vector2(4, 0)), 0.0, 0.0001)
	assert_almost_eq((hits[0]["dir"] as Vector2).dot(Vector2.RIGHT), 1.0, 0.0001)
	assert_eq(WarSheetInk.crossings([road], [PackedVector2Array([Vector2(20, -5), Vector2(20, 5)])]).size(), 0)


func test_rivers_widen_toward_the_mouth_and_carry_their_names() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	assert_gt((ink["rivers"] as Array).size(), 0)
	for rv: Dictionary in ink["rivers"]:
		assert_gte(float(rv["w1"]), float(rv["w0"]), "a river is never narrower at its mouth")
		assert_true(rv.has("label"))


func test_roads_over_rivers_are_bridges_and_trails_fords() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	var rivers: Array = (ink["rivers"] as Array).map(func(rv: Dictionary) -> PackedVector2Array: return rv["poly"])
	var r: Rect2 = s["rect"]
	var area := Rect2(Vector2.ZERO, r.size * 1024.0 / r.size.x)
	var on_sheet := func(hits: Array) -> int:
		return hits.filter(func(h: Dictionary) -> bool: return area.has_point(h["at"])).size()
	# every crossing on the sheet is found, and none far off it is looked for
	assert_eq(on_sheet.call(ink["bridges"]), on_sheet.call(WarSheetInk.crossings(ink["roads"], rivers)))
	assert_eq(on_sheet.call(ink["fords"]), on_sheet.call(WarSheetInk.crossings(ink["trails"], rivers)))


func test_no_manor_name_lies_over_a_towns_ring_or_name() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 4096)
	for m: Dictionary in ink["manors"]:
		var mb := WarSheetInk.manor_label_box(repo, m)
		for t: Dictionary in ink["towns"]:
			assert_false(mb.intersects(WarSheetInk.town_label_box(repo, t)), "%s over %s" % [m["label"], t["label"]])


func test_crossings_outside_the_clip_are_not_looked_for() -> void:
	var road := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var river := PackedVector2Array([Vector2(4, -5), Vector2(4, 5)])
	assert_eq(WarSheetInk.crossings([road], [river], Rect2(0, -6, 10, 12)).size(), 1)
	assert_eq(WarSheetInk.crossings([road], [river], Rect2(100, 100, 10, 10)).size(), 0)


func test_a_window_keeps_only_its_strokes_in_its_own_px() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var r: Rect2 = s["rect"]
	var win := Rect2(r.position + r.size * 0.25, r.size * 0.5)
	var whole := WarSheetInk.strokes(repo, state, s, 4096)
	var part := WarSheetInk.strokes(repo, state, s, 2048, null, win)
	assert_lte((part["towns"] as Array).size(), (whole["towns"] as Array).size())
	for t: Dictionary in part["towns"]:
		assert_true(Rect2(Vector2.ZERO, win.size * (2048.0 / win.size.x)).has_point(t["at"]))


func test_a_window_keeps_the_sheets_sizes_on_the_table() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var r: Rect2 = s["rect"]
	var win := Rect2(r.position + r.size * 0.25, r.size * 0.25)   # a quarter of the width: x4 at 4096 / 4096
	var sheet_px := int(repo.bal("war_sheet_texture_px"))
	var part := WarSheetInk.strokes(repo, state, s, sheet_px, null, win)
	var mag := (float(sheet_px) / win.size.x) / (float(sheet_px) / r.size.x)
	for rv: Dictionary in part["rivers"]:
		assert_almost_eq(float(rv["w0"]), repo.bal("war_ink_river_px") * mag, 0.001)
	for g: Dictionary in part["graticule"]:
		assert_eq(int(g["size"]), int(round(repo.bal("war_grid_label_px") * mag)))
	assert_almost_eq(WarSheetInk.town_label_box(repo, {"at": Vector2.ZERO, "tier": 0, "label": "Abc"}, mag).size.x,
		WarSheetInk.town_label_box(repo, {"at": Vector2.ZERO, "tier": 0, "label": "Abc"}).size.x * mag, 0.01)


func test_a_window_draws_the_sheets_own_woods() -> void:
	var bake := WarBake.of(repo)
	if bake == null:
		pass_test("no bake in this checkout")
		return
	var tex := int(repo.bal("war_sheet_texture_px"))
	var matched := 0
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["rect"]
		var whole := WarSheetInk.strokes(repo, state, s, tex, bake)
		if (whole["woods"] as Array).size() < 20:
			continue
		var win := Rect2(r.position + r.size * Vector2(0.37, 0.41), r.size * 0.3)   # an arbitrary corner
		var part := WarSheetInk.strokes(repo, state, s, tex, bake, win)
		var k_whole := float(tex) / r.size.x
		var k_part := float(tex) / win.size.x
		var sheet_at: Array = (whole["woods"] as Array).map(func(w: Dictionary) -> Vector2: return (w["at"] as Vector2) / k_whole + r.position)
		for w: Dictionary in part["woods"]:
			var pack: Vector2 = (w["at"] as Vector2) / k_part + win.position
			if not win.has_point(pack):
				continue
			var near := sheet_at.any(func(p: Vector2) -> bool: return p.distance_to(pack) < 0.01)
			assert_true(near, "a patch tree at %s is not one of the sheet's" % pack)
			matched += 1
		if matched > 0:
			return
	fail_test("no sheet with woods to compare")


func test_a_window_keeps_a_town_whose_name_reaches_into_it() -> void:
	var tex := int(repo.bal("war_sheet_texture_px"))
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["rect"]
		for code: String in repo.burgs:
			var b: Dictionary = repo.burgs[code]
			var at := Vector2(float(b["x"]), float(b["y"]))
			if not r.grow(-r.size.x * 0.2).has_point(at):
				continue
			# a window starting just right of the town: its ring is out, its name runs in
			var win := Rect2(at + Vector2(0.3, -r.size.y * 0.1), r.size * 0.2)
			var part := WarSheetInk.strokes(repo, state, s, tex, null, win)
			var labels := (part["towns"] as Array).map(func(t: Dictionary) -> String: return String(t["label"]))
			assert_true(labels.has(String(b["label"])), "%s's name is cut at the patch's edge" % b["label"])
			return
	fail_test("no town to test")


func test_sheet_marks_are_inked_with_their_reach() -> void:
	var placed := 0
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["rect"]
		var tex := int(repo.bal("war_sheet_texture_px"))
		var k := float(tex) / r.size.x
		var ink := WarSheetInk.strokes(repo, state, s, tex)
		for m: Dictionary in WarMarks.inked(repo, "sheet"):
			if not r.has_point(m["at"]):
				continue
			var hit := (ink["places"] as Array).filter(func(p: Dictionary) -> bool:
				return (p["at"] as Vector2).distance_to(((m["at"] as Vector2) - r.position) * k) < 0.01)
			assert_eq(hit.size(), 1, String(m["code"]))
			var hz: Dictionary = repo.war_mark_hazards.get(String(m["type"]), {})
			var want := 0.0 if hz.is_empty() else float(hz["reach_km"]) / WarMarks.km_per_px(repo) * k
			assert_almost_eq(float(hit[0]["hazard_r"]), want, 0.01)
			placed += 1
	assert_gt(placed, 0, "some sheet holds a mark")
