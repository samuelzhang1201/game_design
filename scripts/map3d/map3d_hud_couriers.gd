class_name Map3DHudCouriers
extends Map3DHudPiece
## The couriers on the HUD (spec 2026-09-27-courier-core §2): each courier's
## road still ahead as a thin dashed line in the realm's colour, finer than a
## march line; a march order still on the road as a faint dotted line from
## the column to where it will go, an envelope in its end ring; and, past the
## counter scale, each courier as a small square counter with a letter.


func _draw() -> void:
	if not bound() or ctx.state() == null:
		return
	var repo := ctx.repo
	var ink := MapPalette.color_of(repo, repo.resolve_realm("player_realm"))
	var w := repo.bal("map3d_courier_route_px")
	var rects: Dictionary = view.courier_rects()
	for c: Dictionary in ctx.couriers():
		_draw_road(c, (rects.get(int(c["id"]), {}) as Dictionary).get("lead", []), ink, w)
		_draw_pending(c, ink, w)
	for id in rects:
		if bool(rects[id]["counter"]):
			_draw_counter(rects[id]["rect"], ink)


## From where he is DRAWN (`lead`: the drawn rider and the road he is still
## riding to where the engine has him), then the road the engine has left.
func _draw_road(c: Dictionary, lead: Array, ink: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for xz: Vector2 in lead:
		var p3 := Vector3(xz.x, ctx.height_at(xz), xz.y)
		if ctx.camera.is_position_behind(p3):
			return
		pts.append(ctx.camera.unproject_position(p3) / ctx.viewport_px_scale())
	if lead.is_empty():
		var here: Variant = _screen_of_m(Vector2i(int(c["x_m"]), int(c["y_m"])))
		if here == null:
			return
		pts.append(here)
	for p: Array in c["path"]:
		var s: Variant = _screen_of_m(Vector2i(int(p[0]), int(p[1])))
		if s == null:
			break
		pts.append(s)
	for i in range(pts.size() - 1):
		draw_dashed_line(pts[i], pts[i + 1], ink, w, w * 3.0)


func _draw_pending(c: Dictionary, ink: Color, w: float) -> void:
	var order: Dictionary = c["order"]
	if String(order.get("action_code", "")) != "ARMY_MARCH":
		return
	var reg := ArmySystem.regiment(ctx.repo, String(c["target"]))
	if reg.is_empty():
		return
	var from: Variant = _screen_of(ArmySystem.position_of(ctx.repo, ctx.state(), reg))
	var to: Variant = _screen_of_m(Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"])))
	if from == null or to == null:
		return
	var faint := Color(ink, ink.a * ctx.repo.bal("map3d_courier_pending_alpha"))
	draw_dashed_line(from, to, faint, w, w)  # dotted: a dash as long as the line is wide
	var r := ctx.repo.bal("map3d_unit_route_px") * 4.0
	draw_arc(to, r, 0.0, TAU, 24, faint, w, true)
	ResourceIcon.draw_glyph(self, "letter", to, r * 1.4, faint)


func _draw_counter(rect: Rect2, ink: Color) -> void:
	draw_rect(rect, MapPalette.named(ctx.repo, "army_icon_bg"))
	draw_rect(rect, MapPalette.named(ctx.repo, "army_outline"), false, 1.0)
	draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, rect.size.x, 2.0), ink)
	ResourceIcon.draw_glyph(self, "letter", rect.get_center(), rect.size.x * 0.8,
		MapPalette.named(ctx.repo, "army_glyph"))


func _screen_of(pack: Vector2) -> Variant:
	var p := ctx.ground_of_pack(pack)
	if ctx.camera.is_position_behind(p):
		return null
	return ctx.camera.unproject_position(p) / ctx.viewport_px_scale()


func _screen_of_m(m: Vector2i) -> Variant:
	return _screen_of(ArmySystem.metres_to_pack(ctx.repo, m))
