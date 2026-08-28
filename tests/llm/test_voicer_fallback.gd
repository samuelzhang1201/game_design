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
