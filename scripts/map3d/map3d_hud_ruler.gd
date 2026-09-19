class_name Map3DHudRuler
extends Map3DHudPiece
## The MEASUREMENT ruler on the 3D map's HUD (owner 2026-09-18), over the
## scale bar: its ends on the ground, projected; the reading is the
## HORIZONTAL ground distance in the pack's own measure (map_units_per_metre),
## so it matches the 2D map's ruler; ticks on the 1-2-5 step at the target's
## scale, placed along the 3D line so perspective spaces them as the ground does.


func _draw() -> void:
	if not bound():
		return
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
