extends GutTest
## assets/ holds ART, never a scene (owner 2026-10-04: 把所有场景都要放到场景
## folder中去，按照类别归类，assets下面只存放美术资产，不要放场景): a model's
## .glb stays in assets/, its scene is in scenes/models/; the Terrain3D build's
## world scene is scenes/map3d/worlds/<map>.tscn while its data stays in the
## pack's map3d_dir; the tools' scenes are scenes/tools/.


func test_no_scene_lies_under_assets() -> void:
	var found: Array[String] = []
	_walk("res://assets", found)
	assert_eq(found, [] as Array[String], "scenes belong in scenes/, by kind, not in assets/")


func test_every_packs_built_world_scene_is_under_scenes() -> void:
	for file in DirAccess.get_files_at(DataRepository.MAP3D_WORLDS):
		if file.ends_with(".tscn"):
			var id := file.get_basename()
			assert_true(DirAccess.dir_exists_absolute(DataRepository.map3d_dir_of(id)),
				file + "'s data is in its pack's map3d_dir")


func _walk(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tscn") or f.ends_with(".scn"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if sub != "model_wip":
			_walk(dir.path_join(sub), out)
