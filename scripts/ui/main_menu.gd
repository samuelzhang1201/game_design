class_name MainMenu
extends Control
## R13: minimal title screen - Space (or Enter) starts.

signal start_requested

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a1423")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(col)
	var title := Label.new()
	title.text = "Crown and Council"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("deba54"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var hint := Label.new()
	hint.text = "press Space to take the throne"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("8c86a0"))
	col.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and (event.keycode == KEY_SPACE or event.is_action_pressed("ui_accept")):
		start_requested.emit()
