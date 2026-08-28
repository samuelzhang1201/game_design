class_name KingdomCard
extends PanelContainer
## The realm's numbers live HERE (R1/R7/R9) - ministers speak prose, this
## card speaks figures. Two modes: values (court) and changes (day-run).

const METRIC_NAMES := {"treasury": "Gold", "grain": "Grain", "unrest": "Unrest",
	"legitimacy": "Legit", "army_quality": "Army", "church_opinion": "Church"}
const ORDER := ["treasury", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]

var _box: VBoxContainer

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("241c33")
	style.border_color = Color("deba54")
	style.set_border_width_all(2)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
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
	date.add_theme_color_override("font_color", Color("deba54"))
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(date)
	for m in ORDER:
		var now := int(state.metrics[m])
		var l := Label.new()
		if changes.has(m) and int(changes[m]["delta"]) != 0:
			var delta := int(changes[m]["delta"])
			l.text = "%s %d → %d (%+d)" % [METRIC_NAMES[m], now - delta, now, delta]
			l.tooltip_text = changes[m]["reason"]
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			l.add_theme_color_override("font_color",
				Color("7fd47f") if delta > 0 else Color("d47f7f"))
		else:
			l.text = "%s %d" % [METRIC_NAMES[m], now]
		_box.add_child(l)
