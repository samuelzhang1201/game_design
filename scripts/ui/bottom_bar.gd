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
## THE WAR TABLE: emitted with the free band between the two bookmark groups
## (global rect) whenever the row lays out, so the news slip can lie in it.
signal slip_moved(rect: Rect2)

## The strip is the scene's (owner 2026-10-02: the look lives in the editor —
## scenes/bottom_bar.tscn): every tab a silk bookmark of
## assets/2D/ui/war_table/styles/ribbons/ in its group's colour, MEASUREMENT
## wearing its ruler, the gap between the groups where the news slip lies
## (slip_band). _ready only finds the tabs and wires them; the leather strip of
## `ui_war_table` 0 is still dressed in code.
func _ready() -> void:
	_bar = $Bar
	var row: HBoxContainer = $Bar/Row
	for tab: String in TABS:
		var btn: Button = row.get_node(tab.capitalize())
		btn.pressed.connect(func() -> void: tab_selected.emit(tab))
		_buttons[tab] = btn
	if not UiPalette.war_table():
		_dress_leather(row)
	else:
		row.sort_children.connect(_emit_slip)
		resized.connect(_emit_slip)

## The leather strip (`ui_war_table` 0): the bar's panel and its rules, the
## tabs as flat words (or chips, ungrouped — `ui_nav_grouped` 0 puts the
## tabs back in TABS order and drops the rules), placeholders left out by
## `ui_show_placeholder_tabs` 0.
func _dress_leather(row: HBoxContainer) -> void:
	z_index = 0
	_bar.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 4, "column"))
	row.add_theme_constant_override("separation", 8)
	var grouped := Game.data != null and float(Game.data.balance.get("ui_nav_grouped", 0.0)) > 0.0
	var show_placeholders := Game.data == null \
		or float(Game.data.balance.get("ui_show_placeholder_tabs", 1.0)) > 0.0
	for node_name in ["Rule", "ToolRule", "Gap", "Gap2"]:
		var n := row.get_node_or_null(node_name) as Control
		if n == null:
			continue
		if grouped:
			n.visible = true
		else:
			row.remove_child(n)
			n.free()
	if not grouped:
		for i in TABS.size():
			row.move_child(_buttons[TABS[i]], i)
	for tab: String in TABS:
		var btn: Button = _buttons[tab]
		btn.theme_type_variation = &""
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			btn.remove_theme_stylebox_override(state)
		if tab in PLACEHOLDER_TABS and not show_placeholders:
			btn.visible = false
		if grouped:
			UiPalette.flat_tab(btn, 16, 12.0)
			# Centred, so the lit underline stands clear of the bar's own rule.
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		else:
			# Capitals run wide, so the chips pad tighter to keep every tab
			# inside the 1280 px row.
			UiPalette.style_tab(btn, 16, 10.0)
			btn.size_flags_vertical = Control.SIZE_FILL
		if tab == "MEASUREMENT":
			if not grouped:
				btn.icon = null
			else:
				# A tool, not a lens: its ruler in the word's own ink.
				var inks := {"icon_normal_color": "font_color", "icon_hover_color": "font_hover_color",
					"icon_pressed_color": "font_pressed_color", "icon_hover_pressed_color": "font_hover_pressed_color",
					"icon_focus_color": "font_color"}
				for state: String in inks:
					btn.add_theme_color_override(state, btn.get_theme_color(String(inks[state])))

func _emit_slip() -> void:
	slip_moved.emit(slip_band())

## The free band between the two bookmark groups (global rect): from the last
## map tab (MEASUREMENT) to the first screen tab (REALM), ui_slip_pad_px kept
## clear of each (owner 2026-10-01: log界面挪到measurement和 realm tab中间 —
## it had lain under the report, covering the compass).
func slip_band() -> Rect2:
	var left: Button = null
	var right: Button = null
	for tab: String in MAP_TABS:
		if _buttons.has(tab):
			left = _buttons[tab]
	for tab: String in TABS:
		if not tab in MAP_TABS and _buttons.has(tab):
			right = _buttons[tab]
			break
	if left == null or right == null:
		return Rect2(global_position, Vector2(size.x, BAR_HEIGHT))
	var pad := WarTable._num("ui_slip_pad_px", 8.0)
	var x0 := left.get_global_rect().end.x + pad
	var x1 := right.get_global_rect().position.x - pad
	return Rect2(Vector2(x0, global_position.y), Vector2(maxf(x1 - x0, 0.0), BAR_HEIGHT))

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
