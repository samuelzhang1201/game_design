extends GutTest

class FakeClient:
	extends Node
	signal completed(ok: bool, text: String)
	var canned_ok := false
	var canned_text := ""
	func request_completion(_s: String, _u: String, _m: String, _j: bool) -> void:
		completed.emit.call_deferred(canned_ok, canned_text)

var data: DataRepository

# Script-level (not function-local): GDScript lambdas capture local variables
# by value, so a reassignment like `func(res): got = res` inside a lambda
# would not be visible to the enclosing function once it's a local var.
# Reassigning a member variable through the implicit `self` does propagate.
var got: Dictionary = {}

# For the overlapping-call test below; same by-value-capture reasoning as `got`.
var got_a: Dictionary = {}
var got_b: Dictionary = {}
var calls_a := 0
var calls_b := 0

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_briefing_falls_back_to_template_on_failure() -> void:
	var fake := FakeClient.new()
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	got = {}
	v.voice_briefing(r, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_true(got["degraded"])
	assert_gt(got["lines"].size(), 0)  # template lines

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

func test_converse_returns_in_character_reply() -> void:
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = "I am Aldwin Reeve, my lord, your Chancellor these eleven years."
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	got = {}
	v.converse("char_chancellor", "who are you", s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_false(got["degraded"])
	assert_eq(got["speaker_id"], "char_chancellor")
	assert_eq(got["speaker"], "Aldwin Reeve")
	assert_string_contains(got["text"], "Chancellor")

func test_converse_falls_back_to_template_on_failure() -> void:
	var fake := FakeClient.new()  # canned_ok=false: the "offline"/error path
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	got = {}
	v.converse("char_chancellor", "who are you", s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_true(got["degraded"])
	# converse_fallback templates all name the speaker.
	assert_string_contains(got["text"], "Aldwin Reeve")

func test_submit_free_text_conversational_ride_along_replies() -> void:
	# "who are you" parses to no action; the addressed minister answers in
	# character instead of the court staying silent (Game.submit_free_text).
	Game.start_campaign(42)
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions": [],
		"court_reaction": {"addressed": ["char_marshal"], "tone": "neutral"}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	got = {}
	Game.submit_free_text("who are you", func(res): got = res)
	await wait_frames(4)
	assert_true(got["ok"])
	assert_eq(got["executed"], [])
	assert_true(got.has("reply"), "conversational text carries a reply")
	assert_eq(String(got["reply"]["speaker_id"]), "char_marshal")
	assert_ne(String(got["reply"]["text"]), "")

func test_overlapping_briefing_calls_both_fire_exactly_once() -> void:
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = "hear ye, the harvest is good"
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	got_a = {}
	got_b = {}
	calls_a = 0
	calls_b = 0
	v.voice_briefing(r, s, data, func(res): got_a = res; calls_a += 1)
	# Second call arrives while the first is still in flight (FakeClient's
	# completed signal is call_deferred, so no frame has passed yet). The
	# busy guard must resolve it immediately with a degraded fallback rather
	# than let it cross-fire with the first call's one-shot listener.
	v.voice_briefing(r, s, data, func(res): got_b = res; calls_b += 1)
	assert_eq(calls_b, 1)
	assert_true(got_b["ok"])
	assert_true(got_b["degraded"])
	assert_gt(got_b["lines"].size(), 0)
	await wait_frames(3)
	assert_eq(calls_a, 1)
	assert_true(got_a["ok"])
	assert_false(got_a["degraded"])
	assert_eq(got_a["lines"][0]["text"], "hear ye, the harvest is good")

func test_voice_event_template_tier_no_client_call() -> void:
	var fake := FakeClient.new()
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var ev := {"event_id": "ev_01", "title_key": "event_ev_01", "voice": "template", "choices": []}
	got = {}
	v.voice_event(ev, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_ne(String(got["text"]), "")

func test_voice_event_mini_falls_back_on_failure() -> void:
	var fake := FakeClient.new()  # canned_ok=false -> failure path
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var ev := {"event_id": "ev_01", "title_key": "event_ev_01", "voice": "mini", "choices": []}
	got = {}
	v.voice_event(ev, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_true(got["degraded"])
	assert_ne(String(got["text"]), "")
