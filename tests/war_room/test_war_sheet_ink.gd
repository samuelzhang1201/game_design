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


## Owner 2026-10-07: the rivers were stiff and ruler-straight. A river is
## inked on a curve with a point every war_ink_river_step_px at most; without
## the build its course is the pack's polyline smoothed (MapGeometry.smooth_open),
## its source and mouth kept where the whole of it is drawn.
func test_a_river_is_inked_on_a_fine_curve_its_ends_kept() -> void:
	var step := repo.bal("war_ink_river_step_px")
	var sources := 0
	var mouths := 0
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["rect"]
		var k := 4096.0 / r.size.x
		var ink := WarSheetInk.strokes(repo, state, s, 4096)
		for rv: Dictionary in ink["rivers"]:
			var poly: PackedVector2Array = rv["poly"]
			for i in poly.size() - 1:
				assert_lte(poly[i].distance_to(poly[i + 1]), step * 1.5, "a point every %s px or so" % step)
			for code: String in repo.rivers:
				var raw: PackedVector2Array = repo.rivers[code]["polyline"]
				if float(rv["t0"]) == 0.0 and poly[0].distance_to((raw[0] - r.position) * k) < 0.01:
					sources += 1
				if float(rv["t1"]) == 1.0 and poly[poly.size() - 1].distance_to((raw[raw.size() - 1] - r.position) * k) < 0.01:
					mouths += 1
		if sources > 0 and mouths > 0:
			break
	assert_gt(sources, 0, "a river drawn from its source starts on the pack's source")
	assert_gt(mouths, 0, "and one drawn to its mouth ends on the pack's mouth")


func test_a_river_line_keeps_only_what_reaches_the_area_and_where_it_lies_along() -> void:
	var poly := PackedVector2Array([Vector2(-100, 0), Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(120, 0), Vector2(220, 0)])
	var c := WarSheetInk.river_line(poly, Rect2(5, -5, 10, 10), 5.0)
	var line: PackedVector2Array = c["poly"]
	assert_eq(line[0], Vector2(-100, 0), "one sample beyond the area's first span")
	assert_eq(line[line.size() - 1], Vector2(120, 0), "and beyond its last")
	assert_almost_eq(float(c["t0"]), 0.0, 0.0001)
	assert_almost_eq(float(c["t1"]), 220.0 / 320.0, 0.0001)
	assert_true((WarSheetInk.river_line(poly, Rect2(500, 500, 5, 5), 5.0)["poly"] as PackedVector2Array).is_empty())


## With the build, each river is the 3D map's own course (rivers.json): many
## samples, its source where the pack's is.
func test_with_the_build_a_river_is_the_3d_maps_course() -> void:
	var bake := WarBake.of(repo)
	if bake == null or bake.river_courses().is_empty():
		pending("no build in this checkout")
		return
	var s := _richest_sheet()
	var r: Rect2 = s["rect"]
	var k := 1024.0 / r.size.x
	var ink := WarSheetInk.strokes(repo, state, s, 1024, bake)
	var courses := bake.river_courses()
	var heads: Array = (ink["rivers"] as Array).map(func(rv: Dictionary) -> Vector2: return (rv["poly"] as PackedVector2Array)[0])
	var area := Rect2(Vector2.ZERO, r.size * k)
	var found := 0
	for code: String in courses:
		var tex := PackedVector2Array()
		for p: Vector2 in courses[code]:
			tex.append((p - r.position) * k)
		var line: PackedVector2Array = WarSheetInk.river_line(tex, area, repo.bal("war_ink_river_step_px"))["poly"]
		if not line.is_empty() and heads.any(func(h: Vector2) -> bool: return h.distance_to(line[0]) < 0.001):
			found += 1
			assert_lt((courses[code] as PackedVector2Array)[0].distance_to((repo.rivers[code]["polyline"] as PackedVector2Array)[0]),
				10.0, "%s rises where the pack's river does" % code)
	assert_eq(found, (ink["rivers"] as Array).size(), "every inked river is a course of the build")


func test_a_rivers_name_runs_along_its_longest_stretch_on_the_sheet() -> void:
	var poly := PackedVector2Array([Vector2(-5, 5), Vector2(2, 5), Vector2(4, 5), Vector2(20, 5), Vector2(30, 5),
		Vector2(50, 5), Vector2(60, 5), Vector2(70, 5)])
	assert_eq(WarSheetInk.longest_run(poly, Rect2(0, 0, 25, 10)), Vector2i(1, 3))
	assert_eq(WarSheetInk.longest_run(poly, Rect2(0, 0, 100, 10)), Vector2i(1, 7))
	assert_eq(WarSheetInk.longest_run(poly, Rect2(200, 0, 10, 10)), Vector2i(0, -1), "none on the sheet")


func test_crossings_on_a_dense_river_are_each_found_once() -> void:
	var road := PackedVector2Array([Vector2(0, 0), Vector2(300, 0)])
	# a river crossing the road three times, once on a bucket's edge (x = 128)
	var river := PackedVector2Array([Vector2(64, -10), Vector2(64, 10), Vector2(128, 10), Vector2(128, -10), Vector2(200, -10), Vector2(200, 10)])
	var hits := WarSheetInk.crossings([road], [river])
	assert_eq(hits.size(), 3)


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
				return (p["ring_at"] as Vector2).distance_to(((m["at"] as Vector2) - r.position) * k) < 0.01)
			assert_eq(hit.size(), 1, String(m["code"]))
			var hz: Dictionary = repo.war_mark_hazards.get(String(m["type"]), {})
			var want := 0.0 if hz.is_empty() else float(hz["reach_km"]) / WarMarks.km_per_px(repo) * k
			assert_almost_eq(float(hit[0]["hazard_r"]), want, 0.01)
			placed += 1
	assert_gt(placed, 0, "some sheet holds a mark")


func test_a_mark_on_a_town_stands_aside_of_its_ring() -> void:
	var tex := int(repo.bal("war_sheet_texture_px"))
	var checked := 0
	for s: Dictionary in WarSheets.series(repo):
		var ink := WarSheetInk.strokes(repo, state, s, tex)
		for p: Dictionary in ink["places"]:
			for t: Dictionary in ink["towns"]:
				var ring := float(repo.bal("war_ink_town_px")) * (1.0 + repo.bal("war_ink_town_tier_growth") * float(int(t["tier"])))
				var d := (p["at"] as Vector2).distance_to(t["at"])
				assert_gte(d, ring + repo.bal("war_mark_px") * 0.7 - 0.01, "a mark touches %s" % t["label"])
				checked += 1
	assert_gt(checked, 0)


func test_a_reach_ring_is_drawn_from_a_mark_just_outside_the_window() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var r: Rect2 = s["rect"]
	var code: String = ""
	for m: Dictionary in WarMarks.inked(repo, "sheet"):
		if String(m["type"]) == "pirates":
			code = String(m["code"])
	var reach_px := float(repo.war_mark_hazards["pirates"]["reach_km"]) / WarMarks.km_per_px(repo)
	var win := Rect2(r.position + r.size * 0.3, r.size * 0.2)
	# the mark stands just past the window's right edge, its ring reaching in
	var spot := Vector2(win.end.x + reach_px * 0.95, win.get_center().y)
	repo.markers[code]["x"] = str(spot.x)
	repo.markers[code]["y"] = str(spot.y)
	var part := WarSheetInk.strokes(repo, state, s, 2048, null, win)
	var rings := (part["places"] as Array).filter(func(p: Dictionary) -> bool: return float(p["hazard_r"]) > 0.0)
	assert_eq(rings.size(), 1, "the ring that reaches into the window is drawn")


## The sheet holding the first market's centre town (a work on the default pack).
func _market_sheet() -> Dictionary:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	return WarSheets.series(repo)[WarSheets.sheet_of(repo, m["at"])]


func test_towns_carry_their_works_and_market() -> void:
	var sheet := _market_sheet()
	var ink := WarSheetInk.strokes(repo, state, sheet, int(repo.bal("war_sheet_texture_px")))
	var works := WarEconomy.works(repo)
	var seen_market := false
	for t: Dictionary in ink["towns"]:
		var code := String(t["code"])
		assert_eq(String(t["works"]), String((works.get(code, {}) as Dictionary).get("glyph", "")), code)
		assert_eq(bool(t["market"]), WarEconomy.market_of_town(repo, code) != "", code)
		seen_market = seen_market or bool(t["market"])
	assert_true(seen_market)


func test_a_towns_glyphs_never_touch_its_ring_or_each_other() -> void:
	var tex := int(repo.bal("war_sheet_texture_px"))
	var checked := 0
	for s: Dictionary in WarSheets.series(repo):
		for t: Dictionary in WarSheetInk.strokes(repo, state, s, tex)["towns"]:
			var ring := repo.bal("war_ink_town_px") * (1.0 + repo.bal("war_ink_town_tier_growth") * float(int(t["tier"])))
			if String(t["works"]) != "":
				assert_gte((t["works_at"] as Vector2).distance_to(t["at"]), ring + repo.bal("war_ink_works_px") * 0.5, String(t["label"]))
				checked += 1
			if bool(t["market"]):
				assert_gte((t["market_at"] as Vector2).distance_to(t["at"]), ring + repo.bal("war_ink_market_px") * 0.5, String(t["label"]))
			if String(t["works"]) != "" and bool(t["market"]):
				assert_gte((t["works_at"] as Vector2).distance_to(t["market_at"]),
					(repo.bal("war_ink_works_px") + repo.bal("war_ink_market_px")) * 0.5, String(t["label"]))
	assert_gt(checked, 0)


func test_a_town_box_grows_to_hold_its_glyphs() -> void:
	var plain := WarSheetInk.town_label_box(repo, {"at": Vector2(500, 500), "tier": 1, "label": "Testford"})
	var marked := WarSheetInk.town_label_box(repo, {"at": Vector2(500, 500), "tier": 1, "label": "Testford",
		"works": "anvil", "market": true})
	assert_lt(marked.position.y, plain.position.y, "room above for the works")
	assert_gt(marked.end.y, plain.end.y, "room below for the market")
	assert_eq(marked.position.x, plain.position.x)


func test_trade_roads_are_inked_by_tier_in_texture_px() -> void:
	var sheet := _market_sheet()
	var tex := int(repo.bal("war_sheet_texture_px"))
	var ink := WarSheetInk.strokes(repo, state, sheet, tex)
	assert_gt((ink["trade"] as Array).size(), 0)
	var r: Rect2 = sheet["rect"]
	var k := float(tex) / r.size.x
	# a road leaving the sheet is drawn to its edge: the sheet grown 2 %, as strokes() asks
	var segs := WarEconomy.trade_segments(repo, r.grow(r.size.x * 0.02))
	assert_eq((ink["trade"] as Array).size(), segs.size())
	for seg: Dictionary in ink["trade"]:
		assert_between(int(seg["tier"]), 1, 3)
		assert_eq((seg["poly"] as PackedVector2Array).size(), 2)
	var first: Dictionary = segs[0]
	assert_almost_eq((ink["trade"][0]["poly"] as PackedVector2Array)[0], ((first["poly"] as PackedVector2Array)[0] - r.position) * k, Vector2.ONE * 0.01)


func test_a_window_keeps_the_trade_roads_in_its_own_px() -> void:
	var sheet := _market_sheet()
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var window := Rect2(m["at"] - Vector2(8, 8), Vector2(16, 16))
	var ink := WarSheetInk.strokes(repo, state, sheet, 2048, null, window)
	var k := 2048.0 / window.size.x
	for seg: Dictionary in ink["trade"]:
		var poly: PackedVector2Array = seg["poly"]
		var grown := Rect2(Vector2.ZERO, window.size * k).grow(window.size.x * k)
		assert_true(grown.has_point(poly[0]) or grown.has_point(poly[1]), "an end in or beside the window")
	for t: Dictionary in ink["towns"]:
		if String(t["code"]) == String(m["burg"]):
			assert_true(bool(t["market"]))


func test_a_walled_towns_glyphs_stand_clear_of_its_walls() -> void:
	var tex := int(repo.bal("war_sheet_texture_px"))
	var checked := 0
	for s: Dictionary in WarSheets.series(repo):
		for t: Dictionary in WarSheetInk.strokes(repo, state, s, tex)["towns"]:
			if not bool(t["walls"]) or (String(t["works"]) == "" and not bool(t["market"])):
				continue
			var ring := repo.bal("war_ink_town_px") * (1.0 + repo.bal("war_ink_town_tier_growth") * float(int(t["tier"])))
			# the wall's square reaches ring x wall_ratio, its corner towers 0.22 of that again
			var wall := ring * repo.bal("war_ink_wall_ratio") * 1.22
			if String(t["works"]) != "":
				assert_gte(absf((t["works_at"] as Vector2).y - (t["at"] as Vector2).y), wall + repo.bal("war_ink_works_px") * 0.5, String(t["label"]))
			if bool(t["market"]):
				assert_gte(absf((t["market_at"] as Vector2).y - (t["at"] as Vector2).y), wall + repo.bal("war_ink_market_px") * 0.5, String(t["label"]))
			checked += 1
	assert_gt(checked, 0)


## The WAR ROOM's rivers (owner 2026-10-07: stiff, ruler-straight): a line
## densified on a curve THROUGH its points, a point every `step` at most.
func test_densify_runs_through_every_point_a_step_apart_at_most() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(40, 25), Vector2(41, 26), Vector2(100, 10)])
	var step := 4.0
	var out := WarSheetInk.densify(pts, step)
	var want := 1
	for i in pts.size() - 1:
		want += maxi(1, ceili(pts[i].distance_to(pts[i + 1]) / step))
	assert_eq(out.size(), want, "1 + ceil(span / step) a span")
	assert_eq(out[0], pts[0], "the source kept")
	assert_eq(out[out.size() - 1], pts[pts.size() - 1], "the mouth kept")
	for p in pts:
		assert_true(out.has(p), "every original point stays on the curve: %s" % p)
	for i in out.size() - 1:
		assert_lte(out[i].distance_to(out[i + 1]), step * 1.5, "no long chord (a curve is a little longer than its chord)")
	assert_eq(WarSheetInk.densify(PackedVector2Array([Vector2.ZERO]), step).size(), 1, "one point is left alone")


func test_densify_bends_where_the_line_turns() -> void:
	var out := WarSheetInk.densify(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), 1.0)
	var off := 0.0
	for p in out:
		if p.x < 9.99 and p.x > 0.01:
			off = maxf(off, absf(p.y))
	assert_gt(off, 0.01, "the first leg curves into the turn: no ruled straight segment and a corner")


func _circle_meets_rect(c: Vector2, r: float, box: Rect2) -> bool:
	var nearest := Vector2(clampf(c.x, box.position.x, box.end.x), clampf(c.y, box.position.y, box.end.y))
	return nearest.distance_to(c) < r


func test_a_town_name_clears_its_seat_piece() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, int(repo.bal("war_sheet_texture_px")))
	assert_gt((ink["towns"] as Array).size(), 0)
	var plinth_r := WarSheetInk.plinth_radius_px(repo)
	assert_gt(plinth_r, 0.0)
	for t: Dictionary in ink["towns"]:
		var nb := WarSheetInk.town_name_box(repo, t)
		assert_false(_circle_meets_rect(t["at"], plinth_r, nb), "%s under its seat piece" % t["label"])
		assert_gte(float(t["name_dx"]), plinth_r, "%s name ends inside the plinth" % t["label"])
		assert_lt(nb.end.x, float(t["at"].x), "%s name stands west of its town" % t["label"])


func test_the_plinth_footprint_in_ink_px_follows_the_table() -> void:
	var want := repo.bal("war_piece_plinth_mm") / 1000.0 * 0.5 / repo.bal("war_table_w_m") * repo.bal("war_sheet_texture_px")
	assert_almost_eq(WarSheetInk.plinth_radius_px(repo), want, 0.001)
	assert_almost_eq(WarSheetInk.plinth_radius_px(repo, 2.0), want * 2.0, 0.001)


func test_the_label_halo_and_graticule_alpha_are_data() -> void:
	assert_true(repo.balance.has("war_ink_label_halo_px"))
	assert_true(repo.balance.has("war_ink_label_clear_px"))
	assert_true(repo.balance.has("war_grid_label_alpha"))
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 4096)
	for g: Dictionary in ink["graticule"]:
		assert_almost_eq(float(g["alpha"]), repo.bal("war_grid_label_alpha"), 0.0001)


func test_the_graticule_figures_are_paler_than_full_rubric() -> void:
	assert_true(repo.balance.has("war_grid_figure_alpha"))
	assert_lt(repo.bal("war_grid_figure_alpha"), 1.0, "the figures step back from full rubric")
	var ink := WarSheetInk.strokes(repo, state, _richest_sheet(), 4096)
	assert_gt((ink["graticule"] as Array).size(), 0)
	for g: Dictionary in ink["graticule"]:
		assert_almost_eq(float(g["fig_alpha"]), repo.bal("war_grid_figure_alpha"), 0.0001)
