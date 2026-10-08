extends GutTest
## The army is read through ArmySystem.roster / regiment only (spec
## 2026-10-07-army-split-and-ground §2.4): the pack's regiments table is the
## split's input, never the live army.

const ALLOWED := ["res://scripts/engine/army_split.gd", "res://scripts/engine/data_repository.gd"]
const NEEDLES := ["world_table(\"military\", \"regiments\")", "repo.regiments", "data.regiments"]


func _scan(dir: String, out: Array) -> void:
	for f: String in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if f.ends_with(".gd") and not path in ALLOWED:
			var text := FileAccess.get_file_as_string(path)
			for n: String in NEEDLES:
				if text.contains(n):
					out.append("%s reads %s" % [path, n])
	for d: String in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)


func test_no_reader_of_the_pack_regiments() -> void:
	var out: Array = []
	_scan("res://scripts", out)
	_scan("res://tools", out)
	assert_eq(out, [], "\n".join(out))
