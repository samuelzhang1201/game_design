extends GutTest
## Map3DView: the 3D MAP tab's view. It loads the built Terrain3D scene only
## when first shown, frames the player's capital, places a marker per
## settlement from live data, and turns rendering off while hidden. The real
## scene is git-ignored (tools/map3d builds it), so these tests use a small
## fixture scene carrying the same `map3d_world` metadata.

const FIXTURE := "user://test_map3d_world.tscn"
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


func _view(path: String = FIXTURE) -> Map3DView:
	var v := Map3DView.create(Game.data, path)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	return v


func _capital_xz() -> Vector2:
	var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
	var burg: Dictionary = Game.data.burgs[String(realm["capital_burg"])]
	return Map3DGeometry.pack_to_world(WORLD, Vector2(float(burg["x"]), float(burg["y"])))


func test_the_default_path_is_the_packs_built_scene() -> void:
	assert_eq(Map3DView.scene_path_for(Game.data.map_id),
		"res://assets/map3d/%s/world.tscn" % Game.data.map_id)


func test_nothing_loads_until_the_view_is_first_shown() -> void:
	var v := _view()
	await wait_frames(1)
	assert_false(v.is_loaded(), "lazy: a 3D world is heavy")
	v.activate()
	assert_true(v.is_loaded())


func test_an_unbuilt_map_says_how_to_build_it() -> void:
	var v := _view("res://no/such/world.tscn")
	v.activate()
	assert_false(v.is_loaded())
	assert_true(v.notice().visible)
	assert_string_contains(v.notice().text, "tools/map3d")


func test_it_opens_on_the_players_capital() -> void:
	var v := _view()
	v.activate()
	assert_almost_eq(v.target().x, _capital_xz().x, 0.01)
	assert_almost_eq(v.target().y, _capital_xz().y, 0.01)
	assert_almost_eq(v.distance(), Game.data.bal("map3d_zoom_start_m"), 0.01)
	assert_true(v.camera().current, "the rig's camera is the viewport's")
	assert_false(v.notice().visible)


func test_every_settlement_gets_a_marker_by_group() -> void:
	var v := _view()
	v.activate()
	var expected := {}
	for code: String in Game.data.burgs:
		var g := String(Game.data.burgs[code].get("group", ""))
		if Game.data.map3d_settlements.has(g):
			expected[g] = int(expected.get(g, 0)) + 1
	var got := v.marker_counts()
	assert_eq(got, expected)
	assert_gt(got.size(), 0, "the pack has settlements")


func test_the_wheel_zooms_within_the_clamp() -> void:
	var v := _view()
	v.activate()
	var d0 := v.distance()
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	v._gui_input(wheel)
	assert_almost_eq(v.distance(), d0 / Game.data.bal("map3d_zoom_factor"), 0.01, "a notch in")
	for i in 200:
		v._gui_input(wheel)
	assert_almost_eq(v.distance(), Game.data.bal("map3d_zoom_min_m"), 0.01, "clamped")


func test_a_left_drag_pans_and_a_right_drag_turns() -> void:
	var v := _view()
	v.activate()
	var t0 := v.target()
	_drag(v, MOUSE_BUTTON_LEFT, Vector2(40, 0))
	assert_lt(v.target().x, t0.x, "the ground follows the mouse right, the target goes left")
	var yaw0 := v.yaw()
	_drag(v, MOUSE_BUTTON_RIGHT, Vector2(40, 0))
	assert_almost_eq(v.yaw(), yaw0 - 40.0 * Game.data.bal("map3d_rotate_deg_per_px"), 0.001)


func test_hiding_the_view_stops_its_rendering() -> void:
	var v := _view()
	v.activate()
	assert_eq(v.viewport().render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	v.deactivate()
	assert_eq(v.viewport().render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_false(v.visible)


func _drag(v: Map3DView, button: MouseButton, by: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	v._gui_input(down)
	var motion := InputEventMouseMotion.new()
	motion.relative = by
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	v._gui_input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	v._gui_input(up)
