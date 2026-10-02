extends GutTest
## CSV guard: DataRepository.parse_csv only refuses a row with FEWER columns
## than the fields code actually reads (`required_cols`) — a row with MORE
## columns than the header (a stray unquoted comma splitting a notes field
## in two) parses "successfully" and just has its tail silently dropped,
## since parse_csv only ever indexes header.size() fields off the line. That
## bit twice: data/missive_art.csv's `board` row and data/balance.csv's
## `map3d_sun_yaw_deg` row. This scans every TOP-LEVEL data/*.csv (not
## data/maps/<id>/, whose pack tables are a different shape and are read by
## other code) with the same quote-aware line reader DataRepository uses
## (FileAccess.get_csv_line) and fails, naming file, line and field count,
## the moment a row's column count does not match its header's exactly.

func test_every_top_level_csv_row_matches_its_header_column_count() -> void:
	var dir := DirAccess.open("res://data")
	assert_not_null(dir, "res://data must be readable")
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".csv"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	assert_gt(names.size(), 0, "should find at least one top-level data/*.csv")
	var failures: Array[String] = []
	for n in names:
		failures.append_array(_mismatches("res://data/" + n))
	assert_true(failures.is_empty(), "\n".join(failures))


## Every line whose field count differs from the header's, as
## "<file> line <N>: <got> fields, header has <want>". data/marker_types.csv
## is the one top-level table with a leading `#`-comment block (its own
## bespoke reader in tools/import_azgaar.gd already skips such lines and
## only ever reads column 0), so a `#`-led line never counts as the header
## or as a data row here either — everywhere else a `#` has no special
## meaning, since no other top-level table uses it.
func _mismatches(path: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out.append("%s: cannot open" % path)
		return out
	var header: PackedStringArray = []
	var line_num := 0
	while not f.eof_reached():
		var line := f.get_csv_line()
		line_num += 1
		if _is_comment_or_blank(line):
			continue
		header = line
		break
	if header.is_empty():
		return out  # an empty or all-comment file: nothing to check
	var want := header.size()
	while not f.eof_reached():
		var line := f.get_csv_line()
		line_num += 1
		if _is_comment_or_blank(line):
			continue
		if line.size() != want:
			out.append("%s line %d: %d fields, header has %d" % [
				path.get_file(), line_num, line.size(), want])
	return out


func _is_comment_or_blank(line: PackedStringArray) -> bool:
	if line.is_empty():
		return true
	var first := line[0].strip_edges()
	if first == "" and line.size() == 1:
		return true  # a trailing blank line at EOF, not a data row
	return first.begins_with("#")


## The art a key wears is an ArtTable .tres picked in the inspector, never a
## res:// path in a CSV (owner 2026-10-02: 为什么把所有素材的对应关系写在csv里).
## maps.csv alone names files: a pack's own bitmaps and directories, data.
func test_no_top_level_csv_names_a_res_path_but_the_packs() -> void:
	for f: String in DirAccess.get_files_at("res://data"):
		if not f.ends_with(".csv") or f == "maps.csv":
			continue
		assert_false(FileAccess.get_file_as_string("res://data/" + f).contains("res://"),
			"%s names a res:// path: put the art in an ArtTable (GameArt)" % f)
