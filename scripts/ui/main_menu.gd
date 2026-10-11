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

var _menu_col: BoxContainer
var _status: Label
## THE LIVING REALM (owner 2026-10-01, title plan A): the live map behind the
## title (null without a built world), the reign it shows, and the words that
## fade as the camera sweeps in.
var _realm: TitleRealm
var _preview: GameState
var _starting := false
## The launch (owner 2026-10-11: 点击游戏图标后有一个短暂的黑屏加载时间，游戏主界面仍然是
## 近景首都旋转的视角): the scene's Curtain holds the window black while the
## boot's threaded loads (BootLoads.title_ready) come in and the living map is
## made behind it a step a frame; then the black lifts off the turning capital
## and the words come in one by one (data/screens/ui/title_entrance.csv, `_enter`).
var _realm_waiting := false
var _frames_shown := 0
var _waited := 0.0
var _entered := false
var _realm_shown := false
var _entrance: Tween
## The speaker top right is the Music row's switch; the row itself stays in
## the menu (the title and the pause menu are one menu), hidden.
var _music: Button
## The speaker's two faces, set on the scene.
@export var speaker_on: Texture2D
@export var speaker_off: Texture2D
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
	for node_name in ["Shade", "TopBar", "Hero", "Caption", "Curtain"]:
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
## 同样的动画效果): the words fade, the camera sweeps down to the opening view
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
	if _entrance != null:
		_entrance.kill()
	var fade := create_tween().set_parallel(true)
	for node_name in ["TopBar", "Hero", "Caption", "Shade", "Curtain"]:
		var n := get_node_or_null(node_name) as CanvasItem
		if n != null and n.visible:
			fade.tween_property(n, "modulate:a", 0.0, Game.data.bal("ui_title_sweep_s") * 0.35)
	_realm.swept.connect(func() -> void:
		# the map as it lies now becomes the sheet that is laid on the table
		landing_frame = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
		done.call(), CONNECT_ONE_SHOT)
	_realm.sweep(to)
	return true

## THE LIVING REALM as a hero (owner 2026-10-11, after a web hero the owner
## gave): the live capital turning full-bleed behind three layers of shade
## (the scene's Shade); top left the crown's arms and house, top right the
## settings and Quit as words in a dark pill and the music as a speaker;
## bottom left the tagline, the name in two lines, the game's first line and
## the two ways in — Take the Throne a cream pill, Continue the Chronicle a
## word; bottom right the place, like a painting's label. Every look is the
## scene's; this fills the words and wires the rows.
func _fill_living_title() -> void:
	_preview = GameState.new_campaign(Game.data, int(Game.data.bal("ui_title_seed")))
	_realm_waiting = TitleRealm.available()
	var crown := MapManors.crown(_preview)
	(%TitleArms as HeraldicShield).set_texture(HouseArms.texture_of_house(Game.data, _preview, crown))
	(%House as Label).text = "House %s" % crown
	var words := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
	var n := Game.data.seats.size()
	(%Tagline as Label).text = "Sixty years · one crown · %s seats at the table" % (
		words[n] if n < words.size() else str(n))
	_menu_col = %Nav
	_status = %Status
	(%StartGame as Button).pressed.connect(_start)
	(%LoadGame as Button).pressed.connect(_on_load_pressed)
	if quit == null:
		quit = _menu_button("Quit to Desktop", func() -> void: get_tree().quit())
		quit.name = "Quit"
	for b: Button in settings + [quit]:
		_title_word(b)
		_menu_col.add_child(b)
		if b.name == "MusicToggle":
			_music = b
			b.visible = false
	(%Sound as Button).pressed.connect(_on_sound_pressed)
	_show_sound()
	var cap := TitleRealm.caption_of(_preview)
	($Caption/Place as Label).text = "%s, seat of House %s" % [cap["place"], cap["house"]]
	($Caption/When as Label).text = "%s, the first year of the reign" % cap["season"]
	# black until the title enters (the scene keeps it off so the editor shows the title)
	$Curtain.visible = true
	for row: Dictionary in Game.data.title_entrance:
		var node := get_node_or_null(NodePath(String(row["node"]))) as CanvasItem
		if node != null and String(row["kind"]) != "curtain":
			for item: CanvasItem in _entrance_items(node, String(row["kind"])):
				item.modulate.a = 0.0

## The living map, made once the boot's loads are in and the black has been
## shown (ui_title_reveal_frames frames); the title enters once it is open,
## or after ui_title_failsafe_s over the bare table, or at once without a
## world. Never once the title is leaving.
func _process(delta: float) -> void:
	if _starting or not UiPalette.war_table():
		return
	_frames_shown += 1
	_waited += delta
	var frames_ok := _frames_shown >= int(Game.data.bal("ui_title_reveal_frames"))
	if _realm_waiting and frames_ok and BootLoads.title_ready():
		_realm_waiting = false
		_realm = TitleRealm.new()
		_realm.name = "LivingRealm"
		_realm.preview = _preview
		add_child(_realm)
		move_child(_realm, 0)
	if _realm != null and _realm.is_open() and not _realm_shown:
		_realm_shown = true
		_show_realm()
	if not _entered and frames_ok and (not TitleRealm.available() or (_realm != null and _realm.is_open())
			or _waited >= Game.data.bal("ui_title_failsafe_s")):
		_enter()

## The live map is open: the bare table goes (at once under the black, else
## fading off the map over the curtain's time).
func _show_realm() -> void:
	var page := $Backdrop as CanvasItem
	if _realm.view == null or _realm.view.context() == null:
		return  # the world would not open: the notice says why, the table stays
	if not _entered:
		page.visible = false
		return
	var t := create_tween()
	t.tween_property(page, "modulate:a", 0.0, _curtain_s())
	t.finished.connect(func() -> void: page.visible = false)

func _curtain_s() -> float:
	for row: Dictionary in Game.data.title_entrance:
		if String(row["kind"]) == "curtain":
			return float(row["duration_ms"]) / 1000.0
	return 0.0

## The entrance (data/screens/ui/title_entrance.csv, after the owner's web hero): the
## black lifts, then each piece comes in at its delay — `fade` in place,
## `lift` up from `lift_px` below (a negative one from above), `ripple` each
## shown child of the node lifting `step_ms` after the last, `rise` a line of
## the name up out of its own clip (`lift_px` per cent of its height).
func _enter() -> void:
	_entered = true
	_entrance = create_tween().set_parallel(true)
	for row: Dictionary in Game.data.title_entrance:
		var node := get_node_or_null(NodePath(String(row["node"]))) as CanvasItem
		if node == null:
			continue
		var kind := String(row["kind"])
		var delay := float(row["delay_ms"]) / 1000.0
		var dur := float(row["duration_ms"]) / 1000.0
		var lift := float(row["lift_px"])
		var trans := Tween.TRANS_QUART if String(row["ease"]) == "quart" else Tween.TRANS_EXPO
		if kind == "curtain":
			_entrance.tween_property(node, "modulate:a", 0.0, dur).set_delay(delay) \
				.set_trans(trans).set_ease(Tween.EASE_OUT)
			_entrance.tween_callback(node.hide).set_delay(delay + dur)
			continue
		var i := 0
		for item: CanvasItem in _entrance_items(node, kind):
			var at := delay + float(row["step_ms"]) / 1000.0 * i
			i += 1
			_entrance.tween_property(item, "modulate:a", 1.0, dur * (0.15 if kind == "rise" else 0.6)) \
				.set_delay(at).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			if kind == "fade" or not item is Control:
				continue
			var c := item as Control
			var rest := c.position.y
			var from := rest + (c.size.y * lift / 100.0 if kind == "rise" else lift)
			c.position.y = from
			_entrance.tween_property(c, "position:y", rest, dur).from(from).set_delay(at) \
				.set_trans(trans).set_ease(Tween.EASE_OUT)
	_entrance.finished.connect(func() -> void:
		# the static design again: every container lays its children out afresh
		for c: Control in [$TopBar, $Hero, $Caption]:
			c.propagate_notification(NOTIFICATION_RESIZED)
			if c is Container:
				(c as Container).queue_sort()
		for box in find_children("*", "Container", true, false):
			(box as Container).queue_sort())

## What one entrance row moves: the node, or for a ripple its shown children.
func _entrance_items(node: CanvasItem, kind: String) -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	if kind == "ripple":
		for c in node.get_children():
			if c is CanvasItem and (c as CanvasItem).visible:
				out.append(c)
	else:
		out.append(node)
	return out

## Whether the title is still to show itself whole (tools wait on it).
func realm_pending() -> bool:
	return _realm_waiting or (_realm != null and not _realm.is_open()) \
		or (UiPalette.war_table() and not _entered) or (_entrance != null and _entrance.is_running())

## A row GameRoot hands in, as a word in the top right pill: the theme's
## TitleNav (no box, the body face, gold under the pointer).
func _title_word(b: Button) -> void:
	# made for the pause menu's leather (command_button's face): give the row
	# back to the theme kind, whose face and size are the title's
	b.remove_theme_font_override("font")
	b.remove_theme_font_size_override("font_size")
	b.theme_type_variation = &"TitleNav"
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

## The speaker: the Music row's switch, its face whether the music plays.
func _on_sound_pressed() -> void:
	if _music != null:
		_music.pressed.emit()
	_show_sound()

func _show_sound() -> void:
	var sound := %Sound as Button
	var on := _music == null or not _music.text.ends_with("Off")
	sound.icon = speaker_on if on else speaker_off
	sound.tooltip_text = _music.text if _music != null else ""

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

## Test seam: the settings rows and Quit (the leather menu's whole column).
func menu_column() -> BoxContainer:
	return _menu_col

## Test seam: any row of the title by name (StartGame, LoadGame, the settings
## rows, Quit).
func row(row_name: String) -> Button:
	return find_child(row_name, true, false) as Button

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_game"):
		_start()
