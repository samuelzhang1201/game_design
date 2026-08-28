class_name GameRoot
extends Control
## Flow state machine (spec §2). Owns exactly one screen scene at a time;
## screens signal upward, GameRoot decides what comes next. R restarts (R12).

enum State {MENU, CONVERSATION, COURT, DAY_RUN}

const MENU_SCENE := "res://scenes/main_menu.tscn"
const COURT_SCENE := "res://scenes/council.tscn"  # interim: Task 6 swaps to court.tscn

var state: State = State.MENU
var current_screen: Node

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
		State.COURT:
			current_screen = load(COURT_SCENE).instantiate()
			# interim flow: council.tscn drives its own tick/interlude until
			# Tasks 4-6 move that orchestration here.
	add_child(current_screen)

func _on_start_requested() -> void:
	Game.start_campaign(42)
	Game.next_tick()
	# interim: straight to COURT; Task 5 inserts CONVERSATION here.
	_switch_to(State.COURT)
