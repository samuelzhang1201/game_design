extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const ClearPiece := preload("res://tests/war_room/clear_piece.gd")
## The room's view laid with a sheet: the table, the ink, the picks (spec §1–2).

var repo: DataRepository
var state: GameState
var view: WarRoomView


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()
	view = load("res://scenes/war_room/war_room.tscn").instantiate()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)  # a sized view, not one stretched to its parent
	view.size = Vector2(1000, 600)
	add_child_autofree(view)
	view.bind(repo, func() -> GameState: return state, func() -> bool: return true)
	view.set_active(true)


func test_laying_a_sheet_builds_the_table_at_the_sheets_ratio() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	assert_eq(view.sheet_index(), 0)
	var table: MeshInstance3D = view.get_node("%Table")
	var aabb := table.mesh.get_aabb()
	var r: Rect2 = WarSheets.series(repo)[0]["rect"]
	assert_almost_eq(aabb.size.x, repo.bal("war_table_w_m"), 0.001)
	assert_almost_eq(aabb.size.z, WarRoomTable.depth_m(r, repo.bal("war_table_w_m")), 0.001)


func test_a_point_on_the_sheet_projects_into_the_view() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var r: Rect2 = WarSheets.series(repo)[0]["rect"]
	var at: Variant = view.screen_pos_of_px(r.get_center())
	assert_not_null(at)
	assert_true(Rect2(Vector2.ZERO, view.size).has_point(at), "the sheet's centre is in the opening view")


func test_the_tree_carries_the_nodes_later_tasks_fill() -> void:
	for n in ["Viewport", "Display", "Camera", "Table", "Pieces", "Pennants", "Room", "Hud", "InkViewport", "Ink"]:
		assert_not_null(view.get_node_or_null("%" + n), n)
	assert_true((view.get_node("%Viewport") as SubViewport).own_world_3d)
	assert_true(view.get_node("%Hud") is WarHud)
	assert_true(view.get_node("%Pennants") is WarPennants)


func test_a_second_lay_supersedes_the_first() -> void:
	view.lay_sheet(0)
	view.lay_sheet(1)  # the first is still awaiting its ink
	await wait_process_frames(3)
	assert_eq(view.sheet_index(), 1)
	var r: Rect2 = WarSheets.series(repo)[1]["rect"]
	var table: MeshInstance3D = view.get_node("%Table")
	assert_almost_eq(table.mesh.get_aabb().size.z, WarRoomTable.depth_m(r, repo.bal("war_table_w_m")), 0.001)


func test_the_ink_cache_holds_one_entry_per_sheet() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	view._inks.store(0, 111, img)
	view._inks.store(0, 222, img.duplicate())
	view._inks.store(1, 333, img.duplicate())
	assert_eq(view._inks.cache.size(), 2, "sheets 0 and 1, not three keys")
	assert_eq(view._inks.cache[0]["key"], 222, "a new key replaces the old texture")
	view._inks.store(2, 1, Image.new())
	assert_false(view._inks.cache.has(2), "an empty readback (headless) stores nothing")


func test_the_ink_cache_keeps_the_laid_sheet_and_one_other() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for sheet in [0, 1, 2]:
		view._inks.store(sheet, 10 + sheet, img.duplicate())
	assert_lte(view._inks.cache.size(), 2, "three sheets laid, at most two kept")
	assert_true(view._inks.cache.has(2), "the laid sheet is kept")
	assert_true(view._inks.cache.has(1), "and the one before it")
	assert_false(view._inks.cache.has(0), "the oldest is let go")


## Perf 2026-10-02: the room shut gives its render targets back and keeps
## only the laid sheet's ink; opened again it is the window's size.
func test_a_shut_room_gives_back_its_render_targets_and_all_but_the_laid_ink() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for sheet in [0, 1]:
		view._inks.store(sheet, 10 + sheet, img.duplicate())
	view.set_active(false)
	var vp: SubViewport = view.get_node("%Viewport")
	assert_eq(vp.size, Vector2i(2, 2), "nothing rendered, nothing held")
	assert_eq(view._inks.cache.keys(), [1], "the laid sheet's ink alone")
	view.set_active(true)
	assert_gt(vp.size.x, 2, "open again, the window's size")


func test_the_ink_viewport_is_smallest_at_rest_and_after_a_paint() -> void:
	var ink: SubViewport = view.get_node("%InkViewport")
	assert_eq(ink.size, WarRoomInk.REST, "nothing is allocated before a sheet is laid")
	view._inks.frame_done = get_tree().process_frame   # headless never posts a draw
	view.lay_sheet(0)
	# frame_done is the process frame here: the paint is over a frame or two on
	await wait_process_frames(5)
	assert_eq(ink.size, WarRoomInk.REST, "the render target is given back after the paint")


func test_the_ink_texture_is_sized_to_the_sheet_not_square() -> void:
	var r: Rect2 = WarSheets.series(repo)[0]["rect"]
	var s := WarRoomInk.tex_size(repo, r)
	assert_eq(s.x, int(repo.bal("war_sheet_texture_px")))
	assert_almost_eq(float(s.y) / float(s.x), r.size.y / r.size.x, 1.0 / float(s.x) + 0.0001)
	assert_almost_eq(WarRoomInk.used_share(repo, r), 1.0, 0.001, "the sheet fills its texture's height")


func test_a_sheet_out_of_range_is_ignored() -> void:
	view.lay_sheet(999)
	await wait_process_frames(1)
	assert_eq(view.sheet_index(), -1)


## The sheet with the most towns inside it (v2's sheets are small: index 0 may
## hold none).
func _town_sheet() -> int:
	var best := 0
	var most := -1
	for s: Dictionary in WarSheets.series(repo):
		var n := 0
		for code: String in repo.burgs:
			var b: Dictionary = repo.burgs[code]
			if (s["rect"] as Rect2).grow(-(s["rect"] as Rect2).size.x * 0.15).has_point(Vector2(float(b["x"]), float(b["y"]))):
				n += 1
		if n > most:
			most = n
			best = int(s["index"])
	return best


func test_pack_at_inverts_screen_pos_of_px_on_land() -> void:
	var si := _town_sheet()
	view.lay_sheet(si)
	await wait_process_frames(2)
	var r: Rect2 = WarSheets.series(repo)[si]["rect"]
	var codes: Array = repo.burgs.keys()
	codes.sort()
	var checked := 0
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var p := Vector2(float(b["x"]), float(b["y"]))
		if not r.grow(-r.size.x * 0.15).has_point(p):
			continue
		var at: Variant = view.screen_pos_of_px(p)
		if at == null:
			continue
		var back := view.pack_at(at)
		assert_lt(back.distance_to(p), r.size.x * 0.01, "%s comes back to itself" % code)
		checked += 1
		if checked >= 5:
			break
	assert_gt(checked, 0, "the sheet has towns to round-trip")


func test_two_views_do_not_share_a_material_or_an_environment() -> void:
	var other: WarRoomView = load("res://scenes/war_room/war_room.tscn").instantiate()
	add_child_autofree(other)
	assert_ne(other.get_node("%Table").material_override, view.get_node("%Table").material_override)
	assert_ne((other.get_node("%Env") as WorldEnvironment).environment, (view.get_node("%Env") as WorldEnvironment).environment)


func test_a_laid_sheet_stands_an_arrow_at_each_neighbouring_side() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var near := WarSheets.neighbours(repo, 0)
	var arrows: Array = view.get_node("%EdgeArrows").get_children()
	assert_eq(arrows.size(), near.size())
	var want: Array = near.values()
	for a: Node in arrows:
		assert_true(int(a.get_meta("sheet")) in want)
		assert_true((a as Label3D).text.ends_with(String(WarSheets.series(repo)[int(a.get_meta("sheet"))]["id"])))


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		view._gui_input(e)


func test_a_click_on_an_edge_arrow_requests_its_sheet() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	var arrow := view.get_node("%EdgeArrows").get_child(0) as Label3D
	var at: Vector2 = (view.get_node("%Camera") as Camera3D).unproject_position(arrow.global_position) / view.window_scale()
	_click(at)
	assert_signal_emitted_with_parameters(view, "sheet_requested", [int(arrow.get_meta("sheet"))])


func test_the_chart_letters_every_nth_column_and_numbers_every_nth_row() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var g := MapCoords.grid_size(repo, repo.bal("war_sheet_deg"))
	var every := int(repo.bal("war_chart_label_every"))
	var labels := view.get_node("%IndexChart").get_children()
	var cols := labels.filter(func(l: Node) -> bool: return String(l.get_meta("axis")) == "col")
	var rows := labels.filter(func(l: Node) -> bool: return String(l.get_meta("axis")) == "row")
	assert_eq(cols.size(), ceili(float(g.x) / every))
	assert_eq(rows.size(), ceili(float(g.y) / every))
	assert_eq((cols[0] as Label3D).text, "A")
	if cols.size() > 1:
		assert_eq((cols[1] as Label3D).text, WarSheets.column_letters(every))


func test_a_click_on_a_land_cell_of_the_chart_asks_for_its_sheet() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var cam: Camera3D = view.get_node("%Camera")
	var chart: MeshInstance3D = view.get_node("%IndexChart")
	var tried := 0
	for s: Dictionary in WarSheets.series(repo):
		var uv := WarIndexChart.uv_of_cell(repo, s).get_center()
		var p := WarRoomWall.chart_point(chart, uv)
		var at := cam.unproject_position(p) / view.window_scale()
		if not Rect2(Vector2.ZERO, view.size).has_point(at):
			continue
		assert_eq(WarRoomWall.pick_chart(chart, cam, repo, at * view.window_scale()), int(s["index"]), String(s["id"]))
		tried += 1
	assert_gt(tried, 0, "the chart is in the opening view")

func test_every_chart_corner_stands_in_the_opening_view() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var cam: Camera3D = view.get_node("%Camera")
	var chart: MeshInstance3D = view.get_node("%IndexChart")
	var half := (chart.mesh as QuadMesh).size * 0.5
	for c: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
		var at := cam.unproject_position(chart.global_transform * Vector3(c.x, c.y, 0.0)) / view.window_scale()
		assert_true(Rect2(Vector2.ZERO, view.size).has_point(at), "corner %s at %s" % [c, at])


func test_a_ray_that_misses_the_chart_picks_nothing() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var cam: Camera3D = view.get_node("%Camera")
	var chart: MeshInstance3D = view.get_node("%IndexChart")
	var far_left := chart.global_transform * Vector3(-(chart.mesh as QuadMesh).size.x, 0.0, 0.0)
	assert_eq(WarRoomWall.pick_chart(chart, cam, repo, cam.unproject_position(far_left)), -1, "beside the board")
	# a ray parallel to the board's face
	var flat := Camera3D.new()
	add_child_autofree(flat)
	flat.global_transform = Transform3D(chart.global_transform.basis, chart.global_position + chart.global_transform.basis.z * 0.5)
	flat.global_transform = flat.global_transform.looking_at(flat.global_position + chart.global_transform.basis.x, chart.global_transform.basis.y)
	assert_eq(WarRoomWall.pick_chart(chart, flat, repo, Vector2(0, 0)), -1, "grazing along the face")


func test_a_swap_requested_mid_roll_is_ignored() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	view.swap_to(1)
	view._process(0.01)
	view.swap_to(2)
	view._process(repo.bal("war_sheet_swap_s"))
	assert_eq(view.sheet_index(), 1, "the roll in progress was not redirected")


func test_a_drag_is_not_a_click_on_the_chart() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	var arrow := view.get_node("%EdgeArrows").get_child(0) as Label3D
	var at: Vector2 = (view.get_node("%Camera") as Camera3D).unproject_position(arrow.global_position) / view.window_scale()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	view._gui_input(press)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = at + Vector2(repo.bal("war_rake_min_px") + 2.0, 0.0)
	view._gui_input(release)
	assert_signal_not_emitted(view, "sheet_requested")


func test_swap_to_lays_the_new_sheet_at_the_midpoint_and_stands_the_table_up_again() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var swap_s := repo.bal("war_sheet_swap_s")
	view.swap_to(1)
	view._process(swap_s * 0.25)
	assert_eq(view.sheet_index(), 0, "still the first sheet before the midpoint")
	assert_lt((view.get_node("%Table") as Node3D).scale.z, 0.6, "rolling up")
	view._process(swap_s * 0.3)
	assert_eq(view.sheet_index(), 1, "laid at the midpoint")
	view._process(swap_s)
	assert_eq((view.get_node("%Table") as Node3D).scale, Vector3.ONE)


func test_closing_the_room_mid_roll_lays_the_sheet_and_stands_the_table_up() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	view.swap_to(1)
	view._process(0.01)
	view.set_active(false)
	assert_eq(view.sheet_index(), 1)
	assert_eq((view.get_node("%Table") as Node3D).scale, Vector3.ONE)


func _press(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	view._gui_input(e)


func _move(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(e)


func _release(at: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = at
	view._gui_input(e)


## A land piece of the laid sheet a click on its own drawn point takes up,
## with that point as `press` (tests/war_room/clear_piece.gd: the camp's
## spread moves pieces off their engine points and may stand one's figures
## over another's base, whatever army_slot_spacing_m is).
func _first_land_piece() -> Dictionary:
	return ClearPiece.find(view, repo, state)


func _shift(e: InputEventWithModifiers) -> InputEventWithModifiers:
	e.shift_pressed = true
	return e


func _land_pieces() -> Array:
	return WarRoom.on_sheet(repo, state, view.sheet_index()).filter(func(q: Dictionary) -> bool: return not bool(q["naval"]))


## `n` land regiments stood out in the field side by side (no town's
## garrison), their sheet laid.
func _lay_with(n: int) -> bool:
	ArmySystem.ensure(repo, state)
	var codes: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, r) > 0:
			codes.append(String(r["regiment_code"]))
	if codes.size() < n:
		return false
	var base := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, codes[0], state))
	var k := WarSheets.px_per_unit(repo)   # pack px a km
	for i in n:
		var m := ArmySystem.pack_to_metres(repo, base + Vector2(7.0 * (i + 1), 4.0) * k)
		state.regiments[codes[i]]["x_m"] = m.x
		state.regiments[codes[i]]["y_m"] = m.y
	view.lay_sheet(WarSheets.sheet_of(repo, base + Vector2(7.0, 4.0) * k))
	return true


func test_a_click_on_a_piece_selects_its_regiments_and_arms_nothing() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var at: Vector2 = p["press"]
	watch_signals(view)
	_press(at)
	_move(at + Vector2(2, 0))   # under war_rake_min_px
	_release(at + Vector2(2, 0))
	assert_signal_emitted_with_parameters(view, "piece_selected", [String(p["code"])])
	assert_eq(view.plan_input().sel_side, "blue")
	assert_eq(view.plan_input().sel, [String(p["code"])], "one unit a piece")
	assert_false(view.aiming, "a click arms no march")


func test_a_drag_from_a_piece_pans_and_orders_nothing() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var at: Vector2 = p["press"]
	var target := view.camera_rig().target
	watch_signals(view)
	_press(at)
	var m := InputEventMouseMotion.new()
	m.position = at + Vector2(60, 0)
	m.relative = Vector2(60, 0)
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(m)
	_release(at + Vector2(60, 0))
	assert_ne(view.camera_rig().target, target, "the drag panned the room")
	assert_signal_not_emitted(view, "ground_clicked")
	assert_signal_not_emitted(view, "piece_selected")


func test_shift_click_adds_a_piece_and_takes_it_out_and_a_click_away_lets_all_go() -> void:
	if not _lay_with(2):
		pending("no sheet holds two land pieces")
		return
	await wait_process_frames(2)
	var two := _land_pieces()
	var a: Vector2 = view.screen_pos_of_px(two[0]["at"])
	var b: Vector2 = view.screen_pos_of_px(two[1]["at"])
	_press(a)
	_release(a)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = b
	e.pressed = true
	view._gui_input(_shift(e))
	var r := e.duplicate() as InputEventMouseButton
	r.pressed = false
	view._gui_input(r)
	var both: Array = [String(two[0]["code"]), String(two[1]["code"])]
	assert_eq(view.plan_input().sel.size(), both.size(), "Shift adds")
	view._gui_input(_shift(e.duplicate() as InputEventMouseButton))
	view._gui_input(r)
	assert_eq(view.plan_input().sel, [String(two[0]["code"])], "Shift again takes it out")
	var open := _open_spot([a, b])
	assert_ne(open, Vector2(-1, -1), "an open spot of table")
	_press(open)
	_release(open)
	assert_eq(view.plan_input().sel, [], "a click on open table lets the selection go")
	assert_eq(view.selected_army(), "")


## A spot of open table well away from `away` (screen px): no piece, pennant,
## edge arrow or chart under it.
func _open_spot(away: Array) -> Vector2:
	var cam := view.get_node("%Camera") as Camera3D
	for y in range(int(view.size.y * 0.3), int(view.size.y * 0.8), 15):
		for x in range(int(view.size.x * 0.2), int(view.size.x * 0.8), 15):
			var q := Vector2(x, y)
			if view.pack_at(q).x < 0.0 or view.piece_under(q) != "" or away.any(func(w: Vector2) -> bool: return w.distance_to(q) < 70.0):
				continue
			if WarRoomWall.pick_arrow(view.get_node("%EdgeArrows"), cam, q, view.window_scale(), repo.bal("war_pick_px")) >= 0:
				continue
			if WarRoomWall.pick_chart(view.get_node("%IndexChart"), cam, repo, q * view.window_scale()) >= 0:
				continue
			return q
	return Vector2(-1, -1)


func test_shift_drag_boxes_every_land_piece_inside() -> void:
	if not _lay_with(2):
		pending("no sheet holds two land pieces")
		return
	await wait_process_frames(2)
	var want: Array = []
	var box := Rect2()
	for q: Dictionary in _land_pieces():
		var at: Variant = view.screen_pos_of_px(q["at"])
		if at == null:
			continue
		box = Rect2(at, Vector2.ZERO) if want.is_empty() else box.expand(at)
		want.append(String(q["code"]))
	var start := Vector2(-1, -1)
	var end := Vector2(-1, -1)
	for g: float in [20.0, 35.0, 50.0, 70.0]:
		var bx := box.grow(g)
		var corners := [bx.position, Vector2(bx.end.x, bx.position.y), bx.end, Vector2(bx.position.x, bx.end.y)]
		for i in 4:
			var c: Vector2 = corners[i]
			if start.x < 0.0 and view.pack_at(c).x >= 0.0 and view.piece_under(c) == "" and view.plan_input().hint_at(c) == "":
				start = c
				end = corners[(i + 2) % 4]
	assert_true(start.x >= 0.0, "the box starts on open table")
	box = Rect2(start, Vector2.ZERO).expand(end)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = start
	e.pressed = true
	view._gui_input(_shift(e))
	var m := InputEventMouseMotion.new()
	m.position = end
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	view._gui_input(_shift(m))
	assert_true(view.plan_input().marquee().has_area(), "the chalk marquee follows the drag")
	var r := e.duplicate() as InputEventMouseButton
	r.pressed = false
	r.position = end
	view._gui_input(r)
	want.sort()
	var got: Array = view.plan_input().sel.duplicate()
	got.sort()
	assert_eq(got, want)
	assert_eq(view.plan_input().sel_side, "blue")
	assert_false(view.plan_input().marquee().has_area())
	var lit: Array = (view.get_node("%Pieces") as WarPieces).glowing()
	lit.sort()
	assert_eq(lit, want, "each selected piece glows on the table")
	assert_eq((view.get_node("%Hud") as WarHud).marks()["rings"], [], "and no ring is drawn round it on the HUD")


## A box round every land piece of the laid sheet, from a corner on open
## table: [want (codes), start, end] (screen px), [] when none fits.
func _box_corners() -> Array:
	var want: Array = []
	var box := Rect2()
	for q: Dictionary in _land_pieces():
		var at: Variant = view.screen_pos_of_px(q["at"])
		if at == null:
			continue
		box = Rect2(at, Vector2.ZERO) if want.is_empty() else box.expand(at)
		want.append(String(q["code"]))
	for g: float in [20.0, 35.0, 50.0, 70.0]:
		var bx := box.grow(g)
		var corners := [bx.position, Vector2(bx.end.x, bx.position.y), bx.end, Vector2(bx.position.x, bx.end.y)]
		for i in 4:
			var c: Vector2 = corners[i]
			if view.pack_at(c).x >= 0.0 and view.piece_under(c) == "" and view.plan_input().hint_at(c) == "":
				want.sort()
				return [want, c, corners[(i + 2) % 4]]
	return []


## A real left drag `from` -> `to` (Shift when asked), in eight steps.
func _drag(from: Vector2, to: Vector2, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = from
	e.pressed = true
	e.shift_pressed = shift
	view._gui_input(e)
	for i in range(1, 9):
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, float(i) / 8.0)
		m.relative = (to - from) / 8.0
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.shift_pressed = shift
		view._gui_input(m)
	var r := e.duplicate() as InputEventMouseButton
	r.pressed = false
	r.position = to
	view._gui_input(r)


## Owner 2026-10-11: with the blue row lit (its crayon: nothing in hand) a
## PLAIN drag from open table draws the chalk box and selects our pieces in
## it; the table does not pan.
func test_a_plain_drag_with_the_blue_row_lit_boxes_our_pieces() -> void:
	if not _lay_with(2):
		pending("no sheet holds two land pieces")
		return
	await wait_process_frames(2)
	var c := _box_corners()
	assert_false(c.is_empty(), "the box starts on open table")
	view.plan_input().pick_stick("blue")
	assert_eq([view.plan_input().tool.side, view.plan_input().tool.kind], ["blue", ""], "the crayon: ours lit, nothing in hand")
	var target := view.camera_rig().target
	_drag(c[1], c[2])
	var got: Array = view.plan_input().sel.duplicate()
	got.sort()
	assert_eq(got, c[0])
	assert_eq(view.plan_input().sel_side, "blue")
	assert_eq(view.camera_rig().target, target, "a box never pans")


## The red row lit: the same drag takes only the supposed pieces, never ours.
func test_a_plain_drag_with_the_red_row_lit_boxes_only_supposed_pieces() -> void:
	if not _lay_with(2):
		pending("no sheet holds two land pieces")
		return
	await wait_process_frames(2)
	var c := _box_corners()
	assert_false(c.is_empty())
	var mid := view.pack_at((c[1] as Vector2).lerp(c[2], 0.5))
	var id := WarPlans.place(repo, state, "cavalry", 2000, WarPlans.UNKNOWN, mid, 0)
	view.refresh_plans()
	await wait_process_frames(2)
	view.plan_input().pick_stick("red")
	_drag(c[1], c[2])
	assert_eq([view.plan_input().sel_side, view.plan_input().sel], ["red", [id]], "theirs only")


## No row lit (the hand, as the room opens): a plain drag on open table pans
## and selects nothing; the HAND slot puts the row out again.
func test_with_no_row_lit_a_plain_drag_pans() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var at := _open_spot([])
	assert_true(at.x >= 0.0)
	view.plan_input().pick_stick("blue")
	view.plan_input().pick_stick("hand")
	assert_eq(view.plan_input().tool.side, "", "the hand lights no row")
	var target := view.camera_rig().target
	_drag(at, at + Vector2(90, 40))
	assert_ne(view.camera_rig().target, target, "the drag panned the room")
	assert_true(view.plan_input().sel.is_empty())


## Space held: a plain drag pans whatever is in hand — a row lit, or a stick
## that would draw — and boxes or draws nothing.
func test_space_and_a_drag_pans_whatever_is_in_hand() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var at := _open_spot([])
	assert_true(at.x >= 0.0)
	Input.parse_input_event(_key(KEY_SPACE, true))
	await wait_process_frames(1)
	assert_true(WarRoomGestures.space_held())
	for pick: Array in [["blue", ""], ["red", "front"]]:
		view.plan_input().pick_stick(String(pick[0]))
		if String(pick[1]) != "":
			view.plan_input().pick_kind(String(pick[1]), String(pick[0]))
		var target := view.camera_rig().target
		_drag(at, at + Vector2(90, 40))
		assert_ne(view.camera_rig().target, target, "Space and a drag panned (%s)" % [pick])
		assert_true(view.plan_input().sel.is_empty(), "no box (%s)" % [pick])
		assert_true((state.war_plans[WarPlans.STROKES] as Dictionary).is_empty(), "no stroke (%s)" % [pick])
		at = _open_spot([])
	Input.parse_input_event(_key(KEY_SPACE, false))
	await wait_process_frames(1)


## A drag that starts on one of our pieces keeps its meaning with a row lit:
## it pans, and the selection stays as it was.
func test_a_drag_from_our_piece_with_a_row_lit_still_pans() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	view.plan_input().pick_stick("blue")
	var target := view.camera_rig().target
	_drag(p["press"], (p["press"] as Vector2) + Vector2(80, 0))
	assert_ne(view.camera_rig().target, target, "the drag panned the room")
	assert_true(view.plan_input().sel.is_empty(), "nothing boxed")


## Shift-click toggles one of our units in and out; a Shift-drag ADDS what it
## boxes to the selection (never toggling it out).
func test_shift_click_toggles_and_a_shift_box_adds() -> void:
	if not _lay_with(2):
		pending("no sheet holds two land pieces")
		return
	await wait_process_frames(2)
	var p := _first_land_piece()
	var code := String(p["code"])
	var click := func(shift: bool) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = p["press"]
		e.pressed = true
		e.shift_pressed = shift
		view._gui_input(e)
		var r := e.duplicate() as InputEventMouseButton
		r.pressed = false
		view._gui_input(r)
	click.call(false)
	assert_eq(view.plan_input().sel, [code])
	click.call(true)
	assert_true(view.plan_input().sel.is_empty(), "Shift-click took it out")
	click.call(true)
	assert_eq(view.plan_input().sel, [code], "Shift-click put it back")
	var c := _box_corners()
	assert_false(c.is_empty())
	_drag(c[1], c[2], true)
	var got: Array = view.plan_input().sel.duplicate()
	got.sort()
	assert_eq(got, c[0], "the Shift-box added the rest, kept the first")
	_drag(c[1], c[2], true)
	got = view.plan_input().sel.duplicate()
	got.sort()
	assert_eq(got, c[0], "a second Shift-box takes nothing out")


func test_the_blue_arrow_waits_for_a_selection_then_draws_its_march() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var input := view.plan_input()
	watch_signals(input)
	input.pick_kind("arrow", "blue")
	assert_signal_emitted(input, "refused")
	assert_false(input.tool.in_hand(), "no selection: the arrow cannot be taken")
	assert_ne(input.why_of("blue", "arrow"), "")
	var p := _first_land_piece()
	var at: Vector2 = p["press"]
	_press(at)
	_release(at)
	assert_eq(input.why_of("blue", "arrow"), "")
	input.pick_kind("arrow", "blue")
	assert_true(input.tool.in_hand())
	var from := at + Vector2(-40, 30)   # the arrow's start is free
	_press(from)
	for i in 10:
		_move(from + Vector2(12 * i, -6 * i))
	_release(from + Vector2(120, -60))
	assert_signal_emitted(input, "order_drawn")
	var args: Array = get_signal_parameters(input, "order_drawn")
	assert_eq(args[0], [String(p["code"])], "one unit a piece")
	assert_gt((args[1] as PackedVector2Array).size(), 2, "the stroke's own samples, for the fit")
	assert_eq(int(state.war_plans["rev"]), 0, "an order is no stroke on the paper")


func test_a_right_click_on_our_piece_opens_no_menu() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var at: Vector2 = _first_land_piece()["press"]
	watch_signals(view)
	for pressed: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.position = at
		view._gui_input(e)
	assert_signal_not_emitted(view, "ground_menu_requested")
	assert_signal_not_emitted(view, "plan_menu_requested")
	assert_false(view.has_signal("army_menu_requested"), "the room has no order menu of its own")


func test_a_pennant_stands_where_the_order_goes_and_its_click_asks_the_route() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var code := String(p["code"])
	var to: Vector2 = (p["at"] as Vector2) + Vector2(6.0, 0.0)
	var dest := ArmySystem.pack_to_metres(repo, to)
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_MARCH", "dest_x_m": dest.x, "dest_y_m": dest.y})
	view.refresh()
	var pennants: WarPennants = view.get_node("%Pennants")
	var node := pennants.pennant(code)
	assert_not_null(node)
	assert_string_starts_with((node.get_node("Slip") as Label3D).text, "courier riding · ")
	var art := node.get_node("Art") as Node3D
	assert_not_null(art, "the pennant is the room art's model, not a drawn pole and quad")
	var tall := 0.0
	for m: MeshInstance3D in Map3DUnits.meshes(art):
		tall = maxf(tall, ((m.transform * m.get_aabb()).end.y) * art.scale.y)
	assert_almost_eq(tall, repo.bal("war_piece_figure_mm") / 1000.0 * repo.bal("war_pennant_h_ratio"), 0.0005,
		"scaled to the pole height the war_* keys give")
	watch_signals(view)
	var hit: Dictionary = pennants.screen_hits(view.get_node("%Camera"), view.window_scale())[0]
	var at := (hit["rect"] as Rect2).get_center()
	_press(at)
	_release(at)
	assert_signal_emitted_with_parameters(view, "route_clicked", [code, at])
	var arrows: Array = view._pointer.orders()
	assert_eq(arrows.size(), 1, "the march is its blue crayon arrow from the piece to its pennant, never a dashed line")
	assert_eq(String(arrows[0]["kind"]), WarOrderArrows.SEALED)
	assert_false(((view.get_node("%PlanHud") as WarPlanHud).orders_ink()["crayon"] as Array).is_empty(), "drawn in crayon")
	CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	view.refresh()
	assert_string_starts_with((pennants.pennant(code).get_node("Slip") as Label3D).text, "countermand riding · ")
	state.couriers.clear()
	ArmySystem.set_march(repo, state, code, to)
	view.refresh()
	assert_eq((pennants.pennant(code).get_node("Slip") as Label3D).text, "order received")
	ArmySystem.set_garrison(repo, state, code)
	view.refresh()
	assert_null(pennants.pennant(code), "struck when the column stands down")


func test_the_hud_draws_rings_hints_a_marquee_and_the_live_layer_the_supply_road() -> void:
	var hud: WarHud = view.get_node("%Hud")
	var pal: Dictionary = repo.war_palette
	hud.draw_state([], Rect2(), [], pal["plan_red"], pal["chalk"])
	hud.set_supply([], pal["supply_route"])
	assert_false(hud.drawing())
	hud.draw_state([{"at": Vector2(40, 40), "r": 30.0, "colour": pal["plan_blue"]}], Rect2(), [], pal["plan_red"],
		pal["chalk"])
	assert_true(hud.drawing(), "a selection ring")
	hud.draw_state([], Rect2(), [Vector2(80, 80)], pal["plan_red"], pal["chalk"])
	assert_true(hud.drawing(), "an intel hint")
	hud.draw_state([], Rect2(), [], pal["plan_red"], pal["chalk"])
	hud.set_supply([{"at": Vector2(5, 5), "lit": true}], pal["supply_route"])
	assert_true(hud.drawing(), "a lit town")
	var live := view.get_node("%PlanHud") as WarPlanHud
	live.show_road([PackedVector2Array([Vector2(5, 5), Vector2(300, 40)])], pal["supply_route"], 6.0, 16.0)
	assert_true(live.drawing(), "the bold dashed road, under the march's crayon")


func test_a_sheet_roll_hides_the_pennants() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	view.swap_to((view.sheet_index() + 1) % WarSheets.series(repo).size())
	view._process(0.01)
	assert_false((view.get_node("%Pennants") as Node3D).visible, "pennants are put away while the sheet rolls")
	assert_eq(view._pointer.orders(), [], "and so are their arrows")
	view._process(repo.bal("war_sheet_swap_s"))
	assert_true((view.get_node("%Pennants") as Node3D).visible)


func test_the_tier_sets_the_rooms_msaa_from_the_table() -> void:
	var vp: SubViewport = view.get_node("%Viewport")
	var want := {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}
	for tier: String in ["low", "high"]:
		view.set_tier(tier)
		var msaa := int(Map3DQuality.num(Map3DQuality.row(repo, tier), "msaa", 0.0))
		assert_eq(vp.msaa_3d, want[msaa], tier)


func test_the_tin_shader_has_no_uniform_left_unbound() -> void:
	var code := (load("res://scenes/war_room/tin_miniature.gdshader") as Shader).code
	for line: String in code.split("\n"):
		if not line.begins_with("uniform float"):
			continue
		var uniform := line.split(" ")[2]
		assert_true(WarRoomMaterial.TIN_KEYS.has(uniform), "%s is bound from balance.csv" % uniform)


## The room art (Ruling 24): the oak table's top lies just under the sheet's
## sea (y 0) and the index chart lies on it, not floating over it.
func test_the_sheet_and_the_chart_lie_on_the_oak_table() -> void:
	view.lay_sheet(0)
	var oak := view.get_node("Viewport/Room/OakTable") as Node3D
	var top := -INF
	for m: MeshInstance3D in Map3DUnits.meshes(oak):
		var box := oak.transform * (m.transform * m.get_aabb())
		top = maxf(top, box.end.y)
	assert_between(top, -0.006, 0.0025, "the oak top (its iron clamps) meets the sheet's sea at y 0")
	var chart: MeshInstance3D = view.get_node("%IndexChart")
	# R10: the chart leans; its NEAR edge (the pivot) lies on the oak
	var near_y := (chart.global_transform * Vector3(0.0, -(chart.mesh as QuadMesh).size.y * 0.5, 0.0)).y
	assert_between(near_y, top - 0.004, top + 0.004, "the chart's near edge lies on the oak, not above it")
	var feet := INF
	for m: MeshInstance3D in Map3DUnits.meshes(oak):
		feet = minf(feet, (oak.transform * (m.transform * m.get_aabb())).position.y)
	var room := view.get_node("Viewport/Room/Chamber") as Node3D
	var floor_y := INF
	for m: MeshInstance3D in Map3DUnits.meshes(room):
		floor_y = minf(floor_y, (room.transform * (m.transform * m.get_aabb())).position.y)
	assert_almost_eq(feet, floor_y, 0.002, "and its feet still stand on the room's floor")


## R10 (owner-approved 2026-10-12): the chart leans on a reading stand by the key.
func test_chart_leans_by_the_key() -> void:
	view.lay_sheet(0)
	var chart := view.get_node("%IndexChart") as MeshInstance3D
	var tilt := repo.bal("war_chart_tilt_deg")
	assert_almost_eq(chart.rotation_degrees.x, -(90.0 - tilt), 0.01, "the basis pitch is the key's lean")
	# the face turns toward the camera (south, up): its normal leans from straight up by the tilt
	var n := WarRoomWall.chart_normal(chart)
	assert_almost_eq(rad_to_deg(n.angle_to(Vector3.UP)), tilt, 0.01)
	assert_gt(n.z, 0.0, "the face looks south")
	# R17 literals: w 0.86, margin 0.047, tilt 20, near edge z -0.572, the pack's 2560 x 929 map
	assert_almost_eq(tilt, 20.0, 0.0001)
	var h := (chart.mesh as QuadMesh).size.y
	assert_almost_eq(h, 0.40609, 0.0001, "the quad: 0.86 x 929/2560 + 2 x 0.047")
	var far := chart.global_transform * Vector3(0.0, h * 0.5, 0.0)
	var near := chart.global_transform * Vector3(0.0, -h * 0.5, 0.0)
	assert_almost_eq(far.y - near.y, 0.13889, 0.0001, "the far edge rises h x sin 20")
	assert_almost_eq(far.z, -0.95359, 0.0001, "and stands h x cos 20 further north")
	assert_almost_eq(near.z, -0.572, 0.0001, "the pivot is war_chart_z_m")


## The chart and its stand's footprint stay on the oak, north of the laid sheet's deepest
## edge and its arrows, and clear of the candlesticks.
func test_chart_stays_on_the_table() -> void:
	view.lay_sheet(0)
	var chart := view.get_node("%IndexChart") as MeshInstance3D
	var oak := view.get_node("Viewport/Room/OakTable") as Node3D
	var box := AABB()
	var first := true
	for m: MeshInstance3D in Map3DUnits.meshes(oak):
		var b := oak.transform * (m.transform * m.get_aabb())
		box = b if first else box.merge(b)
		first = false
	var h := (chart.mesh as QuadMesh).size.y
	var far := chart.global_transform * Vector3(0.0, h * 0.5, 0.0)
	var near := chart.global_transform * Vector3(0.0, -h * 0.5, 0.0)
	assert_gte(far.z, box.position.z + 0.05, "the far edge stays on the oak with room for the stand's prop")
	assert_lte(near.z, -repo.bal("war_table_max_depth_m") * 0.5 - repo.bal("war_arrow_gap_m") * 0.5, "north of the deepest laid sheet")
	var half_w := (chart.mesh as QuadMesh).size.x * 0.5
	for c in view.candles():
		var stick := c.get_parent() as Node3D
		assert_gt(absf(stick.position.x) - half_w, 0.1, "clear of %s" % stick.name)
	# the opening view keeps the whole chart, letters included, and the far corners clear of the top edge
	var cam: Camera3D = view.get_node("%Camera")
	var quad := (chart.mesh as QuadMesh).size
	for corner: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, -1)]:
		var at := cam.unproject_position(chart.global_transform * Vector3(corner.x * quad.x * 0.5, corner.y * quad.y * 0.5, 0.0)) / view.window_scale()
		assert_gte(at.y, 6.0, "the quad's corner %s is in the opening view" % corner)
		assert_lte(at.y, view.size.y, "and above the bottom")
	for l in chart.get_children():
		var at := cam.unproject_position((l as Node3D).global_position) / view.window_scale()
		assert_true(Rect2(Vector2.ZERO, view.size).has_point(at), "%s at %s" % [(l as Label3D).text, at])


## R17: column letters stand on the NEAR margin and row figures on the west one, clear of the map.
func test_the_chart_letters_stand_on_the_near_and_west_margins() -> void:
	view.lay_sheet(0)
	var chart := view.get_node("%IndexChart") as MeshInstance3D
	var size := WarRoomWall.map_size(chart)
	var quad := (chart.mesh as QuadMesh).size
	var seen := {"col": 0, "row": 0}
	for l in chart.get_children():
		var lab := l as Label3D
		var half := lab.font.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lab.font_size) * lab.pixel_size * 0.5
		seen[String(lab.get_meta("axis"))] += 1
		if lab.get_meta("axis") == "col":
			assert_lt(lab.position.y + half.y, -size.y * 0.5, "%s clear of the map on the near margin" % lab.text)
			# the line box carries a descender the capitals never use: the ink stays inside the quad
			var ink := lab.position.y - half.y + lab.font.get_descent(lab.font_size) * lab.pixel_size
			assert_gt(ink, -quad.y * 0.5, "%s inside the quad" % lab.text)
		else:
			assert_lt(lab.position.x + half.x, -size.x * 0.5, "%s clear of the map on the west margin" % lab.text)
			assert_gt(lab.position.x - half.x, -quad.x * 0.5, "%s inside the quad" % lab.text)
	assert_gt(int(seen["col"]), 0)
	assert_gt(int(seen["row"]), 0)


## A held marker lies on the leaning chart face, standing along its normal; a resting one on the oak.
func test_markers_follow_the_leaning_chart() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var chart := view.get_node("%IndexChart") as MeshInstance3D
	var m := view.marker_for(0)
	var local := chart.global_transform.affine_inverse() * m.global_position
	assert_almost_eq(local.z, 0.0, 0.0005, "on the chart's plane")
	assert_almost_eq((m.global_transform.basis.y.normalized()).dot(WarRoomWall.chart_normal(chart)), 1.0, 0.0001, "standing along its normal")
	var rest := WarRoomWall.tray_point(chart, 1, repo.bal("war_tray_gap_m"), repo.bal("war_tray_off_m"))
	assert_almost_eq(rest.y, repo.bal("war_chart_y_m"), 0.0001, "a resting marker stands on the oak")


## R17: the resting column is off the chart's east edge, so the camera's ray to each marker passes the
## leaning quad's east edge by 3 cm or more (not behind it).
func test_the_resting_markers_are_clear_of_the_leaning_chart() -> void:
	view.lay_sheet(0)
	var chart := view.get_node("%IndexChart") as MeshInstance3D
	var cam: Camera3D = view.get_node("%Camera")
	for slot in 4:
		var rest := WarRoomWall.tray_point(chart, slot, repo.bal("war_tray_gap_m"), repo.bal("war_tray_off_m"))
		var inv := chart.global_transform.affine_inverse()
		var lo := inv * cam.global_position
		var ld := (inv * rest - lo).normalized()
		var t := -lo.z / ld.z   # where the ray meets the chart's plane
		var hit := lo + ld * t
		var quad := (chart.mesh as QuadMesh).size
		assert_gte(hit.x - quad.x * 0.5, 0.03, "slot %d: the ray to the marker meets the chart's plane 3 cm outside its east edge" % slot)


## R17: a marker's base fits inside one chart cell (hand values at w 0.86: the pack's 10 degree cell is
## 0.02016 of the map's width on its short side, 0.017338 m; k = 0.8 x 0.017338 / 0.022 = 0.63047; base 13.87 mm).
func test_marker_fits_one_cell() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var chart := view.get_node("%IndexChart") as MeshInstance3D
	var cell := MapCoords.cell_rect(repo, Vector2i.ZERO, repo.bal("war_sheet_deg")).size
	var size := WarRoomWall.map_size(chart)
	var short_side := minf(cell.x / float(repo.map_info["width"]) * size.x, cell.y / float(repo.map_info["height"]) * size.y)
	assert_almost_eq(short_side, 0.017338, 0.00002, "one cell's short side, metres")
	var m := view.marker_for(0)
	var k := m.global_transform.basis.x.length()
	assert_almost_eq(k, 0.63047, 0.0005, "the marker's scale")
	assert_almost_eq(k * 0.022 * 1000.0, 13.87, 0.02, "its base across, mm (radius 0.011 x 2 x k)")
	assert_lt(k * 0.022, short_side, "and the base lies inside the cell")


## One KEY candle rakes the relief; the rest are short warm accents (fix round 1).
func test_one_key_candle_and_short_accents_from_the_balance_keys() -> void:
	var lights := view.candles()
	assert_between(lights.size(), 1, 4, "a light at each candlestick left (owner 2026-10-12: only the top-left one stays)")
	if lights.size() > 1:
		pending("Phase E9 (delete Candlestick2-4 in war_room.tscn) leaves exactly one candle")
	else:
		assert_eq(lights.size(), 1)
	var key := lights[WarRoomLights.key_index(repo, lights.size())]
	assert_almost_eq(key.light_energy, repo.bal("war_candle_key_energy"), 0.0001)
	assert_almost_eq(key.omni_range, repo.bal("war_candle_key_range_m"), 0.0001)
	assert_almost_eq(key.global_position.y, repo.bal("war_candle_key_y_m"), 0.001, "over the table")
	var stick := key.get_parent() as Node3D
	assert_gt(Vector2(key.global_position.x, key.global_position.z).length(),
		Vector2(stick.position.x, stick.position.z).length(), "out beyond its corner: a raking light")
	for l: OmniLight3D in lights:
		assert_eq(l.light_color, repo.war_palette["candle"])
		if l != key:
			assert_almost_eq(l.light_energy, repo.bal("war_candle_accent_energy"), 0.0001)
			assert_almost_eq(l.omni_range, repo.bal("war_candle_accent_range_m"), 0.0001)
			assert_lt(l.light_energy, key.light_energy, "an accent is no fill")


func test_the_tier_says_how_many_candles_cast_a_shadow_key_first() -> void:
	var lights := view.candles()
	var key := lights[WarRoomLights.key_index(repo, lights.size())]
	for tier: String in ["low", "medium", "high", "ultra"]:
		view.set_tier(tier)
		var row := Map3DQuality.row(repo, tier)
		var want := int(Map3DQuality.num(row, "war_candle_shadows", -1.0))
		assert_gte(want, 0, "%s has the column" % tier)
		want = mini(want, lights.size())
		var n := 0
		for l: OmniLight3D in lights:
			n += 1 if l.shadow_enabled else 0
		assert_eq(n, want, tier)
		assert_eq(key.shadow_enabled, want > 0, "%s: the key candle casts the first shadow" % tier)
		var cube := Map3DQuality.num(row, "war_candle_shadow_cube", 0.0) >= 1.0
		assert_eq(key.omni_shadow_mode, OmniLight3D.SHADOW_CUBE if cube else OmniLight3D.SHADOW_DUAL_PARABOLOID, tier)




func test_a_pennant_with_no_model_still_plants_its_slip() -> void:
	var pennants: WarPennants = view.get_node("%Pennants")
	pennants.model = null
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	var p := _first_land_piece()
	var code := String(p["code"])
	ArmySystem.set_march(repo, state, code, (p["at"] as Vector2) + Vector2(6.0, 0.0))
	view.refresh()
	var node := pennants.pennant(code)
	assert_not_null(node, "planted without its art")
	assert_null(node.get_node_or_null("Art"))
	assert_not_null(node.get_node_or_null("Slip"))
	assert_eq(pennants.screen_hits(view.get_node("%Camera"), view.window_scale()).size(), 1, "and still picked")



func test_wasd_pans_but_not_while_a_text_box_has_focus() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var box := LineEdit.new()
	add_child_autofree(box)
	var before := view.camera_rig().target
	Input.parse_input_event(_key(KEY_A, true))
	await wait_process_frames(1)   # the input buffer is flushed on the frame
	assert_true(view.key_pan(0.1), "A pans the room")
	box.grab_focus()
	var moved := view.camera_rig().target
	assert_false(view.key_pan(0.1), "the talk box keeps its keys")
	await wait_process_frames(1)
	Input.parse_input_event(_key(KEY_A, false))
	await wait_process_frames(1)
	assert_ne(moved, before)
	assert_eq(view.camera_rig().target, moved, "nor does the room's own frame pan it")


func _key(code: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	return e


func test_the_easels_board_faces_the_table() -> void:
	var panel := (view.get_node("%BoardPanel") as Node3D).global_transform
	assert_gt(panel.basis.z.normalized().dot((Vector3.ZERO - panel.origin) * Vector3(1, 0, 1)), 0.0)


func test_entering_the_board_flies_the_camera_square_in_front_of_it_and_back() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var cam := view.get_node("%Camera") as Camera3D
	var before := cam.transform
	view.enter_board()
	assert_eq(view.board_mode(), "to_board")
	await wait_seconds(repo.bal("war_board_fly_s") + 0.2)
	assert_eq(view.board_mode(), "board")
	var panel := (view.get_node("%BoardPanel") as Node3D).global_transform
	assert_almost_eq((-cam.global_transform.basis.z).dot(-panel.basis.z.normalized()), 1.0, 0.001, "square to the panel")
	view.leave_board()
	await wait_seconds(repo.bal("war_board_fly_s") + 0.2)
	assert_eq(view.board_mode(), "table")
	assert_almost_eq(cam.transform.origin.distance_to(before.origin), 0.0, 0.001, "back where it left")


## Owner 2026-10-07: a march's arrow pinned on the table still hung over the
## board after the camera turned to it. The HUD's marks are the table's.
func test_the_huds_marks_are_put_away_while_the_board_holds_the_camera() -> void:
	var p: Dictionary = WarRoom.pieces(repo, state)[0]
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	var code := String(p["code"])
	view.aiming = true
	view.aim_code = code
	view.aim_dest = (WarSheets.series(repo)[int(p["sheet"])]["rect"] as Rect2).get_center()
	view.select(code)
	var hud := view.get_node("%Hud") as WarHud
	# a selected piece glows on the table itself (no HUD ring): a lit town is the HUD's mark here
	hud.set_supply([{"at": Vector2(5, 5), "lit": true}], repo.war_palette["supply_route"])
	assert_true(hud.drawing(), "the HUD's marks are drawn over the table")
	assert_true(hud.is_visible_in_tree())
	view.enter_board()
	assert_false(hud.is_visible_in_tree(), "flying to the board, the marks go")
	await wait_seconds(repo.bal("war_board_fly_s") + 0.2)
	assert_false(hud.is_visible_in_tree(), "and stay away while the board is studied")
	view.leave_board()
	await wait_process_frames(2)
	assert_false(hud.is_visible_in_tree(), "not back until the camera is")
	await wait_seconds(repo.bal("war_board_fly_s") + 0.2)
	assert_true(hud.is_visible_in_tree(), "back over the table, the marks return")


func test_in_board_view_a_left_click_on_the_panel_is_the_boards_not_the_rooms() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	view.enter_board()
	await wait_seconds(repo.bal("war_board_fly_s") + 0.2)
	watch_signals(view)
	var at := view.size * 0.5   # the panel's centre is under the view's centre
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		view._gui_input(e)
	assert_signal_emitted(view, "board_clicked")
	assert_signal_not_emitted(view, "piece_selected")
	assert_signal_not_emitted(view, "selection_cleared")


func _board_click(at: Vector2, jitter: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	view._gui_input(press)
	if jitter != Vector2.ZERO:
		var m := InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.position = at + jitter
		m.relative = jitter
		view._gui_input(m)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.position = at + jitter
	view._gui_input(release)


func test_a_board_click_with_a_little_jitter_is_still_a_click() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	view.enter_board()
	await wait_seconds(repo.bal("war_board_fly_s") + 0.2)
	watch_signals(view)
	_board_click(view.size * 0.5, Vector2(1, 0))
	assert_signal_emit_count(view, "board_clicked", 2, "the press and the release both reach the board")
	var release: Array = get_signal_parameters(view, "board_clicked", 1)
	assert_gte((release[0] as Vector2).x, 0.0, "released on the board")


func test_a_board_drag_still_releases_the_button_but_off_the_board() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	view.enter_board()
	await wait_seconds(repo.bal("war_board_fly_s") + 0.2)
	watch_signals(view)
	_board_click(view.size * 0.5, Vector2(60, 0))
	assert_signal_emit_count(view, "board_clicked", 2, "the button is never left held in the board")
	var release: Array = get_signal_parameters(view, "board_clicked", 1)
	assert_lt((release[0] as Vector2).x, 0.0, "a pan's release lands off the board, so no note fires")


func test_the_table_knows_its_neat_line() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var mat := (view.get_node("%Table") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	var s: Dictionary = WarSheets.series(repo)[0]
	var r: Rect2 = s["rect"]
	var c: Rect2 = s["cell"]
	var want := Vector4((c.position.x - r.position.x) / r.size.x, (c.position.y - r.position.y) / r.size.y,
		(c.end.x - r.position.x) / r.size.x, (c.end.y - r.position.y) / r.size.y)
	var got: Vector4 = mat.get_shader_parameter("neat_uv")
	assert_almost_eq(got.x, want.x, 0.0001)
	assert_almost_eq(got.w, want.w, 0.0001)
	assert_almost_eq(float(mat.get_shader_parameter("collar_ink")), repo.bal("war_collar_ink"), 0.0001)


func test_a_chart_pick_tosses_then_lays_and_a_second_pick_mid_toss_is_ignored() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	var other := 1 if WarSheets.series(repo).size() > 1 else 0
	view.toss_to(other)
	assert_true(view.tossing())
	view.toss_to(0)   # ignored while the marker flies
	assert_signal_not_emitted(view, "sheet_requested", "not laid before it lands")
	await wait_seconds(float(WarToss.plan(Vector3.ZERO, Vector3.ONE, 1, WarToss.rules(repo))["duration"]) + 0.3)
	assert_false(view.tossing())
	assert_signal_emit_count(view, "sheet_requested", 1)
	assert_signal_emitted_with_parameters(view, "sheet_requested", [other])
	var marker := view.marker_for(other)
	var chart := view.get_node("%IndexChart") as MeshInstance3D
	var local := chart.global_transform.affine_inverse() * marker.global_position
	var size := WarRoomWall.map_size(chart)
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
	assert_true(WarIndexChart.uv_of_cell(repo, WarSheets.series(repo)[other]).has_point(uv), "the marker stands on the chosen cell")


func test_a_lay_by_another_route_mid_toss_waits_for_the_toss() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	assert_gte(WarSheets.series(repo).size(), 3)
	view.sheet_requested.connect(view.swap_to)   # as the screen wires it
	var flight := float(WarToss.plan(Vector3.ZERO, Vector3.ONE, 1, WarToss.rules(repo))["duration"])
	view.toss_to(1)
	await wait_seconds(flight - 0.15)
	view.swap_to(2)   # an edge arrow or a margin row just before the marker lands
	await wait_seconds(0.3 + repo.bal("war_sheet_swap_s") * 2.0 + 0.3)
	assert_eq(view.sheet_index(), 1, "the tossed sheet is laid, not one clicked mid-flight")
	var chart := view.get_node("%IndexChart") as MeshInstance3D
	var marker := view.marker_for(1)
	var local := chart.global_transform.affine_inverse() * marker.global_position
	var size := WarRoomWall.map_size(chart)
	assert_true(WarIndexChart.uv_of_cell(repo, WarSheets.series(repo)[1]).has_point(
		Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)), "the marker stands on the laid sheet")


func test_a_new_lay_lets_go_of_the_last_sheets_intelligence() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var mat := (view.get_node("%Table") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	mat.set_shader_parameter("intel_tex", ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8)))
	view.lay_sheet(1)
	assert_null(mat.get_shader_parameter("intel_tex"), "no sheet wears another's supply roads")


func test_a_draft_plants_a_pale_pennant_with_a_draft_slip() -> void:
	var p: Dictionary = {}
	for q: Dictionary in WarRoom.pieces(repo, state):
		if not bool(q["naval"]):
			p = q
			break
	var code := String(p["code"])
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	var rect: Rect2 = WarSheets.series(repo)[int(p["sheet"])]["rect"]
	var to: Vector2 = (p["at"] as Vector2).move_toward(rect.get_center(), 10.0)
	WarDrafts.plant(repo, state, code, "march", to)
	view.refresh()
	await wait_process_frames(1)
	var pen := (view.get_node("%Pennants") as WarPennants).pennant(code + "_draft")
	assert_not_null(pen)
	assert_eq(String(pen.get_meta("code")), code)
	assert_eq((pen.get_node("Slip") as Label3D).text, "draft")
	for m: MeshInstance3D in Map3DUnits.meshes(pen):
		assert_almost_eq(m.transparency, 1.0 - repo.bal("war_draft_alpha"), 0.001)
	WarDrafts.strike(state, code)
	view.refresh()
	await wait_process_frames(1)
	assert_null((view.get_node("%Pennants") as WarPennants).pennant(code + "_draft"))


func test_a_draft_stays_a_blue_crayon_arrow_from_its_piece() -> void:
	var p: Dictionary = {}
	for q: Dictionary in WarRoom.pieces(repo, state):
		if not bool(q["naval"]):
			p = q
			break
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	var rect: Rect2 = WarSheets.series(repo)[int(p["sheet"])]["rect"]
	WarDrafts.plant(repo, state, String(p["code"]), "march", (p["at"] as Vector2).move_toward(rect.get_center(), 10.0))
	view.refresh()
	await wait_process_frames(2)
	var hud := view.get_node("%PlanHud") as WarPlanHud   # under the pending crayon
	var arrows: Array = view._pointer.orders()
	assert_eq(arrows.size(), 1, "one arrow")
	assert_eq(String(arrows[0]["kind"]), WarOrderArrows.DRAFT, "pencilled: the paler draft arrow")
	assert_eq(arrows[0]["members"], [String(p["code"])])
	var crayon: Array = hud.orders_ink()["crayon"]
	assert_false(crayon.is_empty(), "the arrow's crayon")
	for c: Dictionary in crayon:
		assert_eq(String(c["colour"]), "blue_draft")
	assert_true(hud.drawing())


func test_a_resized_view_redraws_its_lines_where_the_pennants_now_stand() -> void:
	var p: Dictionary = {}
	for q: Dictionary in WarRoom.pieces(repo, state):
		if not bool(q["naval"]):
			p = q
			break
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	var rect: Rect2 = WarSheets.series(repo)[int(p["sheet"])]["rect"]
	var to: Vector2 = (p["at"] as Vector2).move_toward(rect.get_center(), 10.0)
	WarDrafts.plant(repo, state, String(p["code"]), "march", to)
	view.refresh()
	await wait_process_frames(2)
	view.size = Vector2(1300, 600)   # the room widens over the column
	await wait_process_frames(2)
	var line: PackedVector2Array = view._pointer.orders()[0]["lines"][0]
	var end: Vector2 = line[line.size() - 1]
	assert_almost_eq(end.distance_to(view.screen_pos_of_px(to)), 0.0, 1.0, "the line follows the view's new projection")


func test_a_refused_draft_says_why_on_its_slip() -> void:
	var p: Dictionary = {}
	for q: Dictionary in WarRoom.pieces(repo, state):
		if not bool(q["naval"]):
			p = q
			break
	var code := String(p["code"])
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	var rect: Rect2 = WarSheets.series(repo)[int(p["sheet"])]["rect"]
	WarDrafts.plant(repo, state, code, "march", (p["at"] as Vector2).move_toward(rect.get_center(), 10.0))
	state.war_drafts[code]["refused"] = "The chancery cannot pay"
	view.refresh()
	await wait_process_frames(1)
	var slip := (view.get_node("%Pennants") as WarPennants).pennant(code + "_draft").get_node("Slip") as Label3D
	assert_string_contains(slip.text, "The chancery cannot pay")


func test_leaning_in_writes_the_near_look_into_the_table() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var mat := (view.get_node("%Table") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	view.lean_to(repo.bal("war_cam_max_m"))
	assert_eq(float(mat.get_shader_parameter("fine_alpha")), 0.0)
	assert_eq(float(mat.get_shader_parameter("contour_m")), repo.bal("war_contour_m"))
	view.lean_to(repo.bal("war_cam_min_m"))
	assert_eq(float(mat.get_shader_parameter("fine_alpha")), 1.0)
	assert_eq(float(mat.get_shader_parameter("contour_m")), WarNear.contour_m(repo, repo.bal("war_cam_min_m")))


func _hover(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	view._gui_input(e)


func test_resting_on_open_table_reads_the_ground_once() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	var r: Rect2 = WarSheets.series(repo)[0]["cell"]
	var at: Vector2 = view.screen_pos_of_px(r.get_center())
	if view.piece_under(at) != "":
		at += Vector2(40, 40)
	_hover(at)
	view._process(repo.bal("war_hover_delay_s") + 0.01)
	assert_signal_emit_count(view, "ground_hovered", 1)
	view._process(1.0)
	assert_signal_emit_count(view, "ground_hovered", 1, "once per rest")
	_hover(at + Vector2(repo.bal("war_hover_still_px") * 4.0, 0))
	assert_signal_emitted(view, "hover_cleared")


func test_no_reading_off_the_table() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	_hover(Vector2(2, 2))   # the room's corner, past the table at the opening view
	view._process(repo.bal("war_hover_delay_s") + 0.01)
	if view.pack_at(Vector2(2, 2)).x < 0.0:
		assert_signal_not_emitted(view, "ground_hovered")


func test_the_fine_prints_legibility_limit_is_bound_from_data() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var mat := (view.get_node("%Table") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	assert_eq(float(mat.get_shader_parameter("fine_texels_per_px")), repo.bal("war_fine_texels_per_px"))


func test_the_near_zoom_patch_comes_on_close_and_goes_far() -> void:
	view._inks.frame_done = get_tree().process_frame   # headless never posts a draw
	view.lay_sheet(0)
	await wait_process_frames(2)
	var mat := (view.get_node("%Table") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	view.lean_to(repo.bal("war_cam_min_m"))
	assert_eq(float(mat.get_shader_parameter("detail_on")), 1.0)
	var uv: Vector4 = mat.get_shader_parameter("detail_uv")
	assert_true(uv.x >= -0.001 and uv.y >= -0.001 and uv.z <= 1.001 and uv.w <= 1.001, "the patch lies on the sheet: %s" % uv)
	assert_lt(uv.z - uv.x, 0.5, "and is a small part of it")
	assert_gt((view.get_node("%DetailViewport") as SubViewport).size.x, 2)
	view.lean_to(repo.bal("war_cam_max_m"))
	assert_eq(float(mat.get_shader_parameter("detail_on")), 0.0)
	assert_eq((view.get_node("%DetailViewport") as SubViewport).size, Vector2i(2, 2), "leaning out gives the patch's target back")
	assert_null(mat.get_shader_parameter("detail_tex"), "and unbinds it")
	view.lean_to(repo.bal("war_cam_min_m"))
	await wait_process_frames(3)
	assert_eq((view.get_node("%DetailViewport") as SubViewport).render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"drawn once, then left alone")
	view.set_active(false)
	assert_eq((view.get_node("%DetailViewport") as SubViewport).size, Vector2i(2, 2), "given back when the room shuts")


func _open_ground() -> Vector2:
	var r: Rect2 = WarSheets.series(repo)[0]["cell"]
	var at: Vector2 = view.screen_pos_of_px(r.get_center())
	if view.piece_under(at) != "":
		at += Vector2(40, 40)
	return at


func test_a_pointer_that_leaves_the_view_reads_nothing() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	_hover(_open_ground())
	view.notification(Control.NOTIFICATION_MOUSE_EXIT)   # onto the folio, the margin, the bars
	view._process(repo.bal("war_hover_delay_s") + 0.01)
	assert_signal_not_emitted(view, "ground_hovered")


func test_a_camera_move_clears_the_slip_and_restarts_the_rest() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	_hover(_open_ground())
	view._process(repo.bal("war_hover_delay_s") + 0.01)
	assert_signal_emit_count(view, "ground_hovered", 1)
	view.lean_to(view.camera_rig().distance * 0.9)   # the wheel, a key pan, the north turn
	assert_signal_emitted(view, "hover_cleared")
	view._process(repo.bal("war_hover_delay_s") + 0.01)
	assert_signal_emit_count(view, "ground_hovered", 1, "no stale reading after the move")


func test_no_reading_while_an_order_is_being_aimed() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	view.aiming = true   # the confirm menu is up beside the tip
	_hover(_open_ground())
	view._process(repo.bal("war_hover_delay_s") + 0.01)
	assert_signal_not_emitted(view, "ground_hovered")
	view.aiming = false


func test_closing_at_a_near_lean_unbinds_the_patch_and_reopening_redraws_it() -> void:
	view._inks.frame_done = get_tree().process_frame
	view.lay_sheet(0)
	await wait_process_frames(2)
	var mat := (view.get_node("%Table") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	view.lean_to(repo.bal("war_cam_min_m"))
	assert_eq(float(mat.get_shader_parameter("detail_on")), 1.0)
	view.set_active(false)
	assert_eq(float(mat.get_shader_parameter("detail_on")), 0.0, "no patch sampled from a given-back target")
	assert_null(mat.get_shader_parameter("detail_tex"))
	view.set_active(true)
	assert_eq(float(mat.get_shader_parameter("detail_on")), 1.0, "drawn again on reopening at the same lean")
	assert_gt((view.get_node("%DetailViewport") as SubViewport).size.x, 2)


## Owner 2026-10-07: a pointer resting on a piece names the piece (its combat
## figures), never the ground under it.
func test_resting_on_a_piece_reads_the_piece_not_the_ground() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var at: Vector2 = view.screen_pos_of_px(p["at"])
	watch_signals(view)
	_hover(at)
	view._process(repo.bal("war_hover_delay_s") + 0.01)
	assert_signal_emitted_with_parameters(view, "piece_hovered", [view.piece_under(at), at])
	assert_signal_not_emitted(view, "ground_hovered")
	view._process(1.0)
	assert_signal_emit_count(view, "piece_hovered", 1, "once per rest")


## Owner 2026-10-07: the supply lines are gold ribbons on the table that end
## where the piece stands NOW, following it as it is pushed.
func test_a_flowing_supply_line_is_laid_and_follows_its_piece() -> void:
	var p := _first_land_piece_anywhere()
	var code := String(p["code"])
	state.supply_lines[code] = SupplyLines._new_record(TownStores.realm_towns(repo, state)[0], 1000, 1)
	state.supply_lines[code]["state"] = SupplyLines.FLOWING
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	if WarSupplyFlow.routes(repo, state, view.sheet_rect()).is_empty():
		pass_test("this fixture's line does not reach the sheet")
		return
	var before := view.supply_mesh()
	assert_not_null(before, "the line is laid")
	var piece := (view.get_node("%Pieces") as WarPieces).piece(code)
	if piece == null:
		return
	piece.position += Vector3(0.05, 0, 0)
	view.redraw_marks()   # as WarPieces asks every frame a piece is pushed
	assert_ne(view.supply_mesh(), before, "laid again to the piece's new place")


## Owner 2026-10-11: a FRONT line is drawn on its own dark dashed mesh, never
## the gold ribbon; flowing again, the dashes go.
func test_a_broken_supply_line_is_laid_dark_dashed() -> void:
	var p := _first_land_piece_anywhere()
	var code := String(p["code"])
	state.supply_lines[code] = SupplyLines._new_record(TownStores.realm_towns(repo, state)[0], 1000, 1)
	state.supply_lines[code]["state"] = SupplyLines.FRONT
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	if WarSupplyFlow.routes(repo, state, view.sheet_rect(), SupplyLines.FRONT).is_empty():
		pass_test("this fixture's line does not reach the sheet")
		return
	assert_null(view.supply_mesh(), "no gold ribbon for a broken line")
	assert_not_null(view.supply_broken_mesh(), "its dark dashes")
	assert_not_null(view.supply_broken_look(), "worn from war_supply_broken.tres")
	state.supply_lines[code]["state"] = SupplyLines.FLOWING
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	assert_null(view.supply_broken_mesh(), "flowing again: no dashes")


func _first_land_piece_anywhere() -> Dictionary:
	for p: Dictionary in WarRoom.pieces(repo, state):
		if not bool(p["naval"]):
			return p
	return {}


## Owner 2026-10-08 (spec 2026-10-08-war-room-draw-orders rulings 10, 19):
## drafts on one drawn path are ONE arrow; the arrow a march being edited
## draws is the pending one alone; sealed and marching, it stays an arrow
## whose tail leaves the piece where it is drawn.
func test_drafts_on_one_path_are_one_arrow_and_an_edited_one_is_the_pending_arrow() -> void:
	view.lay_sheet(int(_first_land_piece_anywhere()["sheet"]))
	await wait_process_frames(2)
	var two := _land_pieces().slice(0, 2)
	if two.size() < 2:
		pending("two land pieces on a sheet")
		return
	var rect := view.sheet_rect()
	var a := String(two[0]["code"])
	var b := String(two[1]["code"])
	var bend := ((two[0]["at"] as Vector2) + rect.get_center()) * 0.5
	var to := rect.get_center()
	WarDrafts.plant(repo, state, a, "march", to, [bend])
	WarDrafts.plant(repo, state, b, "march", to, [])
	view.refresh()
	await wait_process_frames(1)
	var arrows: Array = view._pointer.orders()
	assert_eq(arrows.size(), 1, "one arrow for the order's group")
	assert_eq(arrows[0]["members"], [a, b], "the lead (the bend) with its head, the other its feeder")
	view.aim_code = a
	view.aim_dest = to
	view.aiming = true   # Edit route…: a's march is the pending blue arrow
	view.redraw_marks()
	var left: Array = view._pointer.orders()
	assert_eq(left.size(), 1)
	assert_eq(left[0]["members"], [b], "a's draft is drawn by the pending arrow alone")
	view.aiming = false
	view.aim_code = ""


func test_a_marching_column_keeps_its_arrow_from_where_its_piece_is_drawn() -> void:
	var p := _first_land_piece_anywhere()
	view.lay_sheet(int(p["sheet"]))
	await wait_process_frames(2)
	var code := String(p["code"])
	var to: Vector2 = (p["at"] as Vector2).move_toward(view.sheet_rect().get_center(), 10.0)
	ArmySystem.set_march(repo, state, code, to)
	view.refresh()
	await wait_process_frames(1)
	var arrows: Array = view._pointer.orders()
	assert_eq(arrows.size(), 1)
	assert_eq(String(arrows[0]["kind"]), WarOrderArrows.SEALED, "order received: full strength")
	var line: PackedVector2Array = arrows[0]["lines"][0]
	var node := (view.get_node("%Pieces") as WarPieces).piece(code)
	var at := view.camera().unproject_position(node.global_position) / view.window_scale()
	assert_almost_eq(line[0].distance_to(at), 0.0, 0.5, "the tail leaves the piece where it is drawn")
	assert_almost_eq(line[line.size() - 1].distance_to(view.screen_pos_of_px(to)), 0.0, 1.0, "the head at the end")
	for c: Dictionary in (view.get_node("%PlanHud") as WarPlanHud).orders_ink()["crayon"]:
		assert_eq(String(c["colour"]), "blue")
