extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The war markers' tray (owner 2026-10-12, items 6-7; R11 owner-approved): up
## to war_tray_max markers, one per cell, the held cells laid as ONE sheet over
## their bounding box of at most war_tray_max cells; a toss past it is refused,
## an edge arrow moves every marker one cell. Plus the barrier bars across a
## march where the ground is too steep (item 5).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func after_each() -> void:
	MarchPath.forget()


## A hand-made chart: sheets 0..8 on a 3 x 3 block of cells from (4, 4), and
## sheet 9 alone at (7, 4) — (6, 4) is sea.
func _cells() -> Dictionary:
	var out: Dictionary = {}
	for i in 9:
		out[i] = Vector2i(4 + i % 3, 4 + int(i / 3.0))
	out[9] = Vector2i(7, 4)
	return out


func _sheet_at(cells: Dictionary, at: Vector2i) -> int:
	for s: int in cells:
		if cells[s] == at:
			return s
	return -1


func test_the_tray_holds_the_balance_keys_count() -> void:
	assert_eq(int(repo.bal("war_tray_max")), 4)
	assert_eq(WarTray.of(repo, 4).max_slots, 4)
	assert_eq(WarTray.of(repo, 1).max_slots, 1, "as many slots as markers authored")
	assert_eq(WarTray.of(repo, 9).max_slots, 4, "never more than war_tray_max")
	assert_eq(WarTray.of(repo, 1).max_cells, 4)


## (4,4) + (5,5) is a 2 x 2 box: taken; then (6,4) would make it 3 x 2 = 6
## cells: refused, nothing changed.
func test_toss_refused_past_four_cells() -> void:
	var c := _cells()
	var t := WarTray.new(4, 4, c)
	var a := _sheet_at(c, Vector2i(4, 4))
	var b := _sheet_at(c, Vector2i(5, 5))
	var far := _sheet_at(c, Vector2i(6, 4))
	assert_eq(t.take(a), 0)
	assert_eq(t.take(b), 1, "2 x 2 = 4 cells: taken")
	assert_eq(t.take(far), -1, "3 x 2 = 6 cells: refused")
	assert_eq(t.held(), [a, b])
	assert_eq(t.take(_sheet_at(c, Vector2i(5, 4))), 2, "inside the box: taken")
	assert_eq(t.take(_sheet_at(c, Vector2i(4, 5))), 3, "the 2 x 2 full")
	assert_true(t.full())
	assert_eq(t.take(far), -1, "full: the newest cannot move there either (3 x 2)")


func test_a_one_by_four_column_fits_and_a_fifth_cell_never_does() -> void:
	var c: Dictionary = {}
	for i in 5:
		c[i] = Vector2i(2, i)
	var t := WarTray.new(4, 4, c)
	for i in 4:
		assert_eq(t.take(i), i)
	assert_eq(WarTray.extent_cells([c[0], c[3]]), Vector2i(1, 4))
	assert_eq(t.take(4), -1, "five cells never fit in four")


## Before Marker2-4 are authored the tray has one slot: a toss moves it, as
## the single marker always did.
func test_one_marker_moves_with_every_toss() -> void:
	var c := _cells()
	var t := WarTray.new(1, 4, c)
	assert_eq(t.take(0), 0)
	assert_eq(t.take(9), 0, "moved, however far")
	assert_eq(t.held(), [9])
	assert_eq(t.take(9), -1, "already there")


func test_a_held_cell_gives_its_marker_back_but_never_the_last() -> void:
	var t := WarTray.new(4, 4, _cells())
	t.take(0)
	t.take(1)
	assert_true(t.put_back(1))
	assert_eq(t.slot_of(1), -1)
	assert_false(t.put_back(0), "the last one out stays")
	assert_false(t.put_back(5), "no marker there")
	assert_eq(t.take(3), 1, "the freed slot is the next taken")
	assert_eq(t.newest(), 3)


## A lay without a toss (the first lay, a margin row): a free marker when the
## box fits, else every marker back but the newest, which stands there.
func test_hold_takes_a_marker_or_starts_over_on_one_cell() -> void:
	var t := WarTray.new(4, 4, _cells())
	assert_eq(t.hold(0), 0)
	assert_eq(t.hold(4), 1, "(5,5): a 2 x 2 box")
	assert_eq(t.hold(4), 1, "already held")
	assert_eq(t.hold(9), 1, "(7,4) makes it 4 x 2: the newest stands there alone")
	assert_eq(t.held(), [9])
	assert_eq(t.count(), 1)


func test_edge_arrow_moves_the_markers() -> void:
	var c := _cells()
	var t := WarTray.new(4, 4, c)
	t.take(_sheet_at(c, Vector2i(4, 4)))
	t.take(_sheet_at(c, Vector2i(5, 4)))
	assert_eq(t.shifted(Vector2i(0, 1)), [_sheet_at(c, Vector2i(4, 5)), _sheet_at(c, Vector2i(5, 5))])
	assert_true(t.shift(Vector2i(0, 1)))
	assert_eq(t.count(), 2, "the count of markers unchanged")
	assert_eq(t.held(), [_sheet_at(c, Vector2i(4, 5)), _sheet_at(c, Vector2i(5, 5))])
	assert_false(t.can_shift(Vector2i(0, -2)), "off the sheets")
	assert_true(t.shift(Vector2i(1, 0)))
	assert_false(t.shift(Vector2i(1, 0)), "(7,5) is no sheet: nothing moves")
	assert_eq(t.held(), [_sheet_at(c, Vector2i(5, 5)), _sheet_at(c, Vector2i(6, 5))])
	assert_eq(t.count(), 2)


## Every direction an edge arrow can walk, with 1..4 markers: the count never
## changes and no two markers share a sheet.
func test_a_shift_never_loses_or_doubles_a_marker() -> void:
	var c := _cells()
	var order := [Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)]
	var walked := 0
	for n in range(1, 5):
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var t := WarTray.new(4, 4, c)
			for i in n:
				t.take(_sheet_at(c, order[i]))
			assert_eq(t.count(), n)
			if not t.can_shift(dir):
				continue
			walked += 1
			assert_true(t.shift(dir))
			var held := t.held()
			assert_eq(t.count(), n, "%d markers, shift %s: count unchanged" % [n, dir])
			assert_eq(held.size(), n)
			for i in held.size():
				assert_gte(int(held[i]), 0)
				for j in range(i + 1, held.size()):
					assert_ne(held[i], held[j], "%d markers, shift %s: slots distinct" % [n, dir])
	assert_gt(walked, 4, "the walk really shifted")


## 1 x 4 cells deep is laid narrower so it lies no deeper than
## war_table_max_depth_m; one cell is never narrowed.
func test_union_table_fits_the_oak() -> void:
	var deg := repo.bal("war_sheet_deg")
	var collar := repo.bal("war_sheet_collar_km") * WarSheets.px_per_unit(repo)
	var one := MapCoords.cell_rect(repo, Vector2i(3, 2), deg).grow(collar)
	var one_sheet := {"rect": one, "cols": 1, "rows": 1}
	assert_almost_eq(WarRoomTable.width_for(repo, one_sheet), repo.bal("war_table_w_m"), 0.0001, "one cell: as wide as ever")
	# one cell is never narrowed, however deep its rect
	assert_almost_eq(WarRoomTable.width_for(repo, {"rect": Rect2(0, 0, 100, 900), "cols": 1, "rows": 1}), repo.bal("war_table_w_m"), 0.0001)
	assert_lte(WarRoomTable.depth_m(one, repo.bal("war_table_w_m")), repo.bal("war_table_max_depth_m"))
	var column := MapCoords.cell_rect(repo, Vector2i(3, 2), deg).merge(MapCoords.cell_rect(repo, Vector2i(3, 5), deg)).grow(collar)
	var column_sheet := {"rect": column, "cols": 1, "rows": 4}
	var w := WarRoomTable.width_for(repo, column_sheet)
	assert_lt(w, repo.bal("war_table_w_m"))
	assert_almost_eq(WarRoomTable.depth_m(column, w), repo.bal("war_table_max_depth_m"), 0.0001)
	# the deepest sheet still leaves the index chart its north band of the oak
	var chart_south := repo.bal("war_chart_z_m")   # the leaning chart's near edge (R10)
	assert_lte(chart_south, -repo.bal("war_table_max_depth_m") * 0.5, "the chart's south edge north of the sheet")
	var row := MapCoords.cell_rect(repo, Vector2i(3, 2), deg).merge(MapCoords.cell_rect(repo, Vector2i(6, 2), deg)).grow(collar)
	assert_almost_eq(WarRoomTable.width_for(repo, {"rect": row, "cols": 4, "rows": 1}), repo.bal("war_table_w_m"), 0.0001, "a 4 x 1 row is shallow")
	# the plinth keeps its true size on the oak: a 1 x 4 union's ink px per metre is its own
	var per_m := float(WarRoomInk.tex_size(repo, column).x) / w
	assert_almost_eq(WarSheetInk.plinth_radius_px(repo, 1.0, column_sheet), repo.bal("war_piece_plinth_mm") / 1000.0 * 0.5 * per_m, 0.001)
	assert_gt(WarSheetInk.plinth_radius_px(repo, 1.0, column_sheet), WarSheetInk.plinth_radius_px(repo), "a deep union's ink is denser per metre")
	assert_almost_eq(WarSheetInk.plinth_radius_px(repo, 1.0, one_sheet), WarSheetInk.plinth_radius_px(repo), 0.0001, "one cell: today's value")
	assert_almost_eq(WarSheetInk.name_dx(repo, 0, 1.0, one_sheet), WarSheetInk.name_dx(repo, 0), 0.0001)
	# the relief grid's budget stands on the longer side
	var nx_one := maxi(2, roundi(repo.bal("war_relief_grid") * minf(1.0, one.size.x / one.size.y)))
	assert_eq(nx_one, int(repo.bal("war_relief_grid")), "one cell keeps today's grid")
	var nx_col := maxi(2, roundi(repo.bal("war_relief_grid") * minf(1.0, column.size.x / column.size.y)))
	assert_lt(nx_col, int(repo.bal("war_relief_grid")))
	assert_lte(WarRoomTable.rows_for(column, nx_col), int(repo.bal("war_relief_grid")) + 1)


## The ink stays war_sheet_texture_px across the LONGER side: a deep union
## never asks for a taller texture than one cell's width.
func test_a_deep_union_keeps_its_ink_texture_in_bounds() -> void:
	var px := int(repo.bal("war_sheet_texture_px"))
	var deep := Rect2(0, 0, 100, 380)
	var s := WarRoomInk.tex_size(repo, deep)
	assert_eq(s.y, px)
	assert_lte(WarRoomInk.used_share(repo, deep), 1.0001, "the sheet's rows fit the texture")
	assert_eq(WarRoomInk.tex_size(repo, Rect2(0, 0, 140, 104)).x, px, "a wide sheet as before")


## Above one cell the lower tiers' town names drop (war_union_label_min_tier).
func test_a_union_leaves_out_the_lower_towns_names() -> void:
	var state := SuiteData.campaign(repo, 42)
	var all := WarSheets.series(repo)
	for s: Dictionary in all:
		var e := -1
		for o: Dictionary in all:
			if int(o["col"]) == int(s["col"]) + 1 and int(o["row"]) == int(s["row"]):
				e = int(o["index"])
		if e < 0:
			continue
		var u := WarSheets.union(repo, [int(s["index"]), e])
		var min_tier := int(repo.bal("war_union_label_min_tier"))
		var towns: Array = WarSheetInk.strokes(repo, state, u, WarRoomInk.tex_size(repo, u["rect"]).x)["towns"]
		if towns.is_empty():
			continue
		for t: Dictionary in towns:
			assert_eq(String(t["label"]) != "", int(t["tier"]) >= min_tier, "%s (tier %d)" % [t["code"], t["tier"]])
		return
	pass_test("no pair with towns in this pack")


## The view with four authored markers (the test's own nodes): a toss onto a
## neighbour lays both cells as one; an edge arrow moves both and never adds one.
func test_the_view_lays_the_held_cells_and_its_arrows_move_every_marker() -> void:
	WarSheets.forget()
	var state := SuiteData.campaign(repo, 42)
	var view: WarRoomView = load("res://scenes/war_room/war_room.tscn").instantiate()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(1000, 600)
	var room := view.get_node("Viewport/Room") as Node3D
	var markers: Array[Node3D] = []
	for i in 4:
		var m := Node3D.new()
		m.name = "TestMarker%d" % i
		room.add_child(m)
		markers.append(m)
	view.tray_markers = markers
	add_child_autofree(view)
	view.bind(repo, func() -> GameState: return state, func() -> bool: return true)
	view.set_active(true)
	view.sheet_requested.connect(view.swap_to)   # as the screen wires it
	var all := WarSheets.series(repo)
	var a := -1
	var b := -1
	for s: Dictionary in all:
		var near := WarSheets.neighbours(repo, int(s["index"]))
		if near.has("e") and WarSheets.neighbours(repo, int(near["e"])).has("s") and near.size() >= 2:
			a = int(s["index"])
			b = int(near["e"])
			break
	assert_gte(a, 0, "a sheet with an east neighbour")
	view.lay_sheet(a)
	await wait_process_frames(2)
	assert_eq(view.sheet_key(), str(a), "one marker, one sheet as before")
	assert_almost_eq(view.table_width(), repo.bal("war_table_w_m"), 0.0001)
	var flight := float(WarToss.plan(Vector3.ZERO, Vector3.ONE, 1, WarToss.rules(repo))["duration"])
	view.toss_to(b)
	assert_true(view.tossing())
	await wait_until(func() -> bool: return view.sheet_key() == "%d+%d" % [mini(a, b), maxi(a, b)] and not view.tossing() and not view.rolling(), flight + repo.bal("war_sheet_swap_s") + 2.0)
	assert_eq(view.tray_sheets(), [a, b])
	assert_eq(view.sheet_key(), "%d+%d" % [mini(a, b), maxi(a, b)], "both cells laid as one")
	assert_eq(view.sheet_rect(), WarSheets.union(repo, [a, b])["rect"])
	assert_ne(view.marker_for(a), view.marker_for(b), "a marker each")
	var arrows: Array = view.get_node("%EdgeArrows").get_children()
	assert_gt(arrows.size(), 0, "a side both can move toward")
	var to := int((arrows[0] as Node).get_meta("sheet"))
	view.shift_toward(to)
	await wait_until(func() -> bool: return view.sheet_index() == to, repo.bal("war_sheet_swap_s") + 2.0)
	assert_eq(view.tray_sheets().size(), 2, "every marker moved, none added")
	assert_eq(view.sheet_index(), to)
	assert_eq(view.sheet_key(), String(WarSheets.union(repo, view.tray_sheets())["key"]))
	var resting := 0
	for m: Node3D in markers:
		var on := false
		for s: int in view.tray_sheets():
			on = on or view.marker_for(s) == m
		resting += 0 if on else 1
	assert_eq(resting, 2, "the other two still rest in the tray")


## A hand-built grid, cells of 1 km: a scarp (1.5 rise per run, past army_max_slope)
## down column 4, rows 0..3 of 9 x 5.
func _grid(wall: int) -> MarchPath:
	var bytes := PackedByteArray()
	bytes.resize(45)
	bytes.fill(20)
	for y in 4:
		bytes[y * 9 + 4] = wall
	return MarchPath.build(repo, 9, 5, 1000, bytes)


func test_one_barrier_bar_lies_across_a_march_over_a_scarp() -> void:
	repo.balance["army_march_grid_px"] = 4
	MarchPath.use(repo, _grid(150))
	var from := ArmySystem.metres_to_pack(repo, Vector2i(1500, 2500))
	var to := ArmySystem.metres_to_pack(repo, Vector2i(7500, 2500))
	var bars := WarSlopeBars.bars(repo, [from, to])
	assert_eq(bars.size(), 1, "one run of steep ground, one bar")
	# the run is cell (4, 2) alone, entered from the west: its entry edge is x = 4000 m;
	# the march runs east, so the bar runs north-south, (0.75 + 0.5) cells = 1250 m either side
	var a := ArmySystem.pack_to_metres(repo, bars[0]["a"])
	var b := ArmySystem.pack_to_metres(repo, bars[0]["b"])
	assert_almost_eq(float(a.x), 4000.0, 2.0)
	assert_almost_eq(float(b.x), 4000.0, 2.0)
	assert_almost_eq(absf(float(b.y - a.y)), 2500.0, 3.0)
	assert_eq(bars[0]["cells"], 1)
	repo.balance["army_march_grid_px"] = 0


func test_a_bar_at_a_grazed_corner_sits_where_the_route_touches() -> void:
	repo.balance["army_march_grid_px"] = 4
	var bytes := PackedByteArray()
	bytes.resize(45)
	bytes.fill(20)
	bytes[2 * 9 + 4] = 150   # only cell (4, 2)
	MarchPath.use(repo, MarchPath.build(repo, 9, 5, 1000, bytes))
	var from := ArmySystem.metres_to_pack(repo, Vector2i(2500, 3500))
	var to := ArmySystem.metres_to_pack(repo, Vector2i(5500, 500))
	var bars := WarSlopeBars.bars(repo, [from, to])
	assert_eq(bars.size(), 1)
	# x + y = 6000 touches (4, 2) at its corner (4000, 2000); the bar is centred there,
	# across the (0.7071, -0.7071) march: 1250 m either way along (0.7071, 0.7071)
	var a := ArmySystem.pack_to_metres(repo, bars[0]["a"])
	var b := ArmySystem.pack_to_metres(repo, bars[0]["b"])
	assert_almost_eq(float(a.x), 3116.0, 3.0)
	assert_almost_eq(float(a.y), 1116.0, 3.0)
	assert_almost_eq(float(b.x), 4884.0, 3.0)
	assert_almost_eq(float(b.y), 2884.0, 3.0)
	repo.balance["army_march_grid_px"] = 0


func test_no_bar_on_open_ground_water_or_a_gentle_slope() -> void:
	repo.balance["army_march_grid_px"] = 4
	var from := ArmySystem.metres_to_pack(repo, Vector2i(1500, 2500))
	var to := ArmySystem.metres_to_pack(repo, Vector2i(7500, 2500))
	MarchPath.use(repo, _grid(MarchPath.WATER))
	assert_true(WarSlopeBars.bars(repo, [from, to]).is_empty(), "water is not a scarp")
	MarchPath.use(repo, _grid(50))
	assert_true(WarSlopeBars.bars(repo, [from, to]).is_empty(), "a gentle slope is climbed")
	repo.balance["army_march_grid_px"] = 0


func test_a_march_ending_on_the_scarp_has_no_bar_at_its_own_cell() -> void:
	repo.balance["army_march_grid_px"] = 4
	MarchPath.use(repo, _grid(150))
	var from := ArmySystem.metres_to_pack(repo, Vector2i(1500, 2500))
	var to := ArmySystem.metres_to_pack(repo, Vector2i(4500, 2500))
	assert_true(WarSlopeBars.bars(repo, [from, to]).is_empty(), "the end's own cell never blocks")
	repo.balance["army_march_grid_px"] = 0


func test_a_far_small_bar_is_held_to_the_minimum_length() -> void:
	var e := WarSlopeBars.at_least(Vector2(100, 50), Vector2(110, 50), 40.0)
	assert_eq(e, [Vector2(85, 50), Vector2(125, 50)])
	assert_eq(WarSlopeBars.at_least(Vector2(0, 0), Vector2(0, 60), 40.0), [Vector2(0, 0), Vector2(0, 60)])
