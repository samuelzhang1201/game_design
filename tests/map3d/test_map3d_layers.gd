extends GutTest
## The 3D map's layers, each its own script (spec 2026-09-20 §1, §5 step 4):
## the view builds them and forwards to them; these tests hold that each
## layer is the node the view's seams name, with the same look as before.

const FIXTURE := "user://test_map3d_layers_world.tscn"
const SEA_FIXTURE := "user://test_map3d_layers_sea.tscn"
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
	var sea_root := Node3D.new()
	sea_root.name = "SeaFixture"
	sea_root.set_meta("map3d_world", WORLD)
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	sea.mesh = PlaneMesh.new()
	sea.position = Vector3(0, 5.0, 0)
	sea_root.add_child(sea)
	sea.owner = sea_root
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sea_root.add_child(sun)
	sun.owner = sea_root
	var packed_sea := PackedScene.new()
	packed_sea.pack(sea_root)
	ResourceSaver.save(packed_sea, SEA_FIXTURE)
	sea_root.free()


func after_each() -> void:
	if FileAccess.file_exists("user://rivers.json"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rivers.json"))


func _view(path: String = FIXTURE) -> Map3DView:
	var v := Map3DView.create(Game.data, path)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_rivers_are_their_own_layer() -> void:
	var f := FileAccess.open("user://rivers.json", FileAccess.WRITE)
	f.store_string('{"rivers": [{"code": "a", "points": [[0, 0, 10, 6, 0], [500, 0, 9, 40, 1]]}]}')
	f.close()
	var v := _view()
	var rivers := v.viewport().get_node("Rivers")
	assert_true(rivers is Map3DLayerRivers)
	assert_eq((rivers as Map3DLayerRivers).material(), v.river_material())
	assert_gt((rivers as Map3DLayerRivers).courses().size(), 0, "the bridges read the courses")
	assert_eq(v.river_material().render_priority, Map3DPriority.RIVERS)


func test_no_rivers_file_no_rivers_layer_listed() -> void:
	var v := _view()
	assert_false("Rivers" in v.layer_names())


func test_the_sea_layer_dresses_the_builds_plane() -> void:
	var v := _view(SEA_FIXTURE)
	var sea := v.viewport().get_node("Sea")
	assert_true(sea is Map3DLayerSea)
	assert_eq((sea as Map3DLayerSea).material_override, v.sea_material())
	assert_not_null((sea as Map3DLayerSea).mesh, "the build's plane, taken over")
	assert_eq(v.sea_material().render_priority, Map3DPriority.SEA)
	v.set_layer_visible("Sea", false)
	assert_false((sea as Node3D).visible)


func test_the_suns_shadow_look_is_data() -> void:
	var v := _view(SEA_FIXTURE)
	var suns := v.viewport().find_children("*", "DirectionalLight3D", true, false)
	assert_eq(suns.size(), 1)
	var sun := suns[0] as DirectionalLight3D
	assert_almost_eq(sun.shadow_opacity, Game.data.bal("map3d_sun_shadow_opacity"), 0.0001)
	assert_almost_eq(sun.shadow_blur, Game.data.bal("map3d_sun_shadow_blur"), 0.0001)


func test_the_clouds_are_their_own_layer_with_a_shadow_twin() -> void:
	var v := _view()
	var clouds := v.viewport().get_node("Clouds")
	assert_true(clouds is Map3DLayerClouds)
	var twin := clouds.get_node("Shadows") as MultiMeshInstance3D
	assert_eq(twin.multimesh, (clouds as MultiMeshInstance3D).multimesh, "one shape, one shadow")
	assert_eq(twin.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	var deck := (clouds as MultiMeshInstance3D).material_override as ShaderMaterial
	var shade := twin.material_override as ShaderMaterial
	assert_ne(deck.shader, shade.shader, "two shader files (the Compatibility trap)")
	Game.set_clock_speed(1)
	(clouds as Map3DLayerClouds).step(0.1)
	assert_eq((clouds as Map3DLayerClouds).count(), v.cloud_count())
	Game.set_clock_speed(0)


func test_the_markers_are_their_own_layer() -> void:
	var v := _view()
	var markers := v.viewport().get_node("Markers")
	assert_true(markers is Map3DLayerSettlements)
	assert_eq((markers as Map3DLayerSettlements).counts(), v.marker_counts())
	var spec: Dictionary = Game.data.map3d_settlements["capital"]
	assert_eq(Map3DView.marker_px(spec), Map3DLayerSettlements.marker_px(spec))
	assert_eq(Map3DView.SELECTED_RING_ALWAYS_M, Map3DLayerSettlements.SELECTED_RING_ALWAYS_M)
	assert_false((markers as Map3DLayerSettlements).selected_visible())


func test_the_roads_are_one_builder_writing_lines_and_bridges() -> void:
	var v := _view()
	assert_true(v.component("roads") is Map3DLayerRoads)
	var roads := v.line_mesh("Roads")
	assert_not_null(roads, "the pack's roads draped on the ground")
	var mat := roads.surface_get_material(0) as ShaderMaterial
	assert_eq(mat.render_priority, Map3DPriority.ROADS)
	assert_eq(mat.get_shader_parameter("width_m"), Game.data.bal("map3d_road_width_m"))
	assert_eq(v.bridges(), (v.component("roads") as Map3DLayerRoads).bridges())
	assert_eq(v.bridge_rules()["abut_m"], Game.data.bal("map3d_bridge_abut_m"))


func test_the_borders_rebuild_only_when_ownership_moves() -> void:
	var v := _view()
	var borders := v.component("borders") as Map3DLayerBorders
	assert_not_null(borders)
	v.refresh_borders()
	assert_false(borders.refresh(), "same owners: nothing rebuilt")
	var mine := Game.data.resolve_realm("player_realm")
	var raider := Game.data.resolve_realm("raider_realm")
	var province: String = MapOwnership.provinces_of(Game.data, Game.state, raider)[0]
	MapOwnership.set_owner(Game.data, Game.state, province, mine, "test: conquest")
	assert_true(borders.refresh(), "a conquest rebuilds")
	var band := v.line_mesh("KingdomBand").surface_get_material(0) as ShaderMaterial
	assert_eq(band.render_priority, Map3DPriority.KINGDOM_BAND)
	assert_eq(band.get_shader_parameter("fade_power"), Game.data.bal("map3d_border_band_fade_power"))
	borders.draw_hover(mine)
	assert_eq(borders.hovered(), mine)
	assert_not_null(v.line_mesh("Hover"))
	borders.draw_hover("")
	assert_null(v.line_mesh("Hover"))


func test_the_themes_are_one_layer_that_works_before_load() -> void:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.set_manor_theme("heights")
	assert_true(v.heat_on(), "the theme holds before the world loads")
	var themes := v.component("themes") as Map3DLayerThemes
	assert_not_null(themes)
	assert_eq(themes.theme(), "heights")
	v.activate()
	v.set_manor_theme("manors")
	assert_false(v.heat_on())
	assert_not_null(v.cell_lut())
	assert_not_null(v.viewport().get_node_or_null("Lines/ManorEdges"))
	assert_eq(Map3DView.load_field_map("user://nowhere/world.tscn"), null)
