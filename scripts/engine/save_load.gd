class_name SaveLoad
extends RefCounted

static func save_game(state: GameState, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveLoad: cannot write " + path)
		return false
	f.store_string(JSON.stringify(state.to_dict(), "\t", true))
	return true

static func load_game(path: String) -> GameState:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SaveLoad: cannot read " + path)
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("SaveLoad: corrupt save " + path)
		return null
	return GameState.from_dict(parsed)

static func state_hash(state: GameState) -> String:
	var canonical := JSON.stringify(state.to_dict(), "", true)
	return canonical.sha256_text()
