class_name Voicer
extends Node

var client: Node  # OpenAIClient or a test fake with the same surface
var _config: Dictionary

func _init(c: Node) -> void:
	client = c
	_config = OpenAIClient.load_config()

func voice_briefing(report: TickReport, state: GameState, data: DataRepository,
		cb: Callable) -> void:
	var fallback := TemplateVoicer.render_briefing(report, state, data)
	var p := PromptBuilder.briefing_prompts(report, state)
	client.completed.connect(func(ok: bool, text: String):
		if ok:
			cb.call({"ok": true, "degraded": false,
				"lines": [{"speaker": "Council", "text": text}]})
		else:
			cb.call({"ok": true, "degraded": true, "lines": fallback}),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"],
		String(_config["model_voice"]), false)

func parse_player_text(text: String, report: TickReport, state: GameState,
		data: DataRepository, cb: Callable) -> void:
	var p := PromptBuilder.parse_prompts(text, report, state, data)
	client.completed.connect(func(ok: bool, raw: String):
		if not ok:
			cb.call({"ok": false, "error": "couriers unavailable", "actions": [],
				"court_reaction": {}, "degraded": true})
			return
		var out := ResponseValidator.parse(raw, data)
		out["degraded"] = false
		cb.call(out),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"],
		String(_config["model_parse"]), true)
