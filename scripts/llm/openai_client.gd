class_name OpenAIClient
extends Node

signal completed(ok: bool, text: String)

const CONFIG_PATH := "user://config.json"

static func load_config() -> Dictionary:
	var defaults := {"api_key": "", "model_parse": "gpt-5.6-luna",
		"model_voice": "gpt-5.6-terra", "offline_mode": true}
	if not FileAccess.file_exists(CONFIG_PATH):
		return defaults
	var parsed = JSON.parse_string(FileAccess.open(CONFIG_PATH, FileAccess.READ).get_as_text())
	if not parsed is Dictionary:
		return defaults
	for k in defaults:
		if not parsed.has(k):
			parsed[k] = defaults[k]
	if String(parsed["api_key"]) == "":
		parsed["offline_mode"] = true
	return parsed

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
		{"role": "user", "content": user_prompt}]}
	if force_json:
		body["response_format"] = {"type": "json_object"}
	return JSON.stringify(body)

func _extract_text(raw: String) -> String:
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary and parsed.has("choices") and parsed["choices"].size() > 0:
		return String(parsed["choices"][0]["message"]["content"])
	return ""
