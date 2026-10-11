extends GutTest
## R13 (owner batch 2026-10-12): the rename moved user:// to a new directory;
## the old one's save, config and settings are copied once, never overwritten.

const RunDir := preload("res://tests/run_dir.gd")

var _old: String
var _new: String


func before_each() -> void:
	var base := RunDir.dir("migration")
	_old = base.path_join("old")
	_new = base.path_join("new")
	for d in [_old, _new]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(d.path_join(f)))


func _write(dir: String, name: String, text: String) -> void:
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(dir: String, name: String) -> String:
	return FileAccess.get_file_as_string(dir.path_join(name))


func test_copies_a_missing_file() -> void:
	_write(_old, "save.json", "old save")
	var copied := UserDirMigration.copy_missing(_old, _new, PackedStringArray(["save.json", "config.json"]))
	assert_eq(Array(copied), ["save.json"])
	assert_eq(_read(_new, "save.json"), "old save")
	assert_true(FileAccess.file_exists(_old.path_join("save.json")), "copy, never move")


func test_leaves_an_existing_file_untouched() -> void:
	_write(_old, "save.json", "old save")
	_write(_new, "save.json", "new save")
	var copied := UserDirMigration.copy_missing(_old, _new, PackedStringArray(["save.json"]))
	assert_eq(copied.size(), 0)
	assert_eq(_read(_new, "save.json"), "new save")


func test_no_old_dir_is_a_no_op() -> void:
	var copied := UserDirMigration.copy_missing(_old.path_join("absent"), _new, PackedStringArray(["save.json"]))
	assert_eq(copied.size(), 0)
	assert_false(FileAccess.file_exists(_new.path_join("save.json")))
