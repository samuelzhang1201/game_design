class_name DataRepository
extends RefCounted

static var last_error: String = ""

var balance: Dictionary = {}
var traits: Dictionary = {}
var seats: Dictionary = {}
var actions: Dictionary = {}
var founding: Array[Dictionary] = []
var roles: Array[Dictionary] = []
var relationships: Array[Dictionary] = []
var regions: Dictionary = {}
var locations: Dictionary = {}
var templates: Array[Dictionary] = []
var signatures: Array[Dictionary] = []
var events: Array[Dictionary] = []
var events_by_id: Dictionary = {}
var event_choices: Array[Dictionary] = []
var world_rules: Dictionary = {}
var claim_types: Dictionary = {}

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
	if not _load_if_present(dir + "/policy_actions_domain.csv", ["action_code"],
			func(r): actions[r["action_code"]] = r):
		return false
	if not _load_if_present(dir + "/founding_council.csv", ["id", "display_name", "seat"],
			func(r): founding.append(r)):
		return false
	if not _load_if_present(dir + "/roles.csv", ["id", "display_name", "seat"],
			func(r): roles.append(r)):
		return false
	if not _load_if_present(dir + "/relationships.csv",
			["from_id", "to_id", "rel_type", "sentiment", "reason"],
			func(r): relationships.append(r)):
		return false
	if not _load_if_present(dir + "/world_rules.csv",
			["rule_code", "kind", "verdict"],
			func(r): world_rules[r["rule_code"]] = r):
		return false
	if not _load_if_present(dir + "/claim_types.csv", ["claim_type", "label"],
			func(r): claim_types[r["claim_type"]] = r):
		return false
	if not _load_if_present(dir + "/regions.csv", ["region_code", "label"],
			func(r): regions[r["region_code"]] = r):
		return false
	if not _load_if_present(dir + "/locations.csv",
			["location_code", "region_code", "label", "kind", "occupants"],
			func(r): locations[r["location_code"]] = r):
		return false
	if not _load_if_present(dir + "/templates.csv", ["key", "trait", "text"],
			func(r): templates.append(r)):
		return false
	if not _load_if_present(dir + "/action_signatures.csv",
			["action_code", "variant", "centralism", "militarism", "orthodoxy",
			"tax_incidence", "expansionism"],
			func(r): signatures.append(r)):
		return false
	if not _load_if_present(dir + "/events.csv",
			["event_id", "category", "trigger", "weight", "cooldown_ticks", "once",
			"voice", "title_key"],
			func(r): events.append(r)):
		return false
	for row in events:
		events_by_id[row["event_id"]] = row
	if not _load_if_present(dir + "/event_choices.csv",
			["event_id", "choice_id", "label", "centralism", "militarism", "orthodoxy",
			"tax_incidence", "expansionism", "effects", "requires"],
			func(r): event_choices.append(r)):
		return false
	return true

## Loads a live-gameplay CSV that is nonetheless allowed to be genuinely
## absent (future saves/mods may not ship it yet). A missing file is not an
## error. A present-but-malformed file is: unlike the old _load_optional,
## this cannot silently swallow a parse failure — it fails loud through
## parse_csv's required_cols/last_error contract, same as the always-required
## files above.
func _load_if_present(path: String, required_cols: Array, sink: Callable) -> bool:
	if not FileAccess.file_exists(path):
		return true
	var rows := DataRepository.parse_csv(path, required_cols)
	if DataRepository.last_error != "":
		return false
	for r in rows:
		sink.call(r)
	return true

func bal(key: String) -> float:
	assert(balance.has(key), "balance.csv missing key: " + key)
	return balance[key]
