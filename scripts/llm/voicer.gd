class_name Voicer
extends Node

# Slice 1 is turn-gated (briefing, then wait for player input, then parse —
# never two in-flight calls in practice), but this class must not rely on
# that being true. Both methods attach a one-shot listener to the same
# client.completed signal; if a second call arrived while a first was still
# in flight, the two would cross-fire (one completed() emission resolving
# the wrong cb, and the other cb never firing). _busy defends the
# "cb fires exactly once" contract directly instead of trusting the caller.
var client: Node  # OpenAIClient or a test fake with the same surface
var _config: Dictionary
var _busy := false

func _init(c: Node) -> void:
	client = c
	_config = OpenAIClient.load_config()

func voice_briefing(report: TickReport, state: GameState, data: DataRepository,
		cb: Callable) -> void:
	var fallback := TemplateVoicer.render_briefing(report, state, data)
	if _busy:
		push_warning("Voicer busy — briefing degraded to template")
		cb.call({"ok": true, "degraded": true, "lines": fallback})
		return
	_busy = true
	var p := PromptBuilder.briefing_prompts(report, state)
	client.completed.connect(func(ok: bool, text: String):
		_busy = false
		if ok:
			cb.call({"ok": true, "degraded": false,
				"lines": [{"speaker": "Council", "text": text}]})
		else:
			cb.call({"ok": true, "degraded": true, "lines": fallback}),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"],
		String(_config["model_voice"]), false)

## Voices one event scene. The "template" tier IS the intended voice for that
## event (not a degraded fallback) — its callback fires deferred without ever
## touching client. mini/flagship tiers ask the model to rewrite the same
## template line; any model failure (or a busy Voicer) degrades back to it.
func voice_event(ev: Dictionary, state: GameState, data: DataRepository, cb: Callable) -> void:
	var fallback := TemplateVoicer.line_for(data, String(ev["title_key"]), [], state.tick)
	var tier := String(ev.get("voice", "template"))
	if tier == "template":
		cb.call_deferred({"ok": true, "degraded": false, "text": fallback})
		return
	if _busy:
		push_warning("Voicer busy — event scene degraded to template")
		cb.call({"ok": true, "degraded": true, "text": fallback})
		return
	_busy = true
	var model := String(_config.get("model_flagship", "gpt-5.6-sol")) if tier == "flagship" \
		else String(_config["model_voice"])
	var p := PromptBuilder.briefing_prompts_for_event(ev, state, fallback)
	client.completed.connect(func(ok: bool, text: String):
		_busy = false
		if ok and text != "":
			cb.call({"ok": true, "degraded": false, "text": text})
		else:
			cb.call({"ok": true, "degraded": true, "text": fallback}),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"], model, false)

func parse_player_text(text: String, report: TickReport, state: GameState,
		data: DataRepository, cb: Callable) -> void:
	if _busy:
		cb.call({"ok": false, "error": "voicer busy", "actions": [],
			"court_reaction": {}, "degraded": true})
		return
	_busy = true
	var p := PromptBuilder.parse_prompts(text, report, state, data)
	client.completed.connect(func(ok: bool, raw: String):
		_busy = false
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
