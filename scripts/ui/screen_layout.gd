class_name ScreenLayout
extends RefCounted
## The gameplay screens' shared frame (user rulings 2026-09-09): a left
## column that is always on (the realm dashboard, or the dossier on the
## stage), the map in the middle with a strip of play controls under it, and
## a right detail column that exists only while a map element is selected —
## when it is hidden the map and the strip widen to the edge.
##
## Everything is placed in the 640x360 design viewport; the screens' scenes
## carry the same offsets as a starting state and call `apply` whenever the
## detail column shows or hides. Stateless.

const MARGIN := 4.0
const GAP := 4.0
const LEFT_WIDTH := 120.0
const RIGHT_WIDTH := 140.0
const STRIP_HEIGHT := 92.0

## Room the bottom chrome needs: the news strip and the tab bar.
static func bottom_inset() -> float:
	return NewsTicker.STRIP_HEIGHT + BottomBar.BAR_HEIGHT + 6.0

## Lay out one screen. `top` is where the columns start (below the top bar).
static func apply(top: float, left: Control, map: Control, strip: Control,
		detail: Control, detail_visible: bool) -> void:
	var bottom := bottom_inset()
	var right_inset := MARGIN + (RIGHT_WIDTH + GAP if detail_visible else 0.0)
	var middle_left := MARGIN + LEFT_WIDTH + GAP
	if left != null:
		_place(left, Vector2(0, 0), Vector2(0, 1), MARGIN, top, MARGIN + LEFT_WIDTH, -bottom)
	if map != null:
		_place(map, Vector2(0, 0), Vector2(1, 1), middle_left, top, -right_inset,
			-(bottom + STRIP_HEIGHT + GAP))
	if strip != null:
		_place(strip, Vector2(0, 1), Vector2(1, 1), middle_left, -(bottom + STRIP_HEIGHT),
			-right_inset, -bottom)
	if detail != null:
		_place(detail, Vector2(1, 0), Vector2(1, 1), -(MARGIN + RIGHT_WIDTH), top, -MARGIN, -bottom)
		detail.visible = detail_visible

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
