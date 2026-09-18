extends GutTest

class FakeClient:
	extends Node
	signal completed(ok: bool, text: String)
	var canned_ok := false
	var canned_text := ""
	## Counts requests so a test can assert an API call did NOT happen —
	## needed since event stories must never reach a model.
	var calls := 0
	func request_completion(_s: String, _u: String, _m: String, _j: bool) -> void:
		calls += 1
		completed.emit.call_deferred(canned_ok, canned_text)

var data: DataRepository

# Script-level (not function-local): GDScript lambdas capture local variables
# by value, so a reassignment like `func(res): got = res` inside a lambda
# would not be visible to the enclosing function once it's a local var.
# Reassigning a member variable through the implicit `self` does propagate.
var got: Dictionary = {}

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_parse_path_validates_model_output() -> void:
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}]})
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	got = {}
	v.parse_player_text("lower taxes", r, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_eq(got["actions"][0].action_code, "TAX_RATE_ADJUST")

func test_parse_bad_model_output_reports_error_not_crash() -> void:
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = "I think you should raise taxes, sire!"
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	got = {}
	v.parse_player_text("lower taxes", r, s, data, func(res): got = res)
	await wait_frames(3)
	assert_false(got["ok"])
	assert_ne(got["error"], "")

func test_submit_free_text_conversational_ride_along_replies() -> void:
	# "Marshal, who are you" parses to no action; the minister the player
	# named answers in character instead of the court staying silent — the
	# speaker is chosen BEFORE the single order call (spec 2026-09-09 §4.3),
	# so the narrative comes back in that persona's voice.
	Game.start_campaign(42)
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"narrative": "Ser Brandt of Harrow, my lord.",
		"impacts": {"actions": [],
		"court_reaction": {"addressed": ["char_marshal"], "tone": "neutral"}}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	got = {}
	Game.submit_free_text("Marshal, who are you?", func(res): got = res)
	await wait_frames(4)
	assert_true(got["ok"])
	assert_eq(got["executed"], [])
	assert_true(got.has("reply"), "conversational text carries a reply")
	assert_eq(String(got["reply"]["speaker_id"]), "char_marshal")
	assert_ne(String(got["reply"]["text"]), "")

func test_submit_free_text_consult_gets_in_character_reply() -> void:
	# "how is my army?" parses to COUNCIL_CONSULT (the free ask-for-advice
	# action): the consulted minister must answer in character, not the
	# canned outcome template (user report 2026-08-30). The Marshal is chosen
	# before the call from council_seats.csv `topics` ("army").
	Game.start_campaign(42)
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"narrative": "Soft, my lord, but drilling.",
		"impacts": {"actions":
		[{"action_code": "COUNCIL_CONSULT", "params": {}, "target": "marshal"}]}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	got = {}
	Game.submit_free_text("how is my army?", func(res): got = res)
	await wait_frames(4)
	assert_true(got["ok"])
	assert_eq(got["executed"].size(), 1, "the consult still executes")
	assert_true(got.has("reply"), "the consulted minister answers")
	assert_eq(String(got["reply"]["speaker_id"]), "char_marshal",
		"the consult's target seat answers")

func test_voice_event_never_calls_the_model_whatever_the_voice_value() -> void:
	var s := GameState.new_campaign(data, 42)
	for tier in ["template", "mini", "flagship"]:
		var fake := FakeClient.new()
		fake.canned_ok = true
		fake.canned_text = "MODEL WORDS"
		add_child_autofree(fake)
		var v := Voicer.new(fake)
		add_child_autofree(v)
		var ev := {"event_id": "ev_01", "title_key": "event_ev_01",
			"voice": tier, "choices": []}
		got = {}
		v.voice_event(ev, s, data, func(res): got = res)
		await wait_frames(3)
		assert_true(got["ok"], tier)
		assert_false(got["degraded"], tier + ": authored prose cannot degrade")
		assert_ne(String(got["text"]), "", tier)
		assert_false(String(got["text"]).contains("MODEL WORDS"),
			tier + ": no model text may reach an event scene")
		assert_eq(fake.calls, 0, tier + ": no API call")

func test_voice_event_serves_the_authored_scene() -> void:
	var fake := FakeClient.new()
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var ev := {"event_id": "ev_01", "title_key": "event_ev_01", "choices": []}
	got = {}
	v.voice_event(ev, s, data, func(res): got = res)
	await wait_frames(3)
	assert_eq(String(got["text"]), String(data.event_scenes["ev_01"]),
		"the scene is exactly what RANDOM_EVENTS.md says")

func test_voice_event_marks_an_unauthored_scene_rather_than_inventing_one() -> void:
	var fake := FakeClient.new()
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	got = {}
	v.voice_event({"event_id": "ev_nonexistent", "choices": []}, s, data,
		func(res): got = res)
	await wait_frames(3)
	assert_string_contains(String(got["text"]), "missing scene",
		"a gap in the story document is visible, never papered over")
	assert_eq(fake.calls, 0)

## The two-part order call (spec 2026-09-09 §4): narrative and impacts in ONE
## request, validated before anything reaches the caller.
func test_order_returns_both_parts_through_one_call() -> void:
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"narrative": "The rolls are cut.", "impacts": {"actions":
		[{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}],
		"world": [], "court_reaction": {}}})
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	got = {}
	v.order("lower taxes", "char_steward", r, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_eq(fake.calls, 1, "one call carries narrative and impacts")
	assert_eq(got["narrative"], "The rolls are cut.")
	assert_eq(got["actions"][0].action_code, "TAX_RATE_ADJUST")
