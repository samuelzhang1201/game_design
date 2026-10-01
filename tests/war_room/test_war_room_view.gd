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
	assert_almost_eq(aabb.size.z, WarTable.depth_m(r, repo.bal("war_table_w_m")), 0.001)


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


func test_a_freed_view_mid_lay_makes_no_error() -> void:
	var v: WarRoomView = load("res://scenes/war_room/war_room.tscn").instantiate()
	v.size = Vector2(800, 500)
	add_child(v)
	v.bind(repo, func() -> GameState: return state, func() -> bool: return true)
	v.set_active(true)
	v.lay_sheet(0)
	v.queue_free()
	await wait_frames(3)
	assert_true(true, "no error raised after the view left the tree mid-await")


func test_a_sheet_out_of_range_is_ignored() -> void:
	view.lay_sheet(999)
	await wait_frames(1)
	assert_eq(view.sheet_index(), -1)
