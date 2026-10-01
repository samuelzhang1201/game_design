extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()

func test_parse_prompt_lists_actions_and_schema() -> void:
	var s := SuiteData.campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var p := PromptBuilder.parse_prompts("cut taxes by one", r, s, data)
	assert_string_contains(p["system"], "TAX_RATE_ADJUST")
	assert_string_contains(p["system"], "court_reaction")
	assert_string_contains(p["system"], "JSON")
	assert_string_contains(p["user"], "cut taxes by one")

## Review finding 2026-09-01: the persona sheet now carries the speaker's
## knowledge — and ONLY theirs. The isolation is structural: a secret a
## character does not know never enters their context window at all.
func test_order_prompt_carries_only_the_speakers_knowledge() -> void:
	var s := SuiteData.campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var steward := PromptBuilder.order_prompts("hm", "char_steward", r, s, data)
	assert_string_contains(steward["system"], "What you know and believe:")
	assert_string_contains(steward["system"], "skimmed the treasury",
		"the steward knows the graft secret, so her sheet carries it")
	var marshal := PromptBuilder.order_prompts("hm", "char_marshal", r, s, data)
	assert_false(marshal["system"].contains("skimmed the treasury"),
		"a secret never enters a non-knower's context window")

func test_order_prompt_carries_the_characters_own_replies() -> void:
	var s := SuiteData.campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	AgentMemory.remember(data, s, "char_marshal", "char_marshal",
		"The border holds, my lord.", ["char_marshal"], "war_room", 2)
	var p := PromptBuilder.order_prompts("hm", "char_marshal", r, s, data)
	assert_string_contains(p["system"],
		'You replied, privately: "The border holds, my lord."')

func test_parse_prompt_lists_event_choices_and_promise_rule() -> void:
	var s := SuiteData.campaign(data, 42)
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
	var s := SuiteData.campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	# Seed 42's first tick can itself roll a pending event (see
	# tests/ui/test_court_screen.gd) — force the empty condition explicitly
	# rather than relying on incidental non-firing.
	s.pending_event = {}
	var p := PromptBuilder.parse_prompts("cut taxes by one", r, s, data)
	assert_false(p["system"].contains("EVENT_CHOICE"))

## The two-part order call (spec 2026-09-09 §4): one persona, the action
## catalog, the ledger's writable fields, and the rule binding narrative to
## impacts.
func test_order_prompt_carries_persona_catalog_and_the_correlation_rule() -> void:
	var s := SuiteData.campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var p := PromptBuilder.order_prompts("raise the levies", "char_marshal", r, s, data)
	assert_string_contains(p["system"], "Ser Brandt of Harrow")
	assert_string_contains(p["system"], "LEVY_RAISE")
	assert_string_contains(p["system"], "\"narrative\"")
	assert_string_contains(p["system"], "\"impacts\"")
	assert_string_contains(p["system"], "metrics.grain")
	assert_string_contains(p["system"], "narrative claims no change")
	assert_eq(p["user"], "raise the levies")

func test_order_prompt_with_no_speaker_uses_the_herald() -> void:
	var s := SuiteData.campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var p := PromptBuilder.order_prompts("hm", "", r, s, data)
	assert_string_contains(p["system"], "herald")
