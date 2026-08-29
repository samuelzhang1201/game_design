class_name DayRunScreen
extends Control
## DAY_RUN state screen: the calendar interlude, with the TopBar metrics
## strip showing what changed while the days pass (R6, R9 - the TopBar's
## delta column supersedes the old KingdomCard changes mode; user ruling
## 2026-08-29, UI_example.png chrome).

signal finished

const TOP_BAR_SCENE := preload("res://scenes/top_bar.tscn")

var overlay: CalendarOverlay
var top_bar: TopBar

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := TextureRect.new()
	backdrop.texture = UiPalette.backdrop()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = UiPalette.MAP_TINT
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	# Same middle-area nine-patch frame as the conversation screen (user
	# ruling 2026-08-30: the frame never covers UI; the map stays bright).
	var frame := NinePatchRect.new()
	UiPalette.setup_frame_nine(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 156
	frame.offset_top = 28
	frame.offset_right = -184
	frame.offset_bottom = -4
	add_child(frame)
	overlay = CalendarOverlay.new()
	overlay.finished.connect(func(): finished.emit())
	add_child(overlay)
	# After the overlay so its dim never hides the numbers (R9).
	top_bar = TOP_BAR_SCENE.instantiate()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top_bar)

func run(report: TickReport) -> void:
	overlay.play(report.tick)
