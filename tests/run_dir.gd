extends RefCounted
## This test RUN's own directory under user://. Godot names user:// after
## config/name, so it is ONE directory for every checkout of the project —
## the main one and every worktree — and two suites running at once shared
## every fixed user:// path: one run's after_each deleted the other's
## rivers.json between its write and its Map3DView load (2026-09-28, the
## river tests failing a different one each run). Every fixture a test
## removes again, and the suite's settings file, lives under here.
## tests/post_run.gd removes the run's directory. Nothing sweeps another
## run's: OS.is_process_running answers through waitpid, which only knows
## this process's own children, so it calls every other live suite dead.

const PREFIX := "gut_run_"


## The directory `user://gut_run_<pid>/<name>`, made.
static func dir(name: String) -> String:
	var d := root().path_join(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	return d


static func root() -> String:
	return "user://%s%d" % [PREFIX, OS.get_process_id()]


## Remove this run's directory.
static func sweep() -> void:
	_remove(ProjectSettings.globalize_path(root()))


static func _remove(abs_dir: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	for d: String in DirAccess.get_directories_at(abs_dir):
		_remove(abs_dir.path_join(d))
	for f: String in DirAccess.get_files_at(abs_dir):
		DirAccess.remove_absolute(abs_dir.path_join(f))
	DirAccess.remove_absolute(abs_dir)
