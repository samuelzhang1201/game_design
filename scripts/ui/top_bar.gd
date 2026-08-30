class_name TopBar
extends Control
## Mock-style top resource strip (UI_example.png, supersedes the corner
## KingdomCard): date left, the six realm metrics with this tick's deltas in
## the middle, and a pending-event badge floating just below the bar's right
## end (outside the strip, so a visible badge never widens the bar past its
## frame inset). Self-wiring: subscribes to Game.state_changed /
## report_ready, so screens just instance it.

const METRIC_NAMES := {"treasury": "Gold", "grain": "Grain", "unrest": "Unrest",
	"legitimacy": "Legit", "army_quality": "Army", "church_opinion": "Church"}
const ORDER := ["treasury", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]

var _value_labels: Dictionary = {}
var _delta_labels: Dictionary = {}

func _ready() -> void:
	%Bar.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 6))
	UiPalette.style_header(%DateLabel, 11)
	%EventChip.add_theme_stylebox_override("normal", UiPalette.chip_style())
	UiPalette.style_header(%EventChip, 9)
	%MenuButton.add_theme_font_size_override("font_size", 9)
	%MenuButton.pressed.connect(func() -> void: Game.menu_requested.emit())
	%FlagLabel.add_theme_font_size_override("font_size", 12)
	for m in ORDER:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		var name_l := Label.new()
		name_l.text = String(METRIC_NAMES[m]).to_upper()
		name_l.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
		name_l.add_theme_font_size_override("font_size", 9)
		cell.add_child(name_l)
		var value_l := Label.new()
		value_l.add_theme_font_size_override("font_size", 11)
		cell.add_child(value_l)
		_value_labels[m] = value_l
		var delta_l := Label.new()
		delta_l.add_theme_font_size_override("font_size", 9)
		cell.add_child(delta_l)
		_delta_labels[m] = delta_l
		%MetricsRow.add_child(cell)
	Game.state_changed.connect(refresh)
	Game.report_ready.connect(func(_r: TickReport) -> void: refresh())
	refresh()

func refresh() -> void:
	if Game.state == null:
		return
	%DateLabel.text = Calendar.date_string(Game.state.tick)
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

## Test seam: the current text of one metric's value label.
func metric_text(metric: String) -> String:
	return String(_value_labels[metric].text) if _value_labels.has(metric) else ""

func delta_text(metric: String) -> String:
	return String(_delta_labels[metric].text) if _delta_labels.has(metric) else ""
