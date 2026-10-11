class_name WarPlanHud
extends Control
## The staff's strokes LIVE on the screen (spec 2026-10-07-war-room-
## annotations-and-planning-pieces §2.5): the one being drawn, one being
## dragged, the march pending on its confirm (spec 2026-10-08-war-room-draw-
## orders ruling 10), a chosen stroke's chalk handles and a chosen front's
## facing arrow (ruling 12) — in screen px, drawn as the plan layer draws
## (WarPlanDraw) until the release paints them into plan_tex. Under them all,
## every march's blue crayon arrow, drafted or sealed (ruling 19,
## WarRoomPointer.orders), redrawn from the state so it follows its piece.
## Takes no mouse.

var _ink: Dictionary = {}
var _look: Dictionary = {}
var _handles := PackedVector2Array()
var _chalk := Color.WHITE
var _handle_r := 7.0
var _facing: Dictionary = {}   # {at, dir}: a chosen front's facing arrow, screen px
var _facing_len := 14.0
var _road: Array = []   # runs of PackedVector2Array, screen px
var _exit: Dictionary = {}   # {at, dir, text}: where the road leaves the sheet
var _exit_px := 18
var _exit_halo_px := 5
var _exit_halo_alpha := 0.85
var _orders: Dictionary = {}   # the marches' arrows, WarPlanInk's parts in screen px
var _orders_look: Dictionary = {}
var _gold := Color.GOLD
var _road_w := 6.0
var _road_dash := 16.0
var _slope: Array = []   # barrier bars where the ground is too steep to climb: [{a, b, hatches}] screen px
var _slope_look: Dictionary = {}   # {colour, width, hatch_w}


func show_live(ink: Dictionary, look: Dictionary, handles: PackedVector2Array, chalk: Color, handle_r: float,
		p_facing: Dictionary = {}, facing_len := 14.0) -> void:
	# the wax tooth's UVs run past 1 across a stroke: it tiles (a sampling rule, not a look)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ink = ink
	_look = look
	_handles = handles
	_chalk = chalk
	_handle_r = handle_r
	_facing = p_facing
	_facing_len = facing_len
	queue_redraw()


## The bold dashed gold supply road of a pending march, under its crayon
## (spec 2026-10-08-war-room-draw-orders ruling 14); empty: none.
func show_road(road: Array, gold: Color, width: float, dash: float, p_exit_mark: Dictionary = {},
		font_px := 18, halo_px := 5, halo_alpha := 0.85) -> void:
	_road = road
	_exit = p_exit_mark
	_exit_px = font_px
	_exit_halo_px = halo_px
	_exit_halo_alpha = halo_alpha
	_gold = gold
	_road_w = width
	_road_dash = dash
	queue_redraw()


## Every march's blue crayon arrow, UNDER the pending march and the supply
## road (spec 2026-10-08-war-room-draw-orders ruling 19).
func show_orders(ink: Dictionary, look: Dictionary) -> void:
	if ink.is_empty() and _orders.is_empty():
		return
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_orders = ink
	_orders_look = look
	queue_redraw()


## Barrier bars across the marches where the ground is too steep for a column
## (owner 2026-10-12, item 5; WarSlopeBars): each a bar with hachure ticks,
## under the pending crayon. `look`: {colour, width}. Empty clears.
func show_slope(bars: Array, look: Dictionary) -> void:
	if bars.is_empty() and _slope.is_empty():
		return
	_slope = bars
	_slope_look = look
	queue_redraw()


## The barrier bars drawn now (tests read them).
func slope_bars() -> Array:
	return _slope


## The marches' arrows drawn now (tests read them).
func orders_ink() -> Dictionary:
	return _orders


## The road drawn now (tests read it).
func runs() -> Array:
	return _road


## Where the road leaves the sheet ({} none; tests read it).
func exit_mark() -> Dictionary:
	return _exit


## The facing arrow drawn now ({} none; tests read it).
func facing() -> Dictionary:
	return _facing


func clear_live() -> void:
	if _ink.is_empty() and _handles.is_empty() and _facing.is_empty() and _road.is_empty() and _exit.is_empty():
		return
	_ink = {}
	_handles = PackedVector2Array()
	_facing = {}
	_road = []
	_exit = {}
	queue_redraw()


## True while anything is drawn (tests read it).
func drawing() -> bool:
	return not _ink.is_empty() or not _handles.is_empty() or not _facing.is_empty() or not _road.is_empty() \
		or not (_orders.get("crayon", []) as Array).is_empty() or not _slope.is_empty()


func _draw() -> void:
	if not _orders.is_empty() and not _orders_look.is_empty():
		WarPlanDraw.paint(self, _orders, _orders_look)
	_draw_slope()
	if not _road.is_empty():
		var edge := _gold.darkened(0.5)
		var dashed: Array = []
		for road: PackedVector2Array in _road:
			dashed.append_array(WarPlanGeometry.dashes(road, _road_dash, _road_dash * 0.5))
		for run: PackedVector2Array in dashed:
			draw_polyline(run, edge, _road_w + 2.0, true)
		for run: PackedVector2Array in dashed:
			draw_polyline(run, _gold, _road_w, true)
	if not _exit.is_empty():
		_draw_exit()
	if not _ink.is_empty():
		WarPlanDraw.paint(self, _ink, _look)
	for h in _handles:
		draw_circle(h, _handle_r, Color(_chalk, 0.35))
		draw_arc(h, _handle_r, 0.0, TAU, 20, _chalk, 1.5, true)
	if not _facing.is_empty():
		# a chalk arrow off the line's middle, pointing where the teeth point:
		# a click flips them, a drag across the line turns them there
		var at: Vector2 = _facing["at"]
		var d: Vector2 = _facing["dir"]
		var tail := at - d * _facing_len * 0.5
		var tip := at + d * _facing_len * 0.5
		var side := Vector2(-d.y, d.x) * _facing_len * 0.32
		draw_circle(at, _facing_len * 0.75, Color(_chalk, 0.3))
		draw_line(tail, tip - d * _facing_len * 0.3, _chalk, 2.5, true)
		draw_colored_polygon(PackedVector2Array([tip, tip - d * _facing_len * 0.45 + side, tip - d * _facing_len * 0.45 - side]), _chalk)


func _draw_slope() -> void:
	if _slope.is_empty() or _slope_look.is_empty():
		return
	var col: Color = _slope_look["colour"]
	var w := float(_slope_look["width"])
	for bar: Dictionary in _slope:
		var a: Vector2 = bar["a"]
		var b: Vector2 = bar["b"]
		for h: Array in bar["hatches"]:
			draw_line(h[0], h[1], col, maxf(1.5, w * 0.4), true)
		draw_line(a, b, col.darkened(0.45), w + 2.0, true)
		draw_line(a, b, col, w, true)


## The named exit: a small arrowhead at the sheet's edge pointing off it, and
## "from TOWN · SHEET" in the edge arrows' lettering, inked as the plan is.
func _draw_exit() -> void:
	var at: Vector2 = _exit["at"]
	var d: Vector2 = _exit["dir"]
	var side := Vector2(-d.y, d.x) * _road_w * 1.1
	var back := at - d * _road_w * 2.2
	var tri := PackedVector2Array([at + d * _road_w * 0.4, back + side, back - side])
	draw_colored_polygon(tri, _gold.darkened(0.5))
	var inner := PackedVector2Array([at, back + side * 0.6, back - side * 0.6])
	draw_colored_polygon(inner, _gold)
	var font: Font = _look.get("font") if _look.get("font") != null else ThemeDB.fallback_font
	var text := String(_exit["text"])
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _exit_px).x
	# the name is ink lifted just above the road, running inward from the arrowhead
	var pos := Vector2(back.x - d.x * 10.0 - (w if d.x > 0.0 else 0.0), back.y - _road_w * 2.2 - 2.0)
	var colours: Dictionary = _look.get("colours", {})
	var ink: Color = colours.get("ink", _gold.darkened(0.6))
	var halo: Color = _look.get("halo", Color.WHITE)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _exit_px, _exit_halo_px, Color(halo, _exit_halo_alpha))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _exit_px, ink)
