class_name BottomBar
extends Control
## Bottom tab strip on every gameplay screen (user ruling 2026-08-30),
## outside the map: HEIGHTS | MANORS | REALM | MEASUREMENT |
## WAR ROOM (a placeholder page, owner 2026-09-17) | FAMILIES | LAWS |
## RELIGION | RELATIONSHIP. MAP and PROVINCES went 2026-09-13 (owner):
## the province view is always on, and MAP did nothing a tab needed.
## Pure chrome — GameRoot owns it and decides what each tab opens (MAP
## closes overlays, RELATIONSHIP toggles the graph, the rest open the
## matching InfoScreen table). Replaces the TopBar's RELATIONS button.

signal tab_selected(tab: String)

const TABS := ["HEIGHTS", "MANORS", "REALM", "MEASUREMENT",
	"WAR ROOM", "FAMILIES", "LAWS", "RELIGION", "RELATIONSHIP"]
## Tabs that stay lit while their view is on rather than opening an overlay
## (MILITARY went 2026-09-27: the regiments are always on the map): HEIGHTS
## the height ramp over the land (owner request 2026-09-12, remade
## 2026-09-13), MANORS its theme (MANOR_SYSTEM.md §6: house colours and,
## since ECONOMY was folded into it on 2026-09-19, the output badges),
## exclusive with HEIGHTS — GameRoot keeps them so. The 3D map (owner
## 2026-09-18) is the default and has no tab: GameRoot shows it unless
## HEIGHTS is lit. MEASUREMENT (owner 2026-09-18) lays the ruler over whichever map
## is showing, 2D or 3D, and changes no layer.
const TOGGLES := ["HEIGHTS", "MANORS", "MEASUREMENT"]
## Grouped (owner 2026-09-28, balance ui_nav_grouped): the ways of looking at
## the map on the left, the screens on the right, a gold rule between — the
## strip had put a lens, a tool and five screens in one undifferentiated row.
const MAP_TABS := ["HEIGHTS", "MANORS", "MEASUREMENT"]
## Tabs that open a page still to be built; balance ui_show_placeholder_tabs
## 0 leaves them out of the strip.
const PLACEHOLDER_TABS := ["WAR ROOM"]
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
		UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 4, "column"))
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bar)
	_bar = bar
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var grouped := Game.data != null and float(Game.data.balance.get("ui_nav_grouped", 0.0)) > 0.0
	var show_placeholders := Game.data == null \
		or float(Game.data.balance.get("ui_show_placeholder_tabs", 1.0)) > 0.0
	var order: Array = TABS
	if grouped:
		order = MAP_TABS.duplicate()
		for tab: String in TABS:
			if not tab in MAP_TABS:
				order.append(tab)
	for tab: String in order:
		if tab in PLACEHOLDER_TABS and not show_placeholders:
			continue
		if grouped and tab == order[MAP_TABS.size()]:
			# The rule stands in the MIDDLE of the gap between the groups, so
			# it divides them rather than hugging one.
			row.add_child(_gap("Gap"))
			row.add_child(_rule("Rule", 0.6, 8.0))
			row.add_child(_gap("Gap2"))
		elif grouped and tab == "MEASUREMENT":
			# The ruler is laid over whichever lens is lit, not one of them.
			row.add_child(_rule("ToolRule", 0.3, 14.0))
		var btn := Button.new()
		btn.name = tab.capitalize()
		btn.text = tab
		btn.focus_mode = Control.FOCUS_NONE
		btn.toggle_mode = tab in TOGGLES
		if grouped:
			UiPalette.flat_tab(btn, 16, 12.0)
			# Centred, so the lit underline stands clear of the bar's own rule.
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		else:
			# Tabs read in the tab face (data/ui_fonts.csv); capitals run wide, so
			# the chips pad tighter to keep every tab inside the 1280 px row.
			UiPalette.style_tab(btn, 16, 10.0)
		btn.pressed.connect(func() -> void: tab_selected.emit(tab))
		row.add_child(btn)
		_buttons[tab] = btn

func _gap(gap_name: String) -> Control:
	var gap := Control.new()
	gap.name = gap_name
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return gap

func _rule(rule_name: String, alpha: float, inset: float) -> VSeparator:
	var rule := VSeparator.new()
	rule.name = rule_name
	var line := StyleBoxLine.new()
	line.vertical = true
	line.color = Color(UiPalette.BORDER_GOLD, alpha)
	line.thickness = 1
	line.grow_begin = -inset
	line.grow_end = -inset
	rule.add_theme_stylebox_override("separator", line)
	return rule

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
