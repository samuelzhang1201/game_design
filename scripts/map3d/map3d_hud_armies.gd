class_name Map3DHudArmies
extends Map3DHudPiece
## MILITARY's counters on the 3D map's HUD (owner 2026-09-19, the 2D map's —
## ArmyCounters), over the badges and the names.

var _drawn := 0
## markers()' cut and the pose it was cut for (see there).
var _cache: Array = []
var _key: Array = []


## A counter's height in design px: map_army_badge_native_px of the map at
## the scale the target is seen at (as the 2D counter grows with the zoom),
## held between map3d_army_badge_min_px and map3d_army_badge_max_px so it
## reads far out and never swamps the ground close in (owner: 注意兵棋大小).
func badge_height() -> float:
	if ctx == null:
		return 0.0
	var seen := float(ctx.meta.get("m_per_px", 50.0)) / maxf(ctx.metres_per_pixel(), 0.0001)
	return clampf(ctx.repo.bal("map_army_badge_native_px") * seen,
		ctx.repo.bal("map3d_army_badge_min_px"), ctx.repo.bal("map3d_army_badge_max_px"))


## The counters of the player's regiments before the camera, in design px,
## kept clear of the settlement dots. [] while the layer is off.
func markers() -> Array:
	if not bound() or not view.military():
		return []
	# Asked up to three times a frame — the HUD's draw, Map3DPicker.pick_at and
	# Map3DHudLandmarks' clearance — so it is cut once per camera pose, exactly
	# as Map3DHudLandmarks.marks() is (final review 2026-09-20). Same key shape:
	# the pose, the view's size, the render scale, the layer's own switch and
	# the date (regiments march and are settled by the month).
	var st := ctx.state()
	var key := [ctx.camera.global_transform, ctx.view_size, ctx.viewport_px_scale(),
		view.military(), st.tick if st != null else 0, st.day if st != null else 0]
	if key == _key:
		return _cache
	_cache = _cut()
	_key = key
	return _cache


func _cut() -> Array:
	var repo := ctx.repo
	var camera := ctx.camera
	var s := ctx.viewport_px_scale()
	var h := badge_height()
	var frame := Rect2(Vector2.ZERO, ctx.view_size).grow(h * 4.0)
	var points: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		var xz := Map3DGeometry.pack_to_world(ctx.meta, Vector2(float(r["x"]), float(r["y"])))
		var ground := Vector3(xz.x, ctx.height_at(xz), xz.y)
		if camera.is_position_behind(ground):
			continue
		var sp := camera.unproject_position(ground) / s
		if frame.has_point(sp):
			points.append({"reg": r, "pos": sp})
	return ArmyCounters.layout(repo, points, h, ctx.settlement_rects())


func drawn_count() -> int:
	return _drawn


func _draw() -> void:
	if not bound():
		return
	var list := markers()
	_drawn = list.size()
	ArmyCounters.draw(self, ctx.repo, list, view.selected_army())
