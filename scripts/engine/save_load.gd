class_name SaveLoad
extends RefCounted

## Why the last load_game returned null: "missing", "corrupt" or "outdated"
## (a save older than GameState.MIN_SAVE_VERSION); "" after a good load.
static var last_error := ""

static func save_game(state: GameState, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveLoad: cannot write " + path)
		return false
	f.store_string(JSON.stringify(state.to_dict(), "\t", true, true))
	return true

static func load_game(path: String) -> GameState:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "missing"
		push_error("SaveLoad: cannot read " + path)
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed is Dictionary:
		last_error = "corrupt"
		push_error("SaveLoad: corrupt save " + path)
		return null
	if int((parsed as Dictionary).get("version", 1)) < GameState.MIN_SAVE_VERSION:
		last_error = "outdated"
		return null
	last_error = ""
	return GameState.from_dict(parsed)

static func state_hash(state: GameState) -> String:
	var canonical := JSON.stringify(state.to_dict(), "", true, true)
	return canonical.sha256_text()
