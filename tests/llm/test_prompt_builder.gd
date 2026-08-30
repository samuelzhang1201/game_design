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

func test_converse_prompt_carries_persona_and_speech_only_rule() -> void:
	var s := GameState.new_campaign(data, 42)
	var p := PromptBuilder.converse_prompts("char_marshal", "who are you", s, data)
	assert_string_contains(p["system"], "Ser Brandt of Harrow")
	assert_string_contains(p["system"], "House Harrow")
	assert_string_contains(p["system"], "Relationships:")
	assert_string_contains(p["system"], "you may only speak")
	# Realm facts ground answers like "how is my army?" in engine truth.
	s.metrics["army_quality"] = 47.0
	p = PromptBuilder.converse_prompts("char_marshal", "how is my army?", s, data)
	assert_string_contains(p["system"], "army_quality 47")
	assert_string_contains(p["system"], "treasury")
	assert_eq(p["user"], "how is my army?")

func test_parse_prompt_lists_event_choices_and_promise_rule() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	s.pending_event = {"event_id": "ev_01", "title_key": "event_ev_01", "voice": "template",
		"choices": [{"choice_id": "accept", "label": "Accept them with thanks"}]}
	var p := PromptBuilder.parse_prompts("take the geese", r, s, data)
	assert_string_contains(p["system"], "EVENT_CHOICE")
	assert_string_contains(p["system"], "accept")
	assert_string_contains(p["system"], "promise_code")

## Negative counterpart: with no pending_event, the parse prompt must not
## mention EVENT_CHOICE at all (it isn't a legal action_code in the catalog —
## see data/action_signatures.csv — so it can only ever appear via event_ctx,
## which is built solely when state.pending_event is non-empty).
func test_parse_prompt_omits_event_choice_when_no_pending_event() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	# Seed 42's first tick can itself roll a pending event (see
	# tests/ui/test_court_screen.gd) — force the empty condition explicitly
	# rather than relying on incidental non-firing.
	s.pending_event = {}
	var p := PromptBuilder.parse_prompts("cut taxes by one", r, s, data)
	assert_false(p["system"].contains("EVENT_CHOICE"))
