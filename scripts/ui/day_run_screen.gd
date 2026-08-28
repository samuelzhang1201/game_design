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
	# overlay before card: the overlay's full-rect dim ColorRect would
	# otherwise paint over the card and hide it for the whole interlude
	# (defeats R9 - the numbers are meant to stay visible while the days
	# pass). panel_vertical_offset also lifts the overlay's centered date
	# panel clear of the bottom-anchored card so they don't overlap.
	overlay = CalendarOverlay.new()
	overlay.panel_vertical_offset = -80.0
	overlay.finished.connect(func(): finished.emit())
	add_child(overlay)
	card = load("res://scenes/kingdom_card.tscn").instantiate()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.position.y -= 24
	add_child(card)

func run(report: TickReport) -> void:
	card.show_changes(Game.state, report.metric_deltas)
	overlay.play(report.tick)
