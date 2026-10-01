class_name MainMenu
extends Control
## Title screen (user rulings 2026-08-30): a visible menu — Start Game, Load
## Game, the settings rows and Quit to Desktop, the SAME settings rows, Quit
## and window as the pause menu (owner 2026-09-30: 游戏开始的UI和游戏内的menu
## 功能要一致; GameRoot hands both menus their rows) — instead of the old
## press-Space-only screen. Start Game and
## Space both begin the reign at once with the founding names: the realm and
## the ruler are not customised (owner 2026-09-30; the character-creation
## panel of 2026-09-15 is gone).

signal start_requested
signal load_requested

const PAGE_SHADER := preload("res://scripts/ui/shaders/menu_page.gdshader")
## Both menus' window width, design px (the pause menu wears it too).
const MENU_WIDTH := 440.0

## The settings rows and the Quit row, handed in by GameRoot before the menu
## enters the tree (GameRoot.settings_buttons / quit_button); a menu made
## alone (a test, a tool) makes its own plain Quit.
var settings: Array[Button] = []
var quit: Button = null

var _menu_col: VBoxContainer
var _status: Label
## THE LIVING REALM (owner 2026-10-01, title plan A): the live map behind the
## title (null without a built world), the reign it shows, and the left
## column of the title that fades as the camera sweeps in.
var _realm: TitleRealm
var _preview: GameState
var _left: Control
var _starting := false
## The title's last frame, kept as the reign begins for TableLanding (GameRoot
## takes it once, after the switch).
static var landing_frame: Texture2D

func _ready() -> void:
	if UiPalette.war_table():
		_build_living_title()
		return
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
	card.custom_minimum_size = Vector2(MENU_WIDTH, 0)
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
	for b: Button in settings:
		_menu_col.add_child(b)
	if quit == null:
		quit = _menu_button("Quit to Desktop", func() -> void: get_tree().quit())
		quit.name = "Quit"
	_menu_col.add_child(quit)
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

## The reign begins with the founding names (no player setup). On the living
## title the column fades and the camera sweeps down into the opening view
## first; the reign begins when it lands.
func _start() -> void:
	if _starting:
		return
	Game.player_setup = {}
	if _realm == null or _realm.view == null or _realm.view.context() == null:
		start_requested.emit()
		return
	_starting = true
	var fade := create_tween().set_parallel(true)
	for node_name in ["TitleColumn", "Caption", "Shade"]:
		var n := get_node_or_null(node_name) as CanvasItem
		if n != null:
			fade.tween_property(n, "modulate:a", 0.0, Game.data.bal("ui_title_sweep_s") * 0.35)
	_realm.swept.connect(func() -> void:
		# the map as it lies now becomes the sheet that is laid on the table
		landing_frame = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
		_realm.hand_over()
		start_requested.emit(), CONNECT_ONE_SHOT)
	_realm.sweep()

## THE LIVING REALM (owner 2026-10-01, title plan A): the live map of the home
## province behind (TitleRealm; the painted page when no world is built), the
## reading side darkened, and down the left the house's arms, the name in
## blackletter, a line, the game's own first line and the menu as words — the
## SAME rows as the pause menu (GameRoot hands them in) — and bottom right the
## place, like a painting's label.
func _build_living_title() -> void:
	_preview = GameState.new_campaign(Game.data, int(Game.data.bal("ui_title_seed")))
	if TitleRealm.available():
		_realm = TitleRealm.new()
		_realm.name = "LivingRealm"
		_realm.preview = _preview
		add_child(_realm)
	else:
		var backdrop := TextureRect.new()
		backdrop.texture = UiPalette.backdrop()
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(backdrop)
	var shade := Control.new()
	shade.name = "Shade"
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.draw.connect(func() -> void: _draw_shade(shade))
	shade.resized.connect(shade.queue_redraw)
	add_child(shade)
	var ink := UiPalette.table_color("table_ink", UiPalette.TEXT_SOFT)
	var gold := UiPalette.GOLD
	var muted := Color(ink, 0.62)
	_left = MarginContainer.new()
	_left.name = "TitleColumn"
	_left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_left.offset_left = 120
	_left.offset_right = 120 + MENU_WIDTH + 80
	add_child(_left)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	_left.add_child(col)
	var arms := HeraldicShield.new()
	arms.name = "TitleArms"
	arms.custom_minimum_size = Vector2(54, 64)
	arms.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var family := MapManors.crown(_preview)
	arms.set_texture(HouseArms.texture_of_house(Game.data, _preview, family))
	col.add_child(arms)
	for line: Array in [["Crown", 0.0], ["and Council", 34.0]]:
		var t := Label.new()
		t.name = "Title_" + String(line[0]).replace(" ", "")
		t.text = String(line[0])
		UiPalette.style_title(t, 64, gold)
		t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		t.add_theme_constant_override("shadow_offset_y", 2)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", int(line[1]))
		pad.add_child(t)
		col.add_child(pad)
	var rule := ColorRect.new()
	rule.color = Color(gold, 0.45)
	rule.custom_minimum_size = Vector2(250, 1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(rule)
	var tag := Label.new()
	tag.name = "Tagline"
	var words := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
	var n := Game.data.seats.size()
	tag.text = "Sixty years · one crown · %s seats at the table" % (words[n] if n < words.size() else str(n))
	UiPalette.style_header(tag, 13, muted)
	col.add_child(tag)
	var hook := Label.new()
	hook.name = "Hook"
	hook.text = "\u201cThe realm your father left you is intact, solvent and quietly rotten.\u201d"
	hook.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hook.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	var italic := UiPalette.role_font("body_italic")
	if italic != null:
		hook.add_theme_font_override("font", italic)
	hook.add_theme_font_size_override("font_size", 15)
	hook.add_theme_color_override("font_color", muted)
	col.add_child(hook)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	col.add_child(gap)
	_menu_col = VBoxContainer.new()
	_menu_col.name = "MenuCol"
	_menu_col.add_theme_constant_override("separation", 2)
	col.add_child(_menu_col)
	var start := _menu_button("Start Game", _start)
	start.text = "Take the Throne"
	start.tooltip_text = "Or press Space to take the throne"
	_title_word(start, 26, ink, true)
	_menu_col.add_child(start)
	var load := _menu_button("Load Game", _on_load_pressed)
	load.text = "Continue the Chronicle"
	_title_word(load, 19, Color(ink, 0.85), false)
	_menu_col.add_child(load)
	for b: Button in settings:
		_title_word(b, 15, Color(ink, 0.72), false)
		_menu_col.add_child(b)
	if quit == null:
		quit = _menu_button("Quit to Desktop", func() -> void: get_tree().quit())
		quit.name = "Quit"
	_title_word(quit, 15, Color(ink, 0.72), false)
	_menu_col.add_child(quit)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", muted)
	_menu_col.add_child(_status)
	_build_caption(ink, muted)

## A menu row as a word on the map: no box, the tab face, a gold underline
## under the primary row and under any row the pointer is on.
func _title_word(b: Button, px: int, ink: Color, primary: bool) -> void:
	var under := StyleBoxFlat.new()
	under.bg_color = Color(0, 0, 0, 0)
	under.content_margin_left = 0
	under.content_margin_right = 0
	under.content_margin_top = 3
	under.content_margin_bottom = 4
	var lit := under.duplicate() as StyleBoxFlat
	lit.border_color = UiPalette.GOLD
	lit.border_width_bottom = 2
	for state in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, lit if primary else under)
	for state in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, lit)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var font := UiPalette.role_font("body")
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", px)
	for state in ["font_color", "font_focus_color", "font_disabled_color"]:
		b.add_theme_color_override(state, ink)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, UiPalette.table_color("brass_light", ink))
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	b.add_theme_constant_override("shadow_offset_y", 1)

## Bottom right, like a painting's label: the place the title shows.
func _build_caption(ink: Color, muted: Color) -> void:
	var cap := _realm.caption() if _realm != null else {}
	if cap.is_empty():
		var code := MapManors.home_province(Game.data, _preview)
		var p: Dictionary = Game.data.provinces.get(code, {})
		var burg := String(p.get("capital_burg", ""))
		cap = {"place": String(Game.data.burgs.get(burg, p).get("label", code)),
			"house": MapManors.crown(_preview), "season": Calendar.season_name(_preview.tick)}
	var box := VBoxContainer.new()
	box.name = "Caption"
	box.alignment = BoxContainer.ALIGNMENT_END
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -56
	box.offset_bottom = -40
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var place := Label.new()
	place.name = "Place"
	place.text = "%s, seat of House %s" % [cap["place"], cap["house"]]
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UiPalette.style_header(place, 13, ink)
	place.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	box.add_child(place)
	var when := Label.new()
	when.name = "When"
	when.text = "%s, the first year of the reign" % cap["season"]
	when.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var italic := UiPalette.role_font("body_italic")
	if italic != null:
		when.add_theme_font_override("font", italic)
	when.add_theme_font_size_override("font_size", 14)
	when.add_theme_color_override("font_color", muted)
	when.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	box.add_child(when)

## The reading side: dark at the left edge fading out by ui_title_shade_reach,
## and the corners a touch darker.
func _draw_shade(c: Control) -> void:
	var w := c.size.x
	var h := c.size.y
	var dark := Color(0.055, 0.04, 0.03, Game.data.bal("ui_title_shade"))
	var clear := Color(dark, 0.0)
	var reach := w * Game.data.bal("ui_title_shade_reach")
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(reach, 0), Vector2(reach, h), Vector2(0, h)]),
		PackedColorArray([dark, clear, clear, dark]))
	var band := h * 0.22
	var edge := Color(dark, dark.a * 0.55)
	var edge0 := Color(dark, 0.0)
	c.draw_polygon(PackedVector2Array([Vector2(0, h - band), Vector2(w, h - band), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([edge0, edge0, edge, edge]))
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, band * 0.6), Vector2(0, band * 0.6)]),
		PackedColorArray([edge, edge, edge0, edge0]))

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
