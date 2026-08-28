extends Node
## Autoload "Game": owns the sim; UI talks only to this.

signal report_ready(report: TickReport)

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
	return current_report

func apply_event_choice(choice_id: String) -> Dictionary:
	return engine.events.apply_choice(choice_id, state)

func try_execute(req: ActionRequest) -> Dictionary:
	var err := engine.actions.validate(req, state)
	if err != "":
		return {"ok": false, "error": err, "outcome": null}
	return {"ok": true, "error": "", "outcome": engine.actions.execute(req, state)}

func save_campaign(path: String = "user://save.json") -> bool:
	return SaveLoad.save_game(state, path)

func load_campaign(path: String = "user://save.json") -> bool:
	var loaded := SaveLoad.load_game(path)
	if loaded == null:
		return false
	state = loaded
	return true

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
## without a network call. See tests/ui/test_council_screen.gd.
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

func submit_free_text(text: String, cb: Callable) -> void:
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
						executed.append({"action_code": "EVENT_CHOICE", "ok": true, "effects": [],
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
			cb.call({"ok": true, "executed": executed, "rejected": rejected, "error": ""}))
