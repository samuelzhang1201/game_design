class_name CalendarOverlay
extends Control
## Full-screen interlude played when a turn ends: the date runs day by day
## through the fortnight that just passed, with placeholder news flashes.
## Pure presentation - the engine tick already advanced before play() is
## called, and news selection is hash-based (never touches the campaign RNG,
## so headless runs and UI runs stay identical). Click anywhere to skip.

signal finished

## R6: pacing comes from balance (dayrun_day_seconds); slower, readable.
var day_seconds := 0.22
const NEWS_DAYS := [4, 9, 14]

## Set BEFORE the overlay enters the tree to shift the centered date panel
## up/down (e.g. DayRunScreen offsets it clear of the bottom-anchored
## KingdomCard). Default 0 keeps the overlay's standalone centered layout
## unchanged.
var panel_vertical_offset := 0.0

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
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = UiPalette.DIM_OVERLAY
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.GOLD, 2, 24))
	# 320 (not wider): keeps the centered panel clear of the top-left
	# KingdomCard's corner on every gameplay window aspect (user ruling
	# 2026-08-29 - the card and this panel must never overlap).
	_panel.custom_minimum_size = Vector2(320, 0)
	# Centered via anchors + grow-both so the auto-sizing panel stays centered
	# without a container (containers override their children's anchors).
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position.y += panel_vertical_offset
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_panel.add_child(col)
	season_label = Label.new()
	season_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	season_label.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	col.add_child(season_label)
	date_label = Label.new()
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date_label.add_theme_font_size_override("font_size", 28)
	date_label.add_theme_color_override("font_color", UiPalette.GOLD)
	col.add_child(date_label)
	news_box = VBoxContainer.new()
	news_box.add_theme_constant_override("separation", 4)
	col.add_child(news_box)
	var hint := Label.new()
	hint.text = "click to skip"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	col.add_child(hint)
	_timer = Timer.new()
	_timer.timeout.connect(_advance_day)
	add_child(_timer)
	gui_input.connect(_on_gui_input)

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

func _add_news(text: String) -> void:
	if text == "":
		return
	var l := Label.new()
	l.text = "* " + text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	news_box.add_child(l)

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
