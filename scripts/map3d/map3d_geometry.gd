class_name Map3DGeometry
extends RefCounted
## The 3D map's pure maths (no nodes, tested headless): pack px <-> world
## metres, and the camera rig — a target on the ground, a distance, a yaw
## and a pitch that tilts from oblique up close to near top-down far out,
## the way a campaign map reads. World axes: pack x is +X, pack y (south) is
## +Z, up is +Y; yaw 0 looks north.
##
## `world` is the scene's metadata written by tools/map3d/build_terrain.gd:
## {m_per_px, pack_origin: [x, z], pack_px: [w, h]}.


## World XZ (metres) of a pack pixel.
static func pack_to_world(world: Dictionary, px: Vector2) -> Vector2:
	var o: Array = world["pack_origin"]
	return Vector2(float(o[0]), float(o[1])) + px * float(world["m_per_px"])


## Pack pixel of a world XZ.
static func world_to_pack(world: Dictionary, xz: Vector2) -> Vector2:
	var o: Array = world["pack_origin"]
	return (xz - Vector2(float(o[0]), float(o[1]))) / float(world["m_per_px"])


## Every world XZ of a dictionary as its pack pixel, keyed the same. The WAR
## ROOM's pieces stand where the 3D map DRAWS each regiment (owner 2026-10-02:
## 位置一定要和大地图一致): Map3DView.unit_pack_positions steps the units layer
## at no time passed first, so a view put away under the room answers where it
## WILL draw each piece the moment it is shown again at this share of the day.
static func world_to_pack_all(world: Dictionary, xz_by_key: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in xz_by_key:
		out[k] = world_to_pack(world, xz_by_key[k])
	return out


## The pack's whole canvas in world XZ.
static func world_bounds(world: Dictionary) -> Rect2:
	var p: Array = world["pack_px"]
	return Rect2(pack_to_world(world, Vector2.ZERO),
		Vector2(float(p[0]), float(p[1])) * float(world["m_per_px"]))


## The rig's target kept on the map.
static func clamp_target(xz: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(clampf(xz.x, bounds.position.x, bounds.end.x),
		clampf(xz.y, bounds.position.y, bounds.end.y))


## The distance after `steps` wheel notches (negative is in), each a factor.
static func zoomed(distance: float, steps: int, factor: float, min_d: float, max_d: float) -> float:
	return clampf(distance * pow(factor, steps), min_d, max_d)


## The distance times a gesture's `factor`, clamped (a pinch is not a notch).
static func zoomed_by(distance: float, factor: float, min_d: float, max_d: float) -> float:
	return clampf(distance * factor, min_d, max_d)


## The rig's new target when the distance goes from `old_d` to `new_d` and
## the ground point `anchor` (the one under the pointer) must stay put: the
## view scales about the anchor, so every offset from it scales by new/old.
static func zoom_about(target: Vector2, anchor: Vector2, old_d: float, new_d: float) -> Vector2:
	if old_d <= 0.0:
		return target
	return anchor + (target - anchor) * (new_d / old_d)


## The tilt at a distance: `near_deg` at min_d, `far_deg` at max_d, on a log
## scale so every wheel notch turns the view by the same amount.
static func pitch_for(distance: float, min_d: float, max_d: float, near_deg: float, far_deg: float) -> float:
	var t := 0.0
	if max_d > min_d:
		t = clampf(log(distance / min_d) / log(max_d / min_d), 0.0, 1.0)
	return lerpf(near_deg, far_deg, t)


## The pitch at which the camera, `distance` back from `target` on `yaw_deg`,
## stands clear of the ground: every point of its sight line at share s from
## the target to the camera at least `clear_m` * s over `height_fn(xz)`.
## `pitch_deg` when that already holds, else steepened by `step_deg` until it
## does, no further than `limit_deg`. The oblique near pitch put the camera
## INSIDE a ridge behind the target (2026-09-29): the hill, seen from within,
## was culled away and a trail over it crossed the view as a black streak.
## Steepening keeps the target and the distance, so the scale bar holds.
static func clear_pitch(target: Vector3, distance: float, yaw_deg: float, pitch_deg: float,
		height_fn: Callable, clear_m: float, step_deg: float, samples: int, limit_deg := -89.0) -> float:
	var p := pitch_deg
	while p > limit_deg:
		if _sight_clear(target, distance, yaw_deg, p, height_fn, clear_m, samples):
			return p
		p = maxf(p - step_deg, limit_deg)
	return limit_deg


static func _sight_clear(target: Vector3, distance: float, yaw_deg: float, pitch_deg: float,
		height_fn: Callable, clear_m: float, samples: int) -> bool:
	var cam := pose(target, distance, yaw_deg, pitch_deg).origin
	for i in range(1, samples + 1):
		var s := float(i) / float(samples)
		var q := target.lerp(cam, s)
		if q.y < float(height_fn.call(Vector2(q.x, q.z))) + clear_m * s:
			return false
	return true


## The camera's transform: `distance` back from the target along the view,
## turned by `yaw_deg` about +Y and tilted by `pitch_deg` (negative looks down).
static func pose(target: Vector3, distance: float, yaw_deg: float, pitch_deg: float) -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	return Transform3D(basis, target + basis.z * distance)


## Ground metres under one screen pixel at the target, for a view `fov_deg`
## tall over `view_height_px`.
static func metres_per_pixel(distance: float, fov_deg: float, view_height_px: float) -> float:
	return 2.0 * distance * tan(deg_to_rad(fov_deg) * 0.5) / maxf(view_height_px, 1.0)


## The farthest the camera may sit while its SCALE BAR still reads at or
## under `max_units` of the pack's own measure (owner 2026-09-20: "设置zoom
## out标尺最多150km"). The bar lands on MapGeometry.nice_step's 1-2-5 ladder,
## so a cap of 150 km prints as 100 km: the distance returned is the one just
## under the next rung (200). INF when there is nothing to measure, so a
## caller can min() it with its own ceiling.
static func distance_for_scale(max_units: float, units_per_metre: float, bar_max_px: float,
		fov_deg: float, view_height_px: float) -> float:
	if max_units <= 0.0 or units_per_metre <= 0.0 or bar_max_px <= 0.0:
		return INF
	return distance_for_span(rung_above(max_units) * 0.999, units_per_metre, bar_max_px,
		fov_deg, view_height_px)


## The camera distance at which `bar_max_px` of screen spans `units` of the
## pack's own measure — the scale bar's full run.
static func distance_for_span(units: float, units_per_metre: float, bar_max_px: float,
		fov_deg: float, view_height_px: float) -> float:
	return units / bar_max_px / units_per_metre * maxf(view_height_px, 1.0) \
		/ (2.0 * tan(deg_to_rad(fov_deg) * 0.5))


## How the owner names a zoom: by the SCALE BAR (owner 2026-09-27, "是比例尺，
## 不是高度") — the camera distance at which the bar's full run
## (map_scale_bar_max_px) spans `units` of the pack's measure, so the bar
## reads the 1-2-5 rung at or under it (25 -> "20 km"; 50 -> "50 km").
static func distance_for_bar(repo: DataRepository, meta: Dictionary, units: float,
		view_height_px: float) -> float:
	return distance_for_span(units, map_units_per_metre(repo.map_info, meta),
		repo.bal("map_scale_bar_max_px"), repo.bal("map3d_fov_deg"), view_height_px)


## The smallest 1-2-5 rung strictly above `v` (150 -> 200, 200 -> 500).
static func rung_above(v: float) -> float:
	if v <= 0.0:
		return 0.0
	var base: float = pow(10.0, floor(log(v) / log(10.0)))
	for step: float in [1.0, 2.0, 5.0, 10.0]:
		if base * step > v:
			return base * step
	return base * 10.0


## The farthest the rig may actually sit: `zoom_max_m`, or nearer still if
## the scale bar cap binds (Map3DCameraRig.max_distance's own maths, pulled
## out pure so anything that needs the reachable ceiling — the settlement
## dot's near threshold included — can compute it without a rig). Before a
## view has a size (view_height_px <= 1) there is no bar to read, so only
## the flat ceiling applies.
static func zoom_ceiling_m(zoom_max_m: float, max_units: float, units_per_metre: float,
		bar_max_px: float, fov_deg: float, view_height_px: float) -> float:
	if view_height_px <= 1.0:
		return zoom_max_m
	return minf(zoom_max_m, distance_for_scale(max_units, units_per_metre, bar_max_px,
		fov_deg, view_height_px))


## A value counted DOWN `share` of the way from `ceiling` toward `floor` —
## the settlement dot's near threshold uses this (owner 2026-09-21, replacing
## an absolute metres value that once sat past an unreachable ceiling), but
## the maths itself names neither: share 0 returns `ceiling`, 1 returns
## `floor`. Pure and generic on purpose, so its name cannot be mistaken for
## settlement_dot_min_view_m below, which is the one settlement-specific
## reader (fix round 1 review: the two used to share a name).
static func threshold_from_share(ceiling: float, bottom: float, share: float) -> float:
	return ceiling - share * (ceiling - bottom)


## The settlement dot's near threshold in world metres (owner 2026-09-21
## ruling): the farthest map3d_dot_min_view_share of the RIGHT-NOW reachable
## range (zoom_ceiling_m, which depends on `meta` and the view's own height
## through the scale bar cap) counted down toward map3d_zoom_min_m. The one
## place this is computed — Map3DContext.settlement_rects() and
## Map3DLayerSettlements (build and apply_scale, the latter because a resize
## changes the ceiling) all call this, rather than each other, so neither a
## layer nor the context depends on the other (fix round 1 review: Context
## calling a Layer class inverted the sharing direction every other piece of
## the 3D map follows).
static func settlement_dot_min_view_m(repo: DataRepository, meta: Dictionary,
		view_height_px: float) -> float:
	var ceiling := zoom_ceiling_m(repo.bal("map3d_zoom_max_m"), repo.bal("map3d_zoom_max_scale"),
		map_units_per_metre(repo.map_info, meta), repo.bal("map_scale_bar_max_px"),
		repo.bal("map3d_fov_deg"), view_height_px)
	return threshold_from_share(ceiling, repo.bal("map3d_zoom_min_m"),
		repo.bal("map3d_dot_min_view_share"))


## How far the target moves when the mouse drags the ground by `screen_delta`:
## the ground follows the mouse, so the target moves the other way.
static func pan_delta(screen_delta: Vector2, m_per_px: float, yaw_deg: float) -> Vector2:
	var yaw := deg_to_rad(yaw_deg)
	var right := Vector2(cos(yaw), -sin(yaw))
	var forward := Vector2(-sin(yaw), -cos(yaw))
	return (-right * screen_delta.x + forward * screen_delta.y) * m_per_px


## Where a ray from `origin` along `dir` meets the ground `height_fn(xz)`,
## or null when it looks up. The ground is found by meeting the plane at the
## height under the last guess, again and again: it settles wherever the
## ground is less steep than the ray, which a campaign camera always is.
static func ground_hit(origin: Vector3, dir: Vector3, height_fn: Callable,
		iterations: int = 12) -> Variant:
	if dir.y >= -0.0001:
		return null
	var h: float = height_fn.call(Vector2(origin.x, origin.z))
	var p := origin
	for i in iterations:
		var t := (h - origin.y) / dir.y
		if t < 0.0:
			t = 0.0
		p = origin + dir * t
		h = height_fn.call(Vector2(p.x, p.z))
	return Vector3(p.x, h, p.z)


## The polyline with points added so no segment is longer than `step`; the
## original points are kept, each long segment cut into equal pieces.
static func resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	if pts.size() < 2 or step <= 0.0:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for k in range(1, n):
			out.append(a.lerp(b, float(k) / float(n)))
		out.append(b)
	return out


## The yaw `t` (0..1) of the way home to north from `from_deg`, the short
## way round, smoothstepped so it starts and lands gently.
static func ease_yaw(from_deg: float, t: float) -> float:
	var start := wrapf(from_deg, -180.0, 180.0)
	if t <= 0.0:
		return from_deg
	return start * (1.0 - smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0)))


## The pack's measure per world metre (owner 2026-09-18: the 3D map MEASURES
## LIKE THE 2D MAP): world metres back to pack px (meta m_per_px) times
## map_info.csv distance_scale; 0.001 (km) when either is missing.
static func map_units_per_metre(map_info: Dictionary, meta: Dictionary) -> float:
	var per_px := float(map_info.get("distance_scale", "0"))
	var m_per_px := float(meta.get("m_per_px", 0.0))
	return per_px / m_per_px if per_px > 0.0 and m_per_px > 0.0 else 0.001


## map_info.csv distance_unit, or "km" when the measure falls back.
static func map_unit(map_info: Dictionary, meta: Dictionary) -> String:
	if float(map_info.get("distance_scale", "0")) <= 0.0 or float(meta.get("m_per_px", 0.0)) <= 0.0:
		return "km"
	return String(map_info.get("distance_unit", ""))
