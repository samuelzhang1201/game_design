class_name DayRunScreen
extends Control
## DAY_RUN state screen: the calendar interlude with the KingdomCard showing
## what changed while the days pass (R6, R9).

signal finished

const KINGDOM_CARD_SCENE := preload("res://scenes/kingdom_card.tscn")

var overlay: CalendarOverlay
var card: KingdomCard

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiPalette.BG_SCREEN
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# overlay before card: the overlay's full-rect dim ColorRect would
	# otherwise paint over the card and hide it for the whole interlude
	# (defeats R9 - the numbers are meant to stay visible while the days
	# pass). Card pinned top-left (user ruling 2026-08-29), clear of the
	# overlay's centered date panel, which therefore keeps its default
	# centered position (panel_vertical_offset 0).
	overlay = CalendarOverlay.new()
	overlay.finished.connect(func(): finished.emit())
	add_child(overlay)
	card = KINGDOM_CARD_SCENE.instantiate()
	card.position = Vector2(8, 8)
	add_child(card)

func run(report: TickReport) -> void:
	card.show_changes(Game.state, report.metric_deltas)
	overlay.play(report.tick)
