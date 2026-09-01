class_name CalendarOverlay
extends Control
## The "ROYAL CHRONICLE" live ticker (game_ui.png, user ruling 2026-08-31):
## a TRANSPARENT window that rolls the fortnight day by day after End Turn -
## dated news entries appended as the days pass, surroundings visible through
## it, nothing dimmed. Pure presentation - the engine tick already advanced
## before play() is called, and news selection is hash-based (never touches
## the campaign RNG, so headless runs and UI runs stay identical). Click
## anywhere to skip. The window's placement belongs to the owning screen via
## place_panel(); standalone it sits centered.

signal finished

## R6: pacing comes from balance (dayrun_day_seconds); slower, readable.
var day_seconds := 0.22
const NEWS_DAYS := [4, 9, 14]

var date_label: Label
var season_label: Label
var news_box: VBoxContainer
var _panel: PanelContainer
var _timer: Timer
var _tick := 0
var _day := 0

## Deterministic placeholder news picker: rows with key "news" in
## templates.csv, indexed by a tick/day hash. No RNG stream involved.
static func news_line(data: DataRepository, tick: int, day: int) -> String:
	var pool: Array = []
	for row in data.templates:
		if row["key"] == "news":
			pool.append(row["text"])
	if pool.is_empty():
		return ""
	return pool[(tick * 31 + day * 7) % pool.size()]

func _ready() -> void:
	if Game.data != null:
		day_seconds = Game.data.bal("dayrun_day_seconds")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP  # click anywhere skips
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.GLASS_BG
	style.border_color = UiPalette.BORDER_GOLD
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", style)
	# Centered by default; the owning screen calls place_panel().
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(250, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	_panel.add_child(col)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	col.add_child(header)
	var title := Label.new()
	title.text = "ROYAL CHRONICLE"
	UiPalette.style_header(title, 9)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var live := Label.new()
	live.text = "LIVE"
	live.add_theme_font_size_override("font_size", 8)
	live.add_theme_color_override("font_color", UiPalette.POSITIVE)
	header.add_child(live)
	date_label = Label.new()
	UiPalette.style_header(date_label, 11)
	col.add_child(date_label)
	season_label = Label.new()
	season_label.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	season_label.add_theme_font_size_override("font_size", 9)
	col.add_child(season_label)
	news_box = VBoxContainer.new()
	news_box.add_theme_constant_override("separation", 4)
	col.add_child(news_box)
	var hint := Label.new()
	hint.text = "click to skip"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 9)
	col.add_child(hint)
	_timer = Timer.new()
	_timer.timeout.connect(_advance_day)
	add_child(_timer)
	gui_input.connect(_on_gui_input)

## Anchor the chronicle window to the bottom of the screen (user request
## 2026-08-31: the day-run window always sits at the bottom of the UI):
## left edge at `left`, bottom edge `bottom_margin` px above the screen
## bottom, growing UPWARD as entries are added so it never slides under the
## bottom chrome.
func place_panel_bottom(left: float, bottom_margin: float, width: float) -> void:
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = left
	_panel.offset_right = left + width
	_panel.offset_top = -bottom_margin
	_panel.offset_bottom = -bottom_margin
	_panel.custom_minimum_size = Vector2(width, 0)

## tick: the tick that just BEGAN (engine already advanced) - the interlude
## replays the fortnight belonging to that tick, days 1..15.
func play(tick: int) -> void:
	_tick = tick
	_day = 0
	for child in news_box.get_children():
		child.queue_free()
	season_label.text = "the days pass..."
	date_label.text = Calendar.date_string(_tick, 1)
	visible = true
	_timer.start(day_seconds)

func playing() -> bool:
	return visible

func date_panel() -> PanelContainer:
	return _panel

func _advance_day() -> void:
	_day += 1
	if _day >= Calendar.DAYS_PER_TICK:
		_finish()
		return
	date_label.text = Calendar.date_string(_tick, _day)
	if _day in NEWS_DAYS:
		_add_news(CalendarOverlay.news_line(Game.data, _tick, _day))

## One dated chronicle entry (game_ui.png: gold date line, soft text below).
## Every entry also feeds the persistent bottom news strip via
## Game.publish_news (user request 2026-08-31).
func _add_news(text: String) -> void:
	if text == "":
		return
	Game.publish_news("%s — %s" % [Calendar.date_string(_tick, _day), text])
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 1)
	var date := Label.new()
	date.text = Calendar.date_string(_tick, _day).to_upper()
	UiPalette.style_header(date, 8)
	entry.add_child(date)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	l.add_theme_font_size_override("font_size", 10)
	entry.add_child(l)
	news_box.add_child(entry)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_finish()

func _finish() -> void:
	if not visible:
		return
	_timer.stop()
	date_label.text = Calendar.date_string(_tick, Calendar.DAYS_PER_TICK)
	visible = false
	finished.emit()
