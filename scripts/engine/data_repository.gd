class_name DataRepository
extends RefCounted

static var last_error: String = ""

var balance: Dictionary = {}
var traits: Dictionary = {}
var seats: Dictionary = {}
var actions: Dictionary = {}
var founding: Array[Dictionary] = []
var templates: Array[Dictionary] = []

## Parses a CSV with a header row into an Array of row Dictionaries.
## Returns [] and sets last_error if any row is shorter than required_cols
## or a file error occurs. Extra columns are kept; empty trailing lines skipped.
static func parse_csv(path: String, required_cols: Array) -> Array[Dictionary]:
	last_error = ""
	var out: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "cannot open %s" % path
		return []
	var header := f.get_csv_line()
	var row_num := 1
	while not f.eof_reached():
		var line := f.get_csv_line()
		row_num += 1
		if line.size() == 1 and line[0].strip_edges() == "":
			continue
		if line.size() < required_cols.size():
			last_error = "%s row %d: expected at least %d columns, got %d" % [
				path.get_file(), row_num, required_cols.size(), line.size()]
			return []
		var row := {}
		for i in header.size():
			row[header[i]] = line[i] if i < line.size() else ""
		out.append(row)
	return out

static func load_all(dir: String) -> DataRepository:
	var repo := DataRepository.new()
	if not repo._load(dir):
		return null
	return repo

func _load(dir: String) -> bool:
	var bal_rows := DataRepository.parse_csv(dir + "/balance.csv", ["key", "value"])
	if bal_rows.is_empty():
		return false
	for r in bal_rows:
		balance[r["key"]] = float(r["value"])
	var trait_rows := DataRepository.parse_csv(dir + "/character_traits.csv", ["trait_code"])
	if trait_rows.is_empty():
		return false
	for r in trait_rows:
		traits[r["trait_code"]] = r
	var seat_rows := DataRepository.parse_csv(dir + "/council_seats.csv", ["seat_code"])
	if seat_rows.is_empty():
		return false
	for r in seat_rows:
		seats[r["seat_code"]] = r
	var court_rows := DataRepository.parse_csv(dir + "/policy_actions_court_additions.csv", ["action_code"])
	if court_rows.is_empty():
		return false
	for r in court_rows:
		actions[r["action_code"]] = r
	_load_optional(dir + "/policy_actions_domain.csv", func(r): actions[r["action_code"]] = r)
	_load_optional(dir + "/founding_council.csv", func(r): founding.append(r))
	_load_optional(dir + "/templates.csv", func(r): templates.append(r))
	return true

func _load_optional(path: String, sink: Callable) -> void:
	if not FileAccess.file_exists(path):
		return
	for r in DataRepository.parse_csv(path, []):
		sink.call(r)

func bal(key: String) -> float:
	assert(balance.has(key), "balance.csv missing key: " + key)
	return balance[key]
