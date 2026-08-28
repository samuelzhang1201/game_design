extends GutTest

const FIXTURE_ENV := "res://tests/fixtures/test_env"
const FIXTURE_JSON := "user://test_llm_config.json"

# Member, not local: GDScript lambdas capture locals by value.
var _refusals := 0

func before_each() -> void:
	var f := FileAccess.open(FIXTURE_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify({"model_parse": "json-wins-parse"}))
	f = null

func test_env_overlay_sets_key_and_models() -> void:
	var cfg := OpenAIClient.load_config(FIXTURE_ENV, "user://does_not_exist.json")
	assert_eq(cfg["api_key"], "sk-test-not-a-real-key")
	assert_eq(cfg["model_voice"], "test-model-1")
	assert_eq(cfg["model_flagship"], "test-model-1")
	assert_eq(int(cfg["llm_max_output_tokens"]), 123)

func test_json_overrides_env_per_field() -> void:
	var cfg := OpenAIClient.load_config(FIXTURE_ENV, FIXTURE_JSON)
	assert_eq(cfg["model_parse"], "json-wins-parse")   # json wins
	assert_eq(cfg["model_voice"], "test-model-1")      # env survives where json silent

func test_force_offline_env_var_wins() -> void:
	# run_tests.sh exports CC_FORCE_OFFLINE=1, so even with a key present
	# offline_mode must be forced true — this is the no-live-calls guarantee.
	assert_eq(OS.get_environment("CC_FORCE_OFFLINE"), "1",
		"suite must run under CC_FORCE_OFFLINE=1")
	var cfg := OpenAIClient.load_config(FIXTURE_ENV, "user://does_not_exist.json")
	assert_true(cfg["offline_mode"])

func test_missing_files_yield_offline_defaults() -> void:
	var cfg := OpenAIClient.load_config("res://no_such.env", "user://no_such.json")
	assert_true(cfg["offline_mode"])
	assert_eq(cfg["api_key"], "")

func test_prompt_cap_refuses_without_api_call() -> void:
	Game.start_campaign(42)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions": []})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var cap := int(Game.data.bal("prompt_calls_per_tick"))
	_refusals = 0
	for i in cap + 2:
		Game.submit_free_text("hold court", func(res):
			if not res["ok"] and "no more orders" in String(res["error"]):
				_refusals += 1)
		await wait_frames(2)
	assert_eq(_refusals, 2, "calls beyond the cap are refused in-fiction")
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	_refusals = 0
	Game.submit_free_text("hold court", func(res):
		if not res["ok"] and "no more orders" in String(res["error"]):
			_refusals += 1)
	await wait_frames(2)
	assert_eq(_refusals, 0, "cap resets on a new tick")
