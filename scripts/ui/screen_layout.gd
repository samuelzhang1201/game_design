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
	return NewsTicker.STRIP_HEIGHT + BottomBar.BAR_HEIGHT + 6.0

## Lay out one screen. `top` is where the columns start (below the top bar);
## `right_panels` are every control that can occupy the right slot (they are
## placed alike; the screen decides which one is visible); `right_open` says
## whether the slot is taken, which narrows the map; `right_width` is the
## slot's width on this screen.
static func apply(top: float, left: Control, map: Control, right_panels: Array,
		right_open: bool, right_width: float = RIGHT_WIDTH) -> void:
	var bottom := bottom_inset()
	var right_inset := MARGIN + (right_width + GAP if right_open else 0.0)
	var middle_left := MARGIN + LEFT_WIDTH + GAP
	if left != null:
		_place(left, Vector2(0, 0), Vector2(0, 1), MARGIN, top, MARGIN + LEFT_WIDTH, -bottom)
	if map != null:
		_place(map, Vector2(0, 0), Vector2(1, 1), middle_left, top, -right_inset, -bottom)
	for panel in right_panels:
		if panel != null:
			_place(panel, Vector2(1, 0), Vector2(1, 1), -(MARGIN + right_width), top, -MARGIN, -bottom)

## The ENTER THE COUNCIL handle: a tab standing on the right edge, its text
## running upward, shown only while the right slot is empty.
static func make_handle(text: String) -> Button:
	var b := Button.new()
	b.name = "CouncilHandle"
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if _handle_is_button():
		# The game's core move as its one primary button, level, over the
		# map's top-right corner (owner 2026-09-28, balance ui_council_button).
		UiPalette.primary_button(b, 15)
		return b
	UiPalette.style_tab(b, 14)
	b.size = Vector2(HANDLE_LENGTH, HANDLE_THICKNESS)
	b.pivot_offset = Vector2.ZERO
	b.rotation = -PI / 2.0
	return b

static func _handle_is_button() -> bool:
	return Game != null and Game.data != null and float(Game.data.balance.get("ui_council_button", 0.0)) > 0.0

static func place_handle(handle: Control, top: float) -> void:
	if _handle_is_button():
		var w := handle.get_combined_minimum_size().x
		var h := handle.get_combined_minimum_size().y
		handle.anchor_left = 1.0
		handle.anchor_right = 1.0
		handle.offset_right = -MARGIN - HANDLE_INSET
		handle.offset_left = handle.offset_right - w
		handle.offset_top = top + HANDLE_INSET
		handle.offset_bottom = handle.offset_top + h
		return
	# Rotated -90° about its top-left corner, a (length x thickness) button
	# occupies x in [0, thickness] and y in [-length, 0] from its position.
	handle.anchor_left = 1.0
	handle.anchor_right = 1.0
	handle.offset_left = -MARGIN - HANDLE_THICKNESS
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
