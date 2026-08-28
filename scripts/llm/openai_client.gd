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
	var cfg := {"api_key": "", "model_parse": "gpt-5.6-luna",
		"model_voice": "gpt-5.6-terra", "model_flagship": "gpt-5.6-sol",
		"offline_mode": true, "llm_max_output_tokens": 600}
	_overlay_env(cfg, env_path)
	_overlay_json(cfg, json_path)
	if String(cfg["api_key"]) == "" or OS.get_environment("CC_FORCE_OFFLINE") == "1":
		cfg["offline_mode"] = true
	return cfg

## Parses KEY=VALUE lines ('#' comments, blanks skipped). Recognized keys:
## OPENAI_API_KEY, LLM_MODEL (sets all three tiers), LLM_MODEL_PARSE/_VOICE/
## _FLAGSHIP (per-tier overrides), LLM_MAX_OUTPUT_TOKENS.
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
	var body := {"model": model, "messages": [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt}],
		"max_tokens": int(_config.get("llm_max_output_tokens", 600))}
	if force_json:
		body["response_format"] = {"type": "json_object"}
	return JSON.stringify(body)

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
