extends GutTest
## Editor previews (spec 2026-09-20 §2): each layer node is @tool with a
## `preview` switch that loads the repo itself (no autoload), builds the
## layer as the game would, and adds its children WITHOUT an owner, so
## nothing generated is ever saved into the scene.

func test_a_preview_context_needs_no_game() -> void:
	var ctx := Map3DPreview.context("")
	assert_not_null(ctx.repo)
	assert_not_null(ctx.state(), "a blank state, not Game.state")
	assert_false(is_same(ctx.state(), Game.state))
	assert_eq(ctx.q(), Map3DQuality.row(ctx.repo, "high"))


func test_no_build_means_no_meta_and_a_placeholder() -> void:
	assert_eq(Map3DPreview.meta_for("user://no_such_build"), {})
	var mesh := Map3DPreview.placeholder(StandardMaterial3D.new())
	assert_not_null(mesh)


func test_the_borders_draw_from_a_blank_state() -> void:
	var ctx := Map3DPreview.context("")
	if ctx.meta.is_empty():
		ctx.meta = {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
			"pack_px": [2560, 929], "sea_y": 5.0}
	var code: String = ctx.repo.kingdoms.keys()[0]
	assert_gt(Map3DBorders.kingdom_lines(ctx.repo, ctx.state(), ctx.meta, code, ctx.line_step()).size(), 0)


func test_preview_children_have_no_owner() -> void:
	var ctx := Map3DPreview.context("")
	if ctx.meta.is_empty():
		ctx.meta = {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
			"pack_px": [2560, 929], "sea_y": 5.0}
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 450)
	add_child_autofree(vp)
	ctx.viewport = vp
	var lines := Map3DLayerLines.new()
	vp.add_child(lines)
	lines.preview_build(ctx)
	assert_gt(lines.get_child_count(), 0, "the kingdom border and the seams, previewed")
	for c: Node in lines.get_children():
		assert_null(c.owner, String(c.name) + " is never saved")
	var markers := Map3DLayerSettlements.new()
	vp.add_child(markers)
	markers.preview_build(ctx)
	for c: Node in markers.get_children():
		assert_null(c.owner)


func test_a_pack_with_no_build_gets_the_placeholder() -> void:
	var ctx := Map3DPreview.context("")
	ctx.meta = {}
	var sea := Map3DLayerSea.new()
	add_child_autofree(sea)
	sea.preview_build(ctx)
	assert_eq(sea.get_child_count(), 1, "one placeholder plane, no water")
	assert_null(sea.get_child(0).owner)
	assert_null(sea.mesh, "nothing generated is ever written onto the AUTHORED node")


func test_no_layer_script_reads_game() -> void:
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if f.begins_with("map3d_layer") or f == "map3d_camera_rig.gd" or f == "map3d_preview.gd":
			assert_false(FileAccess.get_file_as_string("res://scripts/map3d/" + f).contains("Game."), f)
