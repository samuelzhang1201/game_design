class_name WarLeavePrompt
extends Control
## Leaving the WAR ROOM with orders still pencilled (owner 2026-10-02, spec
## 2026-10-02-war-room-v2 §3.2): Deploy… (unroll the resolutions and seal
## them), Discard (rub them out), Keep (they stay on the table, saved, for the
## next visit) — or Stay, Escape or a click on the dim to remain in the room.
## A leather window, as everything held up to the eye; it covers the room so
## no click passes through to a piece.

signal chosen(choice: String)


func _ready() -> void:
	visible = false
	# its look is the room's scene (owner 2026-10-02): the veil, the leather
	# window (leather_window_24.tres), the question, Deploy… a Primary, the
	# rest Commands, Discard's word in gules
	(%LeaveDim as ColorRect).gui_input.connect(func(e: InputEvent) -> void:
		var b := e as InputEventMouseButton
		if b != null and b.pressed:
			_choose("stay"))
	for pair: Array in [[%LeaveDeploy, "deploy"], [%LeaveDiscard, "discard"], [%LeaveKeep, "keep"], [%LeaveStay, "stay"]]:
		(pair[0] as Button).pressed.connect(_choose.bind(String(pair[1])))


func open() -> void:
	visible = true
	(%LeaveDeploy as Button).grab_focus()


func _choose(choice: String) -> void:
	if not visible:
		return
	visible = false
	chosen.emit(choice)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k != null and k.pressed and k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_choose("stay")
