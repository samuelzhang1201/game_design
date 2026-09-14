class_name GameRoot
extends Control
## Flow state machine (spec §2). Owns exactly one screen scene at a time;
## screens signal upward, GameRoot decides what comes next. R restarts (R12).
## Also owns the pause menu (user ruling 2026-08-31): the TopBar's MENU
## button (via Game.menu_requested) or Esc opens Resume / Save / Load /
## Restart / Quit to Desktop.

enum State {MENU, CONVERSATION, COURT, DAY_RUN}

const MENU_SCENE := preload("res://scenes/main_menu.tscn")
const CONVERSATION_SCENE := preload("res://scenes/conversation.tscn")
const COURT_SCENE := preload("res://scenes/court.tscn")
const DAY_RUN_SCENE := preload("res://scenes/day_run.tscn")

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
## The PROVINCES tab's state (user request 2026-09-09): root-owned so it
## survives moving between screens, applied to whichever screen's map shows.
var _province_view := true  # the map opens with the seams on (owner 2026-09-12)
var _height_view := false
var _economy_view := false
var _manor_view := false
## The MILITARY tab's state (user request 2026-09-10), owned here for the
## same reason: the layer follows the player from screen to screen.
var _army_view := false

## The design viewport (project.godot window/size): all UI is authored
## against this and scaled to the player's screen by the canvas_items+expand
## stretch. The OS window may never shrink below it, or panels would clip.
const MIN_WINDOW_SIZE := Vector2i(1280, 720)

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
		var out := Game.advance_day()
		for w: Dictionary in out["finished"]:
			Game.publish_news("A %s stands at %s." % [
				String((Game.data.manor_buildings.get(String(w["building"]), {}) as Dictionary).get("label", w["building"])).to_lower(),
				MapManors.label_of(Game.data, int(w["cell"]))])
		if bool(out["ticked"]):
			_pending_report = Game.current_report
			if not Game.state.pending_event.is_empty():
				Game.set_clock_speed(0)
				_clock_acc = 0.0
				_switch_to(State.CONVERSATION)
				current_screen.start([{"kind": "event", "portrait_id": "round_table",
					"speaker": "The Council",
					"event": Game.state.pending_event.duplicate(true)}], _pending_report)
				return

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
		"ECONOMY":
			_info_screen.hide()
			_relations_screen.visible = false
			set_economy_view(not _economy_view)
		"MANORS":
			_info_screen.hide()
			_relations_screen.visible = false
			set_manor_view(not _manor_view)
		"MILITARY":
			_info_screen.hide()
			_relations_screen.visible = false
			set_army_view(not _army_view)
		"RELATIONSHIP":
			_info_screen.hide()
			toggle_relations()
		_:
			_relations_screen.visible = false
			_info_screen.show_tab(tab)

## The province view is ALWAYS on (owner 2026-09-13: the PROVINCES tab and
## the P key went — the seams and province clicks are part of the map).
## Kept as the one place that would turn it off, for tools and tests.
func set_province_view(on: bool) -> void:
	_province_view = on
	if _bottom_bar != null:
		_bottom_bar.set_toggled("PROVINCES", on)
	var map := _current_map()
	if map != null and map.show_provinces != on:
		map.show_provinces = on

func province_view() -> bool:
	return _province_view

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
	var map := _current_map()
	if map != null and map.show_heights != on:
		map.show_heights = on

func height_view() -> bool:
	return _height_view

## Turn the economy view on or off everywhere (owner request 2026-09-13): the
## tab lights up, the map washes every province in the category of what it
## makes most of, and the screen's LEFT column lists what the realm produces
## — the same pattern the military layer follows.
func set_economy_view(on: bool) -> void:
	_economy_view = on
	if on and _manor_view:
		set_manor_view(false)
	if _bottom_bar != null:
		_bottom_bar.set_toggled("ECONOMY", on)
	var map := _current_map()
	if map != null and map.show_economy != on:
		map.show_economy = on
	if current_screen != null and current_screen.has_method("set_economy_view"):
		current_screen.set_economy_view(on)

func economy_view() -> bool:
	return _economy_view

## Turn the MANORS view on or off everywhere (MANOR_SYSTEM.md §6): the tab
## lights up, the map colours every manor by the house that holds it, and
## the screen's LEFT column lists the manors (the Manor Master). A theme
## like HEIGHTS and ECONOMY, so lighting it puts those out, and they it.
func set_manor_view(on: bool) -> void:
	_manor_view = on
	if on:
		if _economy_view:
			set_economy_view(false)
		if _height_view:
			set_height_view(false)
	if _bottom_bar != null:
		_bottom_bar.set_toggled("MANORS", on)
	var map := _current_map()
	if map != null and map.show_manors != on:
		map.show_manors = on
	if current_screen != null and current_screen.has_method("set_manor_view"):
		current_screen.set_manor_view(on)

func manor_view() -> bool:
	return _manor_view

## Turn the military layer on or off everywhere (user request 2026-09-10):
## the tab lights up, the current screen's map draws the realm's regiments
## with their strength bars, and the screen's LEFT column shows the host.
func set_army_view(on: bool) -> void:
	_army_view = on
	if _bottom_bar != null:
		_bottom_bar.set_toggled("MILITARY", on)
	var map := _current_map()
	if map != null:
		map.show_armies = on
	if current_screen != null and current_screen.has_method("set_military_view"):
		current_screen.set_military_view(on)

func army_view() -> bool:
	return _army_view

## The map of the screen that is showing, if it has one.
func _current_map() -> WorldMapView:
	if current_screen != null and current_screen.has_method("world_map"):
		return current_screen.world_map()
	return null

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
			current_screen.end_turn_requested.connect(_on_end_turn_requested)
		State.DAY_RUN:
			current_screen = DAY_RUN_SCENE.instantiate()
			current_screen.finished.connect(_on_day_run_finished)
	add_child(current_screen)
	# The province view follows the player across screens: the new screen's
	# map takes the tab's state, and the map's own P key reports back.
	var map := _current_map()
	if map != null:
		map.show_provinces = _province_view
		map.show_armies = _army_view
		map.province_view_changed.connect(set_province_view)
	if current_screen != null and current_screen.has_method("set_military_view"):
		current_screen.set_military_view(_army_view)
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

const BACKGROUND_STORY_PATH := "res://game_story/background/game_start.md"

func _on_start_requested() -> void:
	Game.start_campaign(42)
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

## The story background (game_story/background/game_start.md) with markdown
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

func _on_end_turn_requested() -> void:
	# Holding council stops the clock (2026-09-13): the player starts it
	# again when the court reconvenes.
	Game.set_clock_speed(0)
	_clock_acc = 0.0
	_pending_report = Game.next_tick()
	_switch_to(State.DAY_RUN)
	current_screen.run(_pending_report)

func _on_day_run_finished() -> void:
	_switch_to(State.CONVERSATION)
	current_screen.start(ConversationBeats.build(_pending_report, Game.state, Game.data), _pending_report)

## The conversation stage already spoke the event/concerns/pitches/outcomes
## (spec §3, R2); COURT re-entered after it shows only the order-bar state
## (metrics + suggestions), not a re-rendered briefing/outcome transcript.
func _on_conversation_finished() -> void:
	_switch_to(State.COURT)
	current_screen.enter_court(_pending_report)
	_pending_report = null
