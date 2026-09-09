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
## Delivers an event's scene. NO MODEL IS INVOLVED, ever (user ruling
## 2026-08-31: every event story is fixed, authored prose). The text is the
## author's own, read from RANDOM_EVENTS.md via StorySource; templates.csv
## keeps only the per-choice outcome lines.
##
## This makes the guarantee structural rather than a data value: there is no
## branch a CSV edit could take to reach the client, and no event prompt
## exists to send. `degraded` is always false because nothing can degrade —
## the authored text either exists or the story document is missing a scene,
## which the suite catches.
func voice_event(ev: Dictionary, state: GameState, data: DataRepository, cb: Callable) -> void:
	cb.call_deferred({"ok": true, "degraded": false,
		"text": scene_text(ev, state, data)})

## The authored scene for an event, or a visible marker when the story
## document has no entry for it — never invented text, and never silence.
static func scene_text(ev: Dictionary, state: GameState, data: DataRepository) -> String:
	var id := String(ev.get("event_id", ""))
	if data.event_scenes.has(id):
		return String(data.event_scenes[id])
	# Legacy saves and hand-built test fixtures may carry a title_key whose
	# line still lives in templates.csv; fall back to it before giving up.
	var key := String(ev.get("title_key", ""))
	if key != "":
		var line := TemplateVoicer.line_for(data, key, [], state.tick)
		if not line.begins_with("[missing template"):
			return line
	return "[missing scene: %s]" % id

## In-character reply from one role to conversational free text (no legal
## action matched — see Game.submit_free_text's ride-along). Failure/offline
## degrades to the converse_fallback template so the court never goes silent.
func converse(speaker_id: String, text: String, state: GameState,
		data: DataRepository, cb: Callable) -> void:
	var c: Character = state.characters[speaker_id]
	var fallback := TemplateVoicer.line_for(data, "converse_fallback", c.traits,
		state.tick, {"name": c.display_name})
	if _busy:
		push_warning("Voicer busy — converse degraded to template")
		cb.call({"ok": true, "degraded": true, "speaker_id": speaker_id,
			"speaker": c.display_name, "text": fallback})
		return
	_busy = true
	var p := PromptBuilder.converse_prompts(speaker_id, text, state, data)
	client.completed.connect(func(ok: bool, reply: String):
		_busy = false
		if ok and reply != "":
			cb.call({"ok": true, "degraded": false, "speaker_id": speaker_id,
				"speaker": c.display_name, "text": reply})
		else:
			cb.call({"ok": true, "degraded": true, "speaker_id": speaker_id,
				"speaker": c.display_name, "text": fallback}),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"],
		String(_config["model_voice"]), false)

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

## The two-part order call (spec 2026-09-09 §4): one request returns the
## speaker's narrative and the impacts. Busy or failing degrades exactly as
## the parse does — no state moves without a validated reply.
func order(text: String, speaker_id: String, report: TickReport, state: GameState,
		data: DataRepository, cb: Callable) -> void:
	if _busy:
		cb.call({"ok": false, "error": "voicer busy", "narrative": "", "actions": [],
			"world": [], "world_rejected": [], "court_reaction": {}, "degraded": true})
		return
	_busy = true
	var p := PromptBuilder.order_prompts(text, speaker_id, report, state, data)
	client.completed.connect(func(ok: bool, raw: String):
		_busy = false
		if not ok:
			cb.call({"ok": false, "error": "couriers unavailable", "narrative": "", "actions": [],
				"world": [], "world_rejected": [], "court_reaction": {}, "degraded": true})
			return
		var out := ResponseValidator.parse_order(raw, data, state)
		out["degraded"] = false
		cb.call(out),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"], String(_config["model_order"]), true)
