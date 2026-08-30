class_name OpenAIClient
extends Node

signal completed(ok: bool, text: String)

const CONFIG_PATH := "user://config.json"
const ENV_PATH := "res://.env"

## Config precedence: defaults -> res://.env (dev convenience, git-ignored)
## -> user://config.json (player override). CC_FORCE_OFFLINE=1 in the OS
## environment forces offline regardless (set by run_tests.sh so the test
## suite can never make live API calls even with a real .env present).
static func load_config(env_path: String = ENV_PATH,
		json_path: String = CONFIG_PATH) -> Dictionary:
	var cfg := {"api_key": "", "api_name": "", "model_parse": "gpt-5.6-luna",
		"model_voice": "gpt-5.6-terra", "model_flagship": "gpt-5.6-sol",
		"offline_mode": true, "llm_max_output_tokens": 600,
		"llm_reasoning_effort": "", "llm_store_requests": false}
	_overlay_env(cfg, env_path)
	_overlay_json(cfg, json_path)
	if String(cfg["api_key"]) == "" or OS.get_environment("CC_FORCE_OFFLINE") == "1":
		cfg["offline_mode"] = true
	return cfg

## Parses KEY=VALUE lines ('#' comments, blanks skipped). Recognized keys:
## OPENAI_API_KEY, OPENAI_API_NAME (informational label for which key/project
## this config is — logged/shown only, never sent to the API), LLM_MODEL
## (sets all three tiers), LLM_MODEL_PARSE/_VOICE/_FLAGSHIP (per-tier
## overrides), LLM_MAX_OUTPUT_TOKENS, LLM_REASONING_EFFORT (reasoning-model
## budget, e.g. "minimal" — REQUIRED with gpt-5-family models, whose default
## effort can spend the whole output cap on hidden reasoning and return empty
## dialogue, verified live 2026-08-30; sent only to models that accept it —
## see _supports_reasoning_effort — so it is safe to leave set when switching
## LLM_MODEL to a non-reasoning model), LLM_STORE_REQUESTS (1/true: send
## "store": true so requests appear on the platform's Logs page — OpenAI
## does not store chat completions by default, which is why an unstored
## request shows up only as aggregate Usage, never in Logs; stored requests
## are retained by OpenAI ~30 days).
static func _overlay_env(cfg: Dictionary, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#") or not "=" in line:
			continue
		var eq := line.find("=")
		var key := line.substr(0, eq).strip_edges()
		var value := line.substr(eq + 1).strip_edges()
		if value == "":
			continue
		match key:
			"OPENAI_API_KEY":
				cfg["api_key"] = value
				cfg["offline_mode"] = false
			"OPENAI_API_NAME":
				cfg["api_name"] = value
			"LLM_MODEL":
				cfg["model_parse"] = value
				cfg["model_voice"] = value
				cfg["model_flagship"] = value
			"LLM_MODEL_PARSE":
				cfg["model_parse"] = value
			"LLM_MODEL_VOICE":
				cfg["model_voice"] = value
			"LLM_MODEL_FLAGSHIP":
				cfg["model_flagship"] = value
			"LLM_MAX_OUTPUT_TOKENS":
				cfg["llm_max_output_tokens"] = int(value)
			"LLM_REASONING_EFFORT":
				cfg["llm_reasoning_effort"] = value
			"LLM_STORE_REQUESTS":
				cfg["llm_store_requests"] = value == "1" or value.to_lower() == "true"

static func _overlay_json(cfg: Dictionary, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return
	for k in cfg:
		if parsed.has(k):
			cfg[k] = parsed[k]

var _config: Dictionary
var _retried := false

func _ready() -> void:
	_config = OpenAIClient.load_config()

func offline() -> bool:
	return bool(_config.get("offline_mode", true))

func request_completion(system_prompt: String, user_prompt: String,
		model: String, force_json: bool) -> void:
	if offline():
		completed.emit.call_deferred(false, "offline")
		return
	_retried = false
	_send(system_prompt, user_prompt, model, force_json)

func _send(system_prompt: String, user_prompt: String, model: String, force_json: bool) -> void:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			if not _retried:
				_retried = true
				_send(system_prompt, user_prompt, model, force_json)
			else:
				completed.emit(false, "http error %d" % code)
			return
		var text := _extract_text(body.get_string_from_utf8())
		completed.emit(text != "", text))
	var err := http.request(_endpoint(), _headers_list(), HTTPClient.METHOD_POST,
		_build_body(system_prompt, user_prompt, model, force_json))
	if err != OK:
		http.queue_free()
		completed.emit.call_deferred(false, "request error %d" % err)

# --- OpenAI wire format lives ONLY below this line; verify against current docs ---

func _endpoint() -> String:
	return "https://api.openai.com/v1/chat/completions"

func _headers_list() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json",
		"Authorization: Bearer " + String(_config["api_key"])])

func _build_body(system_prompt: String, user_prompt: String,
		model: String, force_json: bool) -> String:
	# max_completion_tokens, not the legacy max_tokens: the gpt-5 family
	# rejects max_tokens with HTTP 400 ("Unsupported parameter", verified
	# live 2026-08-30), and every current chat-completions model accepts
	# max_completion_tokens.
	var body := {"model": model, "messages": [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt}],
		"max_completion_tokens": int(_config.get("llm_max_output_tokens", 600))}
	# Only sent when configured AND the model is a reasoning model:
	# non-reasoning models (gpt-4.1-mini verified live 2026-08-30) reject the
	# parameter with HTTP 400, so gating here lets LLM_MODEL switch freely
	# without .env surgery.
	var effort := String(_config.get("llm_reasoning_effort", ""))
	if effort != "" and _supports_reasoning_effort(model):
		body["reasoning_effort"] = effort
	# Opt-in observability: stored requests show on the platform Logs page.
	if bool(_config.get("llm_store_requests", false)):
		body["store"] = true
	if force_json:
		body["response_format"] = {"type": "json_object"}
	return JSON.stringify(body)

## Reasoning-capable model families (accept reasoning_effort): the gpt-5
## family and the o-series (o1/o3/o4...). Everything else rejects it.
static func _supports_reasoning_effort(model: String) -> bool:
	if model.begins_with("gpt-5"):
		return true
	for prefix in ["o1", "o3", "o4"]:
		if model.begins_with(prefix):
			return true
	return false

## Static (and defensive) so it can be unit-tested with canned strings and no
## network: any shape short of a full {"choices":[{"message":{"content":str}}]}
## must return "" rather than crash the request_completed callback — a crash
## there would mean `completed` never emits and cb never fires.
static func _extract_text(raw: String) -> String:
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return ""
	var choices = parsed.get("choices")
	if not choices is Array or choices.is_empty():
		return ""
	var choice = choices[0]
	if not choice is Dictionary:
		return ""
	var message = choice.get("message")
	if not message is Dictionary:
		return ""
	var content = message.get("content")
	if not content is String:
		return ""
	return content
