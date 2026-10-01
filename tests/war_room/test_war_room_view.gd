extends GutTest
## The room's view laid with a sheet: the table, the ink, the picks (spec §1–2).

var repo: DataRepository
var state: GameState
var view: WarRoomView


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	state = GameState.new_campaign(repo, 42)
	WarSheets.forget()
	view = load("res://scenes/war_room/war_room.tscn").instantiate()
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)  # a sized view, not one stretched to its parent
	view.size = Vector2(1000, 600)
	add_child_autofree(view)
	view.bind(repo, func() -> GameState: return state, func() -> bool: return true)
	view.set_active(true)


func test_laying_a_sheet_builds_the_table_at_the_sheets_ratio() -> void:
	view.lay_sheet(0)
	await wait_frames(2)
	assert_eq(view.sheet_index(), 0)
	var table: MeshInstance3D = view.get_node("%Table")
	var aabb := table.mesh.get_aabb()
	var r: Rect2 = WarSheets.series(repo)[0]["rect"]
	assert_almost_eq(aabb.size.x, repo.bal("war_table_w_m"), 0.001)
	assert_almost_eq(aabb.size.z, WarRoomTable.depth_m(r, repo.bal("war_table_w_m")), 0.001)


func test_a_point_on_the_sheet_projects_into_the_view() -> void:
	view.lay_sheet(0)
	await wait_frames(2)
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
	await wait_frames(3)
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


func test_the_ink_viewport_is_smallest_at_rest_and_after_a_paint() -> void:
	var ink: SubViewport = view.get_node("%InkViewport")
	assert_eq(ink.size, WarRoomInk.REST, "nothing is allocated before a sheet is laid")
	view._inks.frame_done = get_tree().process_frame   # headless never posts a draw
	view.lay_sheet(0)
	await wait_seconds(1.0)
	assert_eq(ink.size, WarRoomInk.REST, "the render target is given back after the paint")


func test_the_ink_texture_is_sized_to_the_sheet_not_square() -> void:
	var r: Rect2 = WarSheets.series(repo)[0]["rect"]
	var s := WarRoomInk.tex_size(repo, r)
	assert_eq(s.x, int(repo.bal("war_sheet_texture_px")))
	assert_almost_eq(float(s.y) / float(s.x), r.size.y / r.size.x, 1.0 / float(s.x) + 0.0001)
	assert_almost_eq(WarRoomInk.used_share(repo, r), 1.0, 0.001, "the sheet fills its texture's height")


func test_a_sheet_out_of_range_is_ignored() -> void:
	view.lay_sheet(999)
	await wait_frames(1)
	assert_eq(view.sheet_index(), -1)


func test_pack_at_inverts_screen_pos_of_px_on_land() -> void:
	view.lay_sheet(0)
	await wait_frames(2)
	var r: Rect2 = WarSheets.series(repo)[0]["rect"]
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
	await wait_frames(2)
	var near := WarSheets.neighbours(repo, 0)
	var arrows: Array = view.get_node("%EdgeArrows").get_children()
	assert_eq(arrows.size(), near.size())
	var want: Array = near.values()
	for a: Node in arrows:
		assert_true(int(a.get_meta("sheet")) in want)
		assert_true((a as Label3D).text.ends_with(String(WarSheets.series(repo)[int(a.get_meta("sheet"))]["numeral"])))


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		view._gui_input(e)


func test_a_click_on_an_edge_arrow_requests_its_sheet() -> void:
	view.lay_sheet(0)
	await wait_frames(2)
	watch_signals(view)
	var arrow := view.get_node("%EdgeArrows").get_child(0) as Label3D
	var at: Vector2 = (view.get_node("%Camera") as Camera3D).unproject_position(arrow.global_position) / view.window_scale()
	_click(at)
	assert_signal_emitted_with_parameters(view, "sheet_requested", [int(arrow.get_meta("sheet"))])


func test_every_numeral_on_the_wall_chart_is_in_the_opening_view_and_picks_its_sheet() -> void:
	var cam: Camera3D = view.get_node("%Camera")
	var inside := Rect2(Vector2.ZERO, view.size)
	for laid in WarSheets.series(repo).size():   # whichever sheet is laid, its arrows must not shadow the chart
		view.lay_sheet(laid)
		await wait_frames(2)
		var numerals := view.get_node("%IndexChart").get_children()
		assert_eq(numerals.size(), WarSheets.series(repo).size(), "a numeral a sheet")
		for k in numerals.size():
			var l := numerals[k] as Label3D
			assert_false(cam.is_position_behind(l.global_position), "%s is in front of the camera" % l.text)
			var at := cam.unproject_position(l.global_position) / view.window_scale()
			assert_true(inside.has_point(at), "numeral %s at %s is inside the view %s" % [l.text, at, inside])
			assert_eq(WarRoomPicks.sheet_target(view.get_node("%EdgeArrows"), view.get_node("%IndexChart"), cam, repo, at, view.window_scale()), k, "sheet %d laid: numeral %s picks its own sheet" % [laid, l.text])


func test_every_chart_corner_stands_in_the_opening_view() -> void:
	view.lay_sheet(0)
	await wait_frames(2)
	var cam: Camera3D = view.get_node("%Camera")
	var chart: MeshInstance3D = view.get_node("%IndexChart")
	var half := (chart.mesh as QuadMesh).size * 0.5
	for c: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
		var at := cam.unproject_position(chart.global_transform * Vector3(c.x, c.y, 0.0)) / view.window_scale()
		assert_true(Rect2(Vector2.ZERO, view.size).has_point(at), "corner %s at %s" % [c, at])


func test_a_ray_that_misses_the_chart_picks_nothing() -> void:
	view.lay_sheet(0)
	await wait_frames(2)
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
	await wait_frames(2)
	view.swap_to(1)
	view._process(0.01)
	view.swap_to(2)
	view._process(repo.bal("war_sheet_swap_s"))
	assert_eq(view.sheet_index(), 1, "the roll in progress was not redirected")


func test_a_drag_is_not_a_click_on_the_chart() -> void:
	view.lay_sheet(0)
	await wait_frames(2)
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
	await wait_frames(2)
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
	await wait_frames(2)
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
	await wait_frames(2)
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
	await wait_frames(2)
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
	await wait_frames(2)
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


func test_the_arrow_reads_the_distance_in_the_packs_measure_and_the_days() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_frames(2)
	var p := _first_land_piece()
	var code := String(p["code"])
	var to: Vector2 = (p["at"] as Vector2) + Vector2(10.0, 0.0)
	var dist := 10.0 * float(repo.map_info.get("distance_scale", "1"))
	var days := ArmySystem.march_days(repo, state, code, 10.0 * float(ArmySystem.metres_per_pack_px(repo)))
	assert_eq(view.rake_reading(code, to), "%s %s · ~%d day%s" % [WarRoom.group(int(round(dist))),
		String(repo.map_info.get("distance_unit", "km")), days, "" if days == 1 else "s"])


func test_a_regiment_that_cannot_move_reads_a_word_not_zero_days() -> void:
	view.lay_sheet(int(WarRoom.pieces(repo, state)[0]["sheet"]))
	await wait_frames(2)
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
	await wait_frames(2)
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
	await wait_frames(2)
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
	await wait_frames(2)
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
	await wait_frames(2)
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
	await wait_frames(2)
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
	var near: Vector3 = oak.transform * Vector3(0.0, -0.8, 0.0)
	assert_almost_eq(near.y, -0.8, 0.002, "and its feet still stand on the floor")

