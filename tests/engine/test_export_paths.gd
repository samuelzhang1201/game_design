extends GutTest
## An exported game reads everything through res://: the res:// tree is the
## pack, and a ProjectSettings.globalize_path()'d path points beside the
## executable, where nothing is (perf audit 2026-10-02: the woods, the fields
## and the trees would have vanished from a shipped build). Game code never
## globalizes a path it READS; only the build's own writers may.

## Scripts that globalize a path to WRITE the build (never run in a shipped game).
const WRITERS := ["res://scripts/map3d/map3d_layer_bake.gd"]


func _scripts(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_scripts(dir.path_join(d), out)


func test_game_code_reads_through_res_never_a_path_on_disk() -> void:
	var files: Array[String] = []
	_scripts("res://scripts", files)
	assert_gt(files.size(), 100, "the game's scripts were found")
	for path in files:
		if path in WRITERS:
			continue
		var src := FileAccess.get_file_as_string(path)
		var line_no := 0
		for line in src.split("\n"):
			line_no += 1
			var code := line.split("#")[0]
			assert_false(code.contains("globalize_path("),
				"%s:%d reads through a path on disk, which an exported game cannot" % [path, line_no])
