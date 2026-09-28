extends GutTest
## The 3D map's layers, each its own script (spec 2026-09-20 §1, §5 step 4):
## the view builds them and forwards to them; these tests hold that each
## layer is the node the view's seams name, with the same look as before.

const RunDir := preload("res://tests/run_dir.gd")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
## In this run's own directory (tests/run_dir.gd): user:// is shared by every
## checkout, and a suite running at the same time deleted rivers.json here.
var _dir := RunDir.dir("map3d_layers")
var _fixture := _dir.path_join("world.tscn")
var _sea_fixture := _dir.path_join("sea.tscn")
var _rivers_json := _dir.path_join("rivers.json")


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _fixture)
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
	ResourceSaver.save(packed_sea, _sea_fixture)
	sea_root.free()


func after_each() -> void:
	if FileAccess.file_exists(_rivers_json):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_rivers_json))


func _view(path: String = _fixture) -> Map3DView:
	var v := Map3DView.create(Game.data, path)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_rivers_are_their_own_layer() -> void:
	var f := FileAccess.open(_rivers_json, FileAccess.WRITE)
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


func test_the_sea_layer_is_the_scenes_own_plane() -> void:
	var v := _view(_sea_fixture)
	var sea := v.viewport().get_node("Sea")
	assert_true(sea is Map3DLayerSea)
	assert_eq((sea as Map3DLayerSea).material_override, v.sea_material())
	assert_not_null((sea as Map3DLayerSea).mesh, "the scene's own plane")
	assert_eq(v.sea_material().render_priority, Map3DPriority.SEA)
	v.set_layer_visible("Sea", false)
	assert_false((sea as Node3D).visible)


func test_the_suns_shadow_look_is_data() -> void:
	var v := _view(_sea_fixture)
	var sun := v.viewport().get_node("Sun") as DirectionalLight3D
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
	var capital := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
	assert_eq(v.pick_reach_px(capital, spec, 5000.0), v.context().pick_reach_px(capital, spec, 5000.0))
	assert_eq(Map3DView.SELECTED_RING_ALWAYS_M, Map3DLayerSettlements.SELECTED_RING_ALWAYS_M)
	assert_false((markers as Map3DLayerSettlements).selected_visible())


func test_the_view_owns_a_houses_layer() -> void:
	var v := _view()
	var houses := v.viewport().get_node("Houses")
	assert_true(houses is Map3DLayerHouses)
	assert_eq((houses as Map3DLayerHouses).counts(), v.house_counts())


func test_the_view_builds_the_houses_layer_at_load_not_lazily() -> void:
	# Task 7: build() (which warms Map3DHouses.load_csv, ~91 ms over the real
	# table) must run during _load(), not wait for the first refresh() mid-play.
	# A layer that never had build() called has no MultiMeshInstance3D children
	# yet — one per house type is made only inside build().
	var v := _view()
	var houses := v.viewport().get_node("Houses") as Map3DLayerHouses
	assert_gt(houses.get_child_count(), 0,
		"build() ran at load: one MultiMeshInstance3D child per house type")


func test_a_camera_move_refreshes_the_houses() -> void:
	# The initial _rig.place() in _load() already fired one camera_moved, so
	# the clusters over the player's capital (_view's home) are populated by
	# the time the view is loaded.
	var v := _view()
	var houses := v.viewport().get_node("Houses") as Map3DLayerHouses
	var at_home := houses.counts().duplicate()
	var total_home := 0
	for type: String in at_home:
		total_home += int(at_home[type])
	assert_gt(total_home, 0, "the capital's clusters are up by the time the view loads")
	# A far pan past map3d_house_rebuild_move_m, off every settlement's own
	# map3d_house_view_m, must rebuild through the SAME camera_moved seam —
	# never lazily, never only once.
	(v.component("rig") as Map3DCameraRig).place(
		v.context().bounds.position, Game.data.bal("map3d_zoom_min_m"), 0.0)
	assert_ne(houses.counts(), at_home, "camera_moved drove a fresh refresh() away from home")


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
	# Given back: before_all starts ONE campaign for the whole file, so a
	# conquest left standing would run every later test on a map whose borders
	# have moved (final review 2026-09-20).
	MapOwnership.set_owner(Game.data, Game.state, province, raider, "test: conquest undone")
	assert_eq(MapOwnership.owner_of(Game.data, Game.state, province), raider)


func test_the_themes_are_one_layer_that_works_before_load() -> void:
	var v := Map3DView.create(Game.data, _fixture)
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


## The capital's inner dot must come from data/map3d_settlements.csv's
## inner_px column, never a hardcoded group name (owner 2026-09-20).
func test_the_inner_dot_is_data_driven_not_a_hardcoded_group_name() -> void:
	var layer_src := FileAccess.get_file_as_string("res://scripts/map3d/map3d_layer_settlements.gd")
	assert_false(layer_src.contains("\"capital\""),
		"the layer must read inner_px from the spec, not branch on the group's name")
	var shader_src := FileAccess.get_file_as_string("res://scripts/map3d/settlement_ring.gdshader")
	assert_false(shader_src.to_lower().contains("capital"),
		"the shader must not name a settlement group")


## The kept world (Map3DWorldCache) must not leak into the next file.
func after_all() -> void:
	Map3DWorldCache.clear()
