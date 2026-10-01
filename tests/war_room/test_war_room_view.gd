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
	view._store_ink(0, 111, img)
	view._store_ink(0, 222, img.duplicate())
	view._store_ink(1, 333, img.duplicate())
	assert_eq(view._ink_cache.size(), 2, "sheets 0 and 1, not three keys")
	assert_eq(view._ink_cache[0]["key"], 222, "a new key replaces the old texture")
	view._store_ink(2, 1, Image.new())
	assert_false(view._ink_cache.has(2), "an empty readback (headless) stores nothing")


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
