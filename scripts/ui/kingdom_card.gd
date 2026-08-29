class_name KingdomCard
extends PanelContainer
## The realm's numbers live HERE (R1/R7/R9) - ministers speak prose, this
## card speaks figures. Two modes: values (court) and changes (day-run).

const METRIC_NAMES := {"treasury": "Gold", "grain": "Grain", "unrest": "Unrest",
	"legitimacy": "Legit", "army_quality": "Army", "church_opinion": "Church"}
const ORDER := ["treasury", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]

var _box: VBoxContainer

## Compact corner card (user ruling 2026-08-29): small fonts, thin border,
## tight margins - it sits in the top-left of every gameplay screen and must
## not crowd the content beside it.
const DATE_FONT_SIZE := 12
const ROW_FONT_SIZE := 11

func _ready() -> void:
	add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.GOLD, 1, 6))
	custom_minimum_size = Vector2(140, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)

func show_values(state: GameState) -> void:
	_rebuild(state, {})

func show_changes(state: GameState, deltas: Array) -> void:
	var by_metric := {}
	for d in deltas:
		if by_metric.has(d["metric"]):
			by_metric[d["metric"]]["delta"] += float(d["delta"])
			by_metric[d["metric"]]["reason"] += "\n" + String(d["reason"])
		else:
			by_metric[d["metric"]] = {"delta": float(d["delta"]), "reason": String(d["reason"])}
	_rebuild(state, by_metric)

func _rebuild(state: GameState, changes: Dictionary) -> void:
	for child in _box.get_children():
		child.queue_free()
	var date := Label.new()
	date.text = Calendar.date_string(state.tick)
	date.add_theme_color_override("font_color", UiPalette.GOLD)
	date.add_theme_font_size_override("font_size", DATE_FONT_SIZE)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(date)
	for m in ORDER:
		var now := int(state.metrics[m])
		var l := Label.new()
		l.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
		if changes.has(m) and int(changes[m]["delta"]) != 0:
			var delta := int(changes[m]["delta"])
			l.text = "%s %d → %d (%+d)" % [METRIC_NAMES[m], now - delta, now, delta]
			l.tooltip_text = changes[m]["reason"]
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			l.add_theme_color_override("font_color",
				UiPalette.POSITIVE if delta > 0 else UiPalette.NEGATIVE)
		else:
			l.text = "%s %d" % [METRIC_NAMES[m], now]
		_box.add_child(l)
