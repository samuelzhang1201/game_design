extends GutTest
## Map3DContext (spec 2026-09-20 §1): what every layer of the 3D map shares —
## the pack <-> world round trip, the ground under a point, the scales and the
## camera pose, with no Game autoload and no view.

const FIXTURE := "user://test_map3d_ctx_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_pack_and_world_round_trip() -> void:
	var c := Map3DContext.new(Game.data, WORLD)
	assert_eq(c.to_world(Vector2.ZERO), Vector2(-64000.0, -23220.0))
	var px := Vector2(1234.5, 456.25)
	var back := c.to_pack(c.to_world(px))
	assert_almost_eq(back.x, px.x, 0.001)
	assert_almost_eq(back.y, px.y, 0.001)


func test_without_terrain_the_ground_is_the_sea() -> void:
	assert_eq(Map3DContext.new(Game.data, WORLD).height_at(Vector2(100, 100)), 5.0)


func test_the_height_seam_replaces_the_terrain() -> void:
	var c := Map3DContext.new(Game.data, WORLD)
	c.height_fn = func(xz: Vector2) -> float: return xz.x * 0.5
	assert_eq(c.height_at(Vector2(10, 0)), 5.0)
	assert_eq(c.ground_of_pack(Vector2.ZERO), Vector3(-64000.0, -32000.0, -23220.0))


func test_the_scales_default_to_one() -> void:
	var c := Map3DContext.new(Game.data, WORLD)
	assert_eq(c.window_scale(), 1.0)
	assert_eq(c.render_scale(), 1.0)
	assert_eq(c.viewport_px_scale(), 1.0)


func test_the_steps_are_the_balance_values() -> void:
	var c := Map3DContext.new(Game.data, WORLD)
	assert_eq(c.line_step(), Game.data.bal("map3d_line_step_m"))
	assert_eq(c.road_step(), Game.data.bal("map3d_road_step_m"))
	assert_eq(c.river_step(), Game.data.bal("map3d_river_mesh_step_m"))


func test_the_view_hands_out_its_context() -> void:
	var v := _view()
	var c := v.context()
	assert_not_null(c)
	assert_eq(c.camera, v.camera())
	assert_eq(c.target, v.target())
	assert_eq(c.distance, v.distance())
	assert_eq(c.yaw, v.yaw())
	assert_eq(c.state(), Game.state)
	assert_eq(c.view_size, v.size)
	assert_eq(c.ground_at(v.size * 0.5), v.ground_at(v.size * 0.5))


func test_a_camera_move_is_announced() -> void:
	var v := _view()
	var c := v.context()
	watch_signals(c)
	v.look_at_home(5000.0)
	assert_signal_emitted(c, "camera_moved")
	assert_eq(c.distance, 5000.0)


func test_the_target_projects_to_the_middle_of_the_view() -> void:
	var v := _view()
	var c := v.context()
	var p: Variant = c.project(Vector3(c.target.x, c.height_at(c.target), c.target.y))
	assert_not_null(p)
	assert_almost_eq((p as Vector2).x, v.size.x * 0.5, 1.0)
	assert_almost_eq((p as Vector2).y, v.size.y * 0.5, 1.0)
	var hit: Variant = c.ground_at(p as Vector2)
	assert_almost_eq((hit as Vector3).x, c.target.x, 5.0)
	assert_almost_eq((hit as Vector3).z, c.target.y, 5.0)


func test_settlement_ground_is_read_at_load_not_per_pose() -> void:
	var v := _view()
	var c := v.context()
	var calls := [0]
	c.height_fn = func(_xz: Vector2) -> float:
		calls[0] += 1
		return 5.0
	v.look_at_home(8000.0)
	calls[0] = 0
	var list := c.projected_settlements()
	assert_gt(list.size(), 0)
	assert_eq(calls[0], 0, "no terrain lookup per settlement")
	assert_true(is_same(c.projected_settlements(), list), "the same pose hands back the same list")
	v.look_at_home(9000.0)
	assert_false(is_same(c.projected_settlements(), list), "a new pose cuts a new one")


func test_the_projected_list_matches_the_marked_burgs() -> void:
	var v := _view()
	var c := v.context()
	var codes: Array = []
	for e: Dictionary in c.projected_settlements():
		codes.append(String(e["code"]))
	assert_eq(codes, c.marked_burgs())
	var capital := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
	var e: Dictionary = c.projected_settlements()[codes.find(capital)]
	assert_true(bool(e["shown"]), "the capital is shown at the opening zoom")
	assert_almost_eq((e["screen"] as Vector2).x, v.size.x * 0.5, 1.0)


func test_cells_are_memoised() -> void:
	var v := _view()
	var c := v.context()
	var id: int = Game.data.manors.keys()[0]
	var calls := [0]
	c.height_fn = func(_xz: Vector2) -> float:
		calls[0] += 1
		return 5.0
	c.cell_ground(id)
	assert_eq(calls[0], 1, "the first ask looks the cell up")
	c.cell_ground(id)
	assert_eq(calls[0], 1, "one lookup per cell, ever")


func _some_burg(group: String) -> String:
	for code: String in Game.data.burgs:
		if String(Game.data.burgs[code].get("group", "")) == group:
			return code
	return ""


## A settlement's click reach is its footprint's projected radius (change 3,
## owner 2026-09-20): the capital's far bigger population reaches farther on
## screen than a village's, at the same distance.
func test_a_bigger_settlement_has_a_wider_pick_reach_at_the_same_distance() -> void:
	var v := _view()
	var c := v.context()
	var capital := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
	var village := _some_burg("village")
	assert_ne(village, "", "the pack has a village")
	var cap_r := c.pick_reach_px(capital, Game.data.map3d_settlements["capital"], 5000.0)
	var vil_r := c.pick_reach_px(village, Game.data.map3d_settlements["village"], 5000.0)
	assert_gt(cap_r, vil_r, "the capital's cluster reaches farther on screen")


## The reach never falls below map3d_pick_px, however small the footprint's
## screen size becomes — the floor that keeps a settlement clickable even
## where its dot is not drawn (change 3's whole point).
func test_pick_reach_never_falls_below_the_pick_floor() -> void:
	var v := _view()
	var c := v.context()
	var village := _some_burg("village")
	assert_ne(village, "", "the pack has a village")
	var r := c.pick_reach_px(village, Game.data.map3d_settlements["village"], 5000000.0)
	assert_almost_eq(r, Game.data.bal("map3d_pick_px"), 0.01,
		"far enough that the footprint's screen size shrinks under the floor")


## settlement_rects() sizes on the DRAWN dot (Map3DLayerSettlements.drawn_px),
## pick_reach_px on the ground footprint — fix round 1, owner 2026-09-20:
## both used to be fed by one function, `marker_px`, and conflating them
## crowded landmark marks out of a huge area where nothing was even drawn.
## Below the dot's near threshold (Map3DGeometry.settlement_dot_min_view_m, a
## SHARE of the reachable range since 2026-09-21) the dot is hidden, so the
## capital contributes NO keep-clear rect there, even though pick_reach_px —
## independent of the dot — is still a real, large number at that same
## distance. Above the cutoff, once the dot is drawn again, it keeps its own
## screen space clear. Fix round 1 review point 4: also pins that the
## capital's own ring MATERIAL carries this exact number — settlement_rects()
## and the shader now both call Map3DGeometry.settlement_dot_min_view_m
## directly rather than one depending on the other, so a rect and the dot it
## is reserving space for can never disagree about where the cutoff sits.
func test_settlement_rects_sizes_on_the_drawn_dot_not_the_footprint() -> void:
	var v := _view()
	var c := v.context()
	var capital := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
	var min_m := Map3DGeometry.settlement_dot_min_view_m(Game.data, c.meta, c.view_size.y)
	var mmi := v.viewport().get_node("Markers/Capital") as MultiMeshInstance3D
	var mat := mmi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter("min_view_m")), min_m, 0.001,
		"the capital's ring material must carry the same threshold settlement_rects() uses")
	var burg: Dictionary = Game.data.burgs[capital]
	var pack_pos := Vector2(float(burg["x"]), float(burg["y"]))
	v.look_at_pack(pack_pos, min_m * 0.5)
	var reach := c.pick_reach_px(capital, Game.data.map3d_settlements["capital"], min_m * 0.5)
	assert_gt(reach, 0.0,
		"the ground footprint reach is real this close, independent of whether a dot is drawn")
	var p := v.size * 0.5  # look_at_pack centres the target on screen
	for r: Rect2 in c.settlement_rects():
		assert_false(r.has_point(p),
			"the dot is hidden below its near threshold: nothing here to keep clear of")
	v.look_at_pack(pack_pos, min_m * 1.5)
	var found := false
	for r: Rect2 in c.settlement_rects():
		if r.has_point(v.size * 0.5):
			found = true
	assert_true(found, "once the dot shows again, it keeps its own screen space clear")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
