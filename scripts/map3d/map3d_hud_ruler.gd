class_name Map3DHudRuler
extends Map3DHudPiece
## The MEASUREMENT ruler on the 3D map's HUD (owner 2026-09-18), over the
## scale bar: its ends on the ground, projected; the reading is the
## HORIZONTAL ground distance in the pack's own measure (map_units_per_metre),
## so it matches the 2D map's ruler; ticks on the 1-2-5 step at the target's
## scale, placed along the 3D line so perspective spaces them as the ground does.


## The aim follows the pointer, so it redraws every frame while one is up.
func _process(_delta: float) -> void:
	if bound() and view.aim_code != "":
		queue_redraw()


func _draw() -> void:
	if not bound():
		return
	_draw_aim()
	var ruler := view.ruler()
	if not view.ruler_on or not ruler.active():
		return
	var camera := ctx.camera
	var a3 := Vector3(ruler.start.x, ctx.height_at(ruler.start), ruler.start.y)
	var b3 := Vector3(ruler.end.x, ctx.height_at(ruler.end), ruler.end.y)
	if camera.is_position_behind(a3) or camera.is_position_behind(b3):
		return
	var s := ctx.viewport_px_scale()
	var k := view.map_units_per_metre()
	var total := ruler.length() * k
	var step := MapRuler.tick_step(ctx.metres_per_pixel() * k, ctx.repo.bal("map_ruler_tick_min_px"))
	var ticks := PackedVector2Array()
	for d in MapRuler.ticks(total, step):
		ticks.append(camera.unproject_position(a3.lerp(b3, d / total)) / s)
	MapRuler.draw(self, camera.unproject_position(a3) / s, camera.unproject_position(b3) / s,
		ticks, view.ruler_reading())


## A MARCH being aimed (owner 2026-09-24): the measuring ruler from the
## regiment's piece to the ground under the pointer, in the player's own
## realm colour and ending in an arrowhead, reading the distance and the days
## it will take at the regiment's own pace (ArmySystem.day_step_m) — the same
## numbers the march will then keep.
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
	var fxz := ctx.to_world(from)
	var a3 := Vector3(fxz.x, ctx.height_at(fxz), fxz.y)
	var b3 := hit as Vector3
	var camera := ctx.camera
	if camera.is_position_behind(a3) or camera.is_position_behind(b3):
		return
	var s := ctx.viewport_px_scale()
	var k := view.map_units_per_metre()
	var total := Vector2(a3.x, a3.z).distance_to(Vector2(b3.x, b3.z)) * k
	var step := MapRuler.tick_step(ctx.metres_per_pixel() * k, repo.bal("map_ruler_tick_min_px"))
	var ticks := PackedVector2Array()
	if total > 0.0:
		for d in MapRuler.ticks(total, step):
			ticks.append(camera.unproject_position(a3.lerp(b3, d / total)) / s)
	var metres := from.distance_to(ctx.to_pack(Vector2(b3.x, b3.z))) \
		* float(ArmySystem.metres_per_pack_px(repo))
	var per_day := ArmySystem.day_step_m(repo, ctx.state(), code)
	var text := MapRuler.reading(total, view.map_unit())
	if per_day > 0:
		var days := int(ceil(metres / float(per_day)))
		text += " · %d day%s" % [days, "" if days == 1 else "s"]
	MapRuler.draw(self, camera.unproject_position(a3) / s, camera.unproject_position(b3) / s,
		ticks, text, 1.0, MapPalette.color_of(repo, String(reg.get("kingdom_code", ""))), true)
