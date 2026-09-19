class_name Map3DHudBadges
extends Map3DHudPiece
## MANORS' output badges on the 3D map's HUD (owner 2026-09-19, the 2D map's
## — ManorBadges), over the kingdom names.

var _drawn := 0


## The working manors (MapEconomy.manors) before the camera whose settlement
## passes the 2D map's town LOD rule at the scale it is SEEN at (screen px
## per pack px at its own distance), in design px, biggest producer first;
## a badge that would overlap a bigger one is left off. [] off the theme.
func badges() -> Array:
	if not bound() or view.manor_theme() != "manors":
		return []
	var repo := ctx.repo
	var camera := ctx.camera
	var s := ctx.viewport_px_scale()
	var m_per_pack := float(ctx.meta.get("m_per_px", 50.0))
	var fov := repo.bal("map3d_fov_deg")
	var h := maxf(ctx.view_size.y, 1.0)
	var eye := camera.global_position
	var frame := Rect2(Vector2.ZERO, ctx.view_size).grow(repo.bal("map_manor_badge_px") * 2.0)
	var all := MapEconomy.manors(repo)
	var out: Array = []
	for id: int in all:
		var m: Dictionary = all[id]
		var ground := ctx.cell_ground(id)
		if camera.is_position_behind(ground):
			continue
		var center := camera.unproject_position(ground) / s
		if not frame.has_point(center):
			continue
		var seen := m_per_pack / Map3DGeometry.metres_per_pixel(eye.distance_to(ground), fov, h)
		var min_pop := MapObjects.min_burg_pop_for_scale(repo, seen)
		var burg := ""
		for code: String in m["burgs"]:
			if MapObjects.burg_visible(repo.burgs[code], min_pop):
				burg = code
				break
		if burg == "":
			continue
		out.append({"cell": id, "burg": burg, "good": String(m["good"]),
			"units": float(m["units"]), "center": center})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["units"] == b["units"]:
			return int(a["cell"]) < int(b["cell"])
		return a["units"] > b["units"])
	var target_scale := m_per_pack / ctx.metres_per_pixel()
	return ManorBadges.place(repo, out, target_scale >= repo.bal("map_manor_label_min_scale"))


func drawn_count() -> int:
	return _drawn


func _draw() -> void:
	if not bound():
		return
	var list := badges()
	_drawn = list.size()
	ManorBadges.draw(self, ctx.repo, list)
