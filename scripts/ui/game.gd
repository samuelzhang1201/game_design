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
	state = GameState.new_campaign(data, seed_value)
	engine = TickEngine.new(data)

func next_tick() -> TickReport:
	current_report = engine.advance(state)
	report_ready.emit(current_report)
	return current_report

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

## Test-only seam: swap in a fake client (same signal/method surface as
## OpenAIClient) so tests exercise Voicer's real parsing/validation path
## without a network call. See tests/ui/test_council_screen.gd.
func use_client_for_tests(fake: Node) -> void:
	if voicer != null:
		voicer.queue_free()
	voicer = Voicer.new(fake)
	add_child(voicer)

func submit_free_text(text: String, cb: Callable) -> void:
	_ensure_llm()
	voicer.parse_player_text(text, current_report, state, data,
		func(res: Dictionary):
			if not res["ok"]:
				cb.call({"ok": false, "executed": [], "rejected": [], "error": res["error"]})
				return
			var executed: Array = []
			var rejected: Array = []
			for req in res["actions"]:
				var attempt := try_execute(req)
				if attempt["ok"]:
					executed.append(attempt["outcome"])
				else:
					rejected.append({"request": req, "error": attempt["error"]})
			engine.actions.apply_court_reaction(res["court_reaction"], state)
			cb.call({"ok": true, "executed": executed, "rejected": rejected, "error": ""}))
