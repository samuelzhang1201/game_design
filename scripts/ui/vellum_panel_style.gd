class_name VellumPanelStyle
extends StyleBox
## A nine-slice whose SOURCE inset and DRAWN inset are separate numbers.
##
## Godot's StyleBoxTexture ties them together — it draws one texture pixel per
## design pixel — so a 20-design-px corner can only ever sample a 20 px region
## of the plate. On a 1280x720 window (canvas_items stretch over a 640x360
## base, so a canvas scale of 2) that is a 2x upscale and the ornament goes
## soft. Every other asset in the game is authored for that scale and lands at
## 1:1 or better: 96 px portrait chips in 48 design px, a 256 px settlement in
## 40, a 1008 px menu frame in 360. The panel was the one exception, and it
## was an exception only because of this coupling.
##
## Here a 475 px plate draws a 20-design-px corner: 75 source px into 40 real
## px, downsampled, crisp — and the hand-drawn ornament survives, which is
## what drawing the border in code would have cost.

var texture: Texture2D = null
## How much of the plate is corner, in TEXTURE px.
var source_inset := 75.0
## How much of the drawn box is corner, in DESIGN px.
var draw_inset := 20.0
## Drawn first, under the plate (owner 2026-09-14): the bright card, when the
## plate is the ornament alone — its rules and corner flourishes on a clear
## ground — rather than the whole vellum sheet. null draws the plate only.
var base: StyleBox = null
## The plate's ink (owner 2026-09-15): the ornament is dark lines on clear,
## which disappear on the dark theme's card, so it is drawn multiplied by this.
## White draws the art as it is.
var tint := Color.WHITE


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if base != null:
		base.draw(to_canvas_item, rect)
	if texture == null:
		return
	var tw := float(texture.get_width())
	var th := float(texture.get_height())
	var s := minf(source_inset, minf(tw, th) / 2.0)
	# Never let the two corners of a short side overlap: a narrow panel keeps
	# its frame, it just gets less of the middle.
	var d := minf(draw_inset, minf(rect.size.x, rect.size.y) / 2.0)
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


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect
