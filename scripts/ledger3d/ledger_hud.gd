# scripts/ledger3d/ledger_hud.gd
class_name LedgerHud
extends Control
## The LEDGER's sphere names (spec 2026-09-30 §6.2), drawn on a 2D layer
## over the 3D view so they always face the screen, cut once per camera pose
## so no two overlap (the Map3DHud practice). The view hands it entries.

var _entries: Array = []
var _font: Font
var _ink := Color.WHITE
var _halo := Color.BLACK
var _px := 14.0
var _halo_px := 4


func style(font: Font, px: float, ink: Color, halo: Color, halo_px: int) -> void:
	_font = font
	_px = px
	_ink = ink
	_halo = halo
	_halo_px = halo_px


func show_entries(entries: Array) -> void:
	_entries = cull(entries, _px, _font)
	queue_redraw()


## Keeps entries in order, dropping any whose box overlaps one already kept.
## An entry may carry `alt`, a second place (under its sphere): a name whose
## own place is taken stands there if that is clear, so a type in a close row
## keeps its name. The box is the text's measured width when a font is given,
## else estimated at 0.55 em a glyph (so the cull is testable without one),
## centred on the place, with a quarter em of air at each end.
static func cull(entries: Array, font_px: float, font: Font = null) -> Array:
	var kept: Array = []
	var boxes: Array[Rect2] = []
	for e: Dictionary in entries:
		var text := String(e["text"])
		var w := float(text.length()) * font_px * 0.55
		if font != null:
			w = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_px)).x
		var places: Array = [e["at"]]
		if e.has("alt"):
			places.append(e["alt"])
		for at: Vector2 in places:
			# the box the name is drawn in (_draw sets its baseline 0.35 em
			# below the place: capitals reach ~0.45 em above the place,
			# descenders ~0.6 em below), with a quarter em of air each side
			# so two names in a row never butt into one another and read as one
			var box := Rect2(at - Vector2(w * 0.5 + font_px * 0.25, font_px * 0.45),
				Vector2(w + font_px * 0.5, font_px * 1.05))
			var clear := true
			for b in boxes:
				if b.intersects(box):
					clear = false
					break
			if clear:
				boxes.append(box)
				var put := e.duplicate()
				put["at"] = at
				kept.append(put)
				break
	return kept


func _draw() -> void:
	if _font == null:
		return
	for e: Dictionary in _entries:
		var text := String(e["text"])
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px)).x
		var at := (e["at"] as Vector2) - Vector2(w * 0.5, -_px * 0.35)
		draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px), _halo_px, _halo)
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(_px),
			_ink if bool(e["strong"]) else Color(_ink, 0.8))
