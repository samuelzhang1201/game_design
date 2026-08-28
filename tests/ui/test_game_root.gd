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
	assert_gt(Game.state.tick, 0)

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
