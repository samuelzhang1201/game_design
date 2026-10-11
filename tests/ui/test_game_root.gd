extends GutTest

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r

func test_bgm_plays_from_startup_and_loops() -> void:
	var r := _root()
	await wait_process_frames(2)
	var bgm := r.bgm_player()
	assert_not_null(bgm, "BGM player exists from app start")
	assert_not_null(bgm.stream, "assets/audio/BGM.mp3 loaded")
	assert_true((bgm.stream as AudioStreamMP3).loop, "track loops")
	assert_true(bgm.playing, "music is playing on the menu")
	# Survives screen swaps: GameRoot owns it, screens come and go.
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	assert_true(bgm.playing, "music continues into the campaign")

func test_space_starts_campaign() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	assert_ne(r.state, GameRoot.State.MENU)
	assert_not_null(Game.state)
	# Regression: the old council screen's auto-start guard used to advance the
	# tick a second time on top of GameRoot's own next_tick() call (Task 3's
	# interim double-advance defect), silently discarding tick 1's report.
	# GameRoot now drives the single next_tick() and renders it via
	# begin_with, so campaign start lands on exactly tick 1.
	assert_eq(Game.state.tick, 1)

## Owner 2026-10-10 (no stall as the game opens): Start makes the reign and
## its opening month in one frame, under the title, and lays the first screen
## in the next; a second Start in between begins nothing more.
func test_the_reign_begins_over_two_frames() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	assert_eq(r.state, GameRoot.State.MENU, "the title still stands this frame")
	assert_not_null(Game.state, "but the reign is made")
	assert_eq(Game.state.tick, 1, "with its opening month")
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	assert_eq(r.state, GameRoot.State.CONVERSATION, "the first screen is laid the next frame")
	assert_eq(Game.state.tick, 1, "a second Start began nothing more")

## The boot asks for the overlays (and, with the 3D map on, the world and the
## art tables) on worker threads, so the title's first frame comes at once
## (BootLoads); all of them come in.
func test_the_boot_reads_the_heavy_art_on_threads() -> void:
	var r := _root()
	await wait_until(func() -> bool: return not BootLoads.loading(), 20.0)
	assert_false(BootLoads.loading(), "every threaded load came in")
	assert_true(BootLoads.title_ready())
	assert_not_null(r.current_screen)

func test_r_restarts_to_menu() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	r._unhandled_input(key)
	await wait_process_frames(2)
	assert_eq(r.state, GameRoot.State.MENU)
	assert_null(Game.state)

func _menu_btn(r: GameRoot, node_name: String) -> Button:
	return r.pause_menu().find_child(node_name, true, false)

## Pause menu (user ruling 2026-08-31): the TopBar's MENU button (via
## Game.menu_requested) opens Resume / Save / Load / Restart / Quit; it
## stays hidden on the main menu, and Restart lands back there.
func test_pause_menu_opens_via_signal_and_restart_returns_to_menu() -> void:
	var r := _root()
	await wait_process_frames(2)
	Game.menu_requested.emit()
	assert_false(r.pause_menu().visible, "no pause menu on the main menu screen")
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	Game.menu_requested.emit()
	assert_true(r.pause_menu().visible, "MENU button opens the pause menu in play")
	_menu_btn(r, "Resume").pressed.emit()
	assert_false(r.pause_menu().visible, "Resume closes it")
	Game.menu_requested.emit()
	_menu_btn(r, "Restart").pressed.emit()
	await wait_process_frames(2)
	assert_eq(r.state, GameRoot.State.MENU)
	assert_null(Game.state)

## Save from the pause menu, restart, load: the loaded campaign resumes at
## court (no pending event) with the saved tick intact.
func test_pause_menu_save_then_load_resumes_at_court() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	var saved_tick: int = Game.state.tick
	Game.menu_requested.emit()
	_menu_btn(r, "SaveGame").pressed.emit()
	_menu_btn(r, "Restart").pressed.emit()
	await wait_process_frames(2)
	assert_null(Game.state)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	Game.menu_requested.emit()
	_menu_btn(r, "LoadGame").pressed.emit()
	await wait_process_frames(2)
	assert_eq(r.state, GameRoot.State.COURT, "a clean save resumes at court")
	assert_eq(Game.state.tick, saved_tick, "the loaded realm keeps its date")
	assert_false(r.pause_menu().visible)

## A save carrying an unresolved event resumes on the court with the event
## waiting as its presenter's matter, as in play (owner 2026-10-02: 统一改成
## 由大臣头像提示); clicking the presenter brings its choices on.
func test_load_with_pending_event_waits_with_its_presenter() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	if not Game.state.pending_event.is_empty():
		Game.apply_event_choice(String(Game.state.pending_event["choices"][0]["choice_id"]))
	Game.engine.events._fire("ev_01", Game.state)
	Game.menu_requested.emit()
	_menu_btn(r, "SaveGame").pressed.emit()
	_menu_btn(r, "LoadGame").pressed.emit()
	await wait_process_frames(2)
	assert_eq(r.state, GameRoot.State.COURT, "the loaded reign waits on the table")
	assert_false(Game.state.pending_event.is_empty(), "the event still waits")
	r.audience_with(ConversationBeats.event_presenter(Game.state, Game.data))
	await wait_process_frames(2)
	assert_eq(r.state, GameRoot.State.CONVERSATION)
	assert_gt(r.current_screen.reply_buttons().size(), 0,
		"the loaded event's choices are live")

## The HEIGHTS tab (owner request 2026-09-12): the relief is a theme you ask
## for, so it starts off and the tab hands it to the screen's map.
func test_heights_tab_toggles_the_maps_height_theme() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	assert_false(r.height_view(), "off by default")
	assert_eq(r.current_screen.map3d_view().manor_theme(), "")
	r.bottom_bar().button("HEIGHTS").pressed.emit()
	await wait_process_frames(1)
	assert_true(r.height_view())
	assert_eq(r.current_screen.map3d_view().manor_theme(), "heights", "the map follows the tab")

## Owner 2026-09-17: a WAR ROOM tab; since 2026-10-01 it opens the plotting
## room over the map, not an info table.
func test_the_war_room_tab_opens_the_plotting_room() -> void:
	assert_true("WAR ROOM" in BottomBar.TABS)
	assert_false("WAR ROOM" in BottomBar.TOGGLES, "it opens a page, it is not a map toggle")
	Game.start_campaign(42)
	Game.next_tick()
	var r := _root()
	await wait_process_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(2)
	r._on_bottom_tab("WAR ROOM")
	assert_true(r.war_room_screen().visible)
	assert_false(r.info_screen().visible, "no info table opens for it")

## The clock (owner 2026-09-13): play is the only switch (owner 2026-09-14).
## The reign opens on the council, still talking, and pressing play moves
## time there too; on the court, at a speed, days pass in real time and
## works finish; paused, nothing moves. Days are waited for, not counted in
## frames: GameRoot._process banks real time.
func test_the_clock_runs_on_the_council_and_the_court_and_stops_paused() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	assert_eq(r.state, GameRoot.State.CONVERSATION, "the reign opens on the council")
	var day_s: float = Game.data.balance["time_day_seconds"]
	Game.data.balance["time_day_seconds"] = 0.001
	# Tick 1 may have rolled an event; a pending event holds the clock, so
	# clear it to watch the days.
	Game.state.pending_event = {}
	var before: int = Game.state.absolute_day()
	r.current_screen.top_bar().clock_button(1).pressed.emit()
	assert_eq(Game.clock_speed, 1)
	await wait_until(func() -> bool: return Game.state.absolute_day() > before, 2.0)
	assert_gt(Game.state.absolute_day(), before, "days pass without Wave them on")
	Game.set_clock_speed(0)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_process_frames(1)
	Game.state.pending_event = {}
	var day_before: int = Game.state.absolute_day()
	await wait_process_frames(5)
	assert_eq(Game.state.absolute_day(), day_before, "paused: nothing moves")
	Game.set_clock_speed(4)
	await wait_until(func() -> bool: return Game.state.absolute_day() > day_before, 2.0)
	assert_gt(Game.state.absolute_day(), day_before, "days pass on the court")
	Game.set_clock_speed(0)
	var frozen: int = Game.state.absolute_day()
	await wait_process_frames(5)
	assert_eq(Game.state.absolute_day(), frozen, "paused again")
	# A tick rolled by the clock stays on the court unless an event pends.
	if Game.state.pending_event.is_empty():
		assert_eq(r.state, GameRoot.State.COURT)
	else:
		assert_eq(r.state, GameRoot.State.CONVERSATION, "an event takes the player to the council")
	Game.data.balance["time_day_seconds"] = day_s


## Final review (owner 2026-09-18): the bench's clock hold writes the state
## through Game, never from GameRoot.
func test_game_holds_the_day_short_of_the_month_end() -> void:
	Game.start_campaign(42)
	Game.state.day = 20
	assert_false(Game.hold_day_before_month_end(25), "under the ceiling: untouched")
	assert_eq(Game.state.day, 20)
	Game.state.day = 26
	assert_true(Game.hold_day_before_month_end(25))
	assert_eq(Game.state.day, 1, "rolled back to the month's first day")

## Owner 2026-09-19: the menu switches the music off, and the choice is
## remembered across sessions (user settings, apart from any save). The
## suite's pre-run hook points the settings at a test file.
func test_the_menu_switches_the_music_off_and_remembers() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameRoot.settings_path))
	var r := _root()
	await wait_process_frames(2)
	assert_true(r.music_on(), "music is on by default")
	var button := r.find_child("MusicToggle", true, false) as Button
	assert_not_null(button, "the pause menu carries the switch")
	button.pressed.emit()
	assert_false(r.music_on())
	assert_true(r.bgm_player().stream_paused, "the track stops")
	var again := _root()
	await wait_process_frames(2)
	assert_false(again.music_on(), "remembered by the next session")
	assert_true(again.bgm_player().stream_paused)
	again.set_music_on(true)
	assert_false(again.bgm_player().stream_paused, "and back on")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameRoot.settings_path))

## Owner 2026-10-02 (开启游戏后的GPU占用很快又是100%): the menus' Frame rate
## row caps Engine.max_fps at a first run's ui_frame_cap_default, cycles the
## balance.csv choices (0 = unlimited) and is remembered; the suite forces 0
## (tests/pre_run.gd) and a cap forced over the setting is the one that runs.
func test_the_frame_rate_row_caps_the_engine_and_remembers() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameRoot.settings_path))
	var bal: Dictionary = Game.data.balance
	var was_forced := FrameCap.forced
	FrameCap.forced = -1
	var r := _root()
	await wait_process_frames(2)
	assert_eq(r.frame_cap_setting(), int(bal["ui_frame_cap_default"]), "a first run's default")
	assert_eq(Engine.max_fps, int(bal["ui_frame_cap_default"]), "and the engine runs at it")
	var button := _menu_btn(r, "FrameCap")
	assert_not_null(button, "the pause menu carries the row")
	button.pressed.emit()
	var next := FrameCap.next_setting(int(bal["ui_frame_cap_default"]), bal)
	assert_eq(r.frame_cap_setting(), next, "a press takes the next choice")
	assert_eq(Engine.max_fps, next, "and caps the engine at once")
	assert_eq(button.text, FrameCap.label(next))
	var again := _root()
	await wait_process_frames(2)
	assert_eq(again.frame_cap_setting(), next, "remembered by the next session")
	FrameCap.forced = 0
	again._cycle_frame_cap()
	assert_eq(Engine.max_fps, 0, "a forced cap wins over the setting")
	FrameCap.forced = was_forced
	FrameCap.apply(0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameRoot.settings_path))

func test_the_frame_cap_choices_cycle_and_read() -> void:
	var bal := {"ui_frame_cap_default": 60.0, "ui_frame_cap_choice_1": 30.0,
		"ui_frame_cap_choice_2": 60.0, "ui_frame_cap_choice_3": 0.0}
	assert_eq(FrameCap.choices(bal), [30, 60, 0] as Array[int])
	assert_eq(FrameCap.next_setting(30, bal), 60)
	assert_eq(FrameCap.next_setting(0, bal), 30, "the last wraps to the first")
	assert_eq(FrameCap.next_setting(45, bal), 30, "an unknown value starts the cycle")
	assert_eq(FrameCap.label(0), "Frame rate: Unlimited")
	assert_eq(FrameCap.label(60), "Frame rate: 60")

func _space() -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	return key

## Owner 2026-09-30 (空格键可以暂停或者继续游戏): Space stops a running clock
## and runs a stopped one again at the speed it last ran.
func test_space_pauses_and_resumes_the_game() -> void:
	var r := _root()
	await wait_process_frames(2)
	r.current_screen.start_requested.emit()
	await wait_process_frames(2)
	Game.set_clock_speed(int(Game.data.bal("time_speed_fast")))
	r._input(_space())
	assert_eq(Game.clock_speed, 0, "Space pauses")
	r._input(_space())
	assert_eq(Game.clock_speed, int(Game.data.bal("time_speed_fast")), "and resumes at the speed it ran")
	Game.set_clock_speed(0)
	r.toggle_pause_menu()
	r._input(_space())
	assert_eq(Game.clock_speed, 0, "not under the pause menu")
	r.toggle_pause_menu()
	var box := LineEdit.new()
	r.add_child(box)
	box.grab_focus()
	r._input(_space())
	assert_eq(Game.clock_speed, 0, "a space typed in a text box is a space")
	box.queue_free()

## Owner 2026-09-30 (游戏开始的UI和游戏内的menu功能要一致): the title screen and
## the pause menu carry the same settings rows and the same Quit, and a
## setting turned in one is read in the other.
func test_the_title_and_pause_menus_share_their_settings() -> void:
	var r := _root()
	await wait_process_frames(2)
	var title: MainMenu = r.current_screen
	for n: String in ["MusicToggle", "GraphicsQuality", "FrameCap", "FpsToggle", "DevMode", "Quit"]:
		var a := title.menu_column().get_node_or_null(n) as Button
		var b := _menu_btn(r, n)
		assert_not_null(a, "the title screen has " + n)
		assert_not_null(b, "the pause menu has " + n)
		if a != null and b != null:
			assert_eq(a.text, b.text, n + " reads the same in both")
	var was := r.dev_mode()
	(title.menu_column().get_node("DevMode") as Button).pressed.emit()
	assert_eq(r.dev_mode(), not was)
	assert_eq(_menu_btn(r, "DevMode").text, (title.menu_column().get_node("DevMode") as Button).text,
		"the pause menu's row follows")
	r.set_dev_mode(was)

## Owner 2026-10-10 (无论是不是dev模式，FPS都可以显示，加一个FPS on/off的按钮在
## menu): the FPS row shows the frame counter whatever DEV MODE says, and
## the choice is remembered.
func test_the_fps_row_shows_the_counter_apart_from_dev_mode() -> void:
	var r := _root()
	await wait_process_frames(2)
	var was_fps := r.show_fps()
	var was_dev := r.dev_mode()
	r.set_dev_mode(false)
	r.set_show_fps(false)
	var row := (r.current_screen as MainMenu).menu_column().get_node("FpsToggle") as Button
	assert_eq(row.text, "FPS: Off")
	row.pressed.emit()
	assert_true(r.fps_counter().visible, "the row shows the counter without dev mode")
	assert_eq(row.text, "FPS: On")
	assert_eq(_menu_btn(r, "FpsToggle").text, "FPS: On", "the pause menu's row follows")
	assert_true(r.fps_counter().text().ends_with(" FPS"), "it reads frames a second")
	var cfg := ConfigFile.new()
	cfg.load(GameRoot.settings_path)
	assert_true(bool(cfg.get_value("graphics", "show_fps", false)), "remembered in the settings")
	r.set_dev_mode(true)
	r.set_dev_mode(false)
	assert_true(r.fps_counter().visible, "dev mode no longer drives it")
	r.set_show_fps(false)
	assert_false(r.fps_counter().visible, "off, it is gone")
	r.set_dev_mode(true)
	assert_false(r.fps_counter().visible, "dev mode alone does not show it")
	r.set_dev_mode(was_dev)
	r.set_show_fps(was_fps)
