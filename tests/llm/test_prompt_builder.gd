extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_parse_prompt_lists_actions_and_schema() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var p := PromptBuilder.parse_prompts("cut taxes by one", r, s, data)
	assert_string_contains(p["system"], "TAX_RATE_ADJUST")
	assert_string_contains(p["system"], "court_reaction")
	assert_string_contains(p["system"], "JSON")
	assert_string_contains(p["user"], "cut taxes by one")

func test_briefing_prompt_carries_personas_and_report() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["grain"] = 10.0
	var r := TickEngine.new(data).advance(s)
	var p := PromptBuilder.briefing_prompts(r, s)
	assert_string_contains(p["system"], "Aldwin Reeve")
	assert_string_contains(p["user"], "grain")

func test_parse_prompt_lists_event_choices_and_promise_rule() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	s.pending_event = {"event_id": "ev_01", "title_key": "event_ev_01", "voice": "template",
		"choices": [{"choice_id": "accept", "label": "Accept them with thanks"}]}
	var p := PromptBuilder.parse_prompts("take the geese", r, s, data)
	assert_string_contains(p["system"], "EVENT_CHOICE")
	assert_string_contains(p["system"], "accept")
	assert_string_contains(p["system"], "promise_code")
