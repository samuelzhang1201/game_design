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
var _drafts: Array = []   # each draft's pencil line, a polyline in screen px (spec 2026-10-02-war-room-v2 §3.1)
var _pencil := Color.GRAY
var _repo: DataRepository
var _gold := Color.GOLD
var _road_w := 6.0
var _road_dash := 16.0


func show_live(ink: Dictionary, look: Dictionary, handles: PackedVector2Array, chalk: Color, handle_r: float,
		facing: Dictionary = {}, facing_len := 14.0) -> void:
	# the wax tooth's UVs run past 1 across a stroke: it tiles (a sampling rule, not a look)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
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


## The drafts' graphite pencils, UNDER every crayon (a pending march drawn
## over a shared path hides them; spec 2026-10-08-war-room-draw-orders).
func show_drafts(repo: DataRepository, drafts: Array, pencil: Color) -> void:
	_repo = repo
	_drafts = drafts
	_pencil = pencil
	queue_redraw()


## The draft lines being drawn (tests read it).
func draft_lines() -> Array:
	return _drafts


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
	return not _ink.is_empty() or not _handles.is_empty() or not _facing.is_empty() or _road.size() >= 2 \
		or not _drafts.is_empty()


func _draw() -> void:
	if _repo != null:
		for line: Variant in _drafts:
			var r := PackedVector2Array(line)
			if r.size() > 2:   # a route's curve, one stroke up to its last segment
				draw_polyline(r.slice(0, r.size() - 1), _pencil, _repo.bal("war_draft_pencil_px"), true)
			if r.size() >= 2:
				_pencilled(r[r.size() - 2], r[r.size() - 1])
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


## A draft's pencil stroke from the piece to its pennant: solid graphite, not
## the map's dashes (taste: a tool never borrows the map's line language),
## ending in a small open arrowhead; dashed only if war_draft_pencil_dash_px > 0.
func _pencilled(a: Vector2, b: Vector2) -> void:
	var width := _repo.bal("war_draft_pencil_px")
	var dash := _repo.bal("war_draft_pencil_dash_px")
	if dash > 0.0:
		for d: PackedVector2Array in WarPlanGeometry.dashes(PackedVector2Array([a, b]), dash, dash):
			draw_polyline(d, _pencil, width, true)
	else:
		draw_line(a, b, _pencil, width, true)
	var head := _repo.bal("war_draft_head_px")
	if a.distance_to(b) <= head * 2.0:
		return
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tail := b - dir * head
	draw_polyline(PackedVector2Array([tail + side * head * 0.55, b, tail - side * head * 0.55]), _pencil, width, true)
