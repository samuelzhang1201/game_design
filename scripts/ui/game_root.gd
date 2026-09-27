class_name GameRoot
extends Control
## Flow state machine (spec §2). Owns exactly one screen scene at a time;
## screens signal upward, GameRoot decides what comes next. R restarts (R12).
## Also owns the pause menu (user ruling 2026-08-31): the TopBar's MENU
## button (via Game.menu_requested) or Esc opens Resume / Save / Load /
## Restart / Quit to Desktop.

## DAY_RUN (the end-turn calendar screen) was removed 2026-09-18 (owner):
## time runs on the clock in COURT and CONVERSATION, and nothing led there.
enum State {MENU, CONVERSATION, COURT}

const MENU_SCENE := preload("res://scenes/main_menu.tscn")
const CONVERSATION_SCENE := preload("res://scenes/conversation.tscn")
const COURT_SCENE := preload("res://scenes/court.tscn")

const BGM_PATH := "res://assets/BGM.mp3"
const BGM_VOLUME_DB := -12.0

var state: State = State.MENU
var current_screen: Node
var _pending_report: TickReport
## Seconds of the clock not yet spent as days (owner 2026-09-13).
var _clock_acc := 0.0
var _pause_menu: Control
var _pause_status: Label
var _relations_screen: RelationshipGraphScreen
var _bottom_bar: BottomBar
var _news_ticker: NewsTicker
var _info_screen: InfoScreen
var _bgm: AudioStreamPlayer
## The player's own settings, apart from any save (owner 2026-09-19: the menu
## switches the music off). The suite's pre-run hook points this at a test
## file so a developer's own choice never reaches a test.
static var settings_path := "user://settings.cfg"
var _music_on := true
var _music_button: Button
## The pause menu's 3D-map graphics tier (Map3DQuality), cycled in place.
var _quality_button: Button
## The PROVINCES tab's state (user request 2026-09-09): root-owned so it
## survives moving between screens, applied to whichever screen's map shows.
var _height_view := false
var _manor_view := false
## The MILITARY tab's state (user request 2026-09-10), owned here for the
## same reason: the layer follows the player from screen to screen.
var _army_view := false
## DEV MODE (the pause menu's switch, owner 2026-09-27).
var _dev_mode := false
var _dev_button: Button
var _ruler_view := false
## Which map the panel shows (owner 2026-09-18: the 3D map is the default):
## the last result of _sync_map_view, never set by hand.
var _map3d_view := false
## Test/tool seam for "the pack has a built 3D scene": -1 asks the disk.
var _map3d_scene := -1

## The design viewport (project.godot window/size): all UI is authored
## against this and scaled to the player's screen by the canvas_items+expand
## stretch. The OS window may never shrink below it, or panels would clip.
const MIN_WINDOW_SIZE := Vector2i(1280, 720)

## The kept 3D world (Map3DWorldCache) outlives the screens, not the game:
## the showing screen's world is handed back first so the clear frees it
## (a world still lent would be kept by its view's own teardown, and leak).
func _exit_tree() -> void:
	if current_screen != null and current_screen.has_method("map3d_view") \
			and current_screen.map3d_view() != null:
		(current_screen.map3d_view() as Map3DView).release_world()
	Map3DWorldCache.clear()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Fit-any-screen guarantee: fullscreen scales the whole UI to the monitor
	# (stretch settings in project.godot); a windowed player cannot drag the
	# window smaller than the design size.
	get_window().min_size = MIN_WINDOW_SIZE
	# One game-wide Theme, inherited by every screen (see UiPalette).
	theme = UiPalette.build_theme()
	Game.menu_requested.connect(toggle_pause_menu)
	Game.relations_requested.connect(toggle_relations)
	_relations_screen = RelationshipGraphScreen.new()
	_relations_screen.name = "RelationsScreen"
	_relations_screen.visible = false
	add_child(_relations_screen)
	_info_screen = InfoScreen.new()
	_info_screen.name = "InfoScreen"
	add_child(_info_screen)
	_bottom_bar = BottomBar.new()
	_bottom_bar.name = "BottomBar"
	_bottom_bar.visible = false
	_bottom_bar.tab_selected.connect(_on_bottom_tab)
	add_child(_bottom_bar)
	# The persistent transparent news strip (user request 2026-08-31): pinned
	# just above the bottom tab bar on every gameplay screen.
	_news_ticker = NewsTicker.new()
	_news_ticker.name = "NewsTicker"
	_news_ticker.visible = false
	add_child(_news_ticker)
	_load_settings()
	_build_pause_menu()
	_start_bgm()
	_switch_to(State.MENU)

## The clock (owner 2026-09-13): at Game.clock_speed, a day passes every
## time_day_seconds / speed. Works finish, the thirtieth day runs the tick,
## and an event that the tick rolls stops the clock and takes the player to
## the council, the only stage that renders a choice. Real time lives here
## and nowhere lower: the engine only ever sees advance_day.
## PLAY IS THE ONLY SWITCH (owner 2026-09-14): the clock runs on the council
## stage as well as the court, so nobody has to wave the ministers on before
## time will move.
func _process(delta: float) -> void:
	if not state in [State.COURT, State.CONVERSATION] or Game.state == null or Game.clock_speed <= 0:
		return
	if (_pause_menu != null and _pause_menu.visible) or not Game.state.pending_event.is_empty():
		return
	var per_day := maxf(Game.data.bal("time_day_seconds") / float(Game.clock_speed), 0.001)
	_clock_acc += delta
	var steps := 0
	while _clock_acc >= per_day and steps < 8:
		_clock_acc -= per_day
		steps += 1
		var before := works_progress()
		var out := Game.advance_day()
		# The news bar (owner 2026-09-14): a work's progress at each milestone,
		# its completion, and the month's close.
		announce_milestones(before, works_progress())
		for w: Dictionary in out["finished"]:
			Game.publish_news("The %s at %s is complete." % [
				String((Game.data.manor_buildings.get(String(w["building"]), {}) as Dictionary).get("label", w["building"])).to_lower(),
				MapManors.label_of(Game.data, int(w["cell"]))])
		if bool(out["ticked"]):
			_pending_report = Game.current_report
			announce_month(_pending_report)
			if not Game.state.pending_event.is_empty():
				Game.set_clock_speed(0)
				_clock_acc = 0.0
				Game.day_progress = 0.0
				_switch_to(State.CONVERSATION)
				current_screen.start([{"kind": "event", "portrait_id": "round_table",
					"speaker": "The Council",
					"event": Game.state.pending_event.duplicate(true)}], _pending_report)
				return

	Game.day_progress = clampf(_clock_acc / per_day, 0.0, 1.0)

## Every work in progress's share done: "cell|building" -> 0..1.
func works_progress() -> Dictionary:
	var out: Dictionary = {}
	if Game.state == null:
		return out
	for key: String in Game.state.manor_works:
		for w: Dictionary in Game.state.manor_works[key]:
			out["%s|%s" % [key, String(w["building"])]] = MapManors.work_progress(Game.state, int(key), String(w["building"]))
	return out

## A headline for every work that crossed a milestone (balance.csv
## news_build_milestone_1 and _2, owner: 30% and 70%) between two readings;
## completion has its own line.
func announce_milestones(before: Dictionary, now: Dictionary) -> void:
	var marks := [Game.data.bal("news_build_milestone_1"), Game.data.bal("news_build_milestone_2")]
	var keys: Array = now.keys()
	keys.sort()
	for key: String in keys:
		var was := float(before.get(key, 0.0))
		var is_now := float(now[key])
		for mark: float in marks:
			if was < mark and is_now >= mark and is_now < 1.0:
				var cell := int(key.get_slice("|", 0))
				var code := key.get_slice("|", 1)
				Game.publish_news("The %s at %s is %d%% done." % [
					String((Game.data.manor_buildings.get(code, {}) as Dictionary).get("label", code)).to_lower(),
					MapManors.label_of(Game.data, cell), roundi(mark * 100.0)])

## The month's close as news: what the crown's treasury and the lord's purse
## took, and an event if one waits. (Other important news is a placeholder
## for now: this is where it will go.)
func announce_month(report: TickReport) -> void:
	if report == null:
		return
	var crown := 0.0
	var lord := 0.0
	for d in report.metric_deltas:
		match String(d["metric"]):
			"treasury":
				crown += float(d["delta"])
			"lord_gold":
				lord += float(d["delta"])
	Game.publish_news("The month closes: the crown's treasury %+d gold, your purse %+d gold." % [roundi(crown), roundi(lord)])
	if Game.state != null and not Game.state.pending_event.is_empty():
		Game.publish_news("An event awaits the council.")

func _unhandled_input(event: InputEvent) -> void:
	if state == State.MENU:
		return
	if event.is_action_pressed("restart") and not _pause_menu.visible:
		Game.restart()
		_switch_to(State.MENU)
	elif event.is_action_pressed("ui_cancel"):
		toggle_pause_menu()

## The pause menu lives above every screen (built last, kept as a sibling
## that survives _switch_to's screen swaps).
func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.visible = false
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks under it
	var dim := ColorRect.new()
	dim.color = UiPalette.DIM_OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_menu.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.GOLD, 2, 28))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(300, 0)
	_pause_menu.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var title := Label.new()
	title.text = "COUNCIL IN RECESS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.style_header(title, 18)
	col.add_child(title)
	col.add_child(_menu_button("Resume", toggle_pause_menu))
	col.add_child(_menu_button("Save Game", _on_menu_save))
	col.add_child(_menu_button("Load Game", _on_menu_load))
	col.add_child(_menu_button("Restart", _on_menu_restart))
	_music_button = _menu_button(_music_label(), func() -> void: set_music_on(not _music_on))
	_music_button.name = "MusicToggle"
	col.add_child(_music_button)
	_quality_button = _menu_button(_quality_label(), _cycle_quality)
	_quality_button.name = "GraphicsQuality"
	col.add_child(_quality_button)
	_dev_button = _menu_button(_dev_label(), func() -> void: set_dev_mode(not _dev_mode))
	_dev_button.name = "DevMode"
	col.add_child(_dev_button)
	col.add_child(_menu_button("Quit to Desktop", func() -> void: get_tree().quit()))
	_pause_status = Label.new()
	_pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_status.add_theme_font_size_override("font_size", 18)
	_pause_status.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	col.add_child(_pause_status)
	add_child(_pause_menu)

## Background music from app start, looping across every screen (GameRoot
## outlives all screen swaps, so the track never restarts on navigation).
## Loads via the import pipeline with a raw-file fallback (same reasoning as
## UiPalette.load_art: exported builds pack imports, fresh checkouts and
## headless runs may not have imported yet). Missing file = silent, no error.
func _start_bgm() -> void:
	var stream: AudioStream = null
	if ResourceLoader.exists(BGM_PATH):
		stream = load(BGM_PATH) as AudioStream
	elif FileAccess.file_exists(BGM_PATH):
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(BGM_PATH)
		stream = mp3
	if stream == null:
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "Bgm"
	_bgm.stream = stream
	_bgm.volume_db = BGM_VOLUME_DB
	add_child(_bgm)
	_bgm.play()
	_bgm.stream_paused = not _music_on

## Music on or off (the pause menu's switch), remembered in settings_path.
func set_music_on(on: bool) -> void:
	_music_on = on
	if _bgm != null:
		_bgm.stream_paused = not on
	if _music_button != null:
		_music_button.text = _music_label()
	var cfg := ConfigFile.new()
	cfg.load(settings_path)  # a missing file is a fresh one
	cfg.set_value("audio", "music", on)
	cfg.save(settings_path)

func music_on() -> bool:
	return _music_on

func _music_label() -> String:
	return "Music: On" if _music_on else "Music: Off"

## The 3D map's graphics tier (spec 2026-09-20 §4), remembered in settings_path:
## "auto" (the GPU's detection) or a graphics_quality.csv tier.
func quality_setting() -> String:
	return Map3DQuality.setting(settings_path)

func _quality_label() -> String:
	var s := quality_setting()
	return "Graphics: %s" % (s.capitalize() if s != Map3DQuality.AUTO else "Auto")

## The next choice (auto, low .. ultra), saved and worn by the showing 3D map.
func _cycle_quality() -> void:
	Map3DQuality.save_setting(settings_path, Map3DQuality.next_setting(quality_setting()))
	_quality_button.text = _quality_label()
	if current_screen != null and current_screen.has_method("map3d_view"):
		var v: Map3DView = current_screen.map3d_view()
		if v != null:
			v.set_quality(Map3DQuality.resolve_here(settings_path))

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		_music_on = bool(cfg.get_value("audio", "music", true))
		_dev_mode = bool(cfg.get_value("game", "dev_mode", false))

## DEV MODE (owner 2026-09-27: "menu中新增一个dev模式，on/off"): the map shows
## every realm's regiments. Remembered in settings_path; the showing map
## follows at once, a map made later on its first sync.
func set_dev_mode(on: bool) -> void:
	_dev_mode = on
	if _dev_button != null:
		_dev_button.text = _dev_label()
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	cfg.set_value("game", "dev_mode", on)
	cfg.save(settings_path)
	_apply_dev_mode()

func dev_mode() -> bool:
	return _dev_mode

func _dev_label() -> String:
	return "Dev mode: On" if _dev_mode else "Dev mode: Off"

func _apply_dev_mode() -> void:
	if current_screen != null and current_screen.has_method("map3d_view"):
		var v: Map3DView = current_screen.map3d_view()
		if v != null:
			v.set_dev_mode(_dev_mode)

## Test seam.
func bgm_player() -> AudioStreamPlayer:
	return _bgm

func _menu_button(label: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.name = label.replace(" ", "")
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(handler)
	return btn

func toggle_pause_menu() -> void:
	if state == State.MENU:
		return
	_pause_status.text = ""
	_pause_menu.visible = not _pause_menu.visible

func pause_menu() -> Control:
	return _pause_menu

## The relationship graph overlay sits below the pause menu, above screens.
func toggle_relations() -> void:
	if state == State.MENU:
		return
	_relations_screen.visible = not _relations_screen.visible

func relations_screen() -> RelationshipGraphScreen:
	return _relations_screen

## Bottom bar routing: MAP is the default view (close every overlay — the
## live world map sits in the court screen's middle zone, user ruling
## 2026-09-03), RELATIONSHIP toggles the graph, the rest open their info
## table.
func _on_bottom_tab(tab: String) -> void:
	match tab:
		"HEIGHTS":
			_info_screen.hide()
			_relations_screen.visible = false
			set_height_view(not _height_view)
		"MANORS":
			_info_screen.hide()
			_relations_screen.visible = false
			set_manor_view(not _manor_view)
		"MEASUREMENT":
			_info_screen.hide()
			_relations_screen.visible = false
			set_ruler_view(not _ruler_view)
		"RELATIONSHIP":
			_info_screen.hide()
			toggle_relations()
		_:
			_relations_screen.visible = false
			_info_screen.show_tab(tab)

## Turn the relief view on or off everywhere (owner request 2026-09-12): the
## tab lights up and the current screen's map ramps the land by height. The
## default sheet stays flat — height is a layer you ask for, not a tint
## baked into the land.
func set_height_view(on: bool) -> void:
	_height_view = on
	if on and _manor_view:
		set_manor_view(false)
	if _bottom_bar != null:
		_bottom_bar.set_toggled("HEIGHTS", on)
	_sync_map_view()

func height_view() -> bool:
	return _height_view

## Turn the MANORS view on or off everywhere (MANOR_SYSTEM.md §6): the tab
## lights up, the map colours every manor by the house that holds it, and
## the screen's LEFT column lists the manors (the Manor Master), with each
## working manor's output badge on the map (ECONOMY was folded in, owner
## 2026-09-19). A theme like HEIGHTS, so lighting it puts that out, and it
## this.
func set_manor_view(on: bool) -> void:
	_manor_view = on
	if on:
		if _height_view:
			set_height_view(false)
	if _bottom_bar != null:
		_bottom_bar.set_toggled("MANORS", on)
	if current_screen != null and current_screen.has_method("set_manor_view"):
		current_screen.set_manor_view(on)
	_sync_map_view()

func manor_view() -> bool:
	return _manor_view

## The host in the current screen's LEFT column (the MILITARY tab that lit
## it is gone, owner 2026-09-27: the regiments are always on the map and the
## host opens from a regiment's card). Kept as the root's switch for it.
func set_army_view(on: bool) -> void:
	_army_view = on
	if current_screen != null and current_screen.has_method("set_military_view"):
		current_screen.set_military_view(on)

func army_view() -> bool:
	return _army_view

## The MEASUREMENT tab (owner 2026-09-18): the ruler over whichever map is
## showing, 2D or 3D, on every screen with a map. It changes no layer; the
## maps route their clicks to the ruler while it is on (MapRuler).
func set_ruler_view(on: bool) -> void:
	_ruler_view = on
	if _bottom_bar != null:
		_bottom_bar.set_toggled("MEASUREMENT", on)
	_apply_ruler()

func ruler_view() -> bool:
	return _ruler_view

## The current screen's map takes the tab's state — called on every
## map sync too, so a screen swap or a 3D view made on first use follows it.
func _apply_ruler() -> void:
	if current_screen != null and current_screen.has_method("map3d_view"):
		var v: Map3DView = current_screen.map3d_view()
		if v != null:
			v.ruler_on = _ruler_view

## The one rule for the map panel (the 2D map was deleted 2026-09-24): the
## 3D map is shown on every screen with a map, handed the theme and the
## counters; without a built scene it shows its notice naming build_pack.sh.
## balance map3d_default 0 holds it unloaded — the test suite does, since a
## headless run cannot render Terrain3D (tests/pre_run.gd). Runs on every
## layer change and every screen swap.
func _sync_map_view() -> void:
	var on := Game.data.bal("map3d_default") > 0.0
	_map3d_view = on and map3d_available()
	if current_screen != null and current_screen.has_method("set_map3d_theme"):
		var theme_name := "manors" if _manor_view else ("heights" if _height_view else "")
		current_screen.set_map3d_theme(theme_name, true)   # the regiments always show
	if current_screen != null and current_screen.has_method("set_map3d_view"):
		current_screen.set_map3d_view(on)
	_apply_ruler()
	_apply_dev_mode()

func map3d_available() -> bool:
	if _map3d_scene >= 0:
		return _map3d_scene == 1
	return Map3DView.has_scene(Game.data.map_id)

## Test/tool seam: pretend the pack's 3D scene is (or is not) built.
func force_map3d_scene(has: bool) -> void:
	_map3d_scene = 1 if has else 0
	_sync_map_view()

func map3d_view() -> bool:
	return _map3d_view

## Tools only: keep the clock short of the month's end (tools/map3d/bench.gd
## runs the clock for real per-frame cost, but a completed month can roll a
## random event mid-bench, which stops the clock and swaps the screen to the
## council — freeing whatever the caller is timing). Game rolls the day back
## to 1 once it passes `day_ceiling` (Game.hold_day_before_month_end — the
## state is Game's to write); the root forgets its own accumulated clock
## seconds with it.
func hold_clock_before_month_end(day_ceiling: int) -> void:
	if Game.hold_day_before_month_end(day_ceiling):
		_clock_acc = 0.0

func bottom_bar() -> BottomBar:
	return _bottom_bar

func news_ticker() -> NewsTicker:
	return _news_ticker

func info_screen() -> InfoScreen:
	return _info_screen

func _on_menu_save() -> void:
	if Game.state == null:
		_pause_status.text = "No realm to preserve."
		return
	_pause_status.text = "The realm is preserved." if Game.save_campaign() \
		else "The scribes failed us."

func _on_menu_load() -> void:
	if not Game.load_campaign():
		_pause_status.text = "No saved realm found."
		return
	_pause_menu.visible = false
	_pending_report = null
	# A loaded save with a decision still pending resumes on the conversation
	# stage (the only screen that renders event choices); otherwise the court
	# reconvenes on the loaded state, suggestions returning next tick.
	if not Game.state.pending_event.is_empty():
		_switch_to(State.CONVERSATION)
		current_screen.start([{"kind": "event", "portrait_id": "round_table",
			"speaker": "The Council",
			"event": Game.state.pending_event.duplicate(true)}], TickReport.new())
	else:
		_switch_to(State.COURT)
		current_screen.enter_court(null)

func _on_menu_restart() -> void:
	_pause_menu.visible = false
	Game.restart()
	_switch_to(State.MENU)

func _switch_to(new_state: State) -> void:
	if current_screen != null:
		# the old screen dies at the frame's end, the new one loads now: its
		# 3D world goes back to Map3DWorldCache first, to be re-parented
		if current_screen.has_method("map3d_view") and current_screen.map3d_view() != null:
			(current_screen.map3d_view() as Map3DView).release_world()
		current_screen.queue_free()
		current_screen = null
	state = new_state
	match new_state:
		State.MENU:
			current_screen = MENU_SCENE.instantiate()
			current_screen.start_requested.connect(_on_start_requested)
			current_screen.load_requested.connect(_on_menu_load_from_title)
		State.CONVERSATION:
			current_screen = CONVERSATION_SCENE.instantiate()
			current_screen.finished.connect(_on_conversation_finished)
		State.COURT:
			current_screen = COURT_SCENE.instantiate()
	add_child(current_screen)
	if current_screen != null and current_screen.has_method("set_military_view"):
		current_screen.set_military_view(_army_view)
	_sync_map_view()
	# Overlays stay above screens across swaps: bottom bar, then info and
	# relations, with the pause menu topmost.
	if _bottom_bar != null:
		_bottom_bar.visible = new_state != State.MENU
		move_child(_bottom_bar, get_child_count() - 1)
	if _news_ticker != null:
		_news_ticker.visible = new_state != State.MENU
		move_child(_news_ticker, get_child_count() - 1)
	if _info_screen != null:
		_info_screen.hide()
		move_child(_info_screen, get_child_count() - 1)
	if _relations_screen != null:
		_relations_screen.visible = false
		move_child(_relations_screen, get_child_count() - 1)
	if _pause_menu != null:
		move_child(_pause_menu, get_child_count() - 1)

const BACKGROUND_STORY_PATH := "res://game_story/chapter_0/game_start.md"

func _on_start_requested() -> void:
	Game.start_campaign(44)
	_pending_report = Game.next_tick()
	_switch_to(State.CONVERSATION)
	# The reign opens with the game background as a nameless narration beat
	# (user ruling 2026-08-30) so the player knows the challenge ahead.
	var beats := ConversationBeats.build(_pending_report, Game.state, Game.data)
	var story := _load_background_story()
	if story != "":
		beats.push_front({"kind": "narration", "portrait_id": "round_table",
			"speaker": "", "text": story})
	current_screen.start(beats, _pending_report)

## The story background (game_story/chapter_0/game_start.md) with markdown
## chrome stripped for in-game narration and {player_realm}-style tokens
## filled from the loaded pack. Empty when the file is absent.
func _load_background_story() -> String:
	if not FileAccess.file_exists(BACKGROUND_STORY_PATH):
		return ""
	var raw := FileAccess.get_file_as_string(BACKGROUND_STORY_PATH)
	var lines: Array = []
	for line in raw.split("\n"):
		var l := String(line).strip_edges()
		if l.begins_with("#"):
			continue
		lines.append(l.replace("**", ""))
	return Game.data.fill_realms("\n".join(lines).strip_edges())

## Load Game from the title screen: same resume rules as the pause menu.
func _on_menu_load_from_title() -> void:
	if not Game.load_campaign():
		if current_screen is MainMenu:
			current_screen.show_load_failed()
		return
	_pending_report = null
	if not Game.state.pending_event.is_empty():
		_switch_to(State.CONVERSATION)
		current_screen.start([{"kind": "event", "portrait_id": "round_table",
			"speaker": "The Council",
			"event": Game.state.pending_event.duplicate(true)}], TickReport.new())
	else:
		_switch_to(State.COURT)
		current_screen.enter_court(null)

## The conversation stage already spoke the event/concerns/pitches/outcomes
## (spec §3, R2); COURT re-entered after it shows only the order-bar state
## (metrics + suggestions), not a re-rendered briefing/outcome transcript.
func _on_conversation_finished() -> void:
	_switch_to(State.COURT)
	current_screen.enter_court(_pending_report)
	_pending_report = null
