class_name WarPlanName
extends PanelContainer
## The one-line box that names a phase line or an objective (spec
## 2026-10-07-war-room-annotations-and-planning-pieces ruling 16): opened at
## the release point prefilled with the next free default; Enter keeps what is
## written, Escape keeps the default. Its look is the scene's.

signal named(id: String, text: String)

var _id := ""
var _default := ""

@onready var _edit: LineEdit = %NameEdit


func _ready() -> void:
	_edit.text_submitted.connect(func(t: String) -> void: _done(t))
	_edit.focus_exited.connect(commit)   # clicking anywhere else keeps what is written
	_edit.gui_input.connect(func(e: InputEvent) -> void:
		var k := e as InputEventKey
		if k != null and k.pressed and k.keycode == KEY_ESCAPE:
			_done(_default)
			_edit.accept_event())


func open_at(id: String, text: String, pointer: Vector2, bounds: Rect2, max_chars: int) -> void:
	_id = id
	_default = text
	_edit.max_length = max_chars
	_edit.text = text
	visible = true
	reset_size()
	position = WarHoverSlip.place(pointer, get_combined_minimum_size(), bounds, 12.0)
	_edit.grab_focus()
	_edit.select_all()


## Keeps what is written and closes (a press on the table, focus lost).
func commit() -> void:
	_done(_edit.text)


func _done(text: String) -> void:
	if not visible:
		return
	visible = false
	var t := text.strip_edges()
	named.emit(_id, t if t != "" else _default)
