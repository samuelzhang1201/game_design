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
## Tidied the same day (owner, docs/references/UIFIX.png): the two
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

## The bar is laid out in scenes/top_bar.tscn (owner 2026-10-02: the look is
## edited in the editor) — the brass dial, the four studs, the tally board
## with its two named rows of pools, Menu — dressed for THE WAR TABLE. This
## only finds its nodes, wires them and fills them; under ui_war_table 0 it
## puts the 2026-09-28 leather on them instead (_dress_leather).
func _ready() -> void:
	for m: String in ORDER + LORD:
		var cell := %Purses.get_node("Cell_" + m) as HBoxContainer
		_cells[m] = cell
		_icons[m] = cell.get_node("Icon_" + m)
		_value_labels[m] = cell.get_node("Value")
		_delta_labels[m] = cell.get_node("Change")
	for b: Button in %Clock.get_children():
		var speed := int(String(b.name).trim_prefix("Clock_"))
		_clock_buttons[speed] = b
		b.pressed.connect(func() -> void: Game.set_clock_speed(speed))
	%MenuButton.pressed.connect(func() -> void: Game.menu_requested.emit())
	(_clock_buttons[1] as Button).tooltip_text = "Play: a day every %.1f s" % Game.data.bal("time_day_seconds")
	if not UiPalette.war_table():
		_dress_leather()
	Game.clock_changed.connect(func(_s: int) -> void: _refresh_clock())
	Game.clock_held_changed.connect(func(_h: bool) -> void: _refresh_clock())
	_refresh_clock()
	Game.state_changed.connect(refresh)
	Game.report_ready.connect(func(_r: TickReport) -> void: refresh())
	refresh()

## The leather chrome (balance ui_war_table 0): the 2026-09-28 bar — a leather
## strip, the arms beside the date, the clock and Menu as dark chips wearing
## their painted art, the purses with no board under them.
func _dress_leather() -> void:
	%Bar.add_theme_stylebox_override("panel", load("res://assets/2D/ui/panels/styles/leather_bar.tres"))
	%DateDial.visible = false
	for key in ["font_color", "font_shadow_color"]:
		%DateLabel.remove_theme_color_override(key)
	%DateLabel.remove_theme_constant_override("shadow_offset_y")
	%DateLabel.add_theme_font_size_override("font_size", 16)
	%EventChip.add_theme_stylebox_override("normal", UiPalette.chip_style())
	var arts := {0: ["||", "clock_pause"], 1: [">", "clock_play"],
		2: ["%dx" % int(Game.data.bal("time_speed_fast")), "clock_fast"],
		4: ["%dx" % int(Game.data.bal("time_speed_faster")), "clock_faster"]}
	for speed: int in _clock_buttons:
		var b: Button = _clock_buttons[speed]
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.remove_theme_color_override(key)
		b.custom_minimum_size = Vector2(32, 0)
		b.text = String(arts[speed][0])
		UiPalette.compact_button(b, BUTTON_H, 13)
		_art_button(b, String(arts[speed][1]))
	%TallyBoard.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var menu: Button = %MenuButton
	for key in ["font_color", "font_hover_color"]:
		menu.remove_theme_color_override(key)
	menu.icon = null
	menu.text = "MENU"
	UiPalette.compact_button(menu, BUTTON_H, 14, 10.0)
	UiPalette.command_button(menu)
	_art_button(menu, "menu", true)

## A button that shows its key's painted art in place of its text, when the
## art is installed; the text stays as the fallback and the tooltip.
func _art_button(b: Button, key: String, keep_text := false) -> void:
	var tex := ResourceIcon.texture_of(key)
	if tex == null:
		return
	b.icon = tex
	b.add_theme_constant_override("icon_max_width", int(BUTTON_H - 4.0))
	if keep_text:
		# A scroll alone at this size read as a tick mark: icon and word together.
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		return
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.text = ""
	b.custom_minimum_size = Vector2(BUTTON_H + 6.0, BUTTON_H)

## The strip's real height: its panel's minimum, never less than the scene's.
func bar_height() -> float:
	return maxf(offset_bottom, %Bar.get_combined_minimum_size().y)

func refresh() -> void:
	if Game.state == null:
		return
	%DateLabel.text = Calendar.date_string(Game.state.tick, Game.state.day)
	if %DateDial.visible:
		# the day on the brass, the season and year on the wood
		%DateDial.set_day(Game.state.day, %DateLabel.text)
		%DateLabel.text = "%s · Year %d" % [Calendar.season_name(Game.state.tick),
			Calendar.year_of(Game.state.tick)]
	# The crown's arms (owner 2026-09-15) fly beside the date and mark the
	# lord's purse; without art the purse keeps the realm's colour and the
	# house's initial.
	var family := MapManors.crown(Game.state)
	var arms := HouseArms.texture_of_house(Game.data, Game.state, family)
	%DateArms.visible = arms != null and not %DateDial.visible
	%DateArms.set_texture(arms)
	%LordCrest.set_arms(MapPalette.color_of(Game.data, Game.data.resolve_realm("player_realm")),
		family.substr(0, 1).to_upper())
	%LordCrest.set_texture(arms)
	# "House Valorin", not a bare surname that could be anyone's (2026-09-28).
	%HouseName.text = "House " + family
	var deltas := {}
	var settled := Game.current_report != null
	if settled:
		for d in Game.current_report.metric_deltas:
			var metric := String(d["metric"])
			deltas[metric] = float(deltas.get(metric, 0.0)) + float(d["delta"])
	# The change is a month's (owner 2026-09-28: "+1597" said nothing of when).
	var per_month := "/mo"
	for m: String in _value_labels:
		_value_labels[m].text = UiPalette.format_int(int(Game.state.metrics.get(m, 0.0)))
		var delta := int(deltas.get(m, 0.0))
		var dl: Label = _delta_labels[m]
		# ONE change a pool (owner 2026-09-14): the month just settled when
		# there is one; before that, what this month should bring, in grey.
		if settled:
			dl.text = UiPalette.format_delta(delta) + per_month if delta != 0 else ""
			dl.add_theme_color_override("font_color",
				UiPalette.good_color() if delta > 0 else UiPalette.bad_color())
	%EventChip.visible = not Game.state.pending_event.is_empty()
	# What the month brings (RealmEconomy.purses). Right after the month's
	# settlement every province's line is stale and the first read recomputes
	# the realm (~9 ms, perf 2026-10-02): a settled month shows its report's
	# figures, so that read waits for the NEXT frame instead of landing on the
	# tick's. Before a month is settled the figures are the label itself.
	if settled and not _read_now and not RealmEconomy.is_warm(Game.data, Game.state) and is_inside_tree():
		if not _monthly_waiting:
			_monthly_waiting = true
			get_tree().process_frame.connect(_fill_monthly_later, CONNECT_ONE_SHOT)
		return
	_fill_monthly(deltas, settled, per_month)


var _monthly_waiting := false
var _read_now := false


func _fill_monthly_later() -> void:
	_monthly_waiting = false
	if is_inside_tree() and Game.state != null:
		_read_now = true
		refresh()
		_read_now = false


## The month's figures beside each pool, and the tooltips naming both months.
func _fill_monthly(deltas: Dictionary, settled: bool, per_month: String) -> void:
	var purses := RealmEconomy.purses(Game.data, Game.state)
	for m: String in _value_labels:
		var src: Array = MONTHLY[m]
		var monthly := int((purses[String(src[0])] as Dictionary)[String(src[1])])
		_monthly[m] = monthly
		var delta := int(deltas.get(m, 0.0))
		var dl: Label = _delta_labels[m]
		if not settled:
			dl.text = UiPalette.format_delta(monthly) + per_month
			dl.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
		var tip := "%s — last month %s, this month brings about +%d" % [
			String((Game.data.resource_icons.get(m, {}) as Dictionary).get("label", m)),
			("%+d" % delta) if settled else "not yet settled", monthly]
		_value_labels[m].tooltip_text = tip
		dl.tooltip_text = tip

## The lit clock button is the speed the game runs at.
func _refresh_clock() -> void:
	for speed: int in _clock_buttons:
		var b := _clock_buttons[speed] as Button
		b.set_pressed_no_signal(speed == Game.clock_speed)
		# held still (the LEDGER is open, owner 2026-10-01): no play button starts it
		b.disabled = speed > 0 and Game.clock_held

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
	return %CrownMark

func lord_crest() -> HeraldicShield:
	return %LordCrest

func date_arms() -> HeraldicShield:
	return %DateArms

## Test seams: a pool's value label, its whole cell, and the purse grid.
func value_label(metric: String) -> Label:
	return _value_labels.get(metric)

func cell_of(metric: String) -> HBoxContainer:
	return _cells.get(metric)

func purse_grid() -> GridContainer:
	return %Purses
