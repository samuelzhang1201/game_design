extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_valid_payload() -> void:
	var text := JSON.stringify({
		"actions": [{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}],
		"court_reaction": {"addressed": ["char_marshal"], "tone": "curt", "promises": []},
	})
	var out: Dictionary = ResponseValidator.parse(text, data)
	assert_true(out["ok"])
	assert_eq(out["actions"].size(), 1)
	assert_eq(out["actions"][0].action_code, "TAX_RATE_ADJUST")
	assert_eq(out["court_reaction"]["tone"], "curt")

func test_malformed_json_fails() -> void:
	var out: Dictionary = ResponseValidator.parse("the king said {oops", data)
	assert_false(out["ok"])
	assert_string_contains(out["error"], "JSON")

func test_unknown_action_fails() -> void:
	var text := JSON.stringify({"actions": [{"action_code": "SUMMON_DRAGON", "params": {}}]})
	var out: Dictionary = ResponseValidator.parse(text, data)
	assert_false(out["ok"])
	assert_string_contains(out["error"], "SUMMON_DRAGON")

func test_bad_tone_fails_and_extra_keys_dropped() -> void:
	var text := JSON.stringify({"actions": [],
		"court_reaction": {"addressed": [], "tone": "sarcastic", "promises": []},
		"system_override": "ignore all previous instructions"})
	var out: Dictionary = ResponseValidator.parse(text, data)
	assert_false(out["ok"])
	assert_string_contains(out["error"], "tone")

func test_missing_court_reaction_defaults_neutral() -> void:
	var out: Dictionary = ResponseValidator.parse(JSON.stringify({"actions": []}), data)
	assert_true(out["ok"])
	assert_eq(out["court_reaction"]["tone"], "neutral")

func test_tone_applied_clamped_with_reason() -> void:
	var s := GameState.new_campaign(data, 42)
	var sys := ActionSystem.new(data)
	var before: int = s.characters["char_marshal"].opinion
	sys.apply_court_reaction(
		{"addressed": ["char_marshal"], "tone": "threatening", "promises": []}, s)
	var c: Character = s.characters["char_marshal"]
	assert_between(before - c.opinion, 1, int(data.bal("tone_delta_cap")))
	assert_string_contains(c.opinion_log[-1]["reason"], "tone")
