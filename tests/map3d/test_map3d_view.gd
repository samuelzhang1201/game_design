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


func test_rings_take_their_size_from_the_table() -> void:
	var v := _view()
	v.activate()
	var mmi := v.viewport().get_node("Markers/Capital") as MultiMeshInstance3D
	var mat := mmi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var spec: Dictionary = Game.data.map3d_settlements["capital"]
	assert_almost_eq(float(mat.get_shader_parameter("ring_px")), float(spec["ring_px"]), 0.001,
		"design px at the headless render scale of 1")
	assert_almost_eq(float(mat.get_shader_parameter("line_px")), float(spec["line_px"]), 0.001)


func test_a_clicked_settlement_wears_the_gold_ring_until_cleared() -> void:
	var v := _view()
	v.activate()
	var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
	var burg: Dictionary = Game.data.burgs[String(realm["capital_burg"])]
	v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])))
	_click(v, v.size * 0.5)
	assert_true(v.selected_ring_visible())
	v.clear_selection()
	assert_false(v.selected_ring_visible())


func test_a_far_village_carries_its_max_view_m_from_the_table() -> void:
	var v := _view()
	v.activate()
	var mmi := v.viewport().get_node("Markers/Village") as MultiMeshInstance3D
	var mat := mmi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
	var spec: Dictionary = Game.data.map3d_settlements["village"]
	assert_almost_eq(float(mat.get_shader_parameter("max_view_m")), float(spec["max_view_m"]), 0.001)


func test_ring_render_priority_rises_with_tier() -> void:
	var v := _view()
	v.activate()
	var priority := func(group: String) -> int:
		var mmi := v.viewport().get_node("Markers/%s" % group.capitalize()) as MultiMeshInstance3D
		var mat := mmi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
		return mat.render_priority
	assert_lt(priority.call("village"), priority.call("town"), "village < town")
	assert_lt(priority.call("town"), priority.call("city"), "town < city")
	assert_lt(priority.call("city"), priority.call("capital"), "city < capital")
	assert_true(priority.call("village") >= 3, "rings still draw over the lines (0-2)")


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
	motion.position = by
	motion.relative = by
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	v._gui_input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	v._gui_input(up)


func test_a_click_on_a_settlement_opens_its_card() -> void:
	var v := _view()
	v.activate()
	var realm: Dictionary = Game.data.kingdoms[Game.data.resolve_realm("player_realm")]
	var code := String(realm["capital_burg"])
	var burg: Dictionary = Game.data.burgs[code]
	v.look_at_pack(Vector2(float(burg["x"]), float(burg["y"])))
	watch_signals(v)
	_click(v, v.size * 0.5)
	assert_signal_emitted_with_parameters(v, "object_selected",
		[{"title": String(burg["label"]), "obj": {"kind": "burg", "code": code}}])
	assert_eq(v.selected_burg(), code)


func test_a_click_on_open_land_names_its_province() -> void:
	var v := _view()
	v.activate()
	var spot := _open_land()
	v.look_at_pack(spot["px"], Game.data.bal("map3d_zoom_min_m"))
	watch_signals(v)
	_click(v, v.size * 0.5)
	assert_signal_emitted_with_parameters(v, "province_selected", [spot["province"]])
	assert_eq(v.selected_province(), spot["province"])
	assert_not_null(v.line_mesh("Selection"), "the clicked province is outlined")


func test_a_drag_is_not_a_click() -> void:
	var v := _view()
	v.activate()
	watch_signals(v)
	_drag(v, MOUSE_BUTTON_LEFT, Vector2(40, 0))
	assert_signal_not_emitted(v, "province_selected")
	assert_signal_not_emitted(v, "object_selected")


func test_closing_the_card_clears_the_selection() -> void:
	var v := _view()
	v.activate()
	var spot := _open_land()
	v.look_at_pack(spot["px"], Game.data.bal("map3d_zoom_min_m"))
	_click(v, v.size * 0.5)
	watch_signals(v)
	v.clear_selection()
	assert_eq(v.selected_province(), "")
	assert_signal_emitted_with_parameters(v, "object_selected", [{}])
	assert_null(v.line_mesh("Selection"), "no outline left")


func test_borders_and_seams_are_laid_from_the_live_outlines() -> void:
	var v := _view()
	v.activate()
	var rings: Array = []
	for code: String in Game.data.kingdoms:
		rings.append_array(Map3DBorders.kingdom_lines(Game.data, Game.state, WORLD, code,
			Game.data.bal("map3d_line_step_m")))
	var expected: PackedVector3Array = Map3DBorders.ribbon_arrays(rings,
		func(_xz: Vector2) -> float: return 5.0)[Mesh.ARRAY_VERTEX]
	var kingdoms := v.line_mesh("Kingdoms")
	assert_not_null(kingdoms)
	assert_eq(kingdoms.surface_get_array_len(0), expected.size())
	assert_not_null(v.line_mesh("Seams"))


func test_a_conquest_redraws_the_borders() -> void:
	var v := _view()
	v.activate()
	var before := v.line_mesh("Kingdoms")
	var player := Game.data.resolve_realm("player_realm")
	var raider := Game.data.resolve_realm("raider_realm")
	var province := String(MapOwnership.provinces_of(Game.data, Game.state, raider)[0])
	MapOwnership.set_owner(Game.data, Game.state, province, player, "test: conquest")
	v.refresh_borders()
	assert_ne(v.line_mesh("Kingdoms"), before, "a new mesh for the new outline")
	Game.start_campaign(42)


func test_a_pinch_zooms_and_a_two_finger_drag_pans() -> void:
	var v := _view()
	v.activate()
	var d0 := v.distance()
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = v.size * 0.5
	pinch.factor = 1.5
	v._gui_input(pinch)
	assert_lt(v.distance(), d0, "fingers apart zoom in")
	var t0 := v.target()
	var pan := InputEventPanGesture.new()
	pan.position = v.size * 0.5
	pan.delta = Vector2(3, 0)
	v._gui_input(pan)
	assert_ne(v.target(), t0, "two fingers pan")


func test_the_zoom_keeps_the_ground_under_the_pointer() -> void:
	var v := _view()
	v.activate()
	var at := v.size * Vector2(0.8, 0.7)
	var before: Vector3 = v.ground_at(at)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = at
	v._gui_input(wheel)
	var after: Vector3 = v.ground_at(at)
	# The pitch also changes with the distance, so allow a few per cent of
	# the distance rather than demanding an exact fixed point.
	assert_lt(Vector2(after.x, after.z).distance_to(Vector2(before.x, before.z)),
		v.distance() * 0.08)


func test_the_closest_zoom_is_800_m() -> void:
	assert_eq(Game.data.bal("map3d_zoom_min_m"), 800.0)


func test_the_bench_can_switch_each_layer_off() -> void:
	var v := _view()
	v.activate()
	var names := v.layer_names()
	assert_true("Markers" in names and "Lines" in names)
	v.set_layer_visible("Markers", false)
	assert_false((v.viewport().get_node("Markers") as Node3D).visible)
	v.set_layer_visible("Markers", true)
	v.look_at_home(5000.0)
	assert_almost_eq(v.distance(), 5000.0, 0.01)


func _click(v: Map3DView, at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	v._gui_input(down)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	v._gui_input(up)


## A land pixel of some province with no settlement within 60 px of it.
func _open_land() -> Dictionary:
	var img := (load(Game.data.province_texture_path) as Texture2D).get_image()
	for y in range(40, img.get_height() - 40, 25):
		for x in range(40, img.get_width() - 40, 25):
			var pid := MapIndex.id_at(img, Vector2i(x, y))
			var code := String(Game.data.province_by_id(pid).get("province_code", ""))
			if code == "":
				continue
			var clear := true
			for b: Dictionary in Game.data.burgs.values():
				if Vector2(float(b["x"]), float(b["y"])).distance_to(Vector2(x, y)) < 60.0:
					clear = false
					break
			if clear:
				return {"px": Vector2(x + 0.5, y + 0.5), "province": code}
	return {}
