extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

const RunDir := preload("res://tests/run_dir.gd")
var data: DataRepository
## The seed-1234 run's hash, played once and shared by the three tests.
var _base_hash := ""

func before_each() -> void:
	data = SuiteData.repo()

## Scripted year: on listed ticks, execute the listed request.
func _scripted_inputs() -> Dictionary:
	return {
		2: ActionRequest.make("LAW_SET", {"law": "tax_rate", "value": "6"}),
		5: ActionRequest.make("LAW_SET", {"law": "church_policy", "value": "tithe"}),
		9: ActionRequest.make("LEVY_RAISE"),
		14: ActionRequest.make("LAW_SET", {"law": "grain_ration", "value": "ration"}),
		20: ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_marshal"),
		30: ActionRequest.make("BUILD_ECONOMIC", {"project": "road"}),
		41: ActionRequest.make("LAW_SET", {"law": "justice_severity", "value": "4"}),
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
			var path := RunDir.dir("determinism").path_join("det_test.json")
			SaveLoad.save_game(s, path)
			s = SaveLoad.load_game(path)
		if not s.pending_event.is_empty():
			engine.events.apply_choice(String(s.pending_event["choices"][0]["choice_id"]), s)
	return SaveLoad.state_hash(s)

func _base() -> String:
	if _base_hash == "":
		_base_hash = _run_campaign(1234)
	return _base_hash

func test_twin_runs_identical() -> void:
	assert_eq(_run_campaign(1234), _base())

func test_save_load_mid_run_changes_nothing() -> void:
	assert_eq(_run_campaign(1234, 24), _base())

func test_different_seeds_diverge() -> void:
	# Different seeds diverge through gameplay (events consume rng, affecting random rolls)
	assert_ne(_run_campaign(9999), _base())
