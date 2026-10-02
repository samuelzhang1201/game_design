class_name ScreenLayout
extends RefCounted
## The gameplay screens' shared frame (user rulings 2026-09-09): a left
## column that is always on, the map filling the middle, and ONE right slot
## that is empty by default — the council column takes it when the player
## enters the council (the ENTER THE COUNCIL handle on the right edge) — and
## the map widens to the edge when the slot is empty.
##
## The columns divide by kind (owner ruling 2026-09-10): the left column is
## the FACTS column (the realm dashboard, the dossier on the stage, the
## hovered country, the host, the fact card of a clicked map element) and
## the right slot is PEOPLE AND TALK. Each screen orders its own left column
## (_refresh_left); this only places the two of them. LEFT_WIDTH is fixed,
## so what goes in the column wraps and scrolls rather than widening it.
##
## Everything is placed in the 640x360 design viewport; the scenes carry the
## same offsets as a starting state and call `apply` whenever the slot
## changes. Stateless.

const MARGIN := 8.0
const GAP := 8.0

## The screen's edge margin and the gap between its columns: THE WAR TABLE
## spreads its papers apart so the table shows between them (balance
## ui_table_margin_px / ui_table_gap_px); leather keeps MARGIN / GAP.
static func margin() -> float:
	return WarTable._num("ui_table_margin_px", MARGIN) if UiPalette.war_table() else MARGIN

static func gap() -> float:
	return WarTable._num("ui_table_gap_px", GAP) if UiPalette.war_table() else GAP

## The gap between the map and the council column when it is open: the column
## is leather held up to the eye, not paper on the table, and the audience
## window needs the map's width (ui_table_right_gap_px).
static func right_gap() -> float:
	return WarTable._num("ui_table_right_gap_px", GAP) if UiPalette.war_table() else GAP
const LEFT_WIDTH := 240.0
## The council and dialogue column. 300 left the talk a narrow strip once the
## transcript went back to a readable size (owner 2026-09-13).
const RIGHT_WIDTH := 400.0
## The conversation stage's council column (owner 2026-09-15): the talk moved
## into the audience window over the map, leaving the column the room and the
## record, so it gives the map back 80 px.
const TALK_WIDTH := 320.0
const HANDLE_LENGTH := 192.0
const HANDLE_THICKNESS := 28.0
## How far in from the map panel's top-right corner the council button sits.
const HANDLE_INSET := 14.0

## Room the bottom chrome needs: the news strip and the tab bar.
static func bottom_inset() -> float:
	# On THE WAR TABLE the news is a slip between the bookmarks, which hang
	# straight from under the sheet: only the bookmarks' band is kept.
	if UiPalette.war_table():
		return BottomBar.BAR_HEIGHT
	return NewsTicker.STRIP_HEIGHT + BottomBar.BAR_HEIGHT + 6.0

## Lay out one screen. `top` is where the columns start (below the top bar);
## `right_panels` are every control that can occupy the right slot (they are
## placed alike; the screen decides which one is visible); `right_open` says
## whether the slot is taken, which narrows the map; `right_width` is the
## slot's width on this screen.
static func apply(top: float, left: Control, map: Control, right_panels: Array,
		right_open: bool, right_width: float = RIGHT_WIDTH) -> void:
	var bottom := bottom_inset()
	var m := margin()
	var g := gap()
	var right_inset := m + (right_width + right_gap() if right_open else 0.0)
	var middle_left := m + LEFT_WIDTH + g
	if left != null:
		_place(left, Vector2(0, 0), Vector2(0, 1), m, top, m + LEFT_WIDTH, -bottom)
	if map != null:
		# on THE WAR TABLE the bookmarks hang from under the map sheet: the
		# sheet alone reaches down over their tops (ui_bookmark_tuck_px)
		var tuck := WarTable._num("ui_bookmark_tuck_px", 8.0) if UiPalette.war_table() else 0.0
		_place(map, Vector2(0, 0), Vector2(1, 1), middle_left, top, -right_inset, -(bottom - tuck))
	for panel in right_panels:
		if panel != null:
			_place(panel, Vector2(1, 0), Vector2(1, 1), -(m + right_width), top, -m, -bottom)

## The ENTER THE COUNCIL handle: a tab standing on the right edge, its text
## running upward, shown only while the right slot is empty.
static func make_handle(text: String) -> Button:
	if UiPalette.war_table() and _handle_is_button():
		# THE WAR TABLE (owner 2026-10-01): the order as the council's wax seal.
		return WaxSeal.new(text)
	var b := Button.new()
	b.name = "CouncilHandle"
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if _handle_is_button():
		# The game's core move as its one primary button, level, over the
		# map's top-right corner (owner 2026-09-28, balance ui_council_button).
		UiPalette.primary_button(b, 15)
		UiPalette.command_button(b)
		return b
	UiPalette.style_tab(b, 14)
	b.size = Vector2(HANDLE_LENGTH, HANDLE_THICKNESS)
	b.pivot_offset = Vector2.ZERO
	b.rotation = -PI / 2.0
	return b

static func _handle_is_button() -> bool:
	var repo := UiPalette.data()
	return repo != null and float(repo.balance.get("ui_council_button", 0.0)) > 0.0

static func place_handle(handle: Control, top: float) -> void:
	if _handle_is_button():
		var w := handle.get_combined_minimum_size().x
		var h := handle.get_combined_minimum_size().y
		handle.anchor_left = 1.0
		handle.anchor_right = 1.0
		var inset := (WarTable._num("ui_seal_inset_px", HANDLE_INSET) + WarTable._num("ui_sheet_margin_px", 13.0)) \
			if UiPalette.war_table() else HANDLE_INSET
		handle.offset_right = -margin() - inset
		handle.offset_left = handle.offset_right - w
		handle.offset_top = top + inset
		handle.offset_bottom = handle.offset_top + h
		return
	# Rotated -90° about its top-left corner, a (length x thickness) button
	# occupies x in [0, thickness] and y in [-length, 0] from its position.
	handle.anchor_left = 1.0
	handle.anchor_right = 1.0
	handle.offset_left = -margin() - HANDLE_THICKNESS
	handle.offset_top = top + HANDLE_LENGTH + 12.0
	handle.offset_right = handle.offset_left + HANDLE_LENGTH
	handle.offset_bottom = handle.offset_top + HANDLE_THICKNESS

static func _place(c: Control, anchor_min: Vector2, anchor_max: Vector2,
		left: float, top: float, right: float, bottom: float) -> void:
	c.anchor_left = anchor_min.x
	c.anchor_top = anchor_min.y
	c.anchor_right = anchor_max.x
	c.anchor_bottom = anchor_max.y
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom
