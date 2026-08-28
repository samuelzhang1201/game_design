extends GutTest

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func test_boots_to_menu() -> void:
	var r := _root()
	await wait_frames(2)
	assert_eq(r.state, GameRoot.State.MENU)
	assert_not_null(r.current_screen)

func test_space_starts_campaign() -> void:
	var r := _root()
	await wait_frames(2)
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	assert_ne(r.state, GameRoot.State.MENU)
	assert_not_null(Game.state)
	# Regression: the old council screen's auto-start guard used to advance the
	# tick a second time on top of GameRoot's own next_tick() call (Task 3's
	# interim double-advance defect), silently discarding tick 1's report.
	# GameRoot now drives the single next_tick() and renders it via
	# begin_with, so campaign start lands on exactly tick 1.
	assert_eq(Game.state.tick, 1)

func test_r_restarts_to_menu() -> void:
	var r := _root()
	await wait_frames(2)
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	r._unhandled_input(key)
	await wait_frames(2)
	assert_eq(r.state, GameRoot.State.MENU)
	assert_null(Game.state)
