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

## The slip is the scene's (owner 2026-10-02: the look lives in the editor —
## scenes/hud/news_ticker.tscn: the paper slip news_slip.tres, the rubric LOG, the
## crawl and the quiet line in the paper's ink, the log window
## leather_news_log.tres). _ready finds and wires it; the glass bar of
## `ui_war_table` 0 is still dressed in code.
func _ready() -> void:
	_log_button = $Row/LogButton
	_clip = $Row/Crawl
	_label = $Row/Crawl/CrawlLabel
	_quiet = $Row/Crawl/Quiet
	_history_panel = $History
	_history_list = $History/Scroll/Entries
	if Game.data != null:
		_speed = Game.data.bal("news_ticker_speed")
	_log_button.toggled.connect(func(on: bool) -> void: show_history(on))
	_clip.resized.connect(_centre_label)
	Game.news_published.connect(add_item)
	if not UiPalette.war_table():
		_dress_leather()

## The glass bar (`ui_war_table` 0, owner 2026-09-14): translucent and
## rounded, a gold hairline while the nav is grouped (owner 2026-09-28: LOG
## sat alone in an unmarked dark gap), LOG a compact chip.
func _dress_leather() -> void:
	var glass := StyleBoxFlat.new()
	glass.bg_color = GLASS
	glass.set_corner_radius_all(8)
	var framed := Game.data != null and float(Game.data.balance.get("ui_nav_grouped", 0.0)) > 0.0
	if framed:
		glass.border_color = Color(UiPalette.BORDER_GOLD, 0.35)
		glass.set_border_width_all(1)
	($TickerBg as Panel).add_theme_stylebox_override("panel", glass)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		_log_button.remove_theme_stylebox_override(state)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_log_button.remove_theme_color_override(state)
	_log_button.text = "LOG"
	UiPalette.compact_button(_log_button, STRIP_HEIGHT - 8.0, 12, 8.0)
	UiPalette.command_button(_log_button)
	_label.remove_theme_font_override("font")
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", INK)
	_quiet.remove_theme_font_override("font")
	_quiet.text = "No tidings yet. Word will come as the days pass."
	_quiet.add_theme_font_size_override("font_size", 14)
	_quiet.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_quiet.visible = framed

## Lie in `band` (a global rect: the gap between the bookmark groups,
## BottomBar.slip_band), centred and ui_slip_width_px wide at most, just
## under the sheet's edge.
func place_on_table(band: Rect2) -> void:
	var w := minf(WarTable._num("ui_slip_width_px", 380.0), band.size.x)
	var h := WarTable._num("ui_slip_height_px", 32.0)
	var origin := (get_parent() as Control).global_position if get_parent() is Control else Vector2.ZERO
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(band.get_center().x - w * 0.5, band.position.y + WarTable._num("ui_slip_drop_px", 6.0)) - origin
	size = Vector2(maxf(w, 0.0), h)

## One headline: dated, added to the crawl (oldest fall off past MAX_ITEMS)
## and to the history. The crawl position is left alone so a new item never
## makes the line jump.
func add_item(text: String) -> void:
	if text.strip_edges() == "":
		return
	var date := Calendar.date_of_day(Game.news_day()) if Game.state != null else ""
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
		none.theme_type_variation = &"LogEmpty"
		_history_list.add_child(none)
		return
	for entry: Dictionary in _history:
		var l := Label.new()
		l.text = ("%s — %s" % [entry["date"], entry["text"]]) if String(entry["date"]) != "" else String(entry["text"])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.theme_type_variation = &"LogEntry"
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
