extends GutTest
## Static layers baked by the build (spec 2026-09-20 §2): rivers, roads,
## trails and bridges never move, so tools/map3d/bake_layers.gd saves their
## meshes per step set; the view uses them only when every input matches.

const DIR := "user://bake_fixture"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_each() -> void:
	Game.start_campaign(42)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "/layers"))
	var root := Node3D.new()
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, DIR + "/world.tscn")
	root.free()
	var f := FileAccess.open(DIR + "/rivers.json", FileAccess.WRITE)
	f.store_string('{"rivers": [{"code": "a", "points": [[0, 0, 10, 6, 0], [500, 0, 9, 40, 1]]}]}')
	f.close()


func after_each() -> void:
	Map3DWorldCache.clear()
	var abs := ProjectSettings.globalize_path(DIR)
	for f: String in DirAccess.get_files_at(abs + "/layers"):
		DirAccess.remove_absolute(abs + "/layers/" + f)
	for f: String in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs + "/" + f)


func _bake() -> void:
	var ctx := Map3DContext.new(Game.data, WORLD)
	var row := Map3DQuality.row(Game.data, "high")
	ctx.quality = row
	var rv := Map3DLayerRivers.arrays_for(ctx, DIR)
	var rd := Map3DLayerRoads.plan_for(ctx, rv["courses"])
	var meshes := {"rivers": Map3DLayerBake.mesh_of(rv["arrays"]),
		"roads": Map3DLayerBake.mesh_of(rd["Roads"]), "trails": Map3DLayerBake.mesh_of(rd["Trails"]),
		"bridges": Map3DLayerRoads.bridge_mesh(ctx, rd["bridges"])}
	assert_eq(Map3DLayerBake.save(DIR, row, Map3DLayerBake.key(Game.data, DIR, row), meshes), OK)


func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, DIR + "/world.tscn")
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v


func test_the_step_sets() -> void:
	assert_eq(Map3DLayerBake.step_set(Map3DQuality.row(Game.data, "high")), "r100_v100")
	assert_eq(Map3DLayerBake.step_set(Map3DQuality.row(Game.data, "medium")), "r140_v150")
	assert_eq(Map3DLayerBake.step_set(Map3DQuality.row(Game.data, "low")), "r200_v250")


func test_the_key_follows_its_inputs() -> void:
	var row := Map3DQuality.row(Game.data, "high")
	var k1 := Map3DLayerBake.key(Game.data, DIR, row)
	assert_eq(Map3DLayerBake.key(Game.data, DIR, row), k1, "stable")
	var was: float = Game.data.balance["map3d_bridge_abut_m"]
	Game.data.balance["map3d_bridge_abut_m"] = float(was) + 1.0
	assert_ne(Map3DLayerBake.key(Game.data, DIR, row), k1)
	Game.data.balance["map3d_bridge_abut_m"] = was
	assert_ne(Map3DLayerBake.key(Game.data, DIR, Map3DQuality.row(Game.data, "low")), k1)


func test_a_view_uses_a_matching_bake() -> void:
	_bake()
	var v := _view()
	var rivers := v.viewport().get_node("Rivers") as MeshInstance3D
	assert_true(rivers.mesh.resource_path.ends_with(".res"), "the baked rivers")
	assert_eq(rivers.material_override, v.river_material())
	assert_true(v.line_mesh("Roads").resource_path.ends_with(".res"), "the baked roads")


func test_a_stale_bake_is_ignored() -> void:
	_bake()
	var was: float = Game.data.balance["map3d_bridge_abut_m"]
	Game.data.balance["map3d_bridge_abut_m"] = float(was) + 1.0
	var v := _view()
	var rivers := v.viewport().get_node("Rivers") as MeshInstance3D
	assert_eq(rivers.mesh.resource_path, "", "built at runtime")
	Game.data.balance["map3d_bridge_abut_m"] = was


## The runtime key cannot see the geometry code: a change to it must bump FORMAT.
func test_the_geometry_code_is_the_one_the_format_names() -> void:
	var text := ""
	for path: String in Map3DLayerBake.GEOMETRY_SOURCES:
		assert_true(FileAccess.file_exists(path), path)
		text += FileAccess.get_file_as_string(path)
	assert_eq(text.md5_text(), Map3DLayerBake.GEOMETRY_MD5,
		"geometry code changed: update GEOMETRY_MD5, and if the BAKED VERTICES can differ "
		+ "bump Map3DLayerBake.FORMAT too and re-run tools/map3d/bake_layers.gd "
		+ "(an editor-only edit — a @tool line, preview code, a comment — updates the md5 alone)")
