extends GutTest
## The 3D map's look lives in the editor (owner 2026-10-02: "游戏是以你代码导入
## 为准还是编辑器？有冲突咋办" — the scene wins). What a CONVERTED piece's
## scene or .tres declares is what the game draws: a layer sets only what
## comes from the pack and the camera, never a tuned number of its own, and
## no script reads a key that went to the editor.

const RunDir := preload("res://tests/run_dir.gd")
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
var _dir := RunDir.dir("map3d_editor_owned_look")

## Per converted material: the parameters the CODE owns (from the pack, the
## camera, the window's scale, or read from another material), and why.
const CODE_OWNED := {
	# the pack's sea distance field, origin, size and scale; the camera's share
	# of natural water; the shared ripple texture
	"water_sea": ["sea_distance", "pack_origin", "pack_px", "m_per_px", "natural", "ripples"],
	# the river's screen px follow the window's scale; what it shares with the
	# sea is the sea's (below); the camera's natural share
	"water_river": ["px_per_dist", "min_px", "natural", "ripples",
		"mouth_water", "sky", "nat_mouth", "lod_near_m", "lod_far_m"],
	# the deck's shape is generated from the Clouds node's own seed
	"cloud_deck": ["shape"],
	"cloud_shadow": ["shape"],
	# the wind's uniforms are Map3DLayerWind's, every frame
	"tree_sway": ["wind_time", "wind_dir", "sway_m", "sway_height_m", "sway_hz", "flutter"],
	"tree_card": ["wind_time", "wind_dir", "sway_m", "sway_hz"],
	# a ring's colour, sizes and view range are its group's
	# (map3d_settlements.csv, which the picker reads too); its px are scaled
	# to the window; the selection's gold is the HUD's selection colour
	"settlement_ring": ["colour", "dot_px", "inner_px", "ring_px", "line_px", "lift_px", "px_per_dist",
		"max_view_m", "min_view_m"],
	# the clock, the camera and the bake's field map; lift_px scaled
	"march_trail": ["has_field_map", "field_map", "pack_origin", "field_m_per_texel", "now_days",
		"px_per_dist", "lift_px"],
	# the box, the sizes and the speeds follow the camera; the field, the pack
	"precip_fall": ["kind", "box_center", "box_half", "box_height", "fall_m_s", "wind_m_s", "wind_dir",
		"sway_m_s", "strength", "fall_now", "fall_next", "blend", "pack_origin", "m_per_px", "step_px"],
	"precip_drop_rain": ["kind", "length_m", "width_m"],
	"precip_drop_snow": ["kind", "length_m", "width_m"],
	"selection_ring": ["colour", "dot_px", "inner_px", "ring_px", "line_px", "lift_px", "px_per_dist",
		"max_view_m", "min_view_m"],
}
## The river's water that IS the sea's: river parameter -> sea parameter.
const RIVER_FROM_SEA := {"mouth_water": "sea_near", "sky": "sky", "nat_mouth": "nat_shallow",
	"lod_near_m": "ripple_lod_near_m", "lod_far_m": "ripple_lod_far_m"}
## Key prefixes that left balance.csv / terrain_palette.csv for the editor.
const GONE := ["map3d_sun_", "map3d_env_", "map3d_fog_", "map3d_ambient_", "map3d_sea_",
	"map_sea_band_", "map3d_sky", "map3d_border_band", "map3d_border_halo", "map3d_border_width",
	"map3d_seam", "map3d_hover_border", "map3d_selection_width", "map3d_selection_seam",
	"map_manor_line_", "map3d_road_width_px", "map3d_trail_width_px", "map3d_road_alpha",
	"map3d_road_edge_soft", "map3d_road_tile_m", "map3d_road_near_mpp", "map3d_road_far_mpp",
	"map3d_road_fray", "map3d_road_texture_gain", "map3d_road_hide_", "map3d_trail_hide_",
	"map3d_bridge_max_view_m", "map3d_cloud_max", "map3d_cloud_seed", "map3d_cloud_height_m",
	"map3d_cloud_size_", "map3d_cloud_speed_m_s", "map3d_cloud_interval_s", "map3d_cloud_fade_s",
	"map3d_cloud_alpha", "map3d_cloud_near_", "map3d_cloud_shadow_", "map3d_cloud_emission_share",
	"map3d_cloud_depth_ratio", "map3d_cloud_min_gap_m", "map3d_cloud_candidates", "map3d_weather_cloud_",
	"weather_storm_cloud", "map3d_tree_leaf_", "map3d_tree_hue_", "map3d_tree_saturation",
	"map3d_tree_value", "map3d_tree_roughness", "map3d_tree_specular", "map3d_tree_card_alpha",
	"map3d_tree_card_sphere", "map3d_tree_card_lift", "map3d_tree_card_saturation",
	"map3d_tree_card_value", "map3d_tree_card_tint", "map3d_tree_card_far_value",
	"map3d_ring_", "map3d_selected_ring_scale", "map3d_trail_alpha", "map3d_trail_days",
	"map3d_trail_hold", "map3d_trail_crop", "map3d_trail_step", "map3d_trail_half", "map3d_trail_edge",
	"map3d_trail_print", "map3d_trail_lane", "map3d_trail_rag", "map3d_trail_on", "map3d_line_lift_px",
	"map3d_march_trail", "map3d_weather_rain_", "map3d_weather_snow_count", "map3d_weather_snow_life",
	"map3d_weather_snow_length", "map3d_weather_snow_width", "map3d_weather_snow_opacity",
	"map3d_weather_snow_slant", "map3d_weather_snow_sway", "map3d_weather_snow_gain", "map3d_weather_fall_",
	"map3d_weather_gust_", "weather_rain", "weather_flake", "map3d_wind_", "map3d_cloud_wind_deg"]


func before_all() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, _dir.path_join("world.tscn"))
	root.free()
	var f := FileAccess.open(_dir.path_join("rivers.json"), FileAccess.WRITE)
	f.store_string('{"rivers": [{"code": "a", "points": [[0, 0, 10, 6, 0], [500, 0, 9, 40, 1]]}]}')
	f.close()


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, _dir.path_join("world.tscn"))
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_clouds_draw_what_their_tres_say() -> void:
	var v := _view()
	var deck := v.world().get_node("Clouds") as Map3DLayerClouds
	_assert_material_holds(deck.material_override as ShaderMaterial, "cloud_deck", 6)
	_assert_material_holds((deck.get_node("Shadows") as GeometryInstance3D).material_override as ShaderMaterial,
		"cloud_shadow", 1)


## Every ring wears its .tres's keyline and fade, and floats its lift scaled.
func test_the_rings_draw_what_their_tres_say() -> void:
	var v := _view()
	var markers := v.world().get_node("Markers") as Map3DLayerSettlements
	var s := v.context().viewport_px_scale()
	assert_gt(markers.get_child_count(), 1, "the tiers' rings and the selection ring")
	for mmi: MultiMeshInstance3D in markers.get_children():
		var live := mmi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
		var key := "selection_ring" if mmi.name == "Selected" else "settlement_ring"
		_assert_material_holds(live, key, 2)
		var look := load("res://scenes/map3d/materials/%s.tres" % key) as ShaderMaterial
		assert_almost_eq(float(live.get_shader_parameter("lift_px")),
			float(look.get_shader_parameter("lift_px")) * s, 0.0001, String(mmi.name) + ".lift_px, scaled")


## The march trails wear their .tres but for the clock, the camera, the field
## map and the lift (scaled).
func test_the_march_trails_draw_what_their_tres_say() -> void:
	var v := _view()
	var trails := v.world().get_node("Trails") as Map3DLayerTrails
	var mesh := trails.get_child(0) as MeshInstance3D
	_assert_material_holds(mesh.material_override as ShaderMaterial, "march_trail", 12)


## Each kind of falling weather wears its node's materials; the node holds
## its count and life.
func test_the_rain_and_snow_draw_what_their_scene_says() -> void:
	var v := _view()
	for kind: String in ["Rain", "Snow"]:
		var node := v.world().get_node("Precip/" + kind) as Map3DPrecipKind
		_assert_material_holds(node.process_material as ShaderMaterial, "precip_fall", 2)
		_assert_material_holds((node.draw_pass_1 as QuadMesh).material as ShaderMaterial,
			"precip_drop_" + kind.to_lower(), 3)
		assert_gt(node.amount, 1000, kind + "'s count is the scene's")


## The ground's wind stage has no material to save: each of its uniforms is
## an export of the world's Wind node, and every one is handed over.
func test_every_ground_wind_uniform_is_the_wind_nodes() -> void:
	var world := (load("res://scenes/map3d/map3d_world.tscn") as PackedScene).instantiate()
	autofree(world)
	var wind := world.get_node("Wind") as Map3DLayerWind
	var uniforms := RegEx.create_from_string("uniform float wind_([a-z_]+)")
	var named := []
	for m: RegExMatch in uniforms.search_all(Map3DGroundWind.UNIFORMS):
		if m.get_string(1) not in ["on", "time"]:
			named.append(m.get_string(1))
	named.sort()
	var handed: Array = Map3DLayerWind.GROUND.duplicate()
	handed.sort()
	assert_eq(handed, named, "every wind uniform is handed over, and only those")
	for key: String in handed:
		assert_true(wind.get(key) is float, "the Wind node's " + key)


## The woods wear their .tres but for the wind's uniforms.
func test_the_woods_draw_what_their_tres_say() -> void:
	var t := Map3DLayerTrees.new()
	add_child_autofree(t)
	_assert_material_holds(t._material(), "tree_sway", 9)
	_assert_material_holds(t._card_material(), "tree_card", 9)
	assert_ne(t.material, Map3DLayerTrees.CARD_MAT, "a copy: the wind never writes the .tres")


func test_the_waters_draw_what_their_tres_say() -> void:
	var v := _view()
	_assert_material_holds(v.sea_material(), "water_sea")
	var river := v.river_material()
	if river != null:
		_assert_material_holds(river, "water_river")
		var sea := load("res://scenes/map3d/materials/water_sea.tres") as ShaderMaterial
		for k: String in RIVER_FROM_SEA:
			assert_eq(river.get_shader_parameter(k), sea.get_shader_parameter(RIVER_FROM_SEA[k]),
				"the river's %s is the sea's %s: one water" % [k, RIVER_FROM_SEA[k]])


## The roads and trails wear their look but for their drawn width in metres
## (the geometry's), their packed textures and their px scaled; the bridges
## stand under the world's own Bridges node in their stone.
func test_the_roads_and_bridges_draw_what_their_tres_say() -> void:
	var v := _view()
	for pair: Array in [["Roads", Map3DLayerRoads.ROAD_MAT], ["Trails", Map3DLayerRoads.TRAIL_MAT]]:
		var mesh := v.line_mesh(String(pair[0]))
		if mesh == null:
			continue
		var live := mesh.surface_get_material(0) as ShaderMaterial
		var look := pair[1] as ShaderMaterial
		for u: Dictionary in look.shader.get_shader_uniform_list():
			var name := String(u["name"])
			if name in ["width_m", "width_px", "lift_px", "px_per_dist", "surface", "surface_nrm"] \
					or look.get_shader_parameter(name) == null:
				continue
			assert_eq(live.get_shader_parameter(name), look.get_shader_parameter(name), "%s.%s" % [pair[0], name])
	var bridges := v.world().get_node("Bridges") as MeshInstance3D
	assert_not_null(bridges, "the world's own Bridges node")
	assert_eq(bridges.get_parent(), v.world(), "never a node made beside it")


## Every line's live material is its look .tres but for what the code owns:
## its px values scaled to the SubViewport, its render order.
func test_the_lines_draw_what_their_tres_say() -> void:
	var v := _view()
	for pair: Array in [["Kingdoms", Map3DLayerLines.KINGDOM_INK], ["KingdomHalo", Map3DLayerLines.KINGDOM_HALO],
			["KingdomBand", Map3DLayerLines.KINGDOM_BAND], ["Seams", Map3DLayerLines.SEAM]]:
		var mesh := v.line_mesh(String(pair[0]))
		if mesh == null:
			continue
		var live := mesh.surface_get_material(0) as ShaderMaterial
		var look := pair[1] as ShaderMaterial
		for u: Dictionary in look.shader.get_shader_uniform_list():
			var name := String(u["name"])
			if name in Map3DLayerLines.PX_PARAMS or name == "px_per_dist" or look.get_shader_parameter(name) == null:
				continue
			assert_eq(live.get_shader_parameter(name), look.get_shader_parameter(name), "%s.%s" % [pair[0], name])
		var s := v.context().viewport_px_scale()
		for k: String in Map3DLayerLines.PX_PARAMS:
			assert_almost_eq(float(live.get_shader_parameter(k)), float(look.get_shader_parameter(k)) * s, 0.0001,
				"%s.%s, scaled" % [pair[0], k])


func test_no_script_reads_a_key_that_went_to_the_editor() -> void:
	for dir: String in ["res://scripts/map3d", "res://scripts/ui", "res://scripts/engine", "res://tools/map3d"]:
		for f: String in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string(dir.path_join(f))
			for prefix: String in GONE:
				assert_false(text.contains('"%s' % prefix), "%s reads a %s* key, which is the editor's now" % [f, prefix])


func _assert_material_holds(live: ShaderMaterial, key: String, at_least := 10) -> void:
	assert_not_null(live, key)
	var authored := load("res://scenes/map3d/materials/%s.tres" % key) as ShaderMaterial
	var owned: Array = CODE_OWNED[key]
	var checked := 0
	for u: Dictionary in authored.shader.get_shader_uniform_list():
		var name := String(u["name"])
		if name in owned:
			continue
		var want: Variant = authored.get_shader_parameter(name)
		if want == null:
			continue
		checked += 1
		assert_eq(live.get_shader_parameter(name), want,
			"%s.%s: the .tres says %s, the game drew %s — set in code?" % [key, name, want,
				live.get_shader_parameter(name)])
	assert_gte(checked, at_least, key + ": the guard compared the material's look")
