class_name GameRoot
extends Control
## Flow state machine (spec §2). Owns exactly one screen scene at a time;
## screens signal upward, GameRoot decides what comes next. R restarts (R12).

enum State {MENU, CONVERSATION, COURT, DAY_RUN}

const MENU_SCENE := "res://scenes/main_menu.tscn"
const COURT_SCENE := "res://scenes/court.tscn"

var state: State = State.MENU
var current_screen: Node
var _pending_report: TickReport

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_switch_to(State.MENU)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_R \
			and state != State.MENU:
		Game.restart()
		_switch_to(State.MENU)

func _switch_to(new_state: State) -> void:
	if current_screen != null:
		current_screen.queue_free()
		current_screen = null
	state = new_state
	match new_state:
		State.MENU:
			current_screen = load(MENU_SCENE).instantiate()
			current_screen.start_requested.connect(_on_start_requested)
		State.CONVERSATION:
			current_screen = load("res://scenes/conversation.tscn").instantiate()
			current_screen.finished.connect(_on_conversation_finished)
		State.COURT:
			current_screen = load(COURT_SCENE).instantiate()
			current_screen.end_turn_requested.connect(_on_end_turn_requested)
		State.DAY_RUN:
			current_screen = load("res://scenes/day_run.tscn").instantiate()
			current_screen.finished.connect(_on_day_run_finished)
	add_child(current_screen)

func _on_start_requested() -> void:
	Game.start_campaign(42)
	_pending_report = Game.next_tick()
	_switch_to(State.CONVERSATION)
	current_screen.start(ConversationBeats.build(_pending_report, Game.state, Game.data), _pending_report)

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
