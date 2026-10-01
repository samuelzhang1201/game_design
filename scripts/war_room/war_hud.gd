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
var _routes: Array = []   # [from, to] screen px of each piece's dashed line to its pennant


func setup(repo: DataRepository) -> void:
	_repo = repo


func draw_state(rake_from: Vector2, rake_to: Vector2, reading: String, chalk: Vector2, chalk_r: float,
		ink: Color, arrow: Color, chalk_c: Color, font: Font, held := false, routes: Array = []) -> void:
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
	queue_redraw()


## True when anything is drawn: the arrow, the chalk ring or a pennant's line.
func drawing() -> bool:
	return _chalk.x >= 0.0 or not _routes.is_empty() or _has_arrow()


func _has_arrow() -> bool:
	return _from.x >= 0.0 and _to.x >= 0.0 and _from.distance_to(_to) >= _repo.bal("war_hud_min_len_px")


## A dashed line from `a` to `b` (the dash war_hud_dash_px, the gap its own length).
func _dashed(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var dir := (b - a).normalized()
	var dash := _repo.bal("war_hud_dash_px")
	var run := a.distance_to(b)
	var at := 0.0
	while at < run:
		draw_line(a + dir * at, a + dir * minf(at + dash, run), color, width, true)
		at += dash * 2.0


func _draw() -> void:
	if _repo == null:
		return
	if _chalk.x >= 0.0:
		draw_arc(_chalk, _chalk_r, 0.0, TAU, 48, _chalk_c, _repo.bal("war_hud_chalk_px"), true)
	for r: Array in _routes:
		_dashed(r[0], r[1], _ink, _repo.bal("war_hud_arrow_px"))
	if not _has_arrow():
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
