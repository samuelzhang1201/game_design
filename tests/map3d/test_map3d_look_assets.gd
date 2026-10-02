extends GutTest
## The 3D map's look as editor-visible assets (spec 2026-09-20 §2): each
## material a .tres of its shader, with committed 512 px preview textures for
## a checkout without the git-ignored full-resolution ones. Since 2026-10-02
## (owner: the look lives in the editor) a CONVERTED material carries its
## tuned numbers too — test_map3d_editor_owned_look.gd holds those — and the
## rest still hold only their look assets until they are converted.

const RunDir := preload("res://tests/run_dir.gd")
const MATERIALS := {
	"border_line": "res://scripts/map3d/border_line.gdshader",
	"road_line": "res://scripts/map3d/road_line.gdshader",
	"trail_line": "res://scripts/map3d/road_line.gdshader",
	"water_river": "res://scripts/map3d/water_river.gdshader",
	"water_sea": "res://scripts/map3d/water_sea.gdshader",
	"cloud_deck": "res://scripts/map3d/cloud_deck.gdshader",
	"cloud_shadow": "res://scripts/map3d/cloud_shadow.gdshader",
	"settlement_ring": "res://scripts/map3d/settlement_ring.gdshader",
	"selection_ring": "res://scripts/map3d/settlement_ring.gdshader",
	"precip_fall": "res://scripts/map3d/precip_fall.gdshader",
	"precip_drop": "res://scripts/map3d/precip_drop.gdshader",
}
const PREVIEWS := ["rocky_trail_02_alb_ht", "rocky_trail_02_nrm_rgh", "medieval_blocks_03_alb_ht",
	"medieval_blocks_03_nrm_rgh", "cloud_shape"]
## The only shader parameters a .tres may carry: its LOOK ASSETS (the textures
## and the switch that says one is there). Every other parameter is a tuned
## number, which lives in data/*.csv and is bound at load.
const ASSET_PARAMS := ["surface", "surface_nrm", "has_surface", "ripples", "shape"]


func test_each_material_is_its_shader() -> void:
	for key: String in MATERIALS:
		var mat := load("res://scenes/map3d/materials/%s.tres" % key) as ShaderMaterial
		assert_not_null(mat, key)
		assert_eq(mat.shader.resource_path, MATERIALS[key], key)
	assert_ne((load("res://scenes/map3d/materials/cloud_deck.tres") as ShaderMaterial).shader,
		(load("res://scenes/map3d/materials/cloud_shadow.tres") as ShaderMaterial).shader,
		"two cloud shaders, never one (the Compatibility alpha-scissor trap)")
	assert_true(load("res://scenes/map3d/materials/bridge_stone.tres") is StandardMaterial3D)


func test_the_previews_are_committed_and_small() -> void:
	for key: String in PREVIEWS:
		var tex := load("res://assets/3D/terrain/textures_preview/%s.png" % key) as Texture2D
		assert_not_null(tex, key)
		assert_lte(maxi(tex.get_width(), tex.get_height()), 512, key)


## The materials whose tuned numbers live in the .tres (owner 2026-10-02):
## test_map3d_editor_owned_look.gd holds them; the others are not yet converted.
const EDITOR_OWNED := ["water_sea", "water_river", "road_line", "trail_line", "cloud_deck", "cloud_shadow"]


func test_an_unconverted_material_carries_no_tuned_number() -> void:
	for key: String in MATERIALS:
		if key in EDITOR_OWNED:
			continue
		var text := FileAccess.get_file_as_string("res://scenes/map3d/materials/%s.tres" % key)
		for line: String in text.split("\n"):
			if not line.begins_with("shader_parameter/"):
				continue
			var param := line.get_slice("=", 0).trim_prefix("shader_parameter/").strip_edges()
			assert_true(param in ASSET_PARAMS, "%s: %s is CSV's, not the .tres's" % [key, param])
	var road := FileAccess.get_file_as_string("res://scenes/map3d/materials/road_line.tres")
	assert_true(road.contains("3D/terrain/textures_preview/rocky_trail_02_alb_ht.png"))


## A pack ships no picture (CLAUDE.md): every world_*.png is DATA — ids,
## distances, a height field, blend weights — read as an Image or sampled for
## its exact values. The 3D map hands two of them to 3D shaders (the sea's
## distance field, the cell index under the manor tint), and the editor's
## "detect 3D" then re-imports them as VRAM COMPRESSED, which scrambles manor
## ids and bands the sea (found in Task 22's editor pass). Every one of them
## stays lossless with that detection off.
const DATA_BITMAPS := ["index_texture", "province_texture", "biome_texture", "sea_texture",
	"cell_texture", "relief_texture", "settlement_texture"]


func test_a_packs_bitmaps_are_data_and_are_never_recompressed() -> void:
	for id: String in Game.data.maps:
		var row: Dictionary = Game.data.maps[id]
		var paths: Array = []
		for col: String in DATA_BITMAPS:
			if String(row.get(col, "")) != "":
				paths.append(String(row[col]))
		var weights := String(row.get("biome_weights", ""))
		for i in (4 if weights != "" else 0):
			paths.append("%s_%d.png" % [weights, i])
		for path: String in paths:
			if not FileAccess.file_exists(path + ".import"):
				continue
			var text := FileAccess.get_file_as_string(path + ".import")
			assert_true(text.contains("compress/mode=0"), path + " must stay lossless")
			assert_true(text.contains("detect_3d/compress_to=0"),
				path + ": the editor must never re-import a DATA bitmap as VRAM compressed")


func test_a_views_materials_are_its_own_copies() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.set_meta("map3d_world", {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
		"pack_px": [2560, 929], "sea_y": 5.0})
	var packed := PackedScene.new()
	packed.pack(root)
	var path := RunDir.dir("map3d_look_assets").path_join("test_map3d_look_world.tscn")
	ResourceSaver.save(packed, path)
	root.free()
	var a := Map3DView.create(Game.data, path)
	var b := Map3DView.create(Game.data, path)
	for v: Map3DView in [a, b]:
		v.size = Vector2(800, 450)
		add_child_autofree(v)
		v.activate()
	assert_ne(a.sea_material(), b.sea_material())
	assert_eq(a.sea_material().shader, b.sea_material().shader, "one compiled shader")
	var road := a.line_mesh("Roads").surface_get_material(0) as ShaderMaterial
	assert_eq(road.get_shader_parameter("tile_m"), Map3DLayerRoads.ROAD_MAT.get_shader_parameter("tile_m"))
	assert_not_null(road.get_shader_parameter("surface"), "a texture always: full or preview")


## The kept world (Map3DWorldCache) must not leak into the next file: this file
## builds two views over the same fixture, so one of them hands its world back
## to the cache on free (final review 2026-09-20).
func after_all() -> void:
	Map3DWorldCache.clear()
