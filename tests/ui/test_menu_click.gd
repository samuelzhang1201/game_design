extends GutTest
## Owner report 2026-09-16: "点击 start game 无反应". Signal-level tests emit
## `pressed` directly and cannot see a Control that swallows the click, so this
## one pushes a real mouse press and release at the button's centre.

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await wait_process_frames(1)

func test_a_real_click_on_start_game_begins_the_reign() -> void:
	var r := _root()
	await wait_process_frames(3)
	var menu: MainMenu = r.current_screen
	var start: Button = menu.row("StartGame")
	var at := start.get_global_rect().get_center()
	await _click(at)
	await wait_process_frames(2)
	assert_false(r.current_screen is MainMenu, "the click reached Start Game (button at %s)" % at)
