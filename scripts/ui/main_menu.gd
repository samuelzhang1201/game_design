class_name MainMenu
extends Control
## Title screen (user rulings 2026-08-30): a visible menu — Start Game, Load
## Game, Quit — instead of the old press-Space-only screen. Start Game opens
## character creation: first name, family name, and a family flag (simple
## icons for now). The chosen family name is inherited by every role of the
## player's house (GameState.apply_player_setup). Space still quick-starts
## with defaults.

signal start_requested
signal load_requested

var _menu_col: VBoxContainer
var _setup_panel: PanelContainer
var _first_name: LineEdit
var _family_name: LineEdit
var _flag_buttons: Array = []
var _selected_flag := 0
var _status: Label

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
	_build_menu()
	_build_setup_panel()

func _build_menu() -> void:
	_menu_col = VBoxContainer.new()
	_menu_col.name = "MenuCol"
	_menu_col.add_theme_constant_override("separation", 6)
	_menu_col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu_col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu_col.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_menu_col)
	var title := Label.new()
	title.text = "Crown and Council"
	UiPalette.style_header(title, 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_col.add_child(title)
	_menu_col.add_child(_menu_button("Start Game", _open_setup))
	_menu_col.add_child(_menu_button("Load Game", _on_load_pressed))
	_menu_col.add_child(_menu_button("Quit", func() -> void: get_tree().quit()))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 9)
	_status.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	_menu_col.add_child(_status)
	var hint := Label.new()
	hint.text = "Space: take the throne with the founding name"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 8)
	_menu_col.add_child(hint)

func _menu_button(label: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.name = label.replace(" ", "")
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(handler)
	return btn

## Character creation: names + family flag, then Begin Reign.
func _build_setup_panel() -> void:
	_setup_panel = PanelContainer.new()
	_setup_panel.name = "SetupPanel"
	_setup_panel.visible = false
	_setup_panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.GOLD, 1, 12))
	_setup_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_setup_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_setup_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_setup_panel.custom_minimum_size = Vector2(190, 0)
	add_child(_setup_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	_setup_panel.add_child(col)
	var title := Label.new()
	title.text = "FOUND YOUR DYNASTY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiPalette.style_header(title, 11)
	col.add_child(title)
	col.add_child(HSeparator.new())
	col.add_child(_field_label("Given name"))
	_first_name = LineEdit.new()
	_first_name.name = "FirstName"
	_first_name.text = "Aldric"
	_first_name.max_length = 16
	col.add_child(_first_name)
	col.add_child(_field_label("Family name"))
	_family_name = LineEdit.new()
	_family_name.name = "FamilyName"
	_family_name.text = "Valorin"
	_family_name.max_length = 16
	col.add_child(_family_name)
	col.add_child(_field_label("Family flag"))
	var flags := HBoxContainer.new()
	flags.name = "FlagRow"
	flags.add_theme_constant_override("separation", 4)
	col.add_child(flags)
	for i in UiPalette.FLAGS.size():
		var f: Dictionary = UiPalette.FLAGS[i]
		var btn := Button.new()
		btn.name = "Flag_" + String(f["id"])
		btn.text = String(f["symbol"])
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(24, 24)
		btn.add_theme_color_override("font_color", f["color"])
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_select_flag.bind(i))
		flags.add_child(btn)
		_flag_buttons.append(btn)
	_select_flag(0)
	col.add_child(HSeparator.new())
	var begin := _menu_button("Begin Reign", _on_begin_pressed)
	begin.name = "BeginReign"
	col.add_child(begin)
	var back := _menu_button("Back", _close_setup)
	back.name = "Back"
	col.add_child(back)

func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	return l

func _select_flag(index: int) -> void:
	_selected_flag = index
	for i in _flag_buttons.size():
		var f: Dictionary = UiPalette.FLAGS[i]
		_flag_buttons[i].add_theme_stylebox_override("normal",
			UiPalette.chip_style(UiPalette.CHIP_BG,
				f["color"] if i == index else UiPalette.BORDER_GOLD))

func _open_setup() -> void:
	_menu_col.visible = false
	_setup_panel.visible = true

func _close_setup() -> void:
	_setup_panel.visible = false
	_menu_col.visible = true

func _on_begin_pressed() -> void:
	Game.player_setup = {
		"first_name": _first_name.text.strip_edges(),
		"family_name": _family_name.text.strip_edges(),
		"flag": String(UiPalette.FLAGS[_selected_flag]["id"]),
	}
	start_requested.emit()

func _on_load_pressed() -> void:
	load_requested.emit()

func show_load_failed() -> void:
	_status.text = "No saved realm found."

## Test seams.
func setup_panel() -> PanelContainer:
	return _setup_panel

func menu_column() -> VBoxContainer:
	return _menu_col

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_game") and not _setup_panel.visible:
		Game.player_setup = {}
		start_requested.emit()
