class_name NewsTicker
extends Control
## The news bar (user request 2026-08-31, remade 2026-09-14 by the owner): a
## TRANSLUCENT rounded bar in the gap between the map and the bottom tab bar,
## where the realm's news crawls right to left. It moves only while TIME
## RUNS — pausing the clock stops the crawl where it is — and every headline
## is kept, dated, in a history the LOG button opens. Purely presentational:
## it listens to Game.news_published and never touches sim state or the
## campaign RNG. Crawl speed is balance data (news_ticker_speed).

const STRIP_HEIGHT := 32.0
const MAX_ITEMS := 12
const HISTORY_CAP := 60
const HISTORY_SIZE := Vector2(420.0, 220.0)
const SEPARATOR := "      ·      "
## The bar's glass and ink: dark and see-through, so the map shows through.
const GLASS := Color(0.09, 0.075, 0.06, 0.6)  # warm dark glass (owner 2026-09-15; slate 0.12, 0.16, 0.22, 0.5 under the bright theme)
const INK := Color(0.97, 0.96, 0.92)

var _label: Label
var _clip: Control
var _items: Array = []
## Newest first: {date, text}.
var _history: Array = []
var _speed := 18.0
var _log_button: Button
var _history_panel: PanelContainer
var _history_list: VBoxContainer
var _quiet: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -(BottomBar.BAR_HEIGHT + STRIP_HEIGHT)
	offset_bottom = -BottomBar.BAR_HEIGHT
	offset_left = ScreenLayout.MARGIN
	offset_right = -ScreenLayout.MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Game.data != null:
		_speed = Game.data.bal("news_ticker_speed")
	var bg := Panel.new()
	bg.name = "TickerBg"
	var glass := StyleBoxFlat.new()
	glass.bg_color = GLASS
	glass.set_corner_radius_all(8)
	var framed := Game.data != null and float(Game.data.balance.get("ui_nav_grouped", 0.0)) > 0.0
	if framed:
		# A hairline so the bar reads as a place even while it is empty
		# (owner 2026-09-28: LOG sat alone in an unmarked dark gap).
		glass.border_color = Color(UiPalette.BORDER_GOLD, 0.35)
		glass.set_border_width_all(1)
	bg.add_theme_stylebox_override("panel", glass)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 4.0
	row.offset_right = -8.0
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_log_button = Button.new()
	_log_button.name = "LogButton"
	_log_button.text = "LOG"
	_log_button.toggle_mode = true
	_log_button.focus_mode = Control.FOCUS_NONE
	_log_button.tooltip_text = "What has been heard, newest first"
	UiPalette.compact_button(_log_button, STRIP_HEIGHT - 8.0, 12, 8.0)
	UiPalette.command_button(_log_button)
	_log_button.toggled.connect(func(on: bool) -> void: show_history(on))
	row.add_child(_log_button)
	_clip = Control.new()
	_clip.name = "Crawl"
	_clip.clip_contents = true
	_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_clip)
	_label = Label.new()
	_label.name = "CrawlLabel"
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", INK)
	_clip.add_child(_label)
	_clip.resized.connect(_centre_label)
	# Before the first headline the bar says so instead of lying empty.
	_quiet = Label.new()
	_quiet.name = "Quiet"
	_quiet.text = "No tidings yet. Word will come as the days pass."
	_quiet.add_theme_font_size_override("font_size", 14)
	_quiet.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_quiet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_quiet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_quiet.visible = framed
	_clip.add_child(_quiet)
	_build_history()
	Game.news_published.connect(add_item)

func _build_history() -> void:
	_history_panel = PanelContainer.new()
	_history_panel.name = "History"
	_history_panel.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 10))
	_history_panel.anchor_top = 0.0
	_history_panel.anchor_bottom = 0.0
	_history_panel.offset_left = 0.0
	_history_panel.offset_right = HISTORY_SIZE.x
	_history_panel.offset_top = -HISTORY_SIZE.y - 6.0
	_history_panel.offset_bottom = -6.0
	_history_panel.visible = false
	add_child(_history_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_history_panel.add_child(scroll)
	_history_list = VBoxContainer.new()
	_history_list.name = "Entries"
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_history_list)

## One headline: dated, added to the crawl (oldest fall off past MAX_ITEMS)
## and to the history. The crawl position is left alone so a new item never
## makes the line jump.
func add_item(text: String) -> void:
	if text.strip_edges() == "":
		return
	var date := Calendar.date_string(Game.state.tick, Game.state.day) if Game.state != null else ""
	_items.append(text)
	while _items.size() > MAX_ITEMS:
		_items.pop_front()
	_label.text = SEPARATOR.join(_items)
	if _quiet != null:
		_quiet.visible = false
	_label.reset_size()
	_centre_label()
	if _label.position.x == 0.0 and _items.size() == 1:
		_label.position.x = _clip.size.x
	_history.push_front({"date": date, "text": text})
	while _history.size() > HISTORY_CAP:
		_history.pop_back()
	if _history_panel.visible:
		_fill_history()

func _centre_label() -> void:
	if _label == null:
		return
	_label.position.y = maxf((_clip.size.y - _label.size.y) * 0.5, 0.0)

## The crawl moves only while time runs (owner 2026-09-14): a paused clock
## holds the line where it is.
func _process(delta: float) -> void:
	if _label.text == "" or Game.clock_speed <= 0:
		return
	_label.position.x -= _speed * delta
	if _label.position.x + _label.size.x < 0.0:
		_label.position.x = _clip.size.x

## Open or close the history of headlines.
func show_history(on: bool) -> void:
	_history_panel.visible = on
	_log_button.set_pressed_no_signal(on)
	if on:
		_fill_history()

func _fill_history() -> void:
	for child in _history_list.get_children():
		child.queue_free()
	if _history.is_empty():
		var none := Label.new()
		none.text = "Nothing has been heard yet."
		none.add_theme_font_size_override("font_size", 14)
		none.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
		_history_list.add_child(none)
		return
	for entry: Dictionary in _history:
		var l := Label.new()
		l.text = ("%s — %s" % [entry["date"], entry["text"]]) if String(entry["date"]) != "" else String(entry["text"])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
		_history_list.add_child(l)

## Test seams.
func crawl_label() -> Label:
	return _label

func items() -> Array:
	return _items.duplicate()

func history() -> Array:
	return _history.duplicate(true)

func history_panel() -> PanelContainer:
	return _history_panel

func speed() -> float:
	return _speed
