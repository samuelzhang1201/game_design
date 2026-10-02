@tool
class_name ScaledNineSlice
extends StyleBox
## A nine-slice StyleBox for art installed at more than one texture px per
## design px (the Missive board's pieces, library U-20..U-26: hi-res for the
## game's ~3x window scale; each piece's `scale` is on its .tres).
##
## Godot's own StyleBoxTexture draws one texture px per design px — it has no
## scale (CLAUDE.md notes the same trap for the vellum panel plate) — so a
## piece authored 3x oversized drew a border three times its intended width.
## Here `source_inset` (how much of the art is corner, in TEXTURE px) and the
## drawn corner (source_inset / `scale`, in DESIGN px) are separate, the same
## split VellumPanelStyle already draws its plate with.
##
## `source_inset` 0 has no corners to nine-slice — the whole box is the middle
## cell — so instead of STRETCHING the art over the box (VellumPanelStyle's
## middle cell does, which is right for a plate's one painted centre but wrong
## for a repeating material) this TILES it, each tile the art's own size /
## `scale` in design px: the cork board's weave at its real texel density,
## however large the board is drawn.

@export var texture: Texture2D = null:
	set(v):
		texture = v
		emit_changed()
## How much of the art is corner, in TEXTURE px. 0 tiles instead of slicing.
@export var source_inset := 0.0:
	set(v):
		source_inset = v
		emit_changed()
## Texture px per design px the art was authored at.
@export var scale := 1.0:
	set(v):
		scale = v
		emit_changed()
@export var tint := Color.WHITE:
	set(v):
		tint = v
		emit_changed()
## A style drawn FIRST, under the art, over the box shrunk by `fill_inset`
## TEXTURE px (scaled like the corners): what shows through a frame whose
## opening is clear — the Missive board's wood under its carved frame (owner
## 2026-09-30). null draws nothing under.
@export var fill: StyleBox = null:
	set(v):
		fill = v
		emit_changed()
@export var fill_inset := 0.0:
	set(v):
		fill_inset = v
		emit_changed()


## The corner's drawn size in design px (source_inset scaled down); what a
## caller measures a piece's border by.
func draw_inset() -> float:
	return source_inset / scale if scale > 0.0 else source_inset


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if fill != null:
		var f := rect.grow(-(fill_inset / scale if scale > 0.0 else fill_inset))
		if f.size.x > 0.0 and f.size.y > 0.0:
			fill.draw(to_canvas_item, f)
	if texture == null:
		return
	if source_inset <= 0.0:
		_draw_tiled(to_canvas_item, rect)
		return
	var tw := float(texture.get_width())
	var th := float(texture.get_height())
	var s := minf(source_inset, minf(tw, th) / 2.0)
	# never let the two corners of a short side overlap: a narrow box keeps
	# its frame, it just gets less of the middle (VellumPanelStyle's rule)
	var d := minf(draw_inset(), minf(rect.size.x, rect.size.y) / 2.0)
	var sx := [0.0, s, tw - s, tw]
	var sy := [0.0, s, th - s, th]
	var dx := [rect.position.x, rect.position.x + d, rect.end.x - d, rect.end.x]
	var dy := [rect.position.y, rect.position.y + d, rect.end.y - d, rect.end.y]
	var rid := texture.get_rid()
	for r in 3:
		for c in 3:
			var dst := Rect2(dx[c], dy[r], dx[c + 1] - dx[c], dy[r + 1] - dy[r])
			if dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			var src := Rect2(sx[c], sy[r], sx[c + 1] - sx[c], sy[r + 1] - sy[r])
			RenderingServer.canvas_item_add_texture_rect_region(
				to_canvas_item, dst, rid, src, tint)


## Tiled at the art's own size / scale a design-px tile (VellumPanelStyle's
## grain drawing, the same idea: a texel is `1 / scale` design px), the last
## row and column cut to the box. A non-positive `scale` (misconfigured data,
## never a real installed scale) is treated as 1 rather than
## dividing by it — the same fallback draw_inset() uses — since a step that
## never advances (0) or runs backwards (negative) would loop forever.
func _draw_tiled(ci: RID, rect: Rect2) -> void:
	var tw := float(texture.get_width())
	var th := float(texture.get_height())
	var s := scale if scale > 0.0 else 1.0
	var step := Vector2(tw, th) / s
	if step.x <= 0.0 or step.y <= 0.0:
		return
	var rid := texture.get_rid()
	var y := rect.position.y
	while y < rect.end.y:
		var h := minf(step.y, rect.end.y - y)
		var x := rect.position.x
		while x < rect.end.x:
			var w := minf(step.x, rect.end.x - x)
			RenderingServer.canvas_item_add_texture_rect_region(ci,
				Rect2(x, y, w, h), rid, Rect2(0, 0, w * s, h * s), tint)
			x += step.x
		y += step.y


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect
