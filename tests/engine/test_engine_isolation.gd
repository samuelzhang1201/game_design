extends GutTest
## The engine is the simulation and must run headless (CLAUDE.md invariant
## 3; data_architecture_requirements.md §6 and R-12): nothing under
## scripts/engine/ may name a class declared under scripts/ui/ or
## scripts/llm/, nor touch the Game autoload. This is the "sim/ must not
## import presentation/ or llm/" rule as a test — a comment may mention
## them, code may not.

const ENGINE_DIR := "res://scripts/engine"
const FORBIDDEN_DIRS := ["res://scripts/ui", "res://scripts/llm"]

static func _scripts_in(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	out.sort()
	return out

## The class_name of every script in `dirs`.
static func _class_names(dirs: Array) -> PackedStringArray:
	var names := PackedStringArray()
	var re := RegEx.create_from_string("^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for dir: String in dirs:
		for path in _scripts_in(dir):
			for line in FileAccess.get_file_as_string(path).split("\n"):
				var m := re.search(line)
				if m != null:
					names.append(m.get_string(1))
	return names

## The line with its comment cut off; "" for a comment-only line.
static func _code_of(line: String) -> String:
	var s := line.strip_edges()
	if s.begins_with("#") or s.begins_with("##"):
		return ""
	var hash_at := line.find("#")
	return line if hash_at < 0 else line.substr(0, hash_at)

func test_the_engine_names_no_ui_or_llm_class_and_no_autoload() -> void:
	var names := _class_names(FORBIDDEN_DIRS)
	assert_gt(names.size(), 10, "the ui and llm folders declare classes")
	var alternation := "|".join(names)
	var re := RegEx.create_from_string("\\b(%s)\\b|\\bGame\\." % alternation)
	var offences: Array = []
	var engine := _scripts_in(ENGINE_DIR)
	assert_gt(engine.size(), 20, "the engine folder is populated")
	for path in engine:
		var n := 0
		for line in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var code := _code_of(line)
			if code == "":
				continue
			var m := re.search(code)
			if m != null:
				offences.append("%s:%d  %s" % [path.get_file(), n, m.get_string(0)])
	assert_eq(offences, [], "engine code reaching into ui/llm or the Game autoload")
