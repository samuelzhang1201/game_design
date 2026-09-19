extends GutTest
## The 3D map's look as editor-visible assets (spec 2026-09-20 §2): each
## material a .tres holding its shader, textures and render priority — never
## a tuned number, which stays in data/*.csv and is bound at load — with
## committed 512 px preview textures for a checkout without the git-ignored
## full-resolution ones.

const MATERIALS := {
	"border_line": "res://scripts/map3d/border_line.gdshader",
	"road_line": "res://scripts/map3d/road_line.gdshader",
	"water_river": "res://scripts/map3d/water_river.gdshader",
	"water_sea": "res://scripts/map3d/water_sea.gdshader",
	"cloud_deck": "res://scripts/map3d/cloud_deck.gdshader",
	"cloud_shadow": "res://scripts/map3d/cloud_shadow.gdshader",
	"settlement_ring": "res://scripts/map3d/settlement_ring.gdshader",
	"selection_ring": "res://scripts/map3d/settlement_ring.gdshader",
}
const PREVIEWS := ["rocky_trail_02_alb_ht", "rocky_trail_02_nrm_rgh", "medieval_blocks_03_alb_ht",
	"medieval_blocks_03_nrm_rgh", "cloud_shape"]
## The only shader parameters a .tres may carry: its LOOK ASSETS (the textures
## and the switch that says one is there). Every other parameter is a tuned
## number, which lives in data/*.csv and is bound at load.
const ASSET_PARAMS := ["surface", "surface_nrm", "has_surface", "ripples", "shape"]


func test_each_material_is_its_shader() -> void:
	for name: String in MATERIALS:
		var mat := load("res://scenes/map3d/materials/%s.tres" % name) as ShaderMaterial
		assert_not_null(mat, name)
		assert_eq(mat.shader.resource_path, MATERIALS[name], name)
	assert_ne((load("res://scenes/map3d/materials/cloud_deck.tres") as ShaderMaterial).shader,
		(load("res://scenes/map3d/materials/cloud_shadow.tres") as ShaderMaterial).shader,
		"two cloud shaders, never one (the Compatibility alpha-scissor trap)")
	assert_true(load("res://scenes/map3d/materials/bridge_stone.tres") is StandardMaterial3D)


func test_the_previews_are_committed_and_small() -> void:
	for name: String in PREVIEWS:
		var tex := load("res://assets/map3d_preview/%s.png" % name) as Texture2D
		assert_not_null(tex, name)
		assert_lte(maxi(tex.get_width(), tex.get_height()), 512, name)


func test_no_material_carries_a_tuned_number() -> void:
	for name: String in MATERIALS:
		var text := FileAccess.get_file_as_string("res://scenes/map3d/materials/%s.tres" % name)
		for line: String in text.split("\n"):
			if not line.begins_with("shader_parameter/"):
				continue
			var param := line.get_slice("=", 0).trim_prefix("shader_parameter/").strip_edges()
			assert_true(param in ASSET_PARAMS, "%s: %s is CSV's, not the .tres's" % [name, param])
	var road := FileAccess.get_file_as_string("res://scenes/map3d/materials/road_line.tres")
	assert_true(road.contains("map3d_preview/rocky_trail_02_alb_ht.png"))


func test_a_views_materials_are_its_own_copies() -> void:
	Game.start_campaign(42)
	var root := Node3D.new()
	root.set_meta("map3d_world", {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
		"pack_px": [2560, 929], "sea_y": 5.0})
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, "user://test_map3d_look_world.tscn")
	root.free()
	var a := Map3DView.create(Game.data, "user://test_map3d_look_world.tscn")
	var b := Map3DView.create(Game.data, "user://test_map3d_look_world.tscn")
	for v: Map3DView in [a, b]:
		v.size = Vector2(800, 450)
		add_child_autofree(v)
		v.activate()
	assert_ne(a.sea_material(), b.sea_material())
	assert_eq(a.sea_material().shader, b.sea_material().shader, "one compiled shader")
	var road := a.line_mesh("Roads").surface_get_material(0) as ShaderMaterial
	assert_eq(road.get_shader_parameter("tile_m"), Game.data.bal("map3d_road_tile_m"))
	assert_not_null(road.get_shader_parameter("surface"), "a texture always: full or preview")
