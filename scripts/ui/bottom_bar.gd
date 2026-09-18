class_name BottomBar
extends Control
## Bottom tab strip on every gameplay screen (user ruling 2026-08-30),
## outside the map: HEIGHTS | ECONOMY | MANORS | REALM | MILITARY |
## WAR ROOM (a placeholder page, owner 2026-09-17) | FAMILIES | LAWS |
## RELIGION | RELATIONSHIP. MAP and PROVINCES went 2026-09-13 (owner):
## the province view is always on, and MAP did nothing a tab needed.
## Pure chrome — GameRoot owns it and decides what each tab opens (MAP
## closes overlays, RELATIONSHIP toggles the graph, the rest open the
## matching InfoScreen table). Replaces the TopBar's RELATIONS button.

signal tab_selected(tab: String)

const TABS := ["HEIGHTS", "ECONOMY", "MANORS", "REALM", "MILITARY", "WAR ROOM",
	"FAMILIES", "LAWS", "RELIGION", "RELATIONSHIP"]
## Tabs that stay lit while their view is on rather than opening an overlay:
## MILITARY toggles the map's army layer (user request 2026-09-10), HEIGHTS
## the height ramp over the land (owner request 2026-09-12, remade
## 2026-09-13), ECONOMY and MANORS their themes.
## MANORS (MANOR_SYSTEM.md §6) is the fourth theme, exclusive with HEIGHTS
## and ECONOMY — GameRoot keeps them so. The 3D map (owner 2026-09-18) is
## the default and has no tab: GameRoot shows it whenever none of these four
## is lit.
const TOGGLES := ["HEIGHTS", "ECONOMY", "MANORS", "MILITARY"]
## The strip's height. A constant on purpose — NewsTicker and ScreenLayout
## both place themselves off it, so it cannot float — but it
## must stay at least content_height(), and a test pins that. It went stale
## once: the design viewport doubled, every font size with it, and the tabs
## quietly fell off the bottom of the screen (owner report 2026-09-12).
const BAR_HEIGHT := 56.0

var _buttons: Dictionary = {}
var _bar: PanelContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -BAR_HEIGHT
	var bar := PanelContainer.new()
	bar.name = "Bar"
	bar.add_theme_stylebox_override("panel",
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 4))
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bar)
	_bar = bar
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for tab in TABS:
		var btn := Button.new()
		btn.name = tab.capitalize()
		btn.text = tab
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = tab in TOGGLES
		# Tabs read in Cinzel Decorative (owner 2026-09-13); its capitals run
		# wide, so the chips pad tighter to keep all ten tabs inside the
		# 1280 px row.
		UiPalette.style_tab(btn, 16, 10.0)
		btn.pressed.connect(func() -> void: tab_selected.emit(tab))
		row.add_child(btn)
		_buttons[tab] = btn

## What the strip's buttons actually need, once their font size, their chip
## padding and the panel's own margins are counted. BAR_HEIGHT must be at
## least this — the ticker and ScreenLayout both place
## themselves off that constant, so it cannot float, and a test pins the
## relation instead. It went stale once already: the design viewport doubled,
## every font size with it, and the tabs quietly fell off the bottom of the
## screen (owner report 2026-09-12).
func content_height() -> float:
	return 0.0 if _bar == null else _bar.get_combined_minimum_size().y

## Test seam.
func button(tab: String) -> Button:
	return _buttons.get(tab)

## Light or unlight a toggle tab without emitting tab_selected.
func set_toggled(tab: String, on: bool) -> void:
	var btn: Button = _buttons.get(tab)
	if btn != null:
		btn.set_pressed_no_signal(on)
