class_name TopBar
extends Control
## Mock-style top resource strip (UI_example.png, supersedes the corner
## KingdomCard): date left, the six realm metrics with this tick's deltas in
## the middle, and a pending-event badge floating just below the bar's right
## end (outside the strip, so a visible badge never widens the bar past its
## frame inset). Self-wiring: subscribes to Game.state_changed /
## report_ready, so screens just instance it.

const ORDER := ["treasury", "strategic", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]
## Pool metric -> the realm figure (RealmEconomy.realm) it shows monthly.
const POOLS := {"treasury": "tax", "strategic": "strategic", "grain": "civil"}
## The crown's second line: its provinces' own tax, strategic and civil.
const CROWN := ["tax", "strategic", "civil"]

var _value_labels: Dictionary = {}
var _delta_labels: Dictionary = {}
var _icons: Dictionary = {}
var _monthly_labels: Dictionary = {}
var _crown_labels: Dictionary = {}
## speed -> its clock button (0 pause, 1 play, 2x, 4x).
var _clock_buttons: Dictionary = {}

func _ready() -> void:
	%Bar.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 8))
	UiPalette.style_header(%DateLabel, 18)
	%EventChip.add_theme_stylebox_override("normal", UiPalette.chip_style())
	UiPalette.style_header(%EventChip, 14)
	%MenuButton.add_theme_font_size_override("font_size", 16)
	%MenuButton.pressed.connect(func() -> void: Game.menu_requested.emit())
	# The clock (owner 2026-09-13): pause, play, 2x, 4x beside the date.
	# The bar is one of several (each screen has its own), so the buttons
	# only ask Game and follow its answer.
	var clock := HBoxContainer.new()
	clock.name = "Clock"
	clock.add_theme_constant_override("separation", 2)
	var speeds := [["||", 0, "Pause"], [">", 1, "Play: a day every %.1f s" % Game.data.bal("time_day_seconds")],
		["%dx" % int(Game.data.bal("time_speed_fast")), int(Game.data.bal("time_speed_fast")), "Faster"],
		["%dx" % int(Game.data.bal("time_speed_faster")), int(Game.data.bal("time_speed_faster")), "Fastest"]]
	for spec: Array in speeds:
		var b := Button.new()
		b.name = "Clock_%d" % int(spec[1])
		b.text = String(spec[0])
		b.tooltip_text = String(spec[2])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(30, 0)
		var speed: int = spec[1]
		b.pressed.connect(func() -> void: Game.set_clock_speed(speed))
		clock.add_child(b)
		_clock_buttons[speed] = b
	%DateLabel.add_sibling(clock)
	Game.clock_changed.connect(func(_s: int) -> void: _refresh_clock())
	_refresh_clock()
	%FlagLabel.add_theme_font_size_override("font_size", 20)
	for m in ORDER:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		# A glyph with a floating tooltip instead of a word (user request
		# 2026-09-09); the value keeps the same test seam as before.
		var icon := ResourceIcon.create(m)
		icon.name = "Icon_" + m
		cell.add_child(icon)
		_icons[m] = icon
		var value_l := Label.new()
		value_l.add_theme_font_size_override("font_size", 18)
		cell.add_child(value_l)
		_value_labels[m] = value_l
		var delta_l := Label.new()
		delta_l.add_theme_font_size_override("font_size", 14)
		cell.add_child(delta_l)
		_delta_labels[m] = delta_l
		if POOLS.has(m):
			var monthly_l := Label.new()
			monthly_l.add_theme_font_size_override("font_size", 13)
			monthly_l.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
			monthly_l.tooltip_text = "the realm's %s this month" % String(POOLS[m])
			cell.add_child(monthly_l)
			_monthly_labels[m] = monthly_l
		%MetricsRow.add_child(cell)
	# The crown's own provinces (spec §6): the same three figures, smaller,
	# each with its share of the realm.
	for kind: String in CROWN:
		var crown_cell := HBoxContainer.new()
		crown_cell.add_theme_constant_override("separation", 4)
		var crown_icon := ResourceIcon.create({"tax": "treasury", "strategic": "strategic", "civil": "grain"}[kind])
		crown_icon.name = "CrownIcon_" + kind
		crown_cell.add_child(crown_icon)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 13)
		l.tooltip_text = "your provinces' %s this month, and its share of the realm's" % kind
		crown_cell.add_child(l)
		_crown_labels[kind] = l
		%CrownRow.add_child(crown_cell)
	Game.state_changed.connect(refresh)
	Game.report_ready.connect(func(_r: TickReport) -> void: refresh())
	refresh()
	# The bar is exactly as tall as its content, so the columns below can
	# start under it instead of guessing (user report 2026-09-09: the left
	# column overlapped the header).
	offset_bottom = bar_height()

## The strip's real height: its panel's minimum, never less than the scene's.
func bar_height() -> float:
	return maxf(offset_bottom, %Bar.get_combined_minimum_size().y)

func refresh() -> void:
	if Game.state == null:
		return
	%DateLabel.text = Calendar.date_string(Game.state.tick, Game.state.day)
	# The chosen family flag (character creation) flies beside the date.
	var flag_id := String(Game.state.player_setup.get("flag", ""))
	%FlagLabel.visible = flag_id != ""
	if flag_id != "":
		var f := UiPalette.flag_by_id(flag_id)
		%FlagLabel.text = String(f["symbol"])
		%FlagLabel.add_theme_color_override("font_color", f["color"])
	var deltas := {}
	if Game.current_report != null:
		for d in Game.current_report.metric_deltas:
			var m := String(d["metric"])
			deltas[m] = float(deltas.get(m, 0.0)) + float(d["delta"])
	for m in ORDER:
		_value_labels[m].text = str(int(Game.state.metrics[m]))
		var delta := int(deltas.get(m, 0.0))
		var dl: Label = _delta_labels[m]
		dl.text = "%+d" % delta if delta != 0 else ""
		dl.add_theme_color_override("font_color",
			UiPalette.POSITIVE if delta > 0 else UiPalette.NEGATIVE)
	%EventChip.visible = not Game.state.pending_event.is_empty()
	var e := RealmEconomy.realm(Game.data, Game.state)
	for m: String in _monthly_labels:
		_monthly_labels[m].text = "+%d" % int(e["realm"][String(POOLS[m])])
	for kind: String in _crown_labels:
		var realm_v := int(e["realm"][kind])
		var crown_v := int(e["crown"][kind])
		var pct := int(roundf(100.0 * float(crown_v) / maxf(float(realm_v), 1.0)))
		_crown_labels[kind].text = "%d (%d%%)" % [crown_v, pct]

## The lit clock button is the speed the game runs at.
func _refresh_clock() -> void:
	for speed: int in _clock_buttons:
		(_clock_buttons[speed] as Button).set_pressed_no_signal(speed == Game.clock_speed)

## Test seam: the clock button for a speed (0 is pause).
func clock_button(speed: int) -> Button:
	return _clock_buttons.get(speed)

## Test seam: the current text of one metric's value label.
func metric_text(metric: String) -> String:
	return String(_value_labels[metric].text) if _value_labels.has(metric) else ""

func delta_text(metric: String) -> String:
	return String(_delta_labels[metric].text) if _delta_labels.has(metric) else ""

## Test seam: the realm's monthly figure for a pool metric (treasury/strategic/grain).
func monthly_text(metric: String) -> String:
	return String(_monthly_labels[metric].text) if _monthly_labels.has(metric) else ""

## Test seam: the crown's provinces' text for "tax"|"strategic"|"civil".
func crown_text(kind: String) -> String:
	return String(_crown_labels[kind].text) if _crown_labels.has(kind) else ""

## Test seam: the crown row's Label for a kind.
func crown_label(kind: String) -> Label:
	return _crown_labels.get(kind)

## Test seam: the icon standing in for a metric's name.
func icon_for(metric: String) -> ResourceIcon:
	return _icons.get(metric)
