class_name Map3DHudLabels
extends Map3DHudPiece
## The kingdom names on the 3D map's HUD (owner 2026-09-18, the 2D map's
## lettering — MapLettering), under the compass, the scale bar and the ruler.

## The kingdoms lettered on the last draw (a test seam).
var _drawn: PackedStringArray = []
## Each kingdom's label point on the ground, {code: Vector3}, kept while the
## provinces' holders stand (perf 2026-10-02: label_anchor walks every
## province, once per kingdom per camera pose) ...
var _anchors: Dictionary = {}
var _anchors_key: Array = []
## ... and entries() and rects(), cut once per camera pose (the weather marks
## ask for rects() too).
var _entries: Array = []
var _rects: Array = []
var _pose_key: Array = []


## {code: ground point} of every kingdom's LIVE label anchor (MapOwnership.
## label_anchor), cut again when a province changes hands.
func _ground_anchors() -> Dictionary:
	var st := ctx.state()
	var key := [st.get_instance_id() if st != null else 0,
		st.province_owner.hash() if st != null else 0, ctx.repo.get_instance_id()]
	if key == _anchors_key:
		return _anchors
	_anchors = {}
	for code: String in ctx.repo.kingdoms:
		var xz := Map3DGeometry.pack_to_world(ctx.meta, MapOwnership.label_anchor(ctx.repo, st, code))
		_anchors[code] = Vector3(xz.x, ctx.height_at(xz), xz.y)
	_anchors_key = key
	return _anchors


## Whether entries() and rects() are still this pose's; marks them so.
func _same_pose() -> bool:
	var key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(), _anchors_key]
	if key == _pose_key:
		return true
	_pose_key = key
	_entries = []
	_rects = []
	return false


## One entry {code, text, pos (design px), px} per kingdom whose LIVE label
## anchor (MapOwnership.label_anchor) is before the camera and whose word —
## map_label_scale_px pack px tall on the ground, seen from its own distance —
## reaches map_label_min_px; capped at map_label_max_px. A name is lettered
## whole (visual review 2026-10-05: "gate" and half a "Kelvarn" were cut by
## the sheet's edge): a word the view's edge would cut slides inside it —
## never more than half its own size, since only a word that already
## reaches into the view is shown — and stays over its own land.
func entries() -> Array:
	if not bound():
		return []
	var anchors := _ground_anchors()
	if _same_pose() and not _entries.is_empty():
		return _entries
	var out: Array = []
	var repo := ctx.repo
	var camera := ctx.camera
	var s := ctx.viewport_px_scale()
	var height_m := repo.bal("map_label_scale_px") * float(ctx.meta.get("m_per_px", 0.0))
	var eye := camera.global_position
	var font := UiPalette.map_label_font()
	var frame := Rect2(Vector2.ZERO, ctx.view_size)
	for code: String in repo.kingdoms:
		var ground: Vector3 = anchors[code]
		if camera.is_position_behind(ground):
			continue
		var mpp := Map3DGeometry.metres_per_pixel(eye.distance_to(ground),
			repo.bal("map3d_fov_deg"), maxf(ctx.view_size.y, 1.0))
		var px := Map3DGeometry.label_px(height_m, mpp, repo.bal("map_label_min_px"),
			repo.bal("map_label_max_px"))
		if px <= 0.0:
			continue
		var text := String(repo.kingdoms[code]["label"])
		var pos := camera.unproject_position(ground) / s
		if font != null:
			var box := MapLettering.box_centred(repo, font, text, pos, px)
			if not frame.intersects(box):
				continue
			pos += inward(box, frame, px * 0.5)
		out.append({"code": code, "text": text, "pos": pos, "px": px})
	_entries = out
	return out


## How far `box` must move to lie `margin` inside `frame` (ZERO when it
## already does; a box wider than the frame is centred on it).
static func inward(box: Rect2, frame: Rect2, margin: float) -> Vector2:
	var inner := frame.grow(-margin)
	var out := Vector2.ZERO
	for axis: int in 2:
		if box.size[axis] >= inner.size[axis]:
			out[axis] = inner.get_center()[axis] - box.get_center()[axis]
		elif box.position[axis] < inner.position[axis]:
			out[axis] = inner.position[axis] - box.position[axis]
		elif box.end[axis] > inner.end[axis]:
			out[axis] = inner.end[axis] - box.end[axis]
	return out


## The boxes the names are lettered in, in design px (the weather marks keep
## off them).
func rects() -> Array:
	if not bound():
		return []
	var list := entries()
	if not _rects.is_empty() or list.is_empty():
		return _rects
	var font := UiPalette.map_label_font()
	if font == null:
		return []
	for e: Dictionary in list:
		_rects.append(MapLettering.box_centred(ctx.repo, font, String(e["text"]), e["pos"], float(e["px"])))
	return _rects


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
