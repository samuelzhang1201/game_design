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
## The living map waits for the boot's threaded loads (BootLoads.title_ready)
## and for the title's first frames, so the painted page shows at once and the
## map opens over it (owner 2026-10-10: no black screen at launch).
var _realm_waiting := false
var _frames_shown := 0
## The title's last frame, kept as the reign begins for TableLanding (GameRoot
## takes it once, after the switch).
static var landing_frame: Texture2D

## The living title is the scene's (owner 2026-10-02: the look lives in the
## editor — scenes/screens/main_menu.tscn); _ready fills its words and wires it. The
## leather page of `ui_war_table` 0 is still dressed in code.
func _ready() -> void:
	if not UiPalette.war_table():
		_dress_leather()
		return
	_fill_living_title()

func _dress_leather() -> void:
	for node_name in ["Shade", "TitleColumn", "Caption"]:
		var n := get_node_or_null(node_name)
		if n != null:
			remove_child(n)
			n.free()
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
	if not leave(func() -> void: start_requested.emit()):
		start_requested.emit()

## The living title's way into the game, the SAME for Take the Throne and
## Continue the Chronicle (owner 2026-10-01: 点击Continue the Chronicle时，也要有
## 同样的动画效果): the column fades, the camera sweeps down to the opening view
## over the home of `to` (the loaded reign; null the preview's), the map as it
## lies then is kept for TableLanding, then `done` (GameRoot takes the live
## view through `hand_over` as it lays the first screen). False — nothing
## done — without a living map (none, or not yet open): the caller goes on.
func leave(done: Callable, to: GameState = null) -> bool:
	if _starting:
		return true
	if _realm == null or not _realm.is_open() or _realm.view == null or _realm.view.context() == null:
		return false
	_starting = true
	var fade := create_tween().set_parallel(true)
	for node_name in ["TitleColumn", "Caption", "Shade"]:
		var n := get_node_or_null(node_name) as CanvasItem
		if n != null:
			fade.tween_property(n, "modulate:a", 0.0, Game.data.bal("ui_title_sweep_s") * 0.35)
	_realm.swept.connect(func() -> void:
		# the map as it lies now becomes the sheet that is laid on the table
		landing_frame = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
		done.call(), CONNECT_ONE_SHOT)
	_realm.sweep(to)
	return true

## THE LIVING REALM (owner 2026-10-01, title plan A): the live map of the home
## province behind (TitleRealm; the scene's painted Backdrop when no world is
## built), the reading side darkened (the scene's Shade), and down the left
## the house's arms, the name, the game's own first line and the menu as
## words — the SAME rows as the pause menu (GameRoot hands them in, and they
## wear the scene's own word look) — and bottom right the place, like a
## painting's label. Every look is the scene's; this fills the words.
func _fill_living_title() -> void:
	_preview = GameState.new_campaign(Game.data, int(Game.data.bal("ui_title_seed")))
	_realm_waiting = TitleRealm.available()
	_left = $TitleColumn
	($TitleColumn/Col/TitleArms as HeraldicShield).set_texture(
		HouseArms.texture_of_house(Game.data, _preview, MapManors.crown(_preview)))
	var words := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
	var n := Game.data.seats.size()
	($TitleColumn/Col/Tagline as Label).text = "Sixty years · one crown · %s seats at the table" % (
		words[n] if n < words.size() else str(n))
	_menu_col = %MenuCol
	_status = %MenuCol.get_node("Status")
	($TitleColumn/Col/MenuCol/StartGame as Button).pressed.connect(_start)
	($TitleColumn/Col/MenuCol/LoadGame as Button).pressed.connect(_on_load_pressed)
	if quit == null:
		quit = _menu_button("Quit to Desktop", func() -> void: get_tree().quit())
		quit.name = "Quit"
	for b: Button in settings + [quit]:
		_title_word(b)
		_menu_col.add_child(b)
		_menu_col.move_child(b, _status.get_index())
	var cap := TitleRealm.caption_of(_preview)
	($Caption/Place as Label).text = "%s, seat of House %s" % [cap["place"], cap["house"]]
	($Caption/When as Label).text = "%s, the first year of the reign" % cap["season"]

## The living map, made once the boot's loads are in and the painted page has
## been shown (ui_title_reveal_frames frames): the realm behind the page, the
## page fading off it over ui_title_reveal_s. Never once the title is leaving.
func _process(_delta: float) -> void:
	if not _realm_waiting:
		return
	_frames_shown += 1
	if _starting:
		_realm_waiting = false
		return
	if _frames_shown < int(Game.data.bal("ui_title_reveal_frames")) or not BootLoads.title_ready():
		return
	_realm_waiting = false
	_realm = TitleRealm.new()
	_realm.name = "LivingRealm"
	_realm.preview = _preview
	add_child(_realm)
	move_child(_realm, 0)
	_realm.opened.connect(_reveal_realm, CONNECT_ONE_SHOT)

## The live map is up: the painted page fades off it (ui_title_reveal_s).
func _reveal_realm() -> void:
	if _starting or _realm.view == null or _realm.view.context() == null:
		return
	var page := $Backdrop as CanvasItem
	create_tween().tween_property(page, "modulate:a", 0.0, Game.data.bal("ui_title_reveal_s")) \
		.finished.connect(func() -> void: page.visible = false)

## Whether the living map is still to come or opening (tools wait on it).
func realm_pending() -> bool:
	return _realm_waiting or (_realm != null and not _realm.is_open())

## A row GameRoot hands in, as a word on the map: the theme's TitleWordSmall
## (no box, the body face, a gold underline under the pointer).
func _title_word(b: Button) -> void:
	# made for the pause menu's leather (command_button's face): give the row
	# back to the theme kind, whose face and size are the title's
	b.remove_theme_font_override("font")
	b.remove_theme_font_size_override("font_size")
	b.theme_type_variation = &"TitleWordSmall"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

## The live view handed to the game's first screen (TitleRealm.hand_over),
## once; nothing when the title has none.
func hand_over() -> void:
	if _realm != null:
		_realm.hand_over()

## Continue the Chronicle: GameRoot loads the save, then leaves through `leave`.
func _on_load_pressed() -> void:
	if not _starting:
		load_requested.emit()

func show_load_failed(why := "No saved realm found.") -> void:
	_status.text = why

## Test seam.
func menu_column() -> VBoxContainer:
	return _menu_col

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_game"):
		_start()
