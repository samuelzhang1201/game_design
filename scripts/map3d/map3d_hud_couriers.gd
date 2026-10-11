class_name Map3DHudCouriers
extends Map3DHudPiece
## The couriers on the HUD (spec 2026-09-27-courier-core §2): each courier's
## road still ahead as a thin dashed line in the realm's colour, finer than a
## march line; a march order still on the road as a faint dotted line from
## the column to where it will go, an envelope in its end ring; and, past the
## counter scale, each courier as a small square counter with a letter. A
## courier delivers as the day ends (owner 2026-10-02) and leaves the state
## then, his road and pending order with him; only his rider fades
## (Map3DLayerCouriers). Its look is edited on the node (owner 2026-10-02).

## His road ahead, design px wide — finer than a march's.
@export var route_px := 1.2
## An order still on the road: its route dotted at this share of the realm
## colour's opacity, an envelope in its end ring.
@export var pending_alpha := 0.55


func _draw() -> void:
	if not bound() or ctx.state() == null:
		return
	var repo := ctx.repo
	var ink := MapPalette.color_of(repo, repo.resolve_realm("player_realm"))
	var w := route_px
	var rects: Dictionary = view.courier_rects()
	for c: Dictionary in ctx.couriers():
		var r: Dictionary = rects.get(int(c["id"]), {})
		_draw_road(c, r.get("lead", []), ink, w)
		_draw_pending(c, ink, w)
	for id in rects:
		if bool(rects[id]["counter"]):
			_draw_counter(rects[id]["rect"], ink)


## From where he is DRAWN along the whole road still ahead of him (`lead`,
## Map3DLayerCouriers); without one, from where the engine has him.
func _draw_road(c: Dictionary, lead: Array, ink: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for xz: Vector2 in lead:
		var p3 := Vector3(xz.x, ctx.height_at(xz), xz.y)
		if ctx.camera.is_position_behind(p3):
			break
		pts.append(ctx.camera.unproject_position(p3) / ctx.viewport_px_scale())
	if lead.is_empty():
		var here: Variant = _screen_of_m(Vector2i(int(c["x_m"]), int(c["y_m"])))
		if here == null:
			return
		pts.append(here)
	for p: Array in ([] if not lead.is_empty() else c["path"]):
		var s: Variant = _screen_of_m(Vector2i(int(p[0]), int(p[1])))
		if s == null:
			break
		pts.append(s)
	for i in range(pts.size() - 1):
		draw_dashed_line(pts[i], pts[i + 1], ink, w, w * 3.0)


func _draw_pending(c: Dictionary, ink: Color, w: float) -> void:
	var ends := _pending_ends(c)
	if ends.is_empty():
		return
	var to: Vector2 = ends["to"]
	var faint := Color(ink, ink.a * pending_alpha)
	MapRuler.dashed_path(self, ends["pts"], faint, w, w)  # dotted: a dash as long as the line is wide
	var r := ring_px()
	draw_arc(to, r, 0.0, TAU, 24, faint, w, true)
	ResourceIcon.draw_glyph(self, "letter", to, r * 1.4, faint)


## A march order still on the road: {from, to, pts} in design px — the column,
## where it will go and the line between — or {} for any other order or one off the camera.
func _pending_ends(c: Dictionary) -> Dictionary:
	var order: Dictionary = c["order"]
	if String(order.get("action_code", "")) != "ARMY_MARCH":
		return {}
	var reg := ArmySystem.regiment(ctx.repo, String(c["target"]), ctx.state())
	if reg.is_empty():
		return {}
	var from: Variant = _screen_of(ArmySystem.position_of(ctx.repo, ctx.state(), reg))
	var to: Variant = _screen_of_m(Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"])))
	if from == null or to == null:
		return {}
	# through its waypoints and round any scarp, along the road it will walk
	# (specs 2026-10-07-march-waypoints, 2026-10-10-march-slope-detour)
	var pts := PackedVector2Array()
	for p: Vector2 in ArmySystem.curve_px(ctx.repo, ArmySystem.position_of(ctx.repo, ctx.state(), reg),
			CourierSystem.waypoints_px(ctx.repo, order),
			ArmySystem.metres_to_pack(ctx.repo, Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"])))):
		var at: Variant = _screen_of(p)
		if at != null:
			pts.append(at)
	return {"from": from, "to": to, "pts": pts}


## An end ring's radius, design px: a march's (the Armies piece's route_px × 4).
func ring_px() -> float:
	var armies := sibling("Armies") as Map3DHudArmies
	return (armies.route_px if armies != null else 2.0) * 4.0


## Each pending order's envelope ring, as a box in design px.
func pending_rects() -> Array:
	var out: Array = []
	if not bound() or ctx.state() == null:
		return out
	var r := ring_px() + route_px
	for c: Dictionary in ctx.couriers():
		var ends := _pending_ends(c)
		if not ends.is_empty():
			out.append(Rect2((ends["to"] as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0))
	return out


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
