extends GutTest

const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")

var old_data: DataRepository

func before_each() -> void:
	old_data = Game.data
	Game.data = SuiteData.repo()
	Game.restart()
	Game.state = Scenario.contact(Game.data, 10)
	Game.engine = TickEngine.new(Game.data)

func after_each() -> void:
	Game.restart()
	Game.data = old_data

func test_decision_holds_clock_without_finishing_day() -> void:
	Game.set_clock_speed(4)
	var out := Game.advance_day()
	assert_eq(out.get("status", ""), "blocked")
	assert_eq(Game.state.day, 10)
	assert_eq(Game.clock_speed, 0)
	assert_true(Game.holds_clock("battle_decision"))
	Game.hold_clock(true, "war_room")
	Game.hold_clock(false, "war_room")
	Game.set_clock_speed(1)
	assert_eq(Game.clock_speed, 0, "another window cannot unlock a battle decision")

func test_acknowledgement_leaves_manual_pause_and_original_speed() -> void:
	assert_true(Game.has_method("resolve_battle_decision"))
	if not Game.has_method("resolve_battle_decision"):
		return
	Game.set_clock_speed(4)
	var out := Game.advance_day()
	Game.call("resolve_battle_decision", out["decision"]["token"], "continue")
	assert_eq(Game.clock_speed, 0)
	assert_false(Game.holds_clock("battle_decision"))
	assert_eq(Game.state.day, 10, "selection itself consumes no day")
	Game.toggle_clock()
	assert_eq(Game.clock_speed, 4)
	assert_eq(Game.advance_day()["status"], "complete")
	assert_eq(Game.state.day, 11)

func test_encounter_stops_catchup_and_resumes_without_a_second_day_fee() -> void:
	var root: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(root)
	await wait_process_frames(2)
	root.set_process(false)
	root.state = GameRoot.State.COURT
	Game.data.balance["time_day_seconds"] = 8.0
	Game.set_clock_speed(1)
	root._process(40.0)
	assert_eq(Game.state.day, 10)
	assert_eq(Game.clock_speed, 0)
	assert_eq(int(Game.state.battles[0]["rounds"]), 0)
	var panel := root.get_node_or_null("BattleEncounterPanel")
	assert_not_null(panel, "encounter has an authored, actionable panel")
	if panel == null:
		return
	assert_true(panel.visible)
	var button: Button = panel.find_child("Continue", true, false)
	button.pressed.emit()
	assert_eq(Game.clock_speed, 0)
	Game.toggle_clock()
	root._process(0.0)
	assert_eq(Game.state.day, 11, "resume completes the already-paid day boundary")
	root._process(7.9)
	assert_eq(Game.state.day, 11)
	root._process(0.11)
	assert_eq(Game.state.day, 12)

func test_world_day_uses_the_selected_speed() -> void:
	var root: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(root)
	await wait_process_frames(2)
	root.set_process(false)
	root.state = GameRoot.State.COURT
	Game.state.foes.clear()
	Game.data.balance["time_day_seconds"] = 8.0
	for speed: int in [1, 2, 4]:
		root.set("_clock_acc", 0.0)
		Game.set_clock_speed(speed)
		var day := Game.state.day
		var duration := 8.0 / speed
		root._process(duration - 0.1)
		assert_eq(Game.state.day, day, "day remains open at speed %d" % speed)
		root._process(0.11)
		assert_eq(Game.state.day, day + 1, "world advances at speed %d" % speed)

func test_loaded_encounter_restores_named_hold_and_notice() -> void:
	var root: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(root)
	await wait_process_frames(2)
	root.set_process(false)
	root.state = GameRoot.State.COURT
	var out := Game.advance_day()
	var path := "user://test_battle_clock_save.json"
	assert_true(Game.save_campaign(path))
	Game.restart()
	Game.engine = TickEngine.new(Game.data)
	Game.set_clock_speed(4)
	assert_true(Game.load_campaign(path))
	assert_true(Game.holds_clock("battle_decision"))
	assert_eq(Game.clock_speed, 0)
	assert_eq(Game.state.day_resolution["pending_decision"], out["decision"])
	assert_true(root.get_node("BattleEncounterPanel").visible)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_duplicate_old_confirmation_does_not_hide_the_next_encounter() -> void:
	Game.state = Scenario.two_battles(Game.data, 10)
	var root: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(root)
	await wait_process_frames(2)
	root.set_process(false)
	root.state = GameRoot.State.COURT
	var first := Game.advance_day()
	var panel: BattleEncounterPanel = root.get_node("BattleEncounterPanel")
	panel.decision_selected.emit(first["decision"]["token"], "continue")
	var second := Game.advance_day()
	assert_ne(second["decision"]["token"], first["decision"]["token"])
	panel.decision_selected.emit(first["decision"]["token"], "continue")
	assert_true(panel.visible, "a duplicate old response must leave the current decision usable")
	assert_true(Game.holds_clock("battle_decision"))
	assert_eq(Game.state.day_resolution["pending_decision"]["selected"], "")
