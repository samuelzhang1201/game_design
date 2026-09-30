# scripts/ledger3d/ledger_hud.gd
class_name LedgerHud
extends Control
## The LEDGER's sphere names (spec 2026-09-30 §6.2), drawn on a 2D layer
## over the 3D view so they always face the screen, cut once per camera pose
## so no two overlap (the Map3DHud practice). The view hands it entries.
## An entry with `props` (spec §6.3 "a property": a regiment's supplies and
## morale, a goods pool's stock) carries a row of small ring gauges, each
## with its caption, on the far side of its name from its sphere — over a
## name that stands above the sphere, under one set beneath it (its `alt`)
## — so the row never covers the sphere or the threads leaving it. The row
## takes room in the cull.

## The gauge row's measures until the view styles it (balance ledger_gauge_*).
const DEFAULT_GAUGE := {"radius": 7.0, "width": 3.0, "gap": 3.0, "caption_px": 12.0}
const GAUGE_SPACING_EM := 0.9   # between two gauges of one row, in caption ems
const GAUGE_CAPTION_GAP := 3.0  # design px between a ring and its caption

var _entries: Array = []
var _rings: Array = []
var _font: Font
var _title_font: Font
var _title_px := 20.0
var _ink := Color.WHITE
var _halo := Color.BLACK
var _px := 14.0
var _halo_px := 4
var _gauge: Dictionary = DEFAULT_GAUGE.duplicate()
var _fill := Color(0.88, 0.73, 0.42)
var _track := Color(0.29, 0.24, 0.17)
var _ring := Color(0.88, 0.73, 0.42)
var _ring_w := 3.0


func style(font: Font, px: float, ink: Color, halo: Color, halo_px: int) -> void:
	_font = font
	_px = px
	_ink = ink
	_halo = halo
	_halo_px = halo_px


func style_gauges(radius: float, width: float, gap: float, caption_px: float, fill: Color,
		track: Color) -> void:
	_gauge = {"radius": radius, "width": width, "gap": gap, "caption_px": caption_px}
	_fill = fill
	_track = track


func style_title(font: Font, px: float) -> void:
	_title_font = font
	_title_px = px


func style_ring(colour: Color, width_px: float) -> void:
	_ring = colour
	_ring_w = width_px


func show_entries(entries: Array, obstacles: Array = []) -> void:
	_entries = cull(entries, _px, _font, _gauge, obstacles)
	_rings.clear()
	for e: Dictionary in entries:
		if e.has("ring"):
			_rings.append([e["ring_at"], float(e["ring"])])
	queue_redraw()


## "Supplies 64%" for a per-mille gauge, "Morale 70" out of 100, else the
## whole figure grouped by thousands ("Stock 12,400").
static func caption_of(prop: Dictionary) -> String:
	var v := int(prop["value"])
	var m := int(prop["max"])
	var text := ""
	if m == 1000:
		@warning_ignore("integer_division")
		text = "%d%%" % (clampi(v, 0, 1000) / 10)
	else:
		text = UiPalette.format_int(v)
	return "%s %s" % [prop["label"], text]


## The share of the ring filled: value over max, 0..1 (0 for no max).
static func fill_of(prop: Dictionary) -> float:
	var m := float(prop["max"])
	return 0.0 if m <= 0.0 else clampf(float(prop["value"]) / m, 0.0, 1.0)


## The width of a gauge row: each ring, its caption, and the air between.
static func gauge_row_w(props: Array, gauge: Dictionary, font: Font = null) -> float:
	var cpx := float(gauge["caption_px"])
	var w := 0.0
	for i in props.size():
		var cap := caption_of(props[i])
		var cw := float(cap.length()) * cpx * 0.55
		if font != null:
			cw = font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, int(cpx)).x
		w += float(gauge["radius"]) * 2.0 + GAUGE_CAPTION_GAP + cw
		if i > 0:
			w += cpx * GAUGE_SPACING_EM
	return w


## Design px the gauge row adds under a name (0 without gauges).
static func gauge_row_h(props: Array, gauge: Dictionary) -> float:
	if props.is_empty():
		return 0.0
	return float(gauge["gap"]) + maxf(float(gauge["radius"]) * 2.0 + float(gauge["width"]),
		float(gauge["caption_px"]))


## Keeps entries in order, dropping any whose box overlaps one already kept.
## An entry may carry `alt`, a second place (under its sphere): a name whose
## own place is taken stands there if that is clear, so a type in a close row
## keeps its name. The box is the text's measured width when a font is given,
## else estimated at 0.55 em a glyph (so the cull is testable without one),
## centred on the place, with a quarter em of air at each end.
static func cull(entries: Array, font_px: float, font: Font = null, gauge: Dictionary = DEFAULT_GAUGE,
		obstacles: Array = []) -> Array:
	var kept: Array = []
	var boxes: Array[Rect2] = []
	for o in obstacles:
		boxes.append(o)
	for e: Dictionary in entries:
		var px := float(e.get("px", font_px))
		var text := String(e["text"])
		var w := float(text.length()) * px * 0.55
		if font != null:
			w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x
		var props: Array = e.get("props", [])
		var extra_h := gauge_row_h(props, gauge)
		if not props.is_empty():
			w = maxf(w, gauge_row_w(props, gauge, font))
		var places: Array = [e["at"]]
		if e.has("alt"):
			places.append(e["alt"])
		for k in places.size():
			var at: Vector2 = places[k]
			var up := k == 0  # the first place stands above the sphere: its gauges go over it
			# the box the name is drawn in (_draw sets its baseline 0.35 em
			# below the place: capitals reach ~0.45 em above the place,
			# descenders ~0.6 em below), with a quarter em of air each side
			# so two names in a row never butt into one another and read as one
			var box := Rect2(at - Vector2(w * 0.5 + px * 0.25, px * 0.45 + (extra_h if up else 0.0)),
				Vector2(w + px * 0.5, px * 1.05 + extra_h))
			var clear := true
			for b in boxes:
				if b.intersects(box):
					clear = false
					break
			if clear:
				boxes.append(box)
				var put := e.duplicate()
				put["at"] = at
				put["gauges_up"] = up
				kept.append(put)
				break
	return kept


func _draw() -> void:
	for r: Array in _rings:
		draw_arc(r[0], r[1], 0.0, TAU, 48, _ring, _ring_w, true)
	if _font == null:
		return
	for e: Dictionary in _entries:
		var px := float(e.get("px", _px))
		var font: Font = _title_font if bool(e.get("title", false)) and _title_font != null else _font
		var ink: Color = e.get("ink", _ink if bool(e["strong"]) else Color(_ink, 0.8))
		var text := String(e["text"])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x
		var at := (e["at"] as Vector2) - Vector2(w * 0.5, -px * 0.35)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px), _halo_px, _halo)
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px), ink)
		var props: Array = e.get("props", [])
		if not props.is_empty():
			var row_h := gauge_row_h(props, _gauge)
			var top := (e["at"] as Vector2) + Vector2(0, px * 0.6 + float(_gauge["gap"]))
			if bool(e.get("gauges_up", false)):
				top = (e["at"] as Vector2) - Vector2(0, px * 0.45 + row_h)
			_draw_gauges(props, top)


## One row of ring gauges centred under a name, `top` its top centre: each a
## dark track ring with its share filled clockwise from twelve o'clock, then
## its caption in the name's ink over the same halo.
func _draw_gauges(props: Array, top: Vector2) -> void:
	var r := float(_gauge["radius"])
	var width := float(_gauge["width"])
	var cpx := int(_gauge["caption_px"])
	var row_h := gauge_row_h(props, _gauge) - float(_gauge["gap"])
	var x := top.x - gauge_row_w(props, _gauge, _font) * 0.5
	var cy := top.y + row_h * 0.5
	for i in props.size():
		var p: Dictionary = props[i]
		if i > 0:
			x += float(cpx) * GAUGE_SPACING_EM
		var c := Vector2(x + r, cy)
		draw_arc(c, r + width * 0.5 + 1.0, 0.0, TAU, 32, _halo, 1.5, true)
		draw_arc(c, r, 0.0, TAU, 32, _track, width, true)
		var f := fill_of(p)
		if f > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * f, maxi(4, int(32.0 * f)), _fill, width, true)
		x += r * 2.0 + GAUGE_CAPTION_GAP
		var cap := caption_of(p)
		var base := Vector2(x, cy + float(cpx) * 0.35)
		draw_string_outline(_font, base, cap, HORIZONTAL_ALIGNMENT_LEFT, -1, cpx, maxi(_halo_px - 1, 1), _halo)
		draw_string(_font, base, cap, HORIZONTAL_ALIGNMENT_LEFT, -1, cpx, Color(_ink, 0.9))
		x += _font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, cpx).x
