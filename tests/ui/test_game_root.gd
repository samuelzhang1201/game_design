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

func test_bgm_plays_from_startup_and_loops() -> void:
	var r := _root()
	await wait_frames(2)
	var bgm := r.bgm_player()
	assert_not_null(bgm, "BGM player exists from app start")
	assert_not_null(bgm.stream, "assets/BGM.mp3 loaded")
	assert_true((bgm.stream as AudioStreamMP3).loop, "track loops")
	assert_true(bgm.playing, "music is playing on the menu")
	# Survives screen swaps: GameRoot owns it, screens come and go.
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	assert_true(bgm.playing, "music continues into the campaign")

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

func _menu_btn(r: GameRoot, name: String) -> Button:
	return r.pause_menu().find_child(name, true, false)

## Pause menu (user ruling 2026-08-31): the TopBar's MENU button (via
## Game.menu_requested) opens Resume / Save / Load / Restart / Quit; it
## stays hidden on the main menu, and Restart lands back there.
func test_pause_menu_opens_via_signal_and_restart_returns_to_menu() -> void:
	var r := _root()
	await wait_frames(2)
	Game.menu_requested.emit()
	assert_false(r.pause_menu().visible, "no pause menu on the main menu screen")
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	Game.menu_requested.emit()
	assert_true(r.pause_menu().visible, "MENU button opens the pause menu in play")
	_menu_btn(r, "Resume").pressed.emit()
	assert_false(r.pause_menu().visible, "Resume closes it")
	Game.menu_requested.emit()
	_menu_btn(r, "Restart").pressed.emit()
	await wait_frames(2)
	assert_eq(r.state, GameRoot.State.MENU)
	assert_null(Game.state)

## Save from the pause menu, restart, load: the loaded campaign resumes at
## court (no pending event) with the saved tick intact.
func test_pause_menu_save_then_load_resumes_at_court() -> void:
	var r := _root()
	await wait_frames(2)
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var saved_tick: int = Game.state.tick
	Game.menu_requested.emit()
	_menu_btn(r, "SaveGame").pressed.emit()
	_menu_btn(r, "Restart").pressed.emit()
	await wait_frames(2)
	assert_null(Game.state)
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	Game.menu_requested.emit()
	_menu_btn(r, "LoadGame").pressed.emit()
	await wait_frames(2)
	assert_eq(r.state, GameRoot.State.COURT, "a clean save resumes at court")
	assert_eq(Game.state.tick, saved_tick, "the loaded realm keeps its date")
	assert_false(r.pause_menu().visible)

## A save carrying an unresolved event must resume on the conversation
## stage, the only screen that renders event choices - otherwise the
## loaded campaign would be stuck behind court's End-Turn event gate.
func test_load_with_pending_event_resumes_on_conversation() -> void:
	var r := _root()
	await wait_frames(2)
	r.current_screen.start_requested.emit()
	await wait_frames(2)
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	Game.menu_requested.emit()
	_menu_btn(r, "SaveGame").pressed.emit()
	_menu_btn(r, "LoadGame").pressed.emit()
	await wait_frames(2)
	assert_eq(r.state, GameRoot.State.CONVERSATION,
		"a pending event resumes on the conversation stage")
	assert_gt(r.current_screen.reply_buttons().size(), 0,
		"the loaded event's choices are live")

## The PROVINCES tab (user request 2026-09-09) is a toggle in the bottom bar
## that drives the current screen's map and follows the player to the next
## screen; the map's own P key keeps the tab in step.
func test_provinces_tab_toggles_the_maps_province_view_across_screens() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	assert_false(r.province_view(), "off by default")
	r.bottom_bar().button("PROVINCES").pressed.emit()
	await wait_frames(1)
	assert_true(r.province_view())
	assert_true(r.current_screen.world_map().show_provinces, "the court's map follows the tab")
	assert_true(r.bottom_bar().button("PROVINCES").button_pressed, "the tab stays lit")
	r._switch_to(GameRoot.State.CONVERSATION)
	await wait_frames(2)
	assert_true(r.current_screen.world_map().show_provinces, "the next screen's map inherits it")
	r.current_screen.world_map().toggle_provinces()
	assert_false(r.province_view(), "the map's P key reports back to the root")
	assert_false(r.bottom_bar().button("PROVINCES").button_pressed)
