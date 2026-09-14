class_name TopBar
extends Control
## Mock-style top resource strip (UI_example.png, supersedes the corner
## KingdomCard): the date and the clock left, the purses in the middle, and a
## pending-event badge floating just below the bar's right end (outside the
## strip, so a visible badge never widens the bar past its frame inset).
## Self-wiring: subscribes to Game.state_changed / report_ready, so screens
## just instance it.
##
## TWO PURSES (owner 2026-09-14), told apart at a glance: the first row is the
## CROWN's — the realm's treasury, strategic and civil goods — marked with a
## crown; the second is the LORD's own purse, what the player's house holds
## as lord of its own provinces and may spend freely, marked with the house's
## arms. Each figure carries this month's change and, beside it, what the
## month brings in (RealmEconomy.purses). Nothing else sits in the bar: the
## realm's temper — unrest, legitimacy, the army's drill, the church — moved
## to the country card.

## The crown's pools, in order.
const ORDER := ["treasury", "strategic", "grain"]
## The lord's own purse, in the same order.
const LORD := ["lord_gold", "lord_strategic", "lord_civil"]
## metric -> [purse, figure] in RealmEconomy.purses: what the month brings.
const MONTHLY := {
	"treasury": ["realm_share", "tax"], "strategic": ["realm_share", "strategic"],
	"grain": ["realm_share", "civil"],
	"lord_gold": ["lord", "tax"], "lord_strategic": ["lord", "strategic"],
	"lord_civil": ["lord", "civil"],
}

var _value_labels: Dictionary = {}
var _delta_labels: Dictionary = {}
var _icons: Dictionary = {}
var _monthly_labels: Dictionary = {}
## speed -> its clock button (0 pause, 1 play, 2x, 4x).
var _clock_buttons: Dictionary = {}
var _crown_mark: Control
var _lord_crest: HeraldicShield

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
	# The crown's row: a crown, then its three pools.
	_crown_mark = Control.new()
	_crown_mark.name = "CrownMark"
	_crown_mark.custom_minimum_size = Vector2(26, 26)
	_crown_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_crown_mark.mouse_filter = Control.MOUSE_FILTER_PASS
	_crown_mark.tooltip_text = "The crown's — the realm's treasury and stores, which pay the court and buy land across the border"
	_crown_mark.draw.connect(func() -> void:
		ResourceIcon.draw_glyph(_crown_mark, "crown", _crown_mark.size / 2.0,
			minf(_crown_mark.size.x, _crown_mark.size.y), UiPalette.GOLD))
	%MetricsRow.add_child(_crown_mark)
	for m: String in ORDER:
		%MetricsRow.add_child(_cell(m, 18, 14))
	# The lord's row: the house's arms, then its own purse.
	_lord_crest = HeraldicShield.new()
	_lord_crest.name = "LordCrest"
	_lord_crest.custom_minimum_size = Vector2(22, 26)
	_lord_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lord_crest.mouse_filter = Control.MOUSE_FILTER_PASS
	_lord_crest.tooltip_text = "Your house's own — what your provinces pay you as their lord, yours to spend: it buys and builds manors inside the realm"
	%CrownRow.add_child(_lord_crest)
	for m: String in LORD:
		%CrownRow.add_child(_cell(m, 16, 13))
	Game.state_changed.connect(refresh)
	Game.report_ready.connect(func(_r: TickReport) -> void: refresh())
	refresh()
	# The bar is exactly as tall as its content, so the columns below can
	# start under it instead of guessing (user report 2026-09-09: the left
	# column overlapped the header).
	offset_bottom = bar_height()

## One pool: its icon (a glyph with a floating tooltip, user request
## 2026-09-09), the stock, this month's change, and the month's income.
func _cell(m: String, value_px: int, small_px: int) -> HBoxContainer:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override("separation", 6)
	var icon := ResourceIcon.create(m)
	icon.name = "Icon_" + m
	cell.add_child(icon)
	_icons[m] = icon
	var value_l := Label.new()
	value_l.add_theme_font_size_override("font_size", value_px)
	cell.add_child(value_l)
	_value_labels[m] = value_l
	var delta_l := Label.new()
	delta_l.add_theme_font_size_override("font_size", small_px)
	cell.add_child(delta_l)
	_delta_labels[m] = delta_l
	var monthly_l := Label.new()
	monthly_l.add_theme_font_size_override("font_size", small_px - 1)
	monthly_l.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	monthly_l.tooltip_text = "what this purse takes in a month"
	cell.add_child(monthly_l)
	_monthly_labels[m] = monthly_l
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
	if Game.current_report != null:
		for d in Game.current_report.metric_deltas:
			var metric := String(d["metric"])
			deltas[metric] = float(deltas.get(metric, 0.0)) + float(d["delta"])
	var purses := RealmEconomy.purses(Game.data, Game.state)
	for m: String in _value_labels:
		_value_labels[m].text = str(int(Game.state.metrics.get(m, 0.0)))
		var delta := int(deltas.get(m, 0.0))
		var dl: Label = _delta_labels[m]
		dl.text = "%+d" % delta if delta != 0 else ""
		dl.add_theme_color_override("font_color",
			UiPalette.POSITIVE if delta > 0 else UiPalette.NEGATIVE)
		var src: Array = MONTHLY[m]
		_monthly_labels[m].text = "+%d" % int((purses[String(src[0])] as Dictionary)[String(src[1])])
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

func delta_text(metric: String) -> String:
	return String(_delta_labels[metric].text) if _delta_labels.has(metric) else ""

## Test seam: what a pool takes in a month.
func monthly_text(metric: String) -> String:
	return String(_monthly_labels[metric].text) if _monthly_labels.has(metric) else ""

## Test seam: the icon standing in for a pool's name.
func icon_for(metric: String) -> ResourceIcon:
	return _icons.get(metric)

## Test seams: the marks that tell the two purses apart.
func crown_mark() -> Control:
	return _crown_mark

func lord_crest() -> HeraldicShield:
	return _lord_crest

## Test seam: the lord row's value label for a pool.
func value_label(metric: String) -> Label:
	return _value_labels.get(metric)
