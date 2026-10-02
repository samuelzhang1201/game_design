@tool
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

@export var texture: Texture2D = null
## How much of the plate is corner, in TEXTURE px.
@export var source_inset := 75.0
## How much of the drawn box is corner, in DESIGN px.
@export var draw_inset := 20.0
## Drawn first, under the plate (owner 2026-09-14): the bright card, when the
## plate is the ornament alone — its rules and corner flourishes on a clear
## ground — rather than the whole vellum sheet. null draws the plate only.
@export var base: StyleBox = null
## The plate's ink (owner 2026-09-15): the ornament is dark lines on clear,
## which disappear on the dark theme's card, so it is drawn multiplied by this.
## White draws the art as it is.
@export var tint := Color.WHITE
## The card's material (owner 2026-09-28, after the UI critique: the flat
## card read cheap): a seamless grain tiled over the body at `grain_px` design
## px a texel and `grain_alpha`, a light-to-dark shade from top to bottom, and
## an inner hairline `inner_inset` in from the edge. All zero draws nothing.
@export var grain: Texture2D = null
## The grain's dark half (UiPalette.panel_grain), drawn the same way.
@export var grain_dark: Texture2D = null
@export var grain_px := 1.0
@export var grain_alpha := 0.0
@export var shade_top := 0.0
@export var shade_bottom := 0.0
@export var inner_rule := Color(0, 0, 0, 0)
## The light that the grain's bright half and the top shade are laid in: warm
## parchment, so the leather stays brown (white laid over it greyed it).
@export var light := Color(1.0, 0.88, 0.68)
@export var inner_inset := 4.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if base != null:
		base.draw(to_canvas_item, rect)
	var body := rect.grow(-1.0)
	if grain_alpha > 0.0 and body.has_area():
		if grain != null:
			_draw_grain(to_canvas_item, body, grain, Color(light, grain_alpha))
		if grain_dark != null:
			_draw_grain(to_canvas_item, body, grain_dark, Color(1, 1, 1, grain_alpha))
	if (shade_top > 0.0 or shade_bottom > 0.0) and body.has_area():
		var top := Color(light, shade_top)
		var bottom := Color(0, 0, 0, shade_bottom)
		RenderingServer.canvas_item_add_polygon(to_canvas_item,
			PackedVector2Array([body.position, Vector2(body.end.x, body.position.y),
				body.end, Vector2(body.position.x, body.end.y)]),
			PackedColorArray([top, top, bottom, bottom]))
	if inner_rule.a > 0.0:
		var r := rect.grow(-inner_inset)
		if r.has_area():
			var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
				r.end, Vector2(r.position.x, r.end.y), r.position])
			RenderingServer.canvas_item_add_polyline(to_canvas_item, pts,
				PackedColorArray([inner_rule]), 1.0)
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


## The grain tiled by hand (the canvas item's repeat is its owner's, not the
## style's), the last row and column cut to the body.
func _draw_grain(ci: RID, body: Rect2, tex: Texture2D, tint_grain: Color) -> void:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var step := Vector2(tw, th) * grain_px
	var rid := tex.get_rid()
	var y := body.position.y
	while y < body.end.y:
		var h := minf(step.y, body.end.y - y)
		var x := body.position.x
		while x < body.end.x:
			var w := minf(step.x, body.end.x - x)
			RenderingServer.canvas_item_add_texture_rect_region(ci,
				Rect2(x, y, w, h), rid, Rect2(0, 0, w / grain_px, h / grain_px), tint_grain)
			x += step.x
		y += step.y


func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect
