class_name WarReportRoll
extends Control
## The steward's report rolling up as the WAR ROOM opens over its column, and
## down again as it closes (spec 2026-10-02-war-room-v2 §1.2). An overlay laid
## on the column's rect: it draws the top share of a capture of the report
## (the paper as it lay) above a roller, the share eased from 1 to 0 (up) or 0
## to 1 (down), and frees itself. Without a capture (headless, or none taken)
## it draws the paper's own colour. Under the leather chrome (`paper` false)
## the same share slides the column up and fades it instead of rolling it.

const ROLLER_WOOD := Color(0.36, 0.24, 0.14)
const ROLLER_CAP := Color(0.62, 0.48, 0.22)

var _capture: Texture2D
var _up := true
var _seconds := 0.4
var _roller := 12.0
var _paper := true
var _t := 0.0


static func play(host: Node, rect: Rect2, capture: Texture2D, up: bool, seconds: float,
		roller_px: float, paper: bool) -> WarReportRoll:
	var r := WarReportRoll.new()
	r.name = "WarReportRoll"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.top_level = true
	r.position = rect.position
	r.size = rect.size
	r._capture = capture
	r._up = up
	r._seconds = maxf(seconds, 0.01)
	r._roller = roller_px
	r._paper = paper
	host.add_child(r)
	return r


## The share of the paper showing now: 1 open, 0 rolled to its roller.
func share() -> float:
	var k := smoothstep(0.0, 1.0, clampf(_t / _seconds, 0.0, 1.0))
	return 1.0 - k if _up else k


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= _seconds:
		queue_free()


func _draw() -> void:
	var s := share()
	if not _paper:
		var drop := (1.0 - s) * size.y * 0.25
		var r := Rect2(0.0, -drop, size.x, size.y)
		if _capture != null:
			draw_texture_rect(_capture, r, false, Color(1, 1, 1, s))
		else:
			draw_rect(r, Color(UiPalette.PANEL_BG, s))
		return
	var h := (size.y - _roller) * s
	if h > 0.5:
		var body := Rect2(0.0, 0.0, size.x, h)
		if _capture != null:
			draw_texture_rect_region(_capture, body,
				Rect2(Vector2.ZERO, Vector2(_capture.get_width(), _capture.get_height() * h / size.y)))
		else:
			draw_rect(body, UiPalette.table_color("paper", UiPalette.PANEL_BG))
	draw_roller(self, Rect2(0.0, h, size.x, _roller))


## A wooden roller across `r`: a dark core, a lit band along its top, brass
## end caps. Static so the card's roll (WarRoomScreen) draws the same one.
static func draw_roller(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, ROLLER_WOOD)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), ROLLER_WOOD.lightened(0.25))
	ci.draw_rect(Rect2(r.position + Vector2(0.0, r.size.y * 0.8), Vector2(r.size.x, r.size.y * 0.2)), ROLLER_WOOD.darkened(0.4))
	var cap := r.size.y * 0.3
	ci.draw_rect(Rect2(r.position - Vector2(cap, 0.0), Vector2(cap, r.size.y)), ROLLER_CAP)
	ci.draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(cap, r.size.y)), ROLLER_CAP)
