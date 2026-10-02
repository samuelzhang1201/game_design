class_name WarScrollReveal
extends Control
## The WAR ROOM comes down like a hanging scroll (owner 2026-10-02: 点击war
## room的进入动画太突兀，做成一个从上往下的卷轴拉下来即可 — replacing the
## steward's report rolling up while the room widened over its column). An
## overlay on the room's rect: opening, the room is already laid underneath
## and `cover` is a capture of the screen it hides, drawn BELOW a wooden
## roller that descends from the rod at the top to the foot; closing, `cover`
## is a capture of the room, drawn ABOVE the roller as it rises back, the live
## screen showing beneath. It takes no clicks and frees itself. Without a
## capture (headless) it draws only the roller.

const ROLLER_WOOD := Color(0.36, 0.24, 0.14)
const ROLLER_CAP := Color(0.62, 0.48, 0.22)
## The soft shadow the roller casts on the paper just above it, as a share of
## the roller's thickness (the scroll's lower edge curls round it).
const CURL_SHADOW := 1.6
## The scroll's paper showing above the roller, as a share of its thickness.
const PAPER_BAND := 2.2

var _cover: Texture2D
var _down := true
var _seconds := 0.5
var _roller := 16.0
var _t := 0.0


static func play(host: Node, rect: Rect2, cover: Texture2D, down: bool, seconds: float,
		roller_px: float) -> WarScrollReveal:
	var r := WarScrollReveal.new()
	r.name = "WarScrollReveal"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.top_level = true
	r.position = rect.position
	r.size = rect.size
	r._cover = cover
	r._down = down
	r._seconds = maxf(seconds, 0.01)
	r._roller = roller_px
	host.add_child(r)
	return r


## What `viewport` shows inside `rect` (canvas px) now, null headless or off
## screen: the picture the scroll covers or carries.
static func capture(viewport: Viewport, rect: Rect2) -> Texture2D:
	if DisplayServer.get_name() == "headless" or viewport == null:
		return null
	var img := viewport.get_texture().get_image()
	if img == null or img.is_empty():
		return null
	var k := viewport.get_final_transform().get_scale().x
	var px := Rect2i(Vector2i(rect.position * k), Vector2i(rect.size * k)).intersection(
		Rect2i(Vector2i.ZERO, img.get_size()))
	if px.size.x <= 0 or px.size.y <= 0:
		return null
	return ImageTexture.create_from_image(img.get_region(px))


## How far down the scroll hangs: 0 rolled up at the rod, 1 down to its foot.
func share() -> float:
	var k := clampf(_t / _seconds, 0.0, 1.0)
	# eased out on the way down (a pull that settles), in on the way up
	var e := 1.0 - pow(1.0 - k, 3.0) if _down else k * k * k
	return e if _down else 1.0 - e


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t >= _seconds:
		queue_free()


func _draw() -> void:
	var y := (size.y - _roller) * share()
	if _cover != null:
		var tw := float(_cover.get_width())
		var th := float(_cover.get_height())
		var k := th / maxf(size.y, 1.0)
		if _down and y + _roller < size.y:
			# the screen not yet covered, below the roller
			var top := y + _roller * 0.5
			draw_texture_rect_region(_cover, Rect2(0.0, top, size.x, size.y - top),
				Rect2(0.0, top * k, tw, (size.y - top) * k))
		elif not _down and y > 0.5:
			# the room still hanging, above the roller
			draw_texture_rect_region(_cover, Rect2(0.0, 0.0, size.x, y + _roller * 0.5),
				Rect2(0.0, 0.0, tw, (y + _roller * 0.5) * k))
	# the scroll's own paper where it leaves the roller: a parchment band fading
	# up into the room, so what comes down reads as a sheet, not a wipe
	var paper := UiPalette.table_color("paper", Color("e2c995"))
	var band := _roller * PAPER_BAND
	for i in 8:
		var t := float(i) / 8.0
		draw_rect(Rect2(0.0, y - band * (1.0 - t), size.x, band / 8.0 + 0.5), Color(paper, 0.9 * t * t))
	# the paper curls round the roller: a soft shade on the hanging scroll above it
	var shade := _roller * CURL_SHADOW
	for i in 6:
		var a := float(i + 1) / 6.0
		var h := shade * (1.0 - float(i) / 6.0)
		draw_rect(Rect2(0.0, y - h, size.x, h), Color(0, 0, 0, 0.05 * a))
	# the roller's own shadow on the screen beneath it
	for i in 5:
		draw_rect(Rect2(0.0, y + _roller, size.x, _roller * 0.25 * float(5 - i)), Color(0, 0, 0, 0.06))
	# the rod the scroll hangs from, and the roller it unrolls on
	draw_round_roller(self, Rect2(0.0, 0.0, size.x, _roller * 0.6))
	draw_round_roller(self, Rect2(0.0, y, size.x, _roller))


## A turned wooden roller across `r`, shaded as a cylinder lit from above,
## with round brass knobs past both ends.
static func draw_round_roller(ci: CanvasItem, r: Rect2) -> void:
	var bands := 8
	for i in bands:
		var t := (float(i) + 0.5) / float(bands)
		# lit near its top, dark under its belly
		var lit := 1.0 - absf(t - 0.3) * 1.6
		var c := ROLLER_WOOD.lightened(clampf(lit, 0.0, 1.0) * 0.35) if lit > 0.0 else ROLLER_WOOD.darkened(clampf(-lit, 0.0, 1.0) * 0.6)
		ci.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * float(i) / float(bands), r.size.x, r.size.y / float(bands) + 0.5), c)
	var knob := r.size.y * 0.62
	for x in [r.position.x - knob * 0.35, r.end.x + knob * 0.35]:
		var c := Vector2(x, r.position.y + r.size.y * 0.5)
		ci.draw_circle(c, knob, ROLLER_CAP.darkened(0.35))
		ci.draw_circle(c - Vector2(0.0, knob * 0.12), knob * 0.82, ROLLER_CAP)
		ci.draw_circle(c - Vector2(knob * 0.2, knob * 0.3), knob * 0.3, ROLLER_CAP.lightened(0.4))


## A wooden roller across `r`: a dark core, a lit band along its top, brass
## end caps. Static so the card's roll (WarRoomScreen) draws the same one.
static func draw_roller(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, ROLLER_WOOD)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), ROLLER_WOOD.lightened(0.25))
	ci.draw_rect(Rect2(r.position + Vector2(0.0, r.size.y * 0.8), Vector2(r.size.x, r.size.y * 0.2)), ROLLER_WOOD.darkened(0.4))
	var cap := r.size.y * 0.3
	ci.draw_rect(Rect2(r.position - Vector2(cap, 0.0), Vector2(cap, r.size.y)), ROLLER_CAP)
	ci.draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(cap, r.size.y)), ROLLER_CAP)
