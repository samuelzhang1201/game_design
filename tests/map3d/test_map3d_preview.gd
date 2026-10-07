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
	assert_eq(Map3DPreview.meta_for("user://no_such_build/world.tscn"), {})
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


## Task 22 review: Viewport.get_texture() carries an EMPTY viewport_path, so a
## scene saved with it on the Display opens UNBOUND. The editor keeps the
## authored texture, a preview swaps the live one in, and whatever a save
## finds there must carry the path again.
func test_a_saved_display_keeps_its_viewport_path() -> void:
	assert_true(FileAccess.get_file_as_string(Map3DView.VIEW_SCENE).contains(
		'viewport_path = NodePath("Viewport")'), "the authored scene binds the Display")
	var v := (load(Map3DView.VIEW_SCENE) as PackedScene).instantiate() as Map3DView
	add_child_autofree(v)
	var vp := v.get_node("Viewport") as SubViewport
	var display := v.get_node("Display") as TextureRect
	assert_true((vp.get_texture() as ViewportTexture).get_viewport_path_in_scene().is_empty(),
		"the live texture has no path: it is why this test exists")
	Map3DPreview.show_live(display, vp, true)
	assert_eq(display.texture, vp.get_texture(), "a preview shows the live render")
	Map3DPreview.show_live(display, vp, false)
	assert_eq((display.texture as ViewportTexture).get_viewport_path_in_scene(),
		NodePath("Viewport"), "and gives the authored one back")
	var packed := PackedScene.new()
	assert_eq(packed.pack(v), OK)
	var st := packed.get_state()
	for i in st.get_node_count():
		if st.get_node_name(i) != &"Display":
			continue
		for j in st.get_node_property_count(i):
			if st.get_node_property_name(i, j) != &"texture":
				continue
			var tex: ViewportTexture = st.get_node_property_value(i, j)
			assert_false(tex.get_viewport_path_in_scene().is_empty(),
				"a save never writes an unbound Display texture")


## Task 22 review: a save can never write preview state, whatever the editor
## was left in — the view puts everything back on NOTIFICATION_EDITOR_PRE_SAVE.
func test_an_editor_save_puts_every_preview_back() -> void:
	var v := (load(Map3DView.VIEW_SCENE) as PackedScene).instantiate() as Map3DView
	add_child_autofree(v)
	var vp := v.get_node("Viewport") as SubViewport
	var display := v.get_node("Display") as TextureRect
	var world := vp.get_node("World") as Map3DWorld
	var lines := world.get_node("Lines") as Map3DLayerLines
	var rig := world.get_node("CameraRig") as Map3DCameraRig
	world.preview_pack = "some_other_pack"
	world.preview_terrain = false
	lines.preview = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Map3DPreview.show_live(display, vp, true)
	(rig.get_node("RigCamera") as Camera3D).current = true
	v.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	assert_false(lines.preview, "every layer's switch is off")
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_false((display.texture as ViewportTexture).get_viewport_path_in_scene().is_empty())
	assert_false((rig.get_node("RigCamera") as Camera3D).current,
		"the authored camera's `current` is the scene's own: false")
	# final review 2026-09-20: the root's own two are EXPORTED, so a save while
	# previewing another pack would pin every checkout to it.
	assert_eq(world.preview_pack, "", "the world's preview pack is never saved")
	assert_true(world.preview_terrain, "and its terrain switch goes back to the scene's own")


## Ruling (spec 2026-09-20 §1): Map3DContext is what every piece shares, and no
## script under the view reaches for the Game autoload — that is what lets the
## same layer draw in the editor, where Game does not exist. Map3DView itself is
## the ONE exception: it is the screen's node and hands the context down.
## Widened from the layer scripts alone in the final review of 2026-09-20.
func test_no_script_under_the_view_reads_game() -> void:
	var checked := 0
	for f: String in DirAccess.get_files_at("res://scripts/map3d"):
		if not f.ends_with(".gd") or f == "map3d_view.gd":
			continue
		checked += 1
		assert_false(FileAccess.get_file_as_string("res://scripts/map3d/" + f).contains("Game."),
			f + " must take what it needs from Map3DContext, never from the Game autoload")
	assert_gt(checked, 30, "every script under the view was scanned")


## The world is its OWN scene (owner 2026-10-02: 优先处理3d地图的场景), so the
## editor's 3D view opens it: every 3D node of the map under one Map3DWorld,
## instanced into the view's SubViewport, and nothing under it saved by a
## preview.
func test_the_world_is_its_own_scene_inside_the_view() -> void:
	var v := (load(Map3DView.VIEW_SCENE) as PackedScene).instantiate() as Map3DView
	add_child_autofree(v)
	var world := v.get_node_or_null("Viewport/World") as Map3DWorld
	assert_not_null(world, "the view instances the world")
	assert_eq(world.scene_file_path, "res://scenes/map3d/map3d_world.tscn")
	for n in ["WorldSlot", "CameraRig", "Sea", "Rivers", "Bridges", "Lines", "Clouds", "Markers",
			"Houses", "Trees", "Wind", "Environment", "Sun", "FillLight", "Units", "Dust",
			"Couriers", "Precip"]:
		assert_not_null(world.get_node_or_null(n), n + " is the world's")
	assert_eq((v.get_node("Viewport") as SubViewport).get_child_count(), 1, "the world is the viewport's one child")


## Opened on its own, a world's previews go back before a save like the view's.
func test_a_world_on_its_own_puts_every_preview_back() -> void:
	var world := (load("res://scenes/map3d/map3d_world.tscn") as PackedScene).instantiate() as Map3DWorld
	add_child_autofree(world)
	var lines := world.get_node("Lines") as Map3DLayerLines
	world.preview_pack = "some_other_pack"
	lines.preview = true
	world.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	assert_false(lines.preview)
	assert_eq(world.preview_pack, "")
	for c: Node in lines.get_children():
		assert_not_null(c.owner, "nothing a preview built is left to save")
