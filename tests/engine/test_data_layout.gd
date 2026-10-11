extends GutTest
## The data folders (spec 2026-10-11-data-folders-by-scene): data/tables.csv
## and the disk agree, a balance key lives in one file, the engine reads no
## screen's key, and no code names a table by a path the index does not give.

const DATA := "res://data"
## Keys under screens/ that the engine's own look helpers (map and manor
## palettes, the economy view's relief and light, the province card) read.
const ENGINE_LOOK_KEYS := [
	"map_altitude_gain", "map_light_x", "map_light_y", "map_lod_town_pop",
	"map_lod_town_scale", "map_lod_village_scale", "map_manor_alpha",
	"map_manor_crown_deep", "map_manor_foreign_pale", "map_manor_house_sat",
	"map_manor_house_val", "map_manor_saturation", "map_manor_shade_levels",
	"map_manor_shade_step", "map_manor_value", "map_relief_max", "map_relief_min",
	"map_relief_strength", "map_terrain_blend", "province_card_max_towns",
	"ui_war_table",
]
const CODE_DIRS := ["res://scripts", "res://tools", "res://tests"]
const CODE_EXTS := ["gd", "gdshader", "py", "sh"]

func _index() -> Dictionary:
	var out := {}
	for r in DataRepository.parse_csv(DATA + "/tables.csv", ["folder", "table"]):
		out[String(r["table"])] = String(r["folder"])
	return out

## Every file under `dir` (relative to it) whose extension is in `exts`.
func _walk(dir: String, exts: Array, rel := "") -> Array[String]:
	var out: Array[String] = []
	var here := dir if rel == "" else dir + "/" + rel
	for sub in DirAccess.get_directories_at(here):
		if sub.begins_with("."):
			continue
		out.append_array(_walk(dir, exts, sub if rel == "" else rel + "/" + sub))
	for f in DirAccess.get_files_at(here):
		if exts.has(f.get_extension()):
			out.append(f if rel == "" else rel + "/" + f)
	return out

func _data_csvs() -> Array[String]:
	return _walk(DATA, ["csv"]).filter(func(p: String) -> bool: return not p.begins_with("maps/"))

func test_every_csv_on_disk_is_indexed() -> void:
	var index := _index()
	assert_gt(index.size(), 0, "data/tables.csv has rows")
	var problems: Array[String] = []
	for p in _data_csvs():
		if p == "tables.csv" or p.get_file() == "balance.csv":
			continue
		var table := p.get_file().get_basename()
		if not index.has(table):
			problems.append("%s is on disk but not in tables.csv" % p)
		elif index[table] + "/" + table + ".csv" != p:
			problems.append("%s sits outside its indexed folder %s" % [p, index[table]])
	for table: String in index:
		if not FileAccess.file_exists(DataRepository.table_path(DATA, table)):
			problems.append("tables.csv lists %s but %s is missing" % [table, DataRepository.table_path(DATA, table)])
	var rows := DataRepository.parse_csv(DATA + "/tables.csv", ["folder", "table"])
	assert_eq(rows.size(), index.size(), "no table is listed twice in tables.csv")
	assert_true(problems.is_empty(), "\n".join(problems))

func test_balance_files_sit_in_indexed_folders() -> void:
	var folders := DataRepository.table_folders(DATA)
	var stray: Array[String] = []
	for p in _data_csvs():
		if p.get_file() == "balance.csv" and not folders.has(p.get_base_dir()):
			stray.append(p)
	assert_true(stray.is_empty(), "balance.csv outside an indexed folder: %s" % [stray])

func test_no_balance_key_repeats() -> void:
	var merged := DataRepository.load_balance(DATA)
	assert_eq(DataRepository.last_error, "")
	assert_gt(merged.size(), 0)

func _engine_source() -> String:
	var parts: PackedStringArray = []
	for p in _walk("res://scripts/engine", ["gd"]):
		parts.append(FileAccess.get_file_as_string("res://scripts/engine/" + p))
	return "\n".join(parts)

func test_engine_reads_no_screen_key() -> void:
	var src := _engine_source()
	var leaks: Array[String] = []
	for folder in DataRepository.table_folders(DATA):
		if not folder.begins_with("screens/"):
			continue
		var path := "%s/%s/balance.csv" % [DATA, folder]
		if not FileAccess.file_exists(path):
			continue
		for r in DataRepository.parse_csv(path, ["key", "value"]):
			var key := String(r["key"])
			if ENGINE_LOOK_KEYS.has(key):
				continue
			var read := src.contains("\"%s\"" % key)
			if key.ends_with("_table"):  # MapPalette.table_key swaps it in for its base key
				read = read or src.contains("\"%s\"" % key.trim_suffix("_table"))
			if read:
				leaks.append("%s (%s/balance.csv)" % [key, folder])
	assert_true(leaks.is_empty(),
		"the engine reads screen keys; move each to its gameplay folder or list it in ENGINE_LOOK_KEYS:\n" + "\n".join(leaks))

## Every `data/<…>/<table>.csv` a file names must be the indexed path, and no
## file may name the old flat balance file at the data root.
func _stale_paths(root: String, rel_paths: Array[String], index: Dictionary) -> Array[String]:
	var rx := RegEx.create_from_string("\\bdata/((?:[a-z_]+/)*)([a-z0-9_]+)\\.csv")
	var out: Array[String] = []
	for rel in rel_paths:
		var text := FileAccess.get_file_as_string(root + "/" + rel)
		for m in rx.search_all(text):
			var folder := m.get_string(1).trim_suffix("/")
			var table := m.get_string(2)
			if table == "balance" and folder == "":
				out.append("%s/%s: %s" % [root, rel, m.get_string()])
			elif index.has(table) and folder != index[table]:
				out.append("%s/%s: %s (indexed in %s/)" % [root, rel, m.get_string(), index[table]])
	return out

func test_no_flat_data_paths_remain_in_code() -> void:
	var index := _index()
	var stale: Array[String] = []
	for root in CODE_DIRS:
		var files := _walk(root, CODE_EXTS).filter(func(p: String) -> bool: return not p.begins_with("fixtures/"))
		stale.append_array(_stale_paths(root, files, index))
	assert_true(stale.is_empty(), "\n".join(stale))
