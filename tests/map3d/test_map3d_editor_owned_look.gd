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
	"map3d_bridge_max_view_m"]


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


func _assert_material_holds(live: ShaderMaterial, key: String) -> void:
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
	assert_gt(checked, 10, key + ": the guard compared the material's look")
