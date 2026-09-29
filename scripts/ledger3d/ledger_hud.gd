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
	_entries = cull(entries, _px)
	queue_redraw()


## Keeps entries in order, dropping any whose box overlaps one already kept.
## The box is estimated from the text length at the font size (0.55 em a
## glyph), centred on `at`, so the cull needs no Font and is testable.
static func cull(entries: Array, font_px: float) -> Array:
	var kept: Array = []
	var boxes: Array[Rect2] = []
	for e: Dictionary in entries:
		var w := float(String(e["text"]).length()) * font_px * 0.55
		var box := Rect2((e["at"] as Vector2) - Vector2(w * 0.5, font_px), Vector2(w, font_px * 1.2))
		var clear := true
		for b in boxes:
			if b.intersects(box):
				clear = false
				break
		if clear:
			boxes.append(box)
			kept.append(e)
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
