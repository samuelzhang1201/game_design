extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
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


func test_the_chart_letters_its_columns_and_numbers_its_rows() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var g := MapCoords.grid_size(repo, repo.bal("war_sheet_deg"))
	var labels := view.get_node("%IndexChart").get_children()
	assert_eq(labels.size(), g.x + g.y)
	var cols := labels.filter(func(l: Node) -> bool: return String(l.get_meta("axis")) == "col")
	assert_eq(cols.size(), g.x)
	assert_eq((cols[0] as Label3D).text, "A")


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


func _first_land_piece() -> Dictionary:
	for p: Dictionary in WarRoom.on_sheet(repo, state, view.sheet_index()):
		if not bool(p["naval"]):
			return p
	return {}


func test_a_click_on_a_piece_selects_it_and_arms_nothing() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var at: Vector2 = view.screen_pos_of_px(p["at"])
	watch_signals(view)
	_press(at)
	_move(at + Vector2(2, 0))   # under war_rake_min_px
	_release(at + Vector2(2, 0))
	assert_signal_emitted_with_parameters(view, "piece_selected", [String(p["code"])])
	assert_signal_not_emitted(view, "rake_started")


func test_a_drag_from_a_piece_takes_up_the_rake_and_a_release_names_the_ground() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var at: Vector2 = view.screen_pos_of_px(p["at"])
	watch_signals(view)
	_press(at)
	_move(at + Vector2(60, 0))
	assert_signal_emitted_with_parameters(view, "rake_started", [String(p["code"])])
	view.aiming = true   # what ArmyOrderMenu.aim_for sets
	_release(at + Vector2(60, 0))
	assert_signal_emitted(view, "ground_clicked")
	var args: Array = get_signal_parameters(view, "ground_clicked")
	assert_almost_eq((args[1] as Vector2).x, at.x + 60.0, 0.001)


func test_a_refused_rake_lets_go_and_the_rest_of_the_drag_does_nothing() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var at: Vector2 = view.screen_pos_of_px(p["at"])
	watch_signals(view)
	_press(at)
	_move(at + Vector2(30, 0))
	view.cancel_rake()   # what the screen does when the clock runs
	_move(at + Vector2(60, 0))
	_release(at + Vector2(60, 0))
	assert_signal_emit_count(view, "rake_started", 1)
	assert_signal_not_emitted(view, "ground_clicked")
	assert_signal_not_emitted(view, "piece_selected")


func test_the_arrow_reads_the_distance_in_the_packs_measure_and_the_arrival_day() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var code := String(p["code"])
	var to: Vector2 = (p["at"] as Vector2) + Vector2(10.0, 0.0)
	# the rake measures from where the regiment IS (a garrison's piece stands
	# on its town's point, the regiment within the town's reach)
	var dist := view.position_of(code).distance_to(to) * float(repo.map_info.get("distance_scale", "1"))
	# ONE arrival day: the courier's ride, then the march (owner 2026-10-02)
	var days := CourierSystem.arrival_days(repo, state, code, to, view.position_of(code))
	var ride := CourierSystem.eta_days(repo, state, CourierSystem.ORDINARY, code) \
		if CourierSystem.carries_orders(ArmySystem.regiment(repo, code)) else 0
	# the march walked over its ground from the day the courier reaches it
	assert_eq(days, ride + ArmySystem.march_days_between(repo, state, code, view.position_of(code), to,
		state.absolute_day() + ride))
	assert_eq(view.rake_reading(code, to), "%s %s · ~%d day%s" % [WarRoom.group(int(round(dist))),
		String(repo.map_info.get("distance_unit", "km")), days, "" if days == 1 else "s"])


func test_a_regiment_that_cannot_move_reads_a_word_not_zero_days() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var code := String(p["code"])
	var reg := ArmySystem.regiment(repo, code)
	var kept: Dictionary = reg.duplicate()
	for arm: String in repo.army_speed:
		reg[arm] = "0"   # no one under arms: no pace at all
	assert_eq(ArmySystem.day_march_m(repo, state, code), 0, "premise: it cannot march")
	var text := view.rake_reading(code, (p["at"] as Vector2) + Vector2(10.0, 0.0))
	reg.merge(kept, true)   # the pack's row is shared: put it back
	assert_string_ends_with(text, "cannot march")


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
	assert_eq(view._rake._routes().size(), 1, "a dashed line from the piece to its pennant")
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


func test_a_sheet_roll_lets_go_of_the_rake() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var at: Vector2 = view.screen_pos_of_px(p["at"])
	_press(at)
	_move(at + Vector2(40, 0))
	assert_eq(view._rake.code, String(p["code"]))
	view.swap_to((view.sheet_index() + 1) % WarSheets.series(repo).size())
	assert_eq(view._rake.code, "")


func test_the_hud_draws_an_arrow_only_between_two_real_points() -> void:
	var hud: WarHud = view.get_node("%Hud")
	var pal: Dictionary = repo.war_palette
	hud.draw_state(Vector2(-1, -1), Vector2(-1, -1), "", Vector2(-1, -1), 30.0, pal["ink"], pal["arrow"], pal["chalk"], null)
	assert_false(hud.drawing())
	hud.draw_state(Vector2(10, 10), Vector2(90, 10), "80 km · ~2 days", Vector2(-1, -1), 30.0, pal["ink"], pal["arrow"], pal["chalk"], null)
	assert_true(hud.drawing())
	hud.draw_state(Vector2(10, 10), Vector2(10, 10), "", Vector2(-1, -1), 30.0, pal["ink"], pal["arrow"], pal["chalk"], null)
	assert_false(hud.drawing(), "no length, no arrow")


func test_a_rake_released_off_the_table_says_it_was_dropped() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var at: Vector2 = view.screen_pos_of_px(p["at"])
	watch_signals(view)
	_press(at)
	_move(at + Vector2(40, 0))
	view.aiming = true
	_release(Vector2(-50, -50))   # off the table
	assert_signal_emitted(view, "rake_dropped")
	assert_signal_not_emitted(view, "ground_clicked")
	assert_eq(view._rake.code, "")


func test_a_sheet_roll_drops_a_rake_in_hand_and_hides_the_pennants() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_process_frames(2)
	var p := _first_land_piece()
	var at: Vector2 = view.screen_pos_of_px(p["at"])
	_press(at)
	_move(at + Vector2(40, 0))
	watch_signals(view)
	view.swap_to((view.sheet_index() + 1) % WarSheets.series(repo).size())
	assert_signal_emitted(view, "rake_dropped")
	view._process(0.01)
	assert_false((view.get_node("%Pennants") as Node3D).visible, "pennants are put away while the sheet rolls")
	assert_eq(view._rake._routes(), [], "and so are their lines")
	view._process(repo.bal("war_sheet_swap_s"))
	assert_true((view.get_node("%Pennants") as Node3D).visible)


func test_no_rake_in_hand_means_nothing_is_dropped_by_a_roll() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	view.swap_to(1)
	assert_signal_not_emitted(view, "rake_dropped")


func test_the_hud_draws_a_pennants_line_and_its_min_length_is_data() -> void:
	var hud: WarHud = view.get_node("%Hud")
	var pal: Dictionary = repo.war_palette
	hud.draw_state(Vector2(-1, -1), Vector2(-1, -1), "", Vector2(-1, -1), 30.0, pal["ink"], pal["arrow"], pal["chalk"], null, false,
		[[Vector2(10, 10), Vector2(200, 10)]])
	assert_true(hud.drawing(), "a route alone is drawn")
	var short := repo.bal("war_hud_min_len_px") - 1.0
	hud.draw_state(Vector2(10, 10), Vector2(10 + short, 10), "", Vector2(-1, -1), 30.0, pal["ink"], pal["arrow"], pal["chalk"], null)
	assert_false(hud.drawing())


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
	assert_between(chart.position.y, top - 0.004, top + 0.004, "the chart lies on the oak, not above it")
	assert_almost_eq(chart.rotation_degrees.x, -90.0, 0.01, "flat")
	var feet := INF
	for m: MeshInstance3D in Map3DUnits.meshes(oak):
		feet = minf(feet, (oak.transform * (m.transform * m.get_aabb())).position.y)
	var room := view.get_node("Viewport/Room/Chamber") as Node3D
	var floor_y := INF
	for m: MeshInstance3D in Map3DUnits.meshes(room):
		floor_y = minf(floor_y, (room.transform * (m.transform * m.get_aabb())).position.y)
	assert_almost_eq(feet, floor_y, 0.002, "and its feet still stand on the room's floor")


## One KEY candle rakes the relief; the rest are short warm accents (fix round 1).
func test_one_key_candle_and_short_accents_from_the_balance_keys() -> void:
	var lights := view.candles()
	assert_eq(lights.size(), 4, "a light at each candlestick")
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
	var marker := view.get_node("%Marker") as Node3D
	var chart := view.get_node("%IndexChart") as MeshInstance3D
	var local := chart.global_transform.affine_inverse() * marker.global_position
	var size := (chart.mesh as QuadMesh).size
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
	var marker := view.get_node("%Marker") as Node3D
	var local := chart.global_transform.affine_inverse() * marker.global_position
	var size := (chart.mesh as QuadMesh).size
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


func test_a_draft_is_drawn_as_a_pencil_line_from_its_piece() -> void:
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
	var hud := view.get_node("%Hud") as WarHud
	assert_eq(hud.draft_lines().size(), 1)
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
	var hud := view.get_node("%Hud") as WarHud
	var end: Vector2 = hud.draft_lines()[0][1]
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
