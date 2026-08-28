extends GutTest

func test_screen_builds_and_click_executes() -> void:
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	Game.start_campaign(42)
	screen.begin()          # renders first tick
	await wait_frames(2)
	var buttons: Array = screen.suggestion_buttons()
	assert_between(buttons.size(), 2, 3)
	var treasury_before: float = Game.state.metrics["treasury"]
	buttons[0].pressed.emit()
	await wait_frames(2)
	assert_ne(Game.state.recent_outcomes, [])
	screen.end_turn_button().pressed.emit()
	await wait_frames(2)
	assert_eq(Game.state.tick, 2)
