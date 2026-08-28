extends Node
## Autoload "Game": owns the sim; UI talks only to this.

signal report_ready(report: TickReport)

var data: DataRepository
var state: GameState
var engine: TickEngine
var current_report: TickReport

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
