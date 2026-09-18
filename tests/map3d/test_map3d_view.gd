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


## Tests that write rivers.json beside the fixture scene leave nothing
## behind even when an assert fails before their own cleanup line (final
## review, owner 2026-09-18).
func after_each() -> void:
	if FileAccess.file_exists("user://rivers.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rivers.json"))


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
	assert_almost_eq(float(mat.get_shader_parameter("fade_start")), Game.data.bal("map3d_ring_fade_start"),
		0.001, "the shader and pick_at read one fade start")


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
	assert_eq(priority.call("village"), Map3DView.PRIORITY_RING_BASE, "the lowest tier sits at the table's base")


## The render-priority table (final review, owner 2026-09-18): sea < rivers <
## seams < kingdoms < province outline < clouds < every ring, so a
## settlement pin always stands over the weather and the weather over lines.
func test_the_render_priority_table_orders_every_layer() -> void:
	var order := [Map3DView.PRIORITY_SEA, Map3DView.PRIORITY_RIVERS, Map3DView.PRIORITY_SEAMS,
		Map3DView.PRIORITY_KINGDOMS, Map3DView.PRIORITY_SELECTION, Map3DView.PRIORITY_CLOUDS,
		Map3DView.PRIORITY_RING_BASE]
	for i in range(1, order.size()):
		assert_lt(order[i - 1], order[i], "row %d under row %d" % [i - 1, i])
	var v := _view()
	v.activate()
	var clouds := v.viewport().get_node("Clouds") as MultiMeshInstance3D
	assert_eq((clouds.material_override as ShaderMaterial).render_priority, Map3DView.PRIORITY_CLOUDS)
	for mmi: MultiMeshInstance3D in v.viewport().get_node("Markers").get_children():
		var mat := mmi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
		assert_gt(mat.render_priority, Map3DView.PRIORITY_CLOUDS, "%s over the clouds" % mmi.name)
	v.refresh_borders()
	var kingdoms := v.line_mesh("Kingdoms")
	if kingdoms != null:
		assert_eq((kingdoms.surface_get_material(0) as ShaderMaterial).render_priority,
			Map3DView.PRIORITY_KINGDOMS)


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


func test_clouds_come_with_play_and_go_with_pause() -> void:
	var v := _view()
	v.activate()
	assert_true("Clouds" in v.layer_names())
	Game.set_clock_speed(1)
	v._process(0.1)
	assert_eq(v.cloud_count(), int(Game.data.bal("map3d_cloud_max")))
	Game.set_clock_speed(0)
	v._process(Game.data.bal("map3d_cloud_fade_s") + 0.1)
	assert_eq(v.cloud_count(), 0)


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


## Final review (owner 2026-09-18): a ring thinned away by distance is not
## picked — at the farthest zoom a click on a village's own spot (no bigger,
## still-shown settlement near it) names the province under it instead.
func test_a_thinned_village_is_not_picked_at_a_far_zoom() -> void:
	var v := _view()
	v.activate()
	var far := Game.data.bal("map3d_zoom_max_m")
	var village := _lone_village(far)
	assert_false(village.is_empty(), "the pack has a village away from shown rings")
	v.look_at_pack(village["px"], far)
	var picked := v.pick_at(v.size * 0.5)
	assert_eq(String(picked.get("kind", "")), "province", "the hidden ring is skipped")
	assert_eq(String(picked.get("code", "")), village["province"])
	# The same village is picked up close, where its ring shows.
	v.look_at_pack(village["px"], Game.data.bal("map3d_zoom_min_m"))
	assert_eq(v.pick_at(v.size * 0.5), {"kind": "burg", "code": village["code"]})


## A village with a province under it, whose tier ring is hidden at `at_m`
## and with no burg of a tier still shown at `at_m` within 150 pack px.
func _lone_village(at_m: float) -> Dictionary:
	var img := (load(Game.data.province_texture_path) as Texture2D).get_image()
	var fade := Game.data.bal("map3d_ring_fade_start")
	var codes: Array = Game.data.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = Game.data.burgs[code]
		if String(b.get("group", "")) != "village":
			continue
		var px := Vector2(float(b["x"]), float(b["y"]))
		var pid := MapIndex.id_at(img, Vector2i(px.floor()))
		var prov := String(Game.data.province_by_id(pid).get("province_code", ""))
		if prov == "":
			continue
		var clear := true
		for o: Dictionary in Game.data.burgs.values():
			var spec: Dictionary = Game.data.map3d_settlements.get(String(o.get("group", "")), {})
			if spec.is_empty() or float(spec["max_view_m"]) * fade <= at_m:
				continue
			if Vector2(float(o["x"]), float(o["y"])).distance_to(px) < 150.0:
				clear = false
				break
		if clear:
			return {"code": code, "px": px, "province": prov}
	return {}


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


func test_the_hud_is_over_the_view_and_the_compass_turns_it_north() -> void:
	var v := _view()
	v.activate()
	var hud := v.get_node("Hud") as Map3DHud
	assert_not_null(hud)
	_drag(v, MOUSE_BUTTON_RIGHT, Vector2(80, 0))
	assert_ne(v.yaw(), 0.0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = hud.compass_rect().get_center()
	v._gui_input(press)
	v._process(Game.data.bal("map3d_compass_reset_s") + 0.01)
	assert_almost_eq(v.yaw(), 0.0, 0.001)


func test_a_compass_press_that_moves_does_not_pan_or_select() -> void:
	var v := _view()
	v.activate()
	var hud := v.get_node("Hud") as Map3DHud
	var t0 := v.target()
	watch_signals(v)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = hud.compass_rect().get_center()
	v._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(40, 0)
	motion.relative = Vector2(40, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	v._gui_input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = motion.position
	v._gui_input(up)
	assert_eq(v.target(), t0, "a press-and-move that started on the compass never pans")
	assert_signal_not_emitted(v, "object_selected")
	assert_signal_not_emitted(v, "province_selected")


func test_rivers_beside_the_scene_become_the_rivers_layer() -> void:
	var f := FileAccess.open("user://rivers.json", FileAccess.WRITE)
	f.store_string('{"rivers": [{"code": "a", "points": [[0, 0, 10, 6, 0], [500, 0, 9, 40, 1]]}]}')
	f.close()
	var v := _view()
	v.activate()
	var mi := v.viewport().get_node_or_null("Rivers") as MeshInstance3D
	assert_not_null(mi)
	assert_true("Rivers" in v.layer_names())


func test_the_builds_sea_wears_the_banded_water() -> void:
	var root := Node3D.new()
	root.set_meta("map3d_world", WORLD)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = PlaneMesh.new()
	root.add_child(sea)
	sea.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "user://test_map3d_sea.tscn")
	root.free()
	var v := _view("user://test_map3d_sea.tscn")
	v.activate()
	var mat := v.sea_material()
	assert_not_null(mat)
	assert_eq(mat.get_shader_parameter("band_near"), Game.data.bal("map_sea_band_near_px"))
	assert_true("Sea" in v.layer_names())


## Final review (owner 2026-09-18): the palette hex goes in RAW — a Color
## uniform set from GDScript passes straight through under GL Compatibility
## (measured), so the old srgb_to_linear() only fought the emission gamma.
## The Filmic tonemap's lift is undone by map3d_sea_emission_gamma instead.
func test_the_seas_band_colours_go_in_raw() -> void:
	var root := Node3D.new()
	root.set_meta("map3d_world", WORLD)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = PlaneMesh.new()
	root.add_child(sea)
	sea.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "user://test_map3d_sea2.tscn")
	root.free()
	var v := _view("user://test_map3d_sea2.tscn")
	v.activate()
	var mat := v.sea_material()
	var raw: Color = MapTerrain.palette_color(Game.data, "sea_near", MapTerrain.FALLBACK)
	assert_eq(mat.get_shader_parameter("sea_near"), raw, "the palette hex, unconverted")
	assert_eq(mat.get_shader_parameter("emission_share"), Game.data.bal("map3d_sea_emission_share"))
	assert_eq(mat.get_shader_parameter("emission_gamma"), Game.data.bal("map3d_sea_emission_gamma"))
	for key: String in ["ripple_near_m", "ripple_emission_gain", "emission_share_near", "shore_warp_px"]:
		assert_eq(mat.get_shader_parameter(key), Game.data.bal("map3d_sea_" + key), key + " is data")


## Same for the river material: water goes in raw, and the emission
## share/gamma are wired from balance.csv.
func test_the_rivers_colours_go_in_raw() -> void:
	var f := FileAccess.open("user://rivers.json", FileAccess.WRITE)
	f.store_string('{"rivers": [{"code": "a", "points": [[0, 0, 10, 6, 0], [500, 0, 9, 40, 1]]}]}')
	f.close()
	var v := _view()
	v.activate()
	var mat := v.river_material()
	assert_not_null(mat)
	var raw: Color = MapTerrain.palette_color(Game.data, "river", MapTerrain.FALLBACK)
	assert_eq(mat.get_shader_parameter("water"), raw, "the palette hex, unconverted")
	assert_eq(mat.get_shader_parameter("emission_share"), Game.data.bal("map3d_river_emission_share"))
	assert_eq(mat.get_shader_parameter("emission_gamma"), Game.data.bal("map3d_river_emission_gamma"))
	for key: String in ["fresnel_sky_mix", "roughness", "specular", "normal_depth", "bank_wobble_amp"]:
		assert_eq(mat.get_shader_parameter(key), Game.data.bal("map3d_river_" + key), key + " is data")
	assert_eq(mat.get_shader_parameter("lod_far_m"), Game.data.bal("map3d_sea_ripple_lod_far_m"),
		"one LOD for both waters")
