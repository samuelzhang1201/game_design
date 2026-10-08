class_name Map3DHudRuler
extends Map3DHudPiece
## The MARCH aim's ruler on the 3D map's HUD (owner 2026-09-24), over the
## scale bar: draped on the ground, the reading the HORIZONTAL ground distance
## in the pack's own measure (map_units_per_metre); ticks on the 1-2-5 step at
## the target's scale. The MEASUREMENT tab's free ruler it also drew went
## 2026-10-02 (owner: 移除measurement tab和相关功能).


var _eta_key := ""
var _eta := 0


## The aim follows the pointer, so it redraws every frame while one is up.
func _process(_delta: float) -> void:
	if bound() and view.aim_code != "":
		queue_redraw()


## Days for a courier sent now to reach the column (spec 2026-09-27-courier-core
## §2): one Dijkstra per aim, not per frame — the route depends only on where
## the column stands, and the weather only on the day.
func _courier_eta(code: String) -> int:
	var st := ctx.state()
	var reg := ArmySystem.regiment(ctx.repo, code, ctx.state())
	if st == null or reg.is_empty() or not CourierSystem.carries_orders(reg):
		return 0
	var key := "%s|%s|%d" % [code, ArmySystem.position_of(ctx.repo, st, reg), st.absolute_day()]
	if key != _eta_key:
		_eta_key = key
		_eta = CourierSystem.eta_days(ctx.repo, st, CourierSystem.ORDINARY, code)
	return _eta


func _draw() -> void:
	if not bound():
		return
	_draw_aim()


## A MARCH being aimed (owner 2026-09-24): the measuring ruler from the
## regiment's piece to the ground under the pointer, in the player's own
## realm colour and ending in an arrowhead, reading the distance and the days
## it will take, walked over the ground and the weather on the way
## (ArmySystem.march_days_between) — the card's "days out" figure. Through its
## waypoints it runs along the CURVE the column will walk (ArmySystem.curve_px,
## spec 2026-10-07-march-waypoints), each waypoint a small ring to grab
## (Map3DRouteEdit), and measures along it.
func _draw_aim() -> void:
	var code: String = view.aim_code
	if code == "":
		return
	# To the pointer while aiming; to the clicked destination while its
	# confirm is asked (owner 2026-09-27).
	var hit: Variant = view.ground_at(get_local_mouse_position())
	if view.aim_dest.x >= 0.0:
		hit = ctx.ground_of_pack(view.aim_dest)
	if hit == null:
		return
	var repo := ctx.repo
	var reg := ArmySystem.regiment(repo, code, ctx.state())
	var b3 := hit as Vector3
	var to_px := ctx.to_pack(Vector2(b3.x, b3.z))
	var pts := Map3DRouteEdit.control_points(view, ctx, to_px)
	var from: Vector2 = pts[0]
	var wps := view.aim_waypoints
	# from where the piece is DRAWN, along the ground it will walk (owner 2026-09-30: 贴地)
	var world: Array = []
	for p: Vector2 in ArmySystem.curve_px(repo, from, Array(wps), to_px):
		world.append(ctx.to_world(p))
	var path := PackedVector2Array()
	for i in range(1, world.size()):
		var leg := draped(world[i - 1], world[i])
		path.append_array(leg if path.is_empty() else leg.slice(1))
	if path.size() < 2:
		return
	var k := view.map_units_per_metre()
	var total := 0.0
	for i in range(1, world.size()):
		total += (world[i - 1] as Vector2).distance_to(world[i])
	total *= k
	var step := MapRuler.tick_step(ctx.metres_per_pixel() * k, repo.bal("map_ruler_tick_min_px"))
	var ticks := PackedVector2Array()
	if total > 0.0:
		for d in MapRuler.ticks(total, step):
			var t: Variant = on_ground(_along(world, d / k))
			if t != null:
				ticks.append(t)
	# ONE arrival day: the courier's ride, then the march over the ground and
	# the weather it will meet (owner 2026-10-02; spec 2026-10-06 §6)
	var days := 0
	var st := ctx.state()
	if st != null and ArmySystem.day_march_m(repo, st, code) > 0:
		var ride := _courier_eta(code)
		days = ride + ArmySystem.march_days_between(repo, st, code,
			ArmySystem.position_of(repo, st, reg), to_px, st.absolute_day() + ride, Array(wps))
	var text := MapRuler.reading(total, view.map_unit())
	if days > 0:
		text += " · %d day%s" % [days, "" if days == 1 else "s"]
	var ink := MapPalette.color_of(repo, String(reg.get("kingdom_code", "")))
	MapRuler.draw(self, path[0], path[path.size() - 1], ticks, text, 1.0, ink, true, path)
	var r := repo.bal("map3d_route_handle_px")
	for w: Vector2 in wps:
		var at: Variant = on_ground(ctx.to_world(w))
		if at != null:
			draw_circle(at, r, Color(ink, 0.35))
			draw_arc(at, r, 0.0, TAU, 20, ink, 2.0, true)


## The world XZ point `d` world metres along the polyline `world`.
static func _along(world: Array, d: float) -> Vector2:
	var left := d
	for i in range(1, world.size()):
		var a: Vector2 = world[i - 1]
		var b: Vector2 = world[i]
		var seg := a.distance_to(b)
		if left <= seg and seg > 0.0:
			return a.lerp(b, left / seg)
		left -= seg
	return world[world.size() - 1]
