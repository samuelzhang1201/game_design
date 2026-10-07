class_name WarPlanHud
extends Control
## The staff's strokes LIVE on the screen (spec 2026-10-07-war-room-
## annotations-and-planning-pieces §2.5): the one being drawn, one being
## dragged, the march pending on its confirm (spec 2026-10-08-war-room-draw-
## orders ruling 10), a chosen stroke's chalk handles and a chosen front's
## facing arrow (ruling 12) — in screen px, drawn as the plan layer draws
## (WarPlanDraw) until the release paints them into plan_tex. Takes no mouse.

var _ink: Dictionary = {}
var _look: Dictionary = {}
var _handles := PackedVector2Array()
var _chalk := Color.WHITE
var _handle_r := 7.0
var _facing: Dictionary = {}   # {at, dir}: a chosen front's facing arrow, screen px
var _facing_len := 14.0
var _road := PackedVector2Array()
var _gold := Color.GOLD
var _road_w := 6.0
var _road_dash := 16.0


func show_live(ink: Dictionary, look: Dictionary, handles: PackedVector2Array, chalk: Color, handle_r: float,
		facing: Dictionary = {}, facing_len := 14.0) -> void:
	_ink = ink
	_look = look
	_handles = handles
	_chalk = chalk
	_handle_r = handle_r
	_facing = facing
	_facing_len = facing_len
	queue_redraw()


## The bold dashed gold supply road of a pending march, under its crayon
## (spec 2026-10-08-war-room-draw-orders ruling 14); empty: none.
func show_road(road: PackedVector2Array, gold: Color, width: float, dash: float) -> void:
	_road = road
	_gold = gold
	_road_w = width
	_road_dash = dash
	queue_redraw()


## The road drawn now (tests read it).
func road() -> PackedVector2Array:
	return _road


## The facing arrow drawn now ({} none; tests read it).
func facing() -> Dictionary:
	return _facing


func clear_live() -> void:
	if _ink.is_empty() and _handles.is_empty() and _facing.is_empty() and _road.is_empty():
		return
	_ink = {}
	_handles = PackedVector2Array()
	_facing = {}
	_road = PackedVector2Array()
	queue_redraw()


## True while anything is drawn (tests read it).
func drawing() -> bool:
	return not _ink.is_empty() or not _handles.is_empty() or not _facing.is_empty() or _road.size() >= 2


func _draw() -> void:
	if _road.size() >= 2:
		var edge := _gold.darkened(0.5)
		var runs := WarPlanGeometry.dashes(_road, _road_dash, _road_dash * 0.5)
		for run: PackedVector2Array in runs:
			draw_polyline(run, edge, _road_w + 2.0, true)
		for run: PackedVector2Array in runs:
			draw_polyline(run, _gold, _road_w, true)
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
