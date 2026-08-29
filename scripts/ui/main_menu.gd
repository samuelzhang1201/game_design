class_name MainMenu
extends Control
## R13: minimal title screen - Space (or Enter) starts.

signal start_requested

func _ready() -> void:
	var backdrop := TextureRect.new()
	backdrop.texture = UiPalette.backdrop()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var bg := ColorRect.new()
	bg.color = UiPalette.DIM_OVERLAY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var frame := TextureRect.new()
	UiPalette.setup_frame(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(col)
	var title := Label.new()
	title.text = "Crown and Council"
	UiPalette.style_header(title, 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var hint := Label.new()
	hint.text = "press Space to take the throne"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	hint.add_theme_font_size_override("font_size", 10)
	col.add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_game"):
		start_requested.emit()
