class_name DayRunScreen
extends Control
## DAY_RUN state screen: the calendar interlude with the KingdomCard showing
## what changed while the days pass (R6, R9).

signal finished

var overlay: CalendarOverlay
var card: KingdomCard

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("1a1423")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	card = load("res://scenes/kingdom_card.tscn").instantiate()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.position.y -= 24
	add_child(card)
	overlay = CalendarOverlay.new()
	overlay.finished.connect(func(): finished.emit())
	add_child(overlay)

func run(report: TickReport) -> void:
	card.show_changes(Game.state, report.metric_deltas)
	overlay.play(report.tick)
