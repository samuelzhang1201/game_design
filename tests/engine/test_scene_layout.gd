extends GutTest
## assets/ holds ART, never a scene (owner 2026-10-04: 把所有场景都要放到场景
## folder中去，按照类别归类，assets下面只存放美术资产，不要放场景): a model's
## .glb stays in assets/, its scene is in scenes/models/. The one exception is
## the Terrain3D build's generated world.tscn, which build_pack.sh writes into
## the pack's map3d_dir.

const GENERATED := "res://assets/3D/terrain/%s/world.tscn"


func test_no_scene_lies_under_assets() -> void:
	var found: Array[String] = []
	_walk("res://assets", found)
	var stray: Array[String] = []
	for path in found:
		var pack := path.trim_prefix("res://assets/3D/terrain/").get_slice("/", 0)
		if path != GENERATED % pack:
			stray.append(path)
	assert_eq(stray, [] as Array[String], "scenes belong in scenes/, by kind, not in assets/")


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
