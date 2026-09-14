class_name TopBar
extends Control
## Mock-style top resource strip (UI_example.png, supersedes the corner
## KingdomCard): the date and the clock left, the purses in the middle, MENU
## right, and a pending-event badge floating just below the bar's right end
## (outside the strip, so a visible badge never widens the bar past its
## frame inset). Self-wiring: subscribes to Game.state_changed /
## report_ready, so screens just instance it.
##
## TWO PURSES (owner 2026-09-14), told apart at a glance: the crown's —
## the realm's treasury, strategic and civil goods — marked with a crown, and
## the LORD's own purse, marked with the house's arms. Nothing else sits in
## the bar: the realm's temper moved to the country card.
##
## Tidied the same day (owner, development/exmaples/UIFIX.png): the two
## purses are ONE grid — a mark and three pools a row — so gold stands over
## gold; the type is small; each pool shows its stock and ONE change (the
## month just settled, or before any has, what this month should bring, in
## grey), the other figure in the tooltip; the clock and MENU are compact
## buttons centred in the strip; and the strip's content keeps off the
## frame's ornament (UiPalette.clear_ornament).

## The crown's pools, in order.
const ORDER := ["treasury", "strategic", "grain"]
## The lord's own purse, in the same order, so each column is one good.
const LORD := ["lord_gold", "lord_strategic", "lord_civil"]
## metric -> [purse, figure] in RealmEconomy.purses: what the month brings.
const MONTHLY := {
	"treasury": ["realm_share", "tax"], "strategic": ["realm_share", "strategic"],
	"grain": ["realm_share", "civil"],
	"lord_gold": ["lord", "tax"], "lord_strategic": ["lord", "strategic"],
	"lord_civil": ["lord", "civil"],
}
const VALUE_PX := 15
const CHANGE_PX := 12
const ICON_PX := 20.0
## The clock's and MENU's height: one purse row, never the whole strip.
const BUTTON_H := 26.0

var _value_labels: Dictionary = {}
var _delta_labels: Dictionary = {}
var _icons: Dictionary = {}
var _cells: Dictionary = {}
## metric -> what this month brings, for the tooltip and monthly_text.
var _monthly: Dictionary = {}
## speed -> its clock button (0 pause, 1 play, 2x, 4x).
var _clock_buttons: Dictionary = {}
var _crown_mark: Control
var _lord_crest: HeraldicShield

func _ready() -> void:
	%Bar.add_theme_stylebox_override("panel",
		UiPalette.clear_ornament(UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 8)))
	UiPalette.style_header(%DateLabel, 16)
	%EventChip.add_theme_stylebox_override("normal", UiPalette.chip_style())
	UiPalette.style_header(%EventChip, 14)
	UiPalette.compact_button(%MenuButton, BUTTON_H, 14, 10.0)
	%MenuButton.pressed.connect(func() -> void: Game.menu_requested.emit())
	# The clock (owner 2026-09-13): pause, play, 2x, 4x beside the date.
	# The bar is one of several (each screen has its own), so the buttons
	# only ask Game and follow its answer.
	var clock := HBoxContainer.new()
	clock.name = "Clock"
	clock.add_theme_constant_override("separation", 3)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
		b.custom_minimum_size = Vector2(32, 0)
		UiPalette.compact_button(b, BUTTON_H, 13)
		var speed: int = spec[1]
		b.pressed.connect(func() -> void: Game.set_clock_speed(speed))
		clock.add_child(b)
		_clock_buttons[speed] = b
	%DateLabel.add_sibling(clock)
	Game.clock_changed.connect(func(_s: int) -> void: _refresh_clock())
	_refresh_clock()
	%FlagLabel.add_theme_font_size_override("font_size", 18)
	# The purses: one grid, the crown's row over the lord's.
	_crown_mark = Control.new()
	_crown_mark.name = "CrownMark"
	_crown_mark.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	_crown_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_crown_mark.mouse_filter = Control.MOUSE_FILTER_PASS
	_crown_mark.tooltip_text = "The crown's — the realm's treasury and stores, which pay the court and buy land across the border"
	_crown_mark.draw.connect(func() -> void:
		ResourceIcon.draw_glyph(_crown_mark, "crown", _crown_mark.size / 2.0,
			minf(_crown_mark.size.x, _crown_mark.size.y), UiPalette.GOLD))
	%Purses.add_child(_crown_mark)
	for m: String in ORDER:
		%Purses.add_child(_cell(m))
	_lord_crest = HeraldicShield.new()
	_lord_crest.name = "LordCrest"
	_lord_crest.custom_minimum_size = Vector2(ICON_PX * 0.85, ICON_PX)
	_lord_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lord_crest.mouse_filter = Control.MOUSE_FILTER_PASS
	_lord_crest.tooltip_text = "Your house's own — what your provinces pay you as their lord, yours to spend: it buys and builds manors inside the realm"
	%Purses.add_child(_lord_crest)
	for m: String in LORD:
		%Purses.add_child(_cell(m))
	Game.state_changed.connect(refresh)
	Game.report_ready.connect(func(_r: TickReport) -> void: refresh())
	refresh()
	# The bar is exactly as tall as its content, so the columns below can
	# start under it instead of guessing (user report 2026-09-09: the left
	# column overlapped the header).
	offset_bottom = bar_height()

## One pool: its icon, the stock, and its one change.
func _cell(m: String) -> HBoxContainer:
	var cell := HBoxContainer.new()
	cell.name = "Cell_" + m
	cell.add_theme_constant_override("separation", 4)
	var icon := ResourceIcon.create(m)
	icon.name = "Icon_" + m
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	cell.add_child(icon)
	_icons[m] = icon
	var value_l := Label.new()
	value_l.name = "Value"
	value_l.add_theme_font_size_override("font_size", VALUE_PX)
	value_l.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.add_child(value_l)
	_value_labels[m] = value_l
	var delta_l := Label.new()
	delta_l.name = "Change"
	delta_l.add_theme_font_size_override("font_size", CHANGE_PX)
	delta_l.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.add_child(delta_l)
	_delta_labels[m] = delta_l
	_cells[m] = cell
	return cell

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
	# The house's arms, until real coats of arms exist: its flag's colour (the
	# realm's when none was chosen) with its initial.
	var family := MapManors.crown(Game.state)
	var arms: Color = UiPalette.flag_by_id(flag_id)["color"] if flag_id != "" \
		else MapPalette.color_of(Game.data, Game.data.resolve_realm("player_realm"))
	_lord_crest.set_arms(arms, family.substr(0, 1).to_upper())
	var deltas := {}
	var settled := Game.current_report != null
	if settled:
		for d in Game.current_report.metric_deltas:
			var metric := String(d["metric"])
			deltas[metric] = float(deltas.get(metric, 0.0)) + float(d["delta"])
	var purses := RealmEconomy.purses(Game.data, Game.state)
	for m: String in _value_labels:
		var src: Array = MONTHLY[m]
		var monthly := int((purses[String(src[0])] as Dictionary)[String(src[1])])
		_monthly[m] = monthly
		_value_labels[m].text = str(int(Game.state.metrics.get(m, 0.0)))
		var delta := int(deltas.get(m, 0.0))
		var dl: Label = _delta_labels[m]
		# ONE change a pool (owner 2026-09-14): the month just settled when
		# there is one; before that, what this month should bring, in grey.
		if settled:
			dl.text = "%+d" % delta if delta != 0 else ""
			dl.add_theme_color_override("font_color",
				UiPalette.POSITIVE if delta > 0 else UiPalette.NEGATIVE)
		else:
			dl.text = "+%d" % monthly
			dl.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
		var tip := "%s — last month %s, this month brings about +%d" % [
			String((Game.data.resource_icons.get(m, {}) as Dictionary).get("label", m)),
			("%+d" % delta) if settled else "not yet settled", monthly]
		_value_labels[m].tooltip_text = tip
		dl.tooltip_text = tip
	%EventChip.visible = not Game.state.pending_event.is_empty()

## The lit clock button is the speed the game runs at.
func _refresh_clock() -> void:
	for speed: int in _clock_buttons:
		(_clock_buttons[speed] as Button).set_pressed_no_signal(speed == Game.clock_speed)

## Test seam: the clock button for a speed (0 is pause).
func clock_button(speed: int) -> Button:
	return _clock_buttons.get(speed)

## Test seam: the current text of a pool's value label (crown or lord).
func metric_text(metric: String) -> String:
	return String(_value_labels[metric].text) if _value_labels.has(metric) else ""

## Test seam: the pool's one change as shown.
func delta_text(metric: String) -> String:
	return String(_delta_labels[metric].text) if _delta_labels.has(metric) else ""

## Test seam: what a pool takes in a month (in the tooltip, and shown in
## grey before the first month settles).
func monthly_text(metric: String) -> String:
	return "+%d" % int(_monthly[metric]) if _monthly.has(metric) else ""

## Test seam: the icon standing in for a pool's name.
func icon_for(metric: String) -> ResourceIcon:
	return _icons.get(metric)

## Test seams: the marks that tell the two purses apart.
func crown_mark() -> Control:
	return _crown_mark

func lord_crest() -> HeraldicShield:
	return _lord_crest

## Test seams: a pool's value label, its whole cell, and the purse grid.
func value_label(metric: String) -> Label:
	return _value_labels.get(metric)

func cell_of(metric: String) -> HBoxContainer:
	return _cells.get(metric)

func purse_grid() -> GridContainer:
	return %Purses
