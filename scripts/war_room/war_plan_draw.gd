class_name WarPlanDraw
extends RefCounted
## Draws WarPlanInk's parts onto a CanvasItem from inside its _draw (spec
## 2026-10-07-war-room-annotations-and-planning-pieces §2.5, owner's style A):
## crayon polygons filled with the WAX TOOTH — a seamless noise whose alpha
## lets the paper show where the wax skipped — in the stroke's colour, the edge
## pressed a shade darker; pen lines plain; names in the room's lettering. The
## painter (into plan_tex) and the HUD (live, in screen px) both use it.

## `look`: {colours: {blue, red, ink: Color}, tooth: Texture2D or null,
## tooth_uv: uv per px, edge_dark: the edge's shade, edge_px: its width,
## font: Font, caps: Font or null}.
static func paint(canvas: CanvasItem, ink: Dictionary, look: Dictionary) -> void:
	var colours: Dictionary = look["colours"]
	var tooth: Texture2D = look.get("tooth")
	var k := float(look.get("tooth_uv", 0.01))
	var edge_w := float(look.get("edge_px", 1.0))
	for c: Dictionary in ink.get("crayon", []):
		var poly: PackedVector2Array = c["poly"]
		if poly.size() < 3:
			continue
		var col: Color = colours.get(String(c["colour"]), Color.BLACK)
		if tooth != null:
			var uvs := PackedVector2Array()
			for p in poly:
				uvs.append(p * k)
			canvas.draw_colored_polygon(poly, col, uvs, tooth)
		else:
			canvas.draw_colored_polygon(poly, Color(col, col.a * 0.85))
		var edge := poly.duplicate()
		edge.append(poly[0])
		var dark := col.darkened(1.0 - float(look.get("edge_dark", 0.78)))
		dark.a = col.a * 0.9
		canvas.draw_polyline(edge, dark, edge_w, true)
	for p: Dictionary in ink.get("pen", []):
		canvas.draw_polyline(p["line"], colours.get(String(p["colour"]), Color.BLACK), maxf(float(p["width"]), 1.0), true)
	var font: Font = look.get("font")
	if font == null:
		return
	for n: Dictionary in ink.get("names", []):
		var f: Font = look.get("caps") if bool(n["caps"]) and look.get("caps") != null else font
		var size := maxi(int(round(float(n["size"]))), 6)
		var text := String(n["text"])
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at: Vector2 = n["at"]
		var pos := Vector2(at.x - w * 0.5, at.y + size * 0.35)
		canvas.draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(int(size * 0.18), 1),
			look.get("halo", Color(0.886, 0.788, 0.584, 0.85)))
		canvas.draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colours.get(String(n["colour"]), Color.BLACK))
