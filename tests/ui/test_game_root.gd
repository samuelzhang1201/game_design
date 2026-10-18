extends GutTest

const BattleScenario := preload("res://tests/fixtures/battle_scenario.gd")
const SuiteData := preload("res://tests/suite_data.gd")
var _battle_original_data: DataRepository

## Controller tests replace only the view; the real-scene acceptance test stays separate.
class EncounterPanelDouble extends BattleEncounterPanel:
	var shown_decision: Dictionary = {}
	var centered_rect: Rect2
	func _ready() -> void:
		hide()
	func open(_repo: DataRepository, _state: GameState, decision: Dictionary) -> void:
		shown_decision = decision.duplicate(true)
		show()
	func center_on(map_rect: Rect2) -> void:
		centered_rect = map_rect

func after_each() -> void:
	if _battle_original_data != null:
		Game.restart()
		Game.data = _battle_original_data
		_battle_original_data = null

func _battle_root(two := false, day := 10, real_panel := false) -> GameRoot:
	_battle_original_data = Game.data
	Game.restart()
	Game.data = SuiteData.repo()
	Game.data.balance["map3d_default"] = 0.0
	Game.state = BattleScenario.two_battles(Game.data, day) if two else BattleScenario.contact(Game.data, day)
	Game.engine = TickEngine.new(Game.data)
	var root := _root()
	root.set_process(false)
	if not real_panel:
		root._battle_encounter = load("res://scenes/panels/battle_encounter_panel.tscn").instantiate()
		root._battle_encounter.set_script(EncounterPanelDouble)
		root._make_battle_encounter()
	root._switch_to(GameRoot.State.COURT)
	return root

func _confirm_encounter() -> void:
	assert_true(Game.has_method("resolve_battle_decision"), "Game owns encounter acknowledgements")
	if not Game.has_method("resolve_battle_decision"):
		return
	var pending: Dictionary = Game.state.day_resolution.get("pending_decision", {})
	assert_false(pending.is_empty())
	if pending.is_empty():
		return
	var out: Dictionary = Game.call("resolve_battle_decision", String(pending["token"]), "continue")
	assert_eq(out.get("status"), "accepted")
	assert_eq(Game.clock_speed, 0, "a choice does not press Play")

func test_encounter_stops_catchup() -> void:
	var root := _battle_root()
	Game.set_clock_speed(1)
	root._process(40.0)
	assert_eq(Game.clock_speed, 0, "stop at the first eight-second boundary")
	assert_eq(root._clock_acc, 0.0, "discard the remaining four days")
	assert_eq(Game.day_progress, 0.0)
	assert_eq(Game.state.day, 10)
	assert_eq(Game.state.battles.size(), 1)
	assert_eq(int(Game.state.battles[0]["rounds"]), 0)
	for table: Dictionary in [Game.state.regiments, Game.state.foes]:
		for entry: Dictionary in table.values():
			assert_eq(int(entry.get("dead", 0)) + int(entry.get("wounded", 0)), 0)
	_confirm_encounter()
	assert_eq(root._clock_acc, 0.0)
	if not Game.has_method("resolve_battle_decision"):
		return
	root._process(40.0)
	assert_eq(Game.state.day, 10, "confirmation leaves the old transaction paused")
	Game.toggle_clock()
	root._process(0.0)
	assert_eq(Game.state.day, 11, "resume the paid-for day immediately")
	assert_true(Game.state.day_resolution.is_empty())
	root._process(7.9)
	assert_eq(Game.state.day, 11)
	root._process(0.1)
	assert_eq(Game.state.day, 12)

func test_encounter_preserves_selected_speed(speed = use_parameters([1, 2, 4])) -> void:
	var root := _battle_root()
	Game.set_clock_speed(speed)
	var seconds := 8.0 / float(speed)
	root._process(seconds - 0.1)
	assert_true(Game.state.day_resolution.is_empty())
	root._process(0.1)
	assert_eq(Game.clock_speed, 0)
	_confirm_encounter()
	if not Game.has_method("resolve_battle_decision"):
		return
	Game.toggle_clock()
	assert_eq(Game.clock_speed, speed)
	root._process(0.0)
	assert_eq(Game.state.day, 11)
	root._process(seconds - 0.1)
	assert_eq(Game.state.day, 11)
	root._process(0.1)
	assert_eq(Game.state.day, 12)

func test_decision_lock_survives_other_windows() -> void:
	var root := _battle_root()
	Game.set_clock_speed(4)
	root._process(2.0)
	assert_true(Game.holds_clock("battle_decision"))
	for holder: String in ["ledger", "war_room"]:
		Game.hold_clock(true, holder)
		Game.hold_clock(false, holder)
		Game.toggle_clock()
		assert_eq(Game.clock_speed, 0)
	Game.release_clock_holds()
	assert_true(Game.holds_clock("battle_decision"), "view reset cannot dismiss a saved decision")
	_confirm_encounter()
	assert_false(Game.holds_clock("battle_decision"))

func test_encounter_load_restores_pending_decision() -> void:
	var root := _battle_root()
	Game.set_clock_speed(4)
	root._process(2.0)
	var pending: Dictionary = Game.state.day_resolution["pending_decision"].duplicate(true)
	assert_true(Game.save_campaign())
	Game.restart()
	Game._resume_speed = 1  # a fresh process has no in-memory speed preference
	assert_true(Game.load_campaign())
	assert_eq(Game.state.day_resolution["pending_decision"], pending)
	assert_true(Game.holds_clock("battle_decision"))
	assert_eq(Game.clock_speed, 0)
	assert_not_null(Game.engine, "load can resume without an earlier campaign engine")
	_confirm_encounter()
	Game.toggle_clock()
	assert_eq(Game.clock_speed, 4, "the interrupted save remembers the selected speed")

func test_multiple_first_encounters_each_require_confirmation() -> void:
	var root := _battle_root(true)
	Game.set_clock_speed(1)
	root._process(40.0)
	var first: String = Game.state.day_resolution["pending_decision"]["token"]
	_confirm_encounter()
	if not Game.has_method("resolve_battle_decision"):
		return
	Game.toggle_clock()
	root._process(0.0)
	var second: String = Game.state.day_resolution["pending_decision"]["token"]
	assert_ne(first, second)
	assert_eq(Game.clock_speed, 0)
	assert_eq(Game.state.day, 10)
	_confirm_encounter()
	Game.toggle_clock()
	root._process(0.0)
	assert_eq(Game.state.day, 11)
	root._process(8.0)
	assert_eq(Game.state.day, 12, "ongoing battles do not repeat first encounter pauses")

func test_encounter_month_end_only_publishes_after_completion() -> void:
	var root := _battle_root(false, 30)
	watch_signals(Game)
	Game.set_clock_speed(1)
	root._process(40.0)
	assert_eq(Game.state.tick, 1)
	assert_eq(Game.state.day, 30)
	assert_signal_not_emitted(Game, "report_ready")
	var blocked := Game.advance_day()
	assert_eq(blocked.get("status"), "blocked")
	assert_false(bool(blocked.get("ticked", false)), "no completed-day output while blocked")
	_confirm_encounter()
	Game.toggle_clock()
	root._process(0.0)
	assert_eq(Game.state.tick, 2)
	assert_eq(Game.state.day, 1)
	assert_signal_emit_count(Game, "report_ready", 1)

func test_encounter_refuses_stale_invalid_and_repeated_choices() -> void:
	var root := _battle_root()
	Game.set_clock_speed(1)
	root._process(8.0)
	var token: String = Game.state.day_resolution["pending_decision"]["token"]
	var before := SaveLoad.state_hash(Game.state)
	assert_eq(Game.resolve_battle_decision("wrong", "continue")["status"], "stale")
	assert_eq(Game.resolve_battle_decision(token, "wrong")["status"], "invalid")
	assert_eq(SaveLoad.state_hash(Game.state), before)
	assert_true(Game.holds_clock("battle_decision"))
	_confirm_encounter()
	before = SaveLoad.state_hash(Game.state)
	assert_eq(Game.resolve_battle_decision(token, "continue")["status"], "duplicate")
	assert_eq(SaveLoad.state_hash(Game.state), before)
	assert_eq(Game.clock_speed, 0)

func test_ordinary_reinforcement_does_not_repeat_encounter_pause() -> void:
	var root := _battle_root()
	Game.set_clock_speed(1)
	root._process(8.0)
	var battle: Dictionary = Game.state.battles[0]
	var code := String(battle["def"][0])
	var reinforcement := code + "_fixture_reinforcement"
	Game.state.army_roster[reinforcement] = Game.state.army_roster[code].duplicate(true)
	Game.state.army_roster[reinforcement]["regiment_code"] = reinforcement
	Game.state.regiments[reinforcement] = Game.state.regiments[code].duplicate(true)
	assert_true(BattleSystem.join(Game.data, Game.state, int(battle["id"]), reinforcement, "def"))
	_confirm_encounter()
	Game.toggle_clock()
	root._process(0.0)
	assert_eq(Game.clock_speed, 1)
	assert_eq(Game.state.day, 11)
	assert_true(Game.pending_battle_decision().is_empty())

func test_manual_pause_discards_partial_day_time() -> void:
	var root := _battle_root()
	Game.set_clock_speed(1)
	root._process(7.9)
	Game.toggle_clock()
	assert_eq(root._clock_acc, 0.0)
	Game.toggle_clock()
	root._process(0.1)
	assert_true(Game.state.day_resolution.is_empty())
	assert_eq(Game.clock_speed, 1)

func test_compatibility_tick_resumes_day_without_publishing_empty_month() -> void:
	var root := _battle_root()
	var previous := TickReport.new()
	previous.tick = 1
	Game.current_report = previous
	Game.set_clock_speed(1)
	root._process(8.0)
	_confirm_encounter()
	watch_signals(Game)
	Game.next_tick()
	assert_eq(Game.state.day, 11)
	assert_eq(Game.current_report, previous)
	assert_signal_not_emitted(Game, "report_ready")

func test_blocked_day_keeps_notifications_across_json_load() -> void:
	var root := _battle_root()
	var cells := MapManors.manors_of_house(Game.data, Game.state, MapManors.crown(Game.state),
		Game.data.resolve_realm("player_realm"))
	var cell := int(cells[0])
	assert_true(MapManors.start_work(Game.data, Game.state, cell, "chapel", "test"))
	var work: Dictionary = Game.state.manor_works[str(cell)][0]
	work["days"] = 10
	work["done"] = 2900
	var spy := CourierSystem.dispatch_spy(Game.data, Game.state, Vector2(500, 300))
	spy["x_m"] = spy["aim_x_m"]
	spy["y_m"] = spy["aim_y_m"]
	spy["path"] = []
	Game.set_clock_speed(1)
	root._process(8.0)
	assert_false(root.report_popup().visible, "daily notices wait until completion")
	assert_gt(Game.state.next_missive_id, 0, "the spy reported before encounter interruption")
	assert_gt(MapManors.work_progress(Game.state, cell, "chapel"), 0.3)
	assert_true(Game.save_campaign())
	root._on_menu_load()
	var got: Array[String] = []
	var handler := func(line: String) -> void: got.append(line)
	Game.news_published.connect(handler)
	_confirm_encounter()
	Game.toggle_clock()
	root._process(0.0)
	assert_true(root.report_popup().visible, "the saved pre-contact spy report opens once the day completes")
	assert_eq(Game.clock_speed, 0)
	assert_eq(got.filter(func(line: String) -> bool: return "is 30% done" in line).size(), 1)
	root._process(40.0)
	assert_eq(got.filter(func(line: String) -> bool: return "is 30% done" in line).size(), 1)
	Game.news_published.disconnect(handler)

func test_encounter_controller_routes_requests_and_restores_confirmation() -> void:
	var root := _battle_root()
	Game.set_clock_speed(4)
	root._process(2.0)
	var panel := root._battle_encounter as EncounterPanelDouble
	var pending := Game.pending_battle_decision()
	assert_true(panel.visible)
	assert_eq(panel.shown_decision, pending)
	assert_eq(panel.centered_rect, (root.current_screen.map_panel() as Control).get_global_rect())
	assert_lt(panel.get_index(), root._pause_menu.get_index(), "pause menu remains reachable above the encounter")
	panel.decision_selected.emit("stale", "continue")
	assert_true(panel.visible, "an invalid request does not dismiss the encounter")
	assert_eq(Game.pending_battle_decision(), pending)
	panel.deployment_requested.emit()
	assert_true(root.war_room_screen().visible)
	assert_false(panel.visible, "deployment is accessible while the decision remains pending")
	assert_true(Game.holds_clock("battle_decision"))
	assert_eq(Game.pending_battle_decision(), pending)
	root.war_room_screen().close(false)
	assert_true(panel.visible, "closing deployment returns to the same confirmation")
	assert_eq(panel.shown_decision, pending)
	Game.toggle_clock()
	assert_eq(Game.clock_speed, 0)
	assert_true(Game.save_campaign())
	root._on_menu_restart()
	assert_false(panel.visible)
	root._on_menu_load()
	assert_true(panel.visible, "load from the title restores the saved encounter")
	assert_eq(panel.shown_decision, pending)
	panel.decision_selected.emit(String(pending["token"]), "continue")
	assert_false(panel.visible)
	assert_false(Game.holds_clock("battle_decision"))
	assert_eq(Game.clock_speed, 0)
	Game.toggle_clock()
	root._process(0.0)
	assert_eq(Game.state.day, 11, "the routed choice permits the already-paid day to finish")

func test_encounter_panel_is_request_only_and_restores_after_load() -> void:
	var scene_path := "res://scenes/panels/battle_encounter_panel.tscn"
	assert_true(ResourceLoader.exists(scene_path), "encounter look is an editor-authored scene")
	if not ResourceLoader.exists(scene_path):
		return
	var root := _battle_root(false, 10, true)
	Game.set_clock_speed(1)
	root._process(8.0)
	var panel: Control = root.find_child("BattleEncounterPanel", true, false)
	assert_not_null(panel)
	if panel == null:
		return
	await wait_process_frames(5)
	assert_true(panel.visible)
	var map_rect: Rect2 = root.current_screen.map_panel().get_global_rect()
	var window_rect := (panel.get_node("Center/Window") as Control).get_global_rect()
	assert_true(map_rect.encloses(window_rect), "wrapped-label layout must keep the real window inside the map")
	assert_eq((panel.get_node("Center") as Control).size, map_rect.size)
	var standalone: Control = load(scene_path).instantiate()
	add_child_autofree(standalone)
	standalone.call("open", Game.data, Game.state, Game.pending_battle_decision())
	watch_signals(standalone)
	var before := SaveLoad.state_hash(Game.state)
	(standalone.find_child("Continue", true, false) as Button).pressed.emit()
	assert_signal_emit_count(standalone, "decision_selected", 1)
	assert_eq(SaveLoad.state_hash(Game.state), before, "panel only requests an acknowledgement")
	assert_true(Game.save_campaign())
	root._on_menu_restart()
	root._on_menu_load()
	assert_true(panel.visible, "loaded pending decision reopens the same window")
	assert_true(Game.holds_clock("battle_decision"))

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
		var a := title.row(n)
		var b := _menu_btn(r, n)
		assert_not_null(a, "the title screen has " + n)
		assert_not_null(b, "the pause menu has " + n)
		if a != null and b != null:
			assert_eq(a.text, b.text, n + " reads the same in both")
	var was := r.dev_mode()
	title.row("DevMode").pressed.emit()
	assert_eq(r.dev_mode(), not was)
	assert_eq(_menu_btn(r, "DevMode").text, title.row("DevMode").text,
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
	var row := (r.current_screen as MainMenu).row("FpsToggle")
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
