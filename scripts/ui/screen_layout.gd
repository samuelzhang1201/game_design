class_name ScreenLayout
extends RefCounted
## The gameplay screens' shared frame (user rulings 2026-09-09): a left
## column that is always on (the realm dashboard, or the dossier on the
## stage), the map filling the middle, and ONE right slot that is empty by
## default — the council column takes it when the player enters the council
## (the ENTER THE COUNCIL handle on the right edge), the detail column takes
## it while a map element is selected — and the map widens to the edge when
## the slot is empty.
##
## Everything is placed in the 640x360 design viewport; the scenes carry the
## same offsets as a starting state and call `apply` whenever the slot
## changes. Stateless.

const MARGIN := 4.0
const GAP := 4.0
const LEFT_WIDTH := 120.0
const RIGHT_WIDTH := 150.0
const HANDLE_LENGTH := 96.0
const HANDLE_THICKNESS := 14.0

## Room the bottom chrome needs: the news strip and the tab bar.
static func bottom_inset() -> float:
	return NewsTicker.STRIP_HEIGHT + BottomBar.BAR_HEIGHT + 6.0

## Lay out one screen. `top` is where the columns start (below the top bar);
## `right_panels` are every control that can occupy the right slot (they are
## placed alike; the screen decides which one is visible); `right_open` says
## whether the slot is taken, which narrows the map.
static func apply(top: float, left: Control, map: Control, right_panels: Array,
		right_open: bool) -> void:
	var bottom := bottom_inset()
	var right_inset := MARGIN + (RIGHT_WIDTH + GAP if right_open else 0.0)
	var middle_left := MARGIN + LEFT_WIDTH + GAP
	if left != null:
		_place(left, Vector2(0, 0), Vector2(0, 1), MARGIN, top, MARGIN + LEFT_WIDTH, -bottom)
	if map != null:
		_place(map, Vector2(0, 0), Vector2(1, 1), middle_left, top, -right_inset, -bottom)
	for panel in right_panels:
		if panel != null:
			_place(panel, Vector2(1, 0), Vector2(1, 1), -(MARGIN + RIGHT_WIDTH), top, -MARGIN, -bottom)

## The ENTER THE COUNCIL handle: a tab standing on the right edge, its text
## running upward, shown only while the right slot is empty.
static func make_handle(text: String) -> Button:
	var b := Button.new()
	b.name = "CouncilHandle"
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 7)
	b.size = Vector2(HANDLE_LENGTH, HANDLE_THICKNESS)
	b.pivot_offset = Vector2.ZERO
	b.rotation = -PI / 2.0
	return b

static func place_handle(handle: Control, top: float) -> void:
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
