class_name BottomBar
extends Control
## Bottom tab strip on every gameplay screen (user ruling 2026-08-30),
## outside the map: HEIGHTS | MANORS | REALM | MEASUREMENT |
## WAR ROOM (the plotting room, owner 2026-10-01) | FAMILIES | LAWS |
## RELIGION | LEDGER (the realm's ontology, spec 2026-09-30) | MISSIVE (the
## Missive board, owner 2026-09-28).
## MAP and PROVINCES went 2026-09-13 (owner):
## the province view is always on, and MAP did nothing a tab needed.
## Pure chrome — GameRoot owns it and decides what each tab opens (MAP
## closes overlays, LEDGER and MISSIVE toggle their screens, the
## rest open the matching InfoScreen table). Replaces the TopBar's
## RELATIONS button.

signal tab_selected(tab: String)

const TABS := ["HEIGHTS", "MANORS", "REALM", "MEASUREMENT",
	"WAR ROOM", "FAMILIES", "LAWS", "RELIGION", "LEDGER", "MISSIVE"]
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
## 0 leaves them out of the strip. None now: WAR ROOM left the placeholders
## 2026-10-01 (it opens the plotting room).
const PLACEHOLDER_TABS := []
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
		if grouped and tab == "MEASUREMENT":
			# A tool, not a lens (owner 2026-09-28, second critique): it wears
			# a ruler before its word, in the word's own ink.
			btn.icon = ruler_icon()
			btn.add_theme_constant_override("h_separation", 8)
			btn.add_theme_constant_override("icon_max_width", 22)
			var inks := {"icon_normal_color": "font_color", "icon_hover_color": "font_hover_color",
				"icon_pressed_color": "font_pressed_color", "icon_hover_pressed_color": "font_hover_pressed_color",
				"icon_focus_color": "font_color"}
			for state: String in inks:
				btn.add_theme_color_override(state, btn.get_theme_color(String(inks[state])))
		btn.pressed.connect(func() -> void: tab_selected.emit(tab))
		row.add_child(btn)
		_buttons[tab] = btn

## A drawn ruler, white so the button's icon colours tint it: a bar with
## ticks standing on one side, the long ones every fifth (MapRuler's own
## reading of a ruler). Built once at 4x its 11 design px height.
static var _ruler_icon: ImageTexture

static func ruler_icon() -> ImageTexture:
	if _ruler_icon != null:
		return _ruler_icon
	var w := 88
	var h := 44
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var ink := Color(1, 1, 1, 1)
	img.fill_rect(Rect2i(0, h - 8, w, 6), ink)
	for i in 11:
		var x := mini(i * 8 + 2, w - 5)
		var tall := 26 if i % 5 == 0 else 14
		img.fill_rect(Rect2i(x, h - 8 - tall, 4, tall), ink)
	img.generate_mipmaps()
	_ruler_icon = ImageTexture.create_from_image(img)
	return _ruler_icon

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

var _badges: Dictionary = {}

## An unread count drawn on a tab (the Missive board, spec 2026-09-28 §2); 0 hides it.
func set_badge(tab: String, n: int) -> void:
	_badges[tab] = n
	var b := button(tab)
	if b == null:
		return
	var base := String(b.get_meta("label", b.text))
	b.set_meta("label", base)
	b.text = base if n <= 0 else "%s (%d)" % [base, n]

func badge(tab: String) -> int:
	return int(_badges.get(tab, 0))
