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
