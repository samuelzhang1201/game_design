extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

## Scripted year: on listed ticks, execute the listed request.
func _scripted_inputs() -> Dictionary:
	return {
		2: ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}),
		5: ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}),
		9: ActionRequest.make("LEVY_RAISE"),
		14: ActionRequest.make("GRAIN_POLICY_SET", {"mode": "ration"}),
		20: ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_marshal"),
		30: ActionRequest.make("BUILD_ECONOMIC", {"project": "road"}),
		41: ActionRequest.make("JUSTICE_SEVERITY", {"delta": 1}),
	}

func _run_campaign(seed_value: int, reload_at: int = -1) -> String:
	var engine := TickEngine.new(data)
	var s := GameState.new_campaign(data, seed_value)
	var inputs := _scripted_inputs()
	for i in 48:
		engine.advance(s)
		if inputs.has(s.tick) and engine.actions.validate(inputs[s.tick], s) == "":
			engine.actions.execute(inputs[s.tick], s)
		if s.tick == reload_at:
			SaveLoad.save_game(s, "user://det_test.json")
			s = SaveLoad.load_game("user://det_test.json")
	return SaveLoad.state_hash(s)

func test_twin_runs_identical() -> void:
	assert_eq(_run_campaign(1234), _run_campaign(1234))

func test_save_load_mid_run_changes_nothing() -> void:
	assert_eq(_run_campaign(1234), _run_campaign(1234, 24))

func test_different_seeds_diverge() -> void:
	assert_ne(_run_campaign(1234), _run_campaign(9999))
