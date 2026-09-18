class_name DayRunScreen
extends Control
## DAY_RUN state screen (game_ui.png, user ruling 2026-08-31): the same
## bright framed map as every gameplay screen, with the ROYAL CHRONICLE
## transparent ticker at the map's lower left rolling the month (R6, R9
## - the TopBar keeps the numbers and deltas visible throughout).

signal finished

const TOP_BAR_SCENE := preload("res://scenes/top_bar.tscn")

var overlay: CalendarOverlay
var top_bar: TopBar

## The live map in the middle zone; GameRoot applies the province view to it.
var _world_map: WorldMapView
var _map_panel: PanelContainer
var _map3d: Map3DView

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiPalette.BG_SCREEN
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var map_panel := PanelContainer.new()
	map_panel.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 4))
	map_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_panel.offset_left = 220.0
	map_panel.offset_top = 56.0
	map_panel.offset_right = -300.0
	map_panel.offset_bottom = -(NewsTicker.STRIP_HEIGHT + BottomBar.BAR_HEIGHT + 8.0)
	add_child(map_panel)
	_map_panel = map_panel
	# Live world map, same as court/conversation (user ruling 2026-09-03).
	_world_map = WorldMapView.create()
	map_panel.add_child(_world_map)
	overlay = CalendarOverlay.new()
	overlay.finished.connect(func(): finished.emit())
	add_child(overlay)
	# User request 2026-08-31: the chronicle window always sits at the BOTTOM
	# of the UI — left-aligned with the map, growing upward, clear of the
	# news ticker strip and bottom tab bar.
	overlay.place_panel_bottom(110.0, NewsTicker.STRIP_HEIGHT + BottomBar.BAR_HEIGHT + 4.0, 250.0)
	top_bar = TOP_BAR_SCENE.instantiate()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(top_bar)
	map_panel.offset_top = top_bar.bar_height() + 3.0

func run(report: TickReport) -> void:
	overlay.play(report.tick)

## GameRoot's handle on this screen's map (the province view follows it).
func world_map() -> WorldMapView:
	return _world_map

## The 3D MAP tab (GameRoot): the Terrain3D view takes the map panel in
## place of the 2D map while the tab is lit (Map3DView.toggle_in).
func set_map3d_view(on: bool) -> void:
	_map3d = Map3DView.toggle_in(_map_panel, _world_map, _map3d, on)

## Test seam: the 3D view, or null until the tab was first lit.
func map3d_view() -> Map3DView:
	return _map3d
