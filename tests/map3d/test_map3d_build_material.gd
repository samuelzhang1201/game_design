extends GutTest
## The built terrain's material (tools/map3d/build_terrain.gd apply_material).
## 2026-10-04: the build wrote its shader parameters BEFORE switching dual
## scaling on, so the dual-scale uniforms did not exist yet and were saved as
## null — the shader then ran its own defaults (the cliff, at 0.3x, from
## 100-170 m) and the grass was never dual-scaled.

const BuildTerrain := preload("res://tools/map3d/build_terrain.gd")
const DUAL := ["dual_scale_far", "dual_scale_near", "dual_scale_reduction",
	"dual_scale_texture", "tri_scale_reduction"]


func test_apply_material_keeps_the_dual_scale_values() -> void:
	var cam := Camera3D.new()
	var terrain := Terrain3D.new()
	add_child_autofree(cam)
	add_child_autofree(terrain)
	terrain.set_camera(cam)
	await wait_process_frames(1)
	var mat: Terrain3DMaterial = terrain.material
	BuildTerrain.apply_material(mat)
	assert_true(mat.dual_scaling)
	var stored: Dictionary = mat.get("_shader_parameters")
	for key: String in DUAL:
		assert_eq(stored.get(StringName(key)), BuildTerrain.SHADER_PARAMS[key],
			"%s is saved as written, never null" % key)


## Every committed build: no shader parameter saved as null (a null falls
## back to the shader's own default without a word).
func test_no_committed_build_saves_a_null_shader_parameter() -> void:
	var base := DataRepository.MAP3D_WORLDS
	var checked := 0
	for file in DirAccess.get_files_at(base):
		if not file.ends_with(".tscn"):
			continue
		var path := base.path_join(file)
		checked += 1
		for line in FileAccess.get_file_as_string(path).split("\n"):
			assert_false(line.begins_with("&\"") and line.strip_edges().trim_suffix(",").ends_with(": null"),
				"%s: %s" % [path, line])
	if checked == 0:
		pass_test("no committed build in this checkout")


## The committed build's tiles are build_terrain.gd's TEXTURES (by id): the
## cliff's 533 m keeps the size the owner approved while the shader's default
## dual scaling drew it at 0.3x (2026-10-04).
func test_committed_tiles_follow_the_textures_table() -> void:
	var path := BuildTerrain.root() + "/terrain_assets.tres"  # the default pack's build
	if not FileAccess.file_exists(path):
		pass_test("no committed build in this checkout")
		return
	var scales: Array[float] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("uv_scale = "):
			scales.append(float(line.trim_prefix("uv_scale = ")))
	assert_eq(scales.size(), BuildTerrain.TEXTURES.size())
	for t in mini(scales.size(), BuildTerrain.TEXTURES.size()):
		assert_almost_eq(scales[t], 1.0 / float(BuildTerrain.TEXTURES[t][1]), 1e-6,
			"%s's tile" % BuildTerrain.TEXTURES[t][0])
