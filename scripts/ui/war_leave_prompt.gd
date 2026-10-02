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
	mouse_filter = Control.MOUSE_FILTER_STOP
	(%LeaveDim as ColorRect).color = UiPalette.DIM_OVERLAY
	(%LeaveDim as ColorRect).gui_input.connect(func(e: InputEvent) -> void:
		var b := e as InputEventMouseButton
		if b != null and b.pressed:
			_choose("stay"))
	(%LeaveWindow as PanelContainer).add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 24, "window"))
	(%LeaveQuestion as Label).add_theme_font_size_override("font_size", 18)
	(%LeaveQuestion as Label).add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	for pair: Array in [[%LeaveDeploy, "deploy"], [%LeaveDiscard, "discard"], [%LeaveKeep, "keep"], [%LeaveStay, "stay"]]:
		var b := pair[0] as Button
		if pair[1] == "deploy":
			UiPalette.primary_button(b, 15)
		else:
			UiPalette.command_button(b)
		b.pressed.connect(_choose.bind(String(pair[1])))


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
