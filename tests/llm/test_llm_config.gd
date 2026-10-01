extends GutTest

const RunDir := preload("res://tests/run_dir.gd")
const FIXTURE_ENV := "res://tests/fixtures/test_env"
var _fixture_json := RunDir.dir("llm_config").path_join("test_llm_config.json")

# Member, not local: GDScript lambdas capture locals by value.
var _refusals := 0

func before_each() -> void:
	var f := FileAccess.open(_fixture_json, FileAccess.WRITE)
	f.store_string(JSON.stringify({"model_parse": "json-wins-parse"}))
	f = null

func test_env_overlay_sets_key_and_models() -> void:
	var cfg := OpenAIClient.load_config(FIXTURE_ENV, "user://does_not_exist.json")
	assert_eq(cfg["api_key"], "sk-test-not-a-real-key")
	assert_eq(cfg["model_voice"], "test-model-1")
	assert_eq(cfg["model_flagship"], "test-model-1")
	assert_eq(int(cfg["llm_max_output_tokens"]), 123)
	# OPENAI_API_NAME is an informational label only (never sent to the API).
	assert_eq(cfg["api_name"], "test-project")
	assert_eq(cfg["llm_reasoning_effort"], "low")
	assert_true(cfg["llm_store_requests"])

func test_json_overrides_env_per_field() -> void:
	var cfg := OpenAIClient.load_config(FIXTURE_ENV, _fixture_json)
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
	assert_eq(cfg["api_name"], "")
	# Unset by default: non-reasoning models reject the parameter.
	assert_eq(cfg["llm_reasoning_effort"], "")
	assert_false(cfg["llm_store_requests"], "storing is opt-in")

## reasoning_effort must reach reasoning models (else gpt-5-family returns
## empty dialogue) and must NOT reach others (they 400 on the parameter) —
## both failure modes verified against the live API 2026-08-30.
func test_reasoning_effort_sent_only_to_reasoning_models() -> void:
	var c: OpenAIClient = autofree(OpenAIClient.new())
	c._config = {"llm_max_output_tokens": 600, "llm_reasoning_effort": "minimal"}
	var with_it: Dictionary = JSON.parse_string(c._build_body("s", "u", "gpt-5-mini", false))
	assert_eq(String(with_it.get("reasoning_effort", "")), "minimal")
	assert_true(with_it.has("max_completion_tokens"), "modern token cap parameter")
	assert_false(with_it.has("max_tokens"), "legacy parameter must not be sent")
	var without: Dictionary = JSON.parse_string(
		c._build_body("s", "u", "gpt-4.1-mini-2025-04-14", false))
	assert_false(without.has("reasoning_effort"))
	# store is opt-in (absent here), sent only when configured on.
	assert_false(without.has("store"))
	c._config["llm_store_requests"] = true
	var stored: Dictionary = JSON.parse_string(
		c._build_body("s", "u", "gpt-4.1-mini-2025-04-14", false))
	assert_true(bool(stored.get("store", false)))
	c._config["llm_reasoning_effort"] = ""
	var unset: Dictionary = JSON.parse_string(c._build_body("s", "u", "gpt-5-mini", false))
	assert_false(unset.has("reasoning_effort"))

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
		await wait_process_frames(2)
	assert_eq(_refusals, 2, "calls beyond the cap are refused in-fiction")
	Game.next_tick()
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	_refusals = 0
	Game.submit_free_text("hold court", func(res):
		if not res["ok"] and "no more orders" in String(res["error"]):
			_refusals += 1)
	await wait_process_frames(2)
	assert_eq(_refusals, 0, "cap resets on a new tick")

## The two-part order call has its own tier (spec 2026-09-09 §4.3).
func test_order_tier_reads_its_own_key_and_falls_back_to_llm_model() -> void:
	var cfg := OpenAIClient.load_config(FIXTURE_ENV, "user://does_not_exist.json")
	assert_eq(cfg["model_order"], "test-order-model")
	var bare := OpenAIClient.load_config("res://no_such.env", "user://no_such.json")
	assert_eq(bare["model_order"], bare["model_parse"], "defaults to the parse tier")
