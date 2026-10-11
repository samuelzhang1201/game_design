class_name UserDirMigration
extends RefCounted
## The game's user:// directory is named after config/name, so the rename to
## "Beyond the King's Words" left a player's save, key file and settings in
## the old "Crown and Council" directory. Game._ready copies what the new
## directory lacks, once; it never moves and never overwrites (R13, owner
## batch 2026-10-12).

const LEGACY_NAME := "Crown and Council"


## The old name's user-data directory, a sibling of the current one.
static func legacy_dir() -> String:
	return OS.get_user_data_dir().get_base_dir().path_join(LEGACY_NAME)


## Copies each of `files` that exists in `from_dir` and not in `to_dir`;
## returns the names copied. Absent `from_dir` copies nothing.
static func copy_missing(from_dir: String, to_dir: String, files: PackedStringArray) -> PackedStringArray:
	var copied := PackedStringArray()
	for name: String in files:
		var src := from_dir.path_join(name)
		var dst := to_dir.path_join(name)
		if not FileAccess.file_exists(src) or FileAccess.file_exists(dst):
			continue
		var bytes := FileAccess.get_file_as_bytes(src)
		if FileAccess.get_open_error() != OK:
			continue
		# Through a temp file: a failed write must never leave a truncated
		# target, which would block every later retry.
		var tmp := dst + ".part"
		var out := FileAccess.open(tmp, FileAccess.WRITE)
		if out == null:
			continue
		out.store_buffer(bytes)  # returns void in this build; the error is read off the file
		var write_error := out.get_error()
		out.close()
		if write_error != OK or DirAccess.rename_absolute(tmp, dst) != OK:
			DirAccess.remove_absolute(tmp)
			continue
		copied.append(name)
	return copied
