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
	var reg := ArmySystem.regiment(ctx.repo, code)
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
## it will take at the regiment's own pace under today's weather where it
## stands (ArmySystem.march_days) — the card's "days out" figure.
func _draw_aim() -> void:
	var code: String = view.aim_code
	if code == "":
		return
	# To the pointer while aiming; to the clicked destination while COMMIT /
	# CANCEL is asked (owner 2026-09-27).
	var hit: Variant = view.ground_at(get_local_mouse_position())
	if view.aim_dest.x >= 0.0:
		hit = ctx.ground_of_pack(view.aim_dest)
	if hit == null:
		return
	var repo := ctx.repo
	var reg := ArmySystem.regiment(repo, code)
	var from := ArmySystem.position_of(repo, ctx.state(), reg)
	# from where the piece is DRAWN, along the ground it will walk (owner 2026-09-30: 贴地)
	var fxz: Vector2 = view.unit_positions().get(code, ctx.to_world(from))
	var b3 := hit as Vector3
	var bxz := Vector2(b3.x, b3.z)
	var a_px: Variant = on_ground(fxz)
	var b_px: Variant = on_ground(bxz)
	if a_px == null or b_px == null:
		return
	var path := draped(fxz, bxz)
	var k := view.map_units_per_metre()
	var total := fxz.distance_to(bxz) * k
	var step := MapRuler.tick_step(ctx.metres_per_pixel() * k, repo.bal("map_ruler_tick_min_px"))
	var ticks := PackedVector2Array()
	if total > 0.0:
		for d in MapRuler.ticks(total, step):
			var t: Variant = on_ground(fxz.lerp(bxz, d / total))
			if t != null:
				ticks.append(t)
	var metres := from.distance_to(ctx.to_pack(Vector2(b3.x, b3.z))) \
		* float(ArmySystem.metres_per_pack_px(repo))
	# ONE arrival day: the courier's ride, then the march (owner 2026-10-02)
	var days := 0
	if ArmySystem.day_march_m(repo, ctx.state(), code) > 0:
		days = _courier_eta(code) + ArmySystem.march_days(repo, ctx.state(), code, metres)
	var text := MapRuler.reading(total, view.map_unit())
	if days > 0:
		text += " · %d day%s" % [days, "" if days == 1 else "s"]
	MapRuler.draw(self, a_px, b_px, ticks, text, 1.0,
		MapPalette.color_of(repo, String(reg.get("kingdom_code", ""))), true, path)
