class_name Map3DHudNeedle
extends Node2D
## The compass's north needle, drawn as its own CanvasItem after CompassLayer
## so it paints on top of the wheel art: a CanvasItem child always draws over
## its earlier siblings at the same z_index, and a negative z_index on the
## wheel instead would sink it below the view's own TextureRect (a sibling of
## Hud, not a child of it) and hide it entirely. It turns with the view,
## under a drop shadow and a small rotating "N" (fix round 1).

var hud: Map3DHud


func _draw() -> void:
	if hud == null or hud.ctx == null:
		return
	var repo := hud.ctx.repo
	var r := hud.compass_rect()
	if r.size.x <= 0.0:
		return
	var c := r.get_center()
	var reach := r.size.x * 0.5 * repo.bal("map3d_compass_needle_reach")
	var w := r.size.x * 0.5 * repo.bal("map3d_compass_needle_width")
	var gold := MapPalette.named(repo, "map3d_selection")
	var ink := MapTerrain.palette_color(repo, "coast_line", MapTerrain.FALLBACK)
	var halo := Map3DHud.halo(repo)
	if not hud.has_compass_art():
		draw_arc(c, r.size.x * 0.5 - 2.0, 0.0, TAU, 48, ink, 2.0, true)
	draw_set_transform(c, Map3DHud.needle_angle(hud.ctx.yaw), Vector2.ONE)
	var north := PackedVector2Array([Vector2(0, -reach), Vector2(w, 0), Vector2(-w, 0)])
	var south := PackedVector2Array([Vector2(0, reach), Vector2(w, 0), Vector2(-w, 0)])
	var shadow_alpha := repo.bal("map3d_compass_needle_shadow_alpha")
	if shadow_alpha > 0.0:
		var shadow := Color(0.0, 0.0, 0.0, shadow_alpha)
		var by := Vector2(1.5, 2.0)
		draw_colored_polygon(_offset_poly(south, by), shadow)
		draw_colored_polygon(_offset_poly(north, by), shadow)
	draw_colored_polygon(south, Color(ink, 0.85))
	draw_colored_polygon(north, gold)
	draw_polyline(PackedVector2Array([Vector2(0, -reach), Vector2(w, 0), Vector2(0, reach),
		Vector2(-w, 0), Vector2(0, -reach)]), ink, 1.5, true)
	_draw_north_label(gold, halo, reach)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A small "N" just beyond the north tip, in the same rotated frame as the
## needle so it turns with it.
func _draw_north_label(gold: Color, halo: Color, reach: float) -> void:
	var font := UiPalette.display_font()
	if font == null:
		return
	var font_px := 10
	var text := "N"
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x
	var pos := Vector2(-text_w * 0.5, -reach - 4.0)
	if halo.a > 0.0:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 3, halo)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, gold)


static func _offset_poly(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(p + by)
	return out
