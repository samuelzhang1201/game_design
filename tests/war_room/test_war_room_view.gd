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
	assert_null((view.get_node("%Hud") as Control).get_script(), "the HUD has no script until Task 11")


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
	var at: Vector2 = (view.get_node("%Camera") as Camera3D).unproject_position(arrow.global_position) / view._window_scale()
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
			var at := cam.unproject_position(l.global_position) / view._window_scale()
			assert_true(inside.has_point(at), "numeral %s at %s is inside the view %s" % [l.text, at, inside])
			assert_eq(view._pick_sheet_target(at), k, "sheet %d laid: numeral %s picks its own sheet" % [laid, l.text])


func test_every_chart_corner_stands_in_the_opening_view() -> void:
	view.lay_sheet(0)
	await wait_frames(2)
	var cam: Camera3D = view.get_node("%Camera")
	var chart: MeshInstance3D = view.get_node("%IndexChart")
	var half := (chart.mesh as QuadMesh).size * 0.5
	for c: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(-half.x, half.y), Vector2(half.x, half.y)]:
		var at := cam.unproject_position(chart.global_transform * Vector3(c.x, c.y, 0.0)) / view._window_scale()
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
	var at: Vector2 = (view.get_node("%Camera") as Camera3D).unproject_position(arrow.global_position) / view._window_scale()
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
