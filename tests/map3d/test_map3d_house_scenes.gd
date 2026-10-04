extends GutTest
## Every house type is a SCENE (owner 2026-10-04: 每个房屋的模型为什么不是一个
## 场景): assets/3D/buildings/<type>/<type>.tscn inherits its .glb and gives
## each surface its house_surface.gdshader material in the editor, and the map
## draws exactly those materials, adding only the Houses node's tints and the
## weather to its own copies.

const SuiteData := preload("res://tests/suite_data.gd")
const HOUSE_SHADER := preload("res://scripts/map3d/house_surface.gdshader")

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_every_type_names_a_scene_that_inherits_its_glb() -> void:
	for type: String in repo.map3d_houses:
		var path := GameArt.path(GameArt.HOUSE_MODELS, type)
		assert_eq(path.get_extension(), "tscn", type + " is drawn from its scene, not the bare .glb: " + path)
		if not FileAccess.file_exists(path):
			fail_test(type + " has no scene at " + path)
			continue
		var text := FileAccess.get_file_as_string(path)
		var glb := path.get_basename() + ".glb"
		assert_true(text.contains('path="%s"' % glb) and text.contains("instance=ExtResource("),
			type + "'s scene inherits " + glb + " (New Inherited Scene), so a re-export carries over")


func test_every_surface_wears_a_house_material_set_in_its_scene() -> void:
	for type: String in repo.map3d_houses:
		var model := Map3DAssetCache.house_model(GameArt.path(GameArt.HOUSE_MODELS, type))
		if model.is_empty():
			fail_test(type + " has no mesh in its scene")
			continue
		var mats: Array = model["materials"]
		assert_eq(mats.size(), (model["mesh"] as Mesh).get_surface_count(), type + ": a material per surface")
		for i in mats.size():
			var mat := mats[i] as ShaderMaterial
			var where := "%s surface %d" % [type, i]
			if mat == null or mat.shader != HOUSE_SHADER:
				fail_test(where + " is drawn by house_surface.gdshader")
				continue
			var tex := mat.get_shader_parameter("albedo_tex") as Texture2D
			assert_not_null(tex, where + " has its texture")
			if tex != null:
				assert_false(tex.resource_path.contains("::"),
					where + "'s texture is a file beside the .glb, not one embedded in it: " + tex.resource_path)
			assert_has([0, 1, 2], int(mat.get_shader_parameter("role")), where + "'s role is untinted, wall or roof")
			assert_eq(int(mat.get_shader_parameter("wall_count")), 0,
				where + " carries no tints of its own: the editor shows the house as built")


func test_the_textures_import_as_basis_universal_with_mipmaps() -> void:
	var seen := {}
	for type: String in repo.map3d_houses:
		var model := Map3DAssetCache.house_model(GameArt.path(GameArt.HOUSE_MODELS, type))
		for mat: Variant in model.get("materials", []):
			if not (mat is ShaderMaterial):
				continue
			for key: String in ["albedo_tex", "normal_tex"]:
				var tex := (mat as ShaderMaterial).get_shader_parameter(key) as Texture2D
				if tex != null and not tex.resource_path.contains("::"):
					seen[tex.resource_path] = true
	assert_gt(seen.size(), 0, "the house textures were found")
	for path: String in seen:
		var cf := ConfigFile.new()
		assert_eq(cf.load(path + ".import"), OK, path + " has its .import")
		assert_eq(int(cf.get_value("params", "compress/mode", -1)), 4,
			path + " is Basis Universal, GPU-compressed like the textures the .glb embedded")
		assert_true(bool(cf.get_value("params", "mipmaps/generate", false)), path + " has mipmaps")


func test_the_map_draws_a_copy_of_the_scenes_materials_with_the_tints() -> void:
	var model := Map3DAssetCache.house_model(GameArt.path(GameArt.HOUSE_MODELS, "cottage_a"))
	var walls := PackedVector3Array([Vector3.ONE, Vector3(0.9, 0.8, 0.7)])
	var roofs := PackedVector3Array([Vector3.ONE])
	var made: Array = []
	var drawn := Map3DHouseMaterials.tinted(model["mesh"], model["materials"], walls, roofs,
		{"weather_on": 1.0}, made)
	var mats: Array = model["materials"]
	assert_eq(made.size(), mats.size(), "a copy of every surface's material")
	for i in mats.size():
		var scene_mat := mats[i] as ShaderMaterial
		var mat := drawn.surface_get_material(i) as ShaderMaterial
		assert_ne(mat, scene_mat, "surface %d is the layer's own copy, never the scene's" % i)
		assert_eq(mat.get_shader_parameter("albedo_tex"), scene_mat.get_shader_parameter("albedo_tex"),
			"surface %d keeps the scene's texture" % i)
		assert_eq(mat.get_shader_parameter("role"), scene_mat.get_shader_parameter("role"),
			"surface %d keeps the scene's role" % i)
		assert_eq(int(mat.get_shader_parameter("wall_count")), 2, "the Houses node's wall tints")
		assert_eq(float(mat.get_shader_parameter("weather_on")), 1.0, "the weather is laid on the copy")
		assert_eq(int(scene_mat.get_shader_parameter("wall_count")), 0, "the scene's material is untouched")
