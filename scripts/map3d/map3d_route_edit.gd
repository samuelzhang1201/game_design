class_name Map3DRouteEdit
extends RefCounted
## Bending a planned march on the 3D map (owner 2026-10-07: 玩家可以抓住路线，按住
## 左键拖动使路径弯曲——起点终点不变; spec 2026-10-07-march-waypoints ruling 9).
## While the march's confirm stands (`aim_dest` held) a left press within
## map3d_route_grab_px of a waypoint takes it, of the line inserts a waypoint
## there on the leg it lies on; dragging moves it over the ground and the
## release hands the waypoints to ArmyOrderMenu (`route_bent`), which keeps or
## refuses them. The line is the curve the column will walk
## (ArmySystem.curve_px), from where its piece is drawn.

var view: Map3DView
var rig: Map3DCameraRig
var ctx: Map3DContext:
	get: return rig.ctx if rig != null else null
var _index := -1


func bind(p_view: Map3DView, p_rig: Map3DCameraRig) -> void:
	view = p_view
	rig = p_rig


## The planned route's control points, pack px: the piece as drawn, the
## waypoints, the end — `to` (the pointer while aiming) when given.
static func control_points(v: Map3DView, c: Map3DContext, to := Vector2(-1, -1)) -> Array:
	var code: String = v.aim_code
	var st := c.state()
	var from := ArmySystem.position_of(c.repo, st, ArmySystem.regiment(c.repo, code))
	var shown: Dictionary = v.unit_positions()
	if shown.has(code):
		from = c.to_pack(shown[code])
	var out: Array = [from]
	out.append_array(Array(v.aim_waypoints))
	out.append(to if to.x >= 0.0 else v.aim_dest)
	return out


## True while a waypoint is in hand.
func bending() -> bool:
	return _index >= 0


## A left press at `pos` (design px): true when it took a waypoint.
func press(pos: Vector2) -> bool:
	if view == null or ctx == null or view.aim_code == "" or view.aim_dest.x < 0.0 or ctx.camera == null:
		return false
	var grab := ctx.repo.bal("map3d_route_grab_px")
	var wps := view.aim_waypoints
	for i in wps.size():
		var at: Variant = screen_of(wps[i])
		if at != null and (at as Vector2).distance_to(pos) <= grab:
			_index = i
			return true
	var leg := _leg_near(pos, grab)
	var hit: Variant = view.ground_at(pos)
	if leg < 0 or hit == null:
		return false
	var p := ctx.to_pack(Vector2((hit as Vector3).x, (hit as Vector3).z))
	wps.insert(leg, p)
	view.aim_waypoints = wps
	_index = leg
	return true


## The pointer moved with the waypoint in hand: it follows over the ground.
func drag(pos: Vector2) -> void:
	if _index < 0:
		return
	var hit: Variant = view.ground_at(pos)
	if hit == null:
		return
	var wps := view.aim_waypoints
	if _index < wps.size():
		wps[_index] = ctx.to_pack(Vector2((hit as Vector3).x, (hit as Vector3).z))
		view.aim_waypoints = wps


## Let go: the route goes to the order menu to be checked.
func release() -> void:
	if _index < 0:
		return
	_index = -1
	view.route_bent.emit(view.aim_waypoints)


## The leg of the drawn curve within `grab` px of `pos`, nearest first; -1 for none.
func _leg_near(pos: Vector2, grab: float) -> int:
	var repo := ctx.repo
	var pts_m: Array = []
	for p: Vector2 in control_points(view, ctx):
		pts_m.append(ArmySystem.pack_to_metres(repo, p))
	var legs := MarchRoute.legs(pts_m, int(repo.bal("army_route_sample_m")))
	var best := -1
	var best_d := grab
	for i in legs.size():
		var prev: Variant = screen_of(ArmySystem.metres_to_pack(repo, pts_m[i]))
		for q: Vector2i in legs[i]:
			var at: Variant = screen_of(ArmySystem.metres_to_pack(repo, q))
			if prev != null and at != null:
				var d := Geometry2D.get_closest_point_to_segment(pos, prev, at).distance_to(pos)
				if d <= best_d:
					best_d = d
					best = i
			prev = at
	return best


## A pack point on the ground, projected into design px; null behind the camera.
func screen_of(pack: Vector2) -> Variant:
	var p := ctx.ground_of_pack(pack)
	if ctx.camera.is_position_behind(p):
		return null
	return ctx.camera.unproject_position(p) / ctx.viewport_px_scale()
