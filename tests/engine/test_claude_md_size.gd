extends GutTest
## The root CLAUDE.md is read on every model call, so it holds only the rules
## that cut across modules; a subsystem's detail lives in the CLAUDE.md beside
## its code, which is read only when that code is. This holds both to a size,
## and every nested guide the root names to exist.

const ROOT := "res://CLAUDE.md"
const ROOT_MAX_CHARS := 20000
const NESTED_MAX_CHARS := 30000

func _chars(path: String) -> int:
	return FileAccess.get_file_as_string(path).length()

func _nested_guides() -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string("`([a-z0-9_/]+)/CLAUDE\\.md`")
	for m in re.search_all(FileAccess.get_file_as_string(ROOT)):
		var path := "res://%s/CLAUDE.md" % m.get_string(1)
		if not out.has(path):
			out.append(path)
	return out

func test_root_guide_stays_short() -> void:
	var n := _chars(ROOT)
	assert_gt(n, 0, "CLAUDE.md is missing")
	assert_lt(n, ROOT_MAX_CHARS,
		"CLAUDE.md is %d chars: move subsystem detail to its nested CLAUDE.md or spec" % n)

func test_root_names_its_nested_guides() -> void:
	assert_gt(_nested_guides().size(), 5, "the root's table of nested guides is gone")

func test_each_nested_guide_exists_and_stays_short() -> void:
	for path in _nested_guides():
		assert_true(FileAccess.file_exists(path), "%s is named by CLAUDE.md but missing" % path)
		var n := _chars(path)
		assert_lt(n, NESTED_MAX_CHARS,
			"%s is %d chars: write the rule as it stands, move history to the spec" % [path, n])

func test_each_topic_guide_a_nested_guide_names_exists() -> void:
	var re := RegEx.create_from_string("`([a-z0-9_/]+/guide/[a-z0-9_]+\\.md)`")
	for path in _nested_guides():
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			var guide := "res://%s" % m.get_string(1)
			assert_true(FileAccess.file_exists(guide), "%s names %s, which is missing" % [path, guide])
			assert_lt(_chars(guide), NESTED_MAX_CHARS, "%s is over the nested cap" % guide)
