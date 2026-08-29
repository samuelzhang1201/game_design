class_name DayRunScreen
extends Control
## DAY_RUN state screen (game_ui.png, user ruling 2026-08-31): the same
## bright framed map as every gameplay screen, with the ROYAL CHRONICLE
## transparent ticker at the map's lower left rolling the fortnight (R6, R9
## - the TopBar keeps the numbers and deltas visible throughout).

signal finished

const TOP_BAR_SCENE := preload("res://scenes/top_bar.tscn")

var overlay: CalendarOverlay
var top_bar: TopBar

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiPalette.BG_SCREEN
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var map_panel := PanelContainer.new()
	map_panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 1, 2))
	map_panel.position = Vector2(110, 28)
	map_panel.size = Vector2(380, 196)
	add_child(map_panel)
	var map_view := TextureRect.new()
	UiPalette.setup_map_view(map_view)
	map_panel.add_child(map_view)
	overlay = CalendarOverlay.new()
	overlay.finished.connect(func(): finished.emit())
	add_child(overlay)
	# game_ui.png: the chronicle window sits at the map area's lower left,
	# below the map so it covers nothing.
	overlay.place_panel(Vector2(110, 232), 250.0)
	top_bar = TOP_BAR_SCENE.instantiate()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top_bar)

func run(report: TickReport) -> void:
	overlay.play(report.tick)
