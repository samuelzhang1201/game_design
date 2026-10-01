extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

const PITCH_KEYS := ["grain_ration", "build_granary", "raise_tax", "tithe_church",
	"ease_tax", "harsh_justice", "endow_church", "raise_levies", "quiet_rumors", "build_road"]

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()

func test_reply_templates_exist_for_every_pitch() -> void:
	var keys := {}
	for t in data.templates:
		keys[String(t["key"])] = true
	for pk in PITCH_KEYS:
		assert_true(keys.has("reply_" + pk), "missing reply_" + pk)
	for k in ["council_summary_open", "council_summary_decision", "council_summary_idle"]:
		assert_true(keys.has(k), "missing " + k)

func test_no_spoken_numbers_in_new_templates() -> void:
	# R7: replies/summaries carry no numeric placeholders or digits
	for t in data.templates:
		var key := String(t["key"])
		if key.begins_with("reply_") or key.begins_with("council_summary"):
			assert_false("{value}" in String(t["text"]), key)
			var text := String(t["text"])
			var has_digit := false
			for c in text:
				if c >= "0" and c <= "9":
					has_digit = true
					break
			assert_false(has_digit, key + " contains a literal digit: " + text)

func test_round_table_portrait_resolves() -> void:
	assert_true(FileAccess.file_exists("res://assets/2D/portraits/cast/round_table.png"))
	var p := CharacterPortrait.instantiate_for("round_table")
	add_child_autofree(p)
	assert_string_contains(p.scene_file_path, "round_table.tscn")
