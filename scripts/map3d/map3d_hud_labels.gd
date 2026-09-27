class_name Map3DHudLabels
extends Map3DHudPiece
## The kingdom names on the 3D map's HUD (owner 2026-09-18, the 2D map's
## lettering — MapLettering), under the compass, the scale bar and the ruler.

## The kingdoms lettered on the last draw (a test seam).
var _drawn: PackedStringArray = []


## One entry {code, text, pos (design px), px} per kingdom whose LIVE label
## anchor (MapOwnership.label_anchor) is before the camera and whose word —
## map_label_scale_px pack px tall on the ground, seen from its own distance —
## reaches map_label_min_px; capped at map_label_max_px.
func entries() -> Array:
	var out: Array = []
	if not bound():
		return out
	var repo := ctx.repo
	var camera := ctx.camera
	var s := ctx.viewport_px_scale()
	var height_m := repo.bal("map_label_scale_px") * float(ctx.meta.get("m_per_px", 0.0))
	var eye := camera.global_position
	for code: String in repo.kingdoms:
		var xz := Map3DGeometry.pack_to_world(ctx.meta, MapOwnership.label_anchor(repo, ctx.state(), code))
		var ground := Vector3(xz.x, ctx.height_at(xz), xz.y)
		if camera.is_position_behind(ground):
			continue
		var mpp := Map3DGeometry.metres_per_pixel(eye.distance_to(ground),
			repo.bal("map3d_fov_deg"), maxf(ctx.view_size.y, 1.0))
		var px := Map3DGeometry.label_px(height_m, mpp, repo.bal("map_label_min_px"),
			repo.bal("map_label_max_px"))
		if px <= 0.0:
			continue
		out.append({"code": code, "text": String(repo.kingdoms[code]["label"]),
			"pos": camera.unproject_position(ground) / s, "px": px})
	return out


## The boxes the names are lettered in, in design px (the weather marks keep
## off them).
func rects() -> Array:
	var out: Array = []
	var font := UiPalette.map_label_font()
	if font == null:
		return out
	for e: Dictionary in entries():
		out.append(MapLettering.box_centred(ctx.repo, font, String(e["text"]), e["pos"], float(e["px"])))
	return out


func drawn() -> PackedStringArray:
	return _drawn


## Letter the names, upright and faint, the way the 2D map letters them.
func _draw() -> void:
	if not bound():
		return
	_drawn.clear()
	var font := UiPalette.map_label_font()
	if font == null:
		return
	var frame := Rect2(Vector2.ZERO, ctx.view_size)
	for e: Dictionary in entries():
		if MapLettering.draw_centred(self, ctx.repo, font, String(e["text"]), e["pos"],
				float(e["px"]), frame):
			_drawn.append(String(e["code"]))
