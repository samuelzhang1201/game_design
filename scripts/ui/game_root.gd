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
var _pause_menu: Control
var _pause_status: Label
var _relations_screen: RelationshipGraphScreen
var _bottom_bar: BottomBar
var _news_ticker: NewsTicker
var _info_screen: InfoScreen
var _bgm: AudioStreamPlayer

## The design viewport (project.godot window/size): all UI is authored
## against this and scaled to the player's screen by the canvas_items+expand
## stretch. The OS window may never shrink below it, or panels would clip.
const MIN_WINDOW_SIZE := Vector2i(640, 360)

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
		UiPalette.panel_style(UiPalette.GOLD, 1, 14))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(150, 0)
	_pause_menu.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = "COUNCIL IN RECESS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.style_header(title, 10)
	col.add_child(title)
	col.add_child(_menu_button("Resume", toggle_pause_menu))
	col.add_child(_menu_button("Save Game", _on_menu_save))
	col.add_child(_menu_button("Load Game", _on_menu_load))
	col.add_child(_menu_button("Restart", _on_menu_restart))
	col.add_child(_menu_button("Quit to Desktop", func() -> void: get_tree().quit()))
	_pause_status = Label.new()
	_pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_status.add_theme_font_size_override("font_size", 9)
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

## Bottom bar routing: MAP is the default view (close every overlay),
## RELATIONSHIP toggles the graph, the rest open their info table.
func _on_bottom_tab(tab: String) -> void:
	match tab:
		"MAP":
			_info_screen.hide()
			_relations_screen.visible = false
		"RELATIONSHIP":
			_info_screen.hide()
			toggle_relations()
		_:
			_relations_screen.visible = false
			_info_screen.show_tab(tab)

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
## chrome stripped for in-game narration. Empty when the file is absent.
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
	return "\n".join(lines).strip_edges()

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
