extends Node
## Autoload "Game": owns the sim; UI talks only to this.

signal report_ready(report: TickReport)
## Emitted after any mutation of Game.state (orders, event choices, court
## reactions, tick advance, load). UI that mirrors live state (e.g. the
## TopBar) subscribes to this instead of refreshing at call sites.
signal state_changed
## Cross-cutting UI signal: the TopBar's MENU button asks for the pause
## menu; GameRoot (the flow owner) listens and shows it.
signal menu_requested
## The TopBar's RELATIONS button asks for the relationship graph overlay;
## GameRoot listens and toggles it.
signal relations_requested

var data: DataRepository
var state: GameState
var engine: TickEngine
var current_report: TickReport
var client: OpenAIClient
var voicer: Voicer

func _ready() -> void:
	data = DataRepository.load_all("res://data")
	assert(data != null, "data load failed: " + DataRepository.last_error)

func start_campaign(seed_value: int = 42) -> void:
	_reset_llm()
	state = GameState.new_campaign(data, seed_value)
	engine = TickEngine.new(data)

func next_tick() -> TickReport:
	_prompts_this_tick = 0
	current_report = engine.advance(state)
	report_ready.emit(current_report)
	state_changed.emit()
	return current_report

func apply_event_choice(choice_id: String) -> Dictionary:
	var out := engine.events.apply_choice(choice_id, state)
	if not out.is_empty():
		state_changed.emit()
	return out

func try_execute(req: ActionRequest) -> Dictionary:
	var err := engine.actions.validate(req, state)
	if err != "":
		return {"ok": false, "error": err, "outcome": null}
	var outcome := engine.actions.execute(req, state)
	state_changed.emit()
	return {"ok": true, "error": "", "outcome": outcome}

func save_campaign(path: String = "user://save.json") -> bool:
	return SaveLoad.save_game(state, path)

func load_campaign(path: String = "user://save.json") -> bool:
	var loaded := SaveLoad.load_game(path)
	if loaded == null:
		return false
	state = loaded
	state_changed.emit()
	return true

## Restart flow (R12): return to MENU with a clean sim + LLM seam. Called by
## GameRoot's global R handler.
func restart() -> void:
	_reset_llm()
	state = null
	engine = null
	current_report = null
	_prompts_this_tick = 0

func _ensure_llm() -> void:
	if voicer != null:
		return
	client = OpenAIClient.new()
	add_child(client)
	voicer = Voicer.new(client)
	add_child(voicer)

## Tears down any LLM seam (real OpenAIClient, or a test-injected fake — see
## use_client_for_tests) left over from a previous campaign, so a new
## campaign starts with a clean _ensure_llm(). Without this, Game (an
## autoload, so its state outlives any one test) could hold a Voicer wrapping
## a client Node a *previous* test already freed (e.g. via
## add_child_autofree), and the next call that touches the LLM seam
## (voice_briefing/submit_free_text) would connect a signal on a freed
## object.
func _reset_llm() -> void:
	if voicer != null:
		voicer.queue_free()
		voicer = null
	if client != null:
		client.queue_free()
		client = null

## Voices the current tick's briefing through the Voicer (LLM-voiced when an
## API key is configured, template-fallback with degraded=true otherwise —
## see Voicer.voice_briefing). UI callers should route through here rather
## than calling TemplateVoicer.render_briefing directly, so a configured key
## is actually used.
func voice_briefing(cb: Callable) -> void:
	_ensure_llm()
	voicer.voice_briefing(current_report, state, data, cb)

## Voices a pending event's scene through the Voicer (see Voicer.voice_event).
## UI callers should route through here rather than calling TemplateVoicer
## directly, so a configured key is actually used for mini/flagship events.
func voice_event_scene(ev: Dictionary, cb: Callable) -> void:
	_ensure_llm()
	voicer.voice_event(ev, state, data, cb)

## Test-only seam: swap in a fake client (same signal/method surface as
## OpenAIClient) so tests exercise Voicer's real parsing/validation path
## without a network call. See tests/ui/test_court_screen.gd.
func use_client_for_tests(fake: Node) -> void:
	if voicer != null:
		voicer.queue_free()
	if client != null:
		client.queue_free()
		client = null
	voicer = Voicer.new(fake)
	add_child(voicer)

## Game is an autoload, so it is never freed mid-run — but GUT can tear down
## the SceneTree between full test-suite runs, and any leftover client/voicer
## Nodes must go with it or GUT's ObjectDB leak check at exit fires. Mirrors
## _reset_llm's teardown.
func _exit_tree() -> void:
	if voicer != null:
		voicer.queue_free()
	if client != null:
		client.queue_free()

## LLM parse calls per tick are capped (balance: prompt_calls_per_tick) so a
## player cannot burn unbounded API spend; over-cap orders are refused
## in-fiction without any API call. Clicked buttons remain free and unlimited.
var _prompts_this_tick := 0

## `speaker_hint`: the character the player is literally facing (the
## conversation stage passes its current beat's minister) — used to pick who
## answers conversational text; the court screen passes none and the
## Chancellor, "your primary voice" (council_seats.csv), answers instead.
func submit_free_text(text: String, cb: Callable, speaker_hint: String = "") -> void:
	if _prompts_this_tick >= int(data.bal("prompt_calls_per_tick")):
		cb.call({"ok": false, "executed": [], "rejected": [],
			"error": "the council will hear no more orders this fortnight"})
		return
	_prompts_this_tick += 1
	_ensure_llm()
	voicer.parse_player_text(text, current_report, state, data,
		func(res: Dictionary):
			if not res["ok"]:
				cb.call({"ok": false, "executed": [], "rejected": [], "error": res["error"]})
				return
			var executed: Array = []
			var rejected: Array = []
			for req in res["actions"]:
				if req.action_code == "EVENT_CHOICE":
					var ev_out := apply_event_choice(String(req.params.get("choice_id", "")))
					if ev_out.is_empty():
						rejected.append({"request": req, "error": "no such choice awaits"})
					else:
						# FIX 2(c): was hardcoded to [] — the button path
						# (apply_event_choice, see conversation_scene._on_event_choice)
						# already surfaces ev_out["effects"], so the free-text
						# EVENT_CHOICE path must too, or the UI's outcome
						# narration silently sees nothing to say.
						executed.append({"action_code": "EVENT_CHOICE", "ok": true,
							"effects": ev_out["effects"],
							"notes": String(ev_out["label"]), "drift": ev_out["drift"],
							"event_id": String(ev_out["event_id"]),
							"choice_id": String(ev_out["choice_id"])})
					continue
				var attempt := try_execute(req)
				if attempt["ok"]:
					executed.append(attempt["outcome"])
				else:
					rejected.append({"request": req, "error": attempt["error"]})
			engine.actions.apply_court_reaction(res["court_reaction"], state)
			state_changed.emit()
			# Conversational ride-along: text that parsed to no action at all
			# ("who are you") is a question, not an order — a role answers it
			# in character instead of the court falling silent. Shares this
			# submission's single prompt-cap increment (at most one extra call).
			if executed.is_empty() and rejected.is_empty():
				var speaker := _converse_speaker(res["court_reaction"], speaker_hint)
				if speaker != "":
					voicer.converse(speaker, text, state, data,
						func(reply: Dictionary):
							cb.call({"ok": true, "executed": [], "rejected": [],
								"error": "", "reply": reply}))
					return
			cb.call({"ok": true, "executed": executed, "rejected": rejected, "error": ""}))

## Who answers conversational text: whoever the parse says was addressed,
## else the minister the player is facing, else the Chancellor.
func _converse_speaker(court_reaction: Dictionary, hint: String) -> String:
	for id in court_reaction.get("addressed", []):
		if state.characters.has(String(id)) and String(id) != "you":
			return String(id)
	if state.characters.has(hint) and hint != "you":
		return hint
	return String(state.council.get("chancellor", ""))
