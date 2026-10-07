class_name WarHud
extends Control
## The war room's 2D overlay (spec 2026-10-01-war-room-design §3): the rake's
## ink arrow from the piece to the pointer with its reading at the middle
## (dashed once its destination is held for COMMIT), and the chalk ring round a
## chosen piece. Draws only what WarRoomRake hands it; Vector2(-1, -1) hides a
## part.

var _repo: DataRepository
var _from := Vector2(-1, -1)
var _to := Vector2(-1, -1)
var _reading := ""
var _chalk := Vector2(-1, -1)
var _chalk_r := 0.0
var _ink := Color.BLACK
var _arrow := Color.BLACK
var _chalk_c := Color.WHITE
var _font: Font
var _held := false
var _routes: Array = []   # each piece's dashed line to its pennant, a polyline in screen px (its route's curve)
var _drafts: Array = []   # each draft's pencil line, a polyline in screen px (spec 2026-10-02-war-room-v2 §3.1)
var _path := PackedVector2Array()     # the rake bent through waypoints (spec 2026-10-07-march-waypoints), else empty
var _handles := PackedVector2Array()  # the planned waypoints' rings
var _pencil := Color.GRAY


func setup(repo: DataRepository) -> void:
	_repo = repo


func draw_state(rake_from: Vector2, rake_to: Vector2, reading: String, chalk: Vector2, chalk_r: float,
		ink: Color, arrow: Color, chalk_c: Color, font: Font, held := false, routes: Array = [],
		drafts: Array = [], pencil := Color.GRAY) -> void:
	_from = rake_from
	_to = rake_to
	_reading = reading
	_chalk = chalk
	_chalk_r = chalk_r
	_ink = ink
	_arrow = arrow
	_chalk_c = chalk_c
	_font = font
	_held = held
	_routes = routes
	_drafts = drafts
	_pencil = pencil
	queue_redraw()


## The rake's line through planned waypoints (screen px; empty: the straight
## arrow) and the waypoints' rings (spec 2026-10-07-march-waypoints).
func set_route(path: PackedVector2Array, handles: PackedVector2Array) -> void:
	_path = path
	_handles = handles
	queue_redraw()


## The draft lines being drawn (tests read it).
func draft_lines() -> Array:
	return _drafts


## True when anything is drawn: the arrow, the chalk ring or a pennant's line.
func drawing() -> bool:
	return _chalk.x >= 0.0 or not _routes.is_empty() or not _drafts.is_empty() or _has_arrow()


func _has_arrow() -> bool:
	return _from.x >= 0.0 and _to.x >= 0.0 and _from.distance_to(_to) >= _repo.bal("war_hud_min_len_px")


## A dashed line from `a` to `b` (the dash war_hud_dash_px unless `dash` is
## given, the gap its own length).
func _dashed(a: Vector2, b: Vector2, color: Color, width: float, dash := -1.0) -> void:
	var dir := (b - a).normalized()
	if dash <= 0.0:
		dash = _repo.bal("war_hud_dash_px")
	var run := a.distance_to(b)
	var at := 0.0
	while at < run:
		draw_line(a + dir * at, a + dir * minf(at + dash, run), color, width, true)
		at += dash * 2.0


## A draft's pencil stroke from the piece to its pennant: solid graphite, not
## the map's dashes (taste: a tool never borrows the map's line language),
## ending in a small open arrowhead; dashed only if war_draft_pencil_dash_px > 0.
func _pencilled(a: Vector2, b: Vector2) -> void:
	var width := _repo.bal("war_draft_pencil_px")
	var dash := _repo.bal("war_draft_pencil_dash_px")
	if dash > 0.0:
		_dashed(a, b, _pencil, width, dash)
	else:
		draw_line(a, b, _pencil, width, true)
	var head := _repo.bal("war_draft_head_px")
	if a.distance_to(b) <= head * 2.0:
		return
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tail := b - dir * head
	draw_polyline(PackedVector2Array([tail + side * head * 0.55, b, tail - side * head * 0.55]), _pencil, width, true)


## The rake's arrow along its bent line: the shaft through every point, the
## head on the last segment, the reading at the middle point.
func _draw_bent() -> void:
	var width := _repo.bal("war_hud_arrow_px")
	var head := _repo.bal("war_hud_head_px")
	var end := _path[_path.size() - 1]
	var dir := (end - _path[_path.size() - 2]).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tail := end - dir * head
	var shaft := _path.slice(0, _path.size() - 1)
	shaft.append(tail)
	if _held:
		draw_multiline(MapRuler.dash_pieces(shaft, _repo.bal("war_hud_dash_px")), _arrow, width, true)
	else:
		draw_polyline(shaft, _arrow, width, true)
	var half := _repo.bal("war_hud_head_half_px")
	draw_colored_polygon(PackedVector2Array([end, tail + side * half, tail - side * half]), _arrow)
	if _reading != "" and _font != null:
		var mid := _path[int(_path.size() * 0.5)] + side * _repo.bal("war_hud_reading_gap_px")
		var px := int(_repo.bal("war_hud_reading_px"))
		var halo: Color = _repo.war_palette["paper"]
		halo.a = _repo.bal("war_hud_halo_alpha")
		draw_string_outline(_font, mid, _reading, HORIZONTAL_ALIGNMENT_CENTER, -1, px,
			int(_repo.bal("war_hud_reading_outline_px")), halo)
		draw_string(_font, mid, _reading, HORIZONTAL_ALIGNMENT_CENTER, -1, px, _ink)


func _draw() -> void:
	if _repo == null:
		return
	if _chalk.x >= 0.0:
		draw_arc(_chalk, _chalk_r, 0.0, TAU, 48, _chalk_c, _repo.bal("war_hud_chalk_px"), true)
	for line: Variant in _routes:
		var r := PackedVector2Array(line)
		if r.size() > 2:   # a route's curve: the dashes run on across its joints
			draw_multiline(MapRuler.dash_pieces(r, _repo.bal("war_hud_dash_px")), _ink, _repo.bal("war_hud_arrow_px"), true)
		elif r.size() == 2:
			_dashed(r[0], r[1], _ink, _repo.bal("war_hud_arrow_px"))
	for line: Variant in _drafts:
		var r := PackedVector2Array(line)
		if r.size() > 2:   # a route's curve, one stroke up to its last segment
			draw_polyline(r.slice(0, r.size() - 1), _pencil, _repo.bal("war_draft_pencil_px"), true)
		if r.size() >= 2:
			_pencilled(r[r.size() - 2], r[r.size() - 1])
	for h in _handles:
		draw_arc(h, _repo.bal("war_route_handle_px"), 0.0, TAU, 20, _arrow, _repo.bal("war_hud_arrow_px"), true)
	if not _has_arrow():
		return
	if _path.size() > 2:
		_draw_bent()
		return
	var dir := (_to - _from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var head := _repo.bal("war_hud_head_px")
	var width := _repo.bal("war_hud_arrow_px")
	var tail := _to - dir * head
	if _held:
		_dashed(_from, tail, _arrow, width)
	else:
		draw_line(_from, tail, _arrow, width, true)
	var half := _repo.bal("war_hud_head_half_px")
	draw_colored_polygon(PackedVector2Array([_to, tail + side * half, tail - side * half]), _arrow)
	if _reading != "" and _font != null:
		var mid := (_from + _to) * 0.5 + side * _repo.bal("war_hud_reading_gap_px")
		var px := int(_repo.bal("war_hud_reading_px"))
		var halo: Color = _repo.war_palette["paper"]
		halo.a = _repo.bal("war_hud_halo_alpha")
		draw_string_outline(_font, mid, _reading, HORIZONTAL_ALIGNMENT_CENTER, -1, px,
			int(_repo.bal("war_hud_reading_outline_px")), halo)
		draw_string(_font, mid, _reading, HORIZONTAL_ALIGNMENT_CENTER, -1, px, _ink)
