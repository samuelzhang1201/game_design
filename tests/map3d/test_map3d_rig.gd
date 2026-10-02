extends GutTest
## Map3DCameraRig and Map3DInput (spec 2026-09-20 §1): the pose lives in the
## context and the rig moves it; the input says which events the view takes.

const RunDir := preload("res://tests/run_dir.gd")
var _fixture := RunDir.dir("map3d_rig").path_join("test_map3d_rig_world.tscn")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
	root.free()


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _fixture)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_camera_hangs_from_the_rig() -> void:
	var v := _view()
	var rig := v.world().get_node("CameraRig") as Map3DCameraRig
	assert_not_null(rig)
	assert_eq(rig.camera(), v.camera())
	assert_eq(String(v.camera().name), "RigCamera")
	assert_true(v.camera().current)
	assert_almost_eq(v.camera().fov, Game.data.bal("map3d_fov_deg"), 0.001)


func test_the_rig_pans_zooms_and_turns_through_the_context() -> void:
	var v := _view()
	var rig := v.component("rig") as Map3DCameraRig
	var c := v.context()
	watch_signals(c)
	var t0 := c.target
	rig.pan_by(Vector2(40, 0))
	assert_lt(c.target.x, t0.x, "the ground follows the mouse, the target goes the other way")
	assert_signal_emitted(c, "camera_moved")
	rig.zoom_at(v.size * 0.5, 5000.0)
	assert_almost_eq(c.distance, 5000.0, 0.01)
	var yaw0 := c.yaw
	rig.turn_by(10.0)
	assert_almost_eq(c.yaw, yaw0 - 10.0 * Game.data.bal("map3d_rotate_deg_per_px"), 0.0001)
	assert_eq(v.target(), c.target)
	assert_eq(v.distance(), c.distance)
	assert_eq(v.yaw(), c.yaw)


## Perf 2026-10-02: a trackpad sends several gestures a frame; each moved the
## camera at once but told the listeners (pieces, houses, HUD) every time.
## Through the view's input they hear ONE camera_moved a frame.
func test_a_frames_gestures_tell_the_listeners_once() -> void:
	var v := _view()
	var c := v.context()
	await wait_process_frames(2)
	var heard := [0]
	c.camera_moved.connect(func() -> void: heard[0] += 1)
	var t0 := c.target
	for i in 4:
		var g := InputEventPanGesture.new()
		g.delta = Vector2(3, 0)
		g.position = v.size * 0.5
		v._gui_input(g)
	assert_ne(c.target, t0, "the camera moved at once")
	assert_eq(heard[0], 0, "the listeners wait for the frame")
	await wait_process_frames(1)
	assert_eq(heard[0], 1, "and hear it once")
	var rig := v.component("rig") as Map3DCameraRig
	rig.pan_by(Vector2(10, 0))
	assert_eq(heard[0], 2, "a direct pan (a tool, the keys) is told at once")


func test_the_north_ease_runs_on_step() -> void:
	var v := _view()
	var rig := v.component("rig") as Map3DCameraRig
	rig.turn_by(100.0)
	rig.start_north()
	rig.step(Game.data.bal("map3d_compass_reset_s") + 0.01)
	assert_eq(v.context().yaw, 0.0)


func test_the_input_says_which_events_the_view_takes() -> void:
	var v := _view()
	var input := v.component("input") as Map3DInput
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	assert_true(input.handle(wheel), "the wheel zooms")
	var rup := InputEventMouseButton.new()
	rup.button_index = MOUSE_BUTTON_RIGHT
	rup.pressed = false
	# A right release over the ground now offers a spy there (owner
	# 2026-09-28, SpyOrderMenu's ground_menu_requested) — only a release
	# over the sky (no ground under the pointer) still falls through.
	assert_true(input.handle(rup), "a right release on the ground offers a spy")
	var hover := InputEventMouseMotion.new()
	hover.position = Vector2(10, 10)
	assert_false(input.handle(hover), "a bare move is only recorded for the hover")
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = v.size * 0.5
	pinch.factor = 1.2
	assert_true(input.handle(pinch))


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()


## Zooming out stops where the SCALE BAR would read past its cap (owner
## 2026-09-20: "设置zoom out标尺最多150km"; the 1-2-5 ladder makes that 100 km).
func _bar_reading(v: Map3DView) -> float:
	var bar := Map3DHud.scale_bar_for(v.metres_per_pixel() * v.map_units_per_metre(),
		Game.data.bal("map_scale_bar_max_px"), v.map_unit())
	return float(bar.get("distance", 0.0))

func test_zooming_out_stops_before_the_scale_bar_passes_its_cap() -> void:
	var cap := Game.data.bal("map3d_zoom_max_scale")
	for view_h: float in [450.0, 600.0]:
		var v := _view()
		v.size = Vector2(800, view_h)
		v._fit_viewport()
		# Ask for far more than the ceiling: the rig takes what it may.
		v.look_at_home(Game.data.bal("map3d_zoom_max_m") * 10.0)
		var rig := v.world().get_node("CameraRig") as Map3DCameraRig
		assert_almost_eq(v.distance(), rig.max_distance(), 1.0,
			"the far stop is the rig's own ceiling at %d px" % int(view_h))
		assert_lte(v.distance(), Game.data.bal("map3d_zoom_max_m"),
			"never past the balance ceiling")
		assert_lte(_bar_reading(v), cap, "the bar reads at or under its cap at %d px" % int(view_h))
		assert_gt(_bar_reading(v), 0.0, "the bar still reads something")

func test_a_taller_view_may_zoom_out_farther() -> void:
	# More pixels under the same bar means a smaller reading, so the ceiling
	# rises with the view's height.
	var short_v := _view()
	short_v.size = Vector2(800, 400)
	short_v._fit_viewport()
	var tall_v := _view()
	tall_v.size = Vector2(800, 800)
	tall_v._fit_viewport()
	var short_rig := short_v.world().get_node("CameraRig") as Map3DCameraRig
	var tall_rig := tall_v.world().get_node("CameraRig") as Map3DCameraRig
	assert_gt(tall_rig.max_distance(), short_rig.max_distance())
