extends GutTest
## Map3DCameraRig and Map3DInput (spec 2026-09-20 §1): the pose lives in the
## context and the rig moves it; the input says which events the view takes.

const FIXTURE := "user://test_map3d_rig_world.tscn"
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


func test_the_camera_hangs_from_the_rig() -> void:
	var v := _view()
	var rig := v.viewport().get_node("CameraRig") as Map3DCameraRig
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
	assert_false(input.handle(rup), "a right release is not taken, as before")
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
