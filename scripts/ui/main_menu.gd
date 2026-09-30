class_name MainMenu
extends Control
## Title screen (user rulings 2026-08-30): a visible menu — Start Game, Load
## Game, Quit — instead of the old press-Space-only screen. Start Game and
## Space both begin the reign at once with the founding names: the realm and
## the ruler are not customised (owner 2026-09-30; the character-creation
## panel of 2026-09-15 is gone).

signal start_requested
signal load_requested

const PAGE_SHADER := preload("res://scripts/ui/shaders/menu_page.gdshader")

var _menu_col: VBoxContainer
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
	frame.name = "Page"
	UiPalette.setup_frame(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The painted page by candlelight (owner 2026-09-28, second critique: a
	# bright parchment title screen before a dark-leather game): dimmed by
	# the paper alone (menu_page.gdshader), the menu a leather window over it like the game's own.
	if Game != null and Game.data != null:
		var mat := ShaderMaterial.new()
		mat.shader = PAGE_SHADER
		mat.set_shader_parameter("paper_dim", Game.data.bal("ui_menu_page_dim"))
		mat.set_shader_parameter("ink_dim", Game.data.bal("ui_menu_ink_dim"))
		mat.set_shader_parameter("warm", Game.data.bal("ui_menu_page_warm"))
		frame.material = mat
	add_child(frame)
	_build_menu()

func _build_menu() -> void:
	# The menu is a floating window, so it wears the window's leather and
	# ornament (UiPalette.panel_style "window").
	var card := PanelContainer.new()
	card.name = "MenuCard"
	card.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 32, "window"))
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.custom_minimum_size = Vector2(440, 0)
	add_child(card)
	_menu_col = VBoxContainer.new()
	_menu_col.name = "MenuCol"
	_menu_col.add_theme_constant_override("separation", 12)
	card.add_child(_menu_col)
	var title := Label.new()
	title.text = "Crown and Council"
	UiPalette.style_title(title, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu_col.add_child(title)
	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 10)
	_menu_col.add_child(rule)
	var start := _menu_button("Start Game", _start)
	# The screen's one primary action, said where the player looks for it
	# rather than in a footer line (owner 2026-09-28: the footer read as a
	# debug hint).
	UiPalette.primary_button(start, 18)
	start.tooltip_text = "Or press Space to take the throne"
	_menu_col.add_child(start)
	_menu_col.add_child(_menu_button("Load Game", _on_load_pressed))
	_menu_col.add_child(_menu_button("Quit", func() -> void: get_tree().quit()))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	_menu_col.add_child(_status)

func _menu_button(label: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.name = label.replace(" ", "")
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	UiPalette.command_button(btn)
	btn.pressed.connect(handler)
	return btn

## The reign begins with the founding names (no player setup).
func _start() -> void:
	Game.player_setup = {}
	start_requested.emit()

func _on_load_pressed() -> void:
	load_requested.emit()

func show_load_failed() -> void:
	_status.text = "No saved realm found."

## Test seam.
func menu_column() -> VBoxContainer:
	return _menu_col

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_game"):
		_start()
