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


func setup(repo: DataRepository) -> void:
	_repo = repo


func draw_state(rake_from: Vector2, rake_to: Vector2, reading: String, chalk: Vector2, chalk_r: float,
		ink: Color, arrow: Color, chalk_c: Color, font: Font, held := false) -> void:
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
	queue_redraw()


## True when anything is drawn: the arrow, or the chalk ring.
func drawing() -> bool:
	return _chalk.x >= 0.0 or (_from.x >= 0.0 and _to.x >= 0.0 and _from.distance_to(_to) >= 4.0)


func _draw() -> void:
	if _repo == null:
		return
	if _chalk.x >= 0.0:
		draw_arc(_chalk, _chalk_r, 0.0, TAU, 48, _chalk_c, _repo.bal("war_hud_chalk_px"), true)
	if _from.x < 0.0 or _to.x < 0.0 or _from.distance_to(_to) < 4.0:
		return
	var dir := (_to - _from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var head := _repo.bal("war_hud_head_px")
	var width := _repo.bal("war_hud_arrow_px")
	var tail := _to - dir * head
	if _held:
		var dash := _repo.bal("war_hud_dash_px")
		var at := 0.0
		var run := _from.distance_to(tail)
		while at < run:
			draw_line(_from + dir * at, _from + dir * minf(at + dash, run), _arrow, width, true)
			at += dash * 2.0
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
