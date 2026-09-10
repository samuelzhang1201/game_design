extends GutTest
## Per-character conversational memory (spec D4, §4.3): what the player said,
## where, and who else heard it. No belief scoring here — remembering being
## told a thing is not the same as believing it (that is ClaimLedger's job).

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func test_new_campaign_starts_with_no_memories() -> void:
	assert_eq(state.agent_memory.size(), 0)
	assert_eq(AgentMemory.exchanges_for(state, "char_chancellor").size(), 0)

func test_remember_stores_what_was_said_and_who_heard_it() -> void:
	AgentMemory.remember(data, state, "char_chancellor",
		"you", "The granaries are full.", ["char_chancellor", "char_marshal"],
		"council_chamber", 4)
	var entries := AgentMemory.exchanges_for(state, "char_chancellor")
	assert_eq(entries.size(), 1)
	assert_eq(String(entries[0]["speaker"]), "you")
	assert_eq(String(entries[0]["text"]), "The granaries are full.")
	assert_eq(String(entries[0]["location"]), "council_chamber")
	assert_eq(int(entries[0]["tick"]), 4)
	assert_eq(entries[0]["audience"], ["char_chancellor", "char_marshal"],
		"a character knows whether they were told privately or in company")

func test_memory_is_per_character() -> void:
	AgentMemory.remember(data, state, "char_chancellor", "you", "A secret.",
		["char_chancellor"], "council_chamber", 4)
	assert_eq(AgentMemory.exchanges_for(state, "char_chancellor").size(), 1)
	assert_eq(AgentMemory.exchanges_for(state, "char_marshal").size(), 0,
		"the marshal was not in the room and remembers nothing")

func test_memory_caps_at_the_balance_value_keeping_the_newest() -> void:
	var cap := int(data.bal("memory_exchanges_kept"))
	for i in cap + 3:
		AgentMemory.remember(data, state, "char_chancellor", "you",
			"line %d" % i, ["char_chancellor"], "council_chamber", i)
	var entries := AgentMemory.exchanges_for(state, "char_chancellor")
	assert_eq(entries.size(), cap, "capped at memory_exchanges_kept")
	assert_eq(String(entries[entries.size() - 1]["text"]), "line %d" % (cap + 2),
		"the newest line survives")
	assert_eq(String(entries[0]["text"]), "line 3", "the oldest lines fall off the front")

func test_remember_ignores_an_unknown_character() -> void:
	AgentMemory.remember(data, state, "char_nobody", "you", "hello", [],
		"council_chamber", 1)
	assert_false(state.agent_memory.has("char_nobody"))

func test_remember_ignores_empty_text() -> void:
	AgentMemory.remember(data, state, "char_chancellor", "you", "   ", [],
		"council_chamber", 1)
	assert_eq(AgentMemory.exchanges_for(state, "char_chancellor").size(), 0)

func test_describe_for_is_prompt_ready_and_names_the_company() -> void:
	AgentMemory.remember(data, state, "char_chancellor", "you",
		"The granaries are full.", ["char_chancellor"], "council_chamber", 4)
	AgentMemory.remember(data, state, "char_chancellor", "you",
		"Raise the levies.", ["char_chancellor", "char_marshal"], "war_room", 5)
	var text := AgentMemory.describe_for(state, "char_chancellor")
	assert_string_contains(text, "The granaries are full.")
	assert_string_contains(text, "Raise the levies.")
	assert_string_contains(text, "privately", "a solo audience reads as private")
	assert_string_contains(text, "others present", "a shared audience says so")

func test_describe_for_is_empty_when_nothing_was_said() -> void:
	assert_eq(AgentMemory.describe_for(state, "char_marshal"), "")

## Review finding 2026-09-01: memory used to hold only the ruler's voice.
## Replies and other speakers now render under who actually said them.
func test_describe_for_renders_replies_and_other_speakers() -> void:
	AgentMemory.remember(data, state, "char_marshal", "you",
		"Hold the border.", ["char_marshal"], "war_room", 4)
	AgentMemory.remember(data, state, "char_marshal", "char_marshal",
		"It holds, my lord.", ["char_marshal"], "war_room", 4)
	AgentMemory.remember(data, state, "char_marshal", "char_chancellor",
		"The cost worries me.", ["char_marshal", "char_chancellor"], "war_room", 5)
	var text := AgentMemory.describe_for(state, "char_marshal")
	assert_string_contains(text, 'You were told, privately: "Hold the border."')
	assert_string_contains(text, 'You replied, privately: "It holds, my lord."')
	assert_string_contains(text,
		'Aldwin Reeve said, with others present: "The cost worries me."')

func test_memory_survives_save_round_trip() -> void:
	AgentMemory.remember(data, state, "char_chancellor", "you",
		"The granaries are full.", ["char_chancellor"], "council_chamber", 4)
	var restored := GameState.from_dict(state.to_dict())
	var entries := AgentMemory.exchanges_for(restored, "char_chancellor")
	assert_eq(entries.size(), 1)
	assert_eq(String(entries[0]["text"]), "The granaries are full.")
	assert_eq(String(entries[0]["location"]), "council_chamber")

func test_pre_feature_save_loads_with_no_memory() -> void:
	var d := state.to_dict()
	d.erase("agent_memory")
	var restored := GameState.from_dict(d)
	assert_not_null(restored, "old saves are not refused")
	assert_eq(restored.agent_memory.size(), 0)
