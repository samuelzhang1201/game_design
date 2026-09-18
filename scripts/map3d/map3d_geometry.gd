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


## The tilt at a distance: `near_deg` at min_d, `far_deg` at max_d, on a log
## scale so every wheel notch turns the view by the same amount.
static func pitch_for(distance: float, min_d: float, max_d: float, near_deg: float, far_deg: float) -> float:
	var t := 0.0
	if max_d > min_d:
		t = clampf(log(distance / min_d) / log(max_d / min_d), 0.0, 1.0)
	return lerpf(near_deg, far_deg, t)


## The camera's transform: `distance` back from the target along the view,
## turned by `yaw_deg` about +Y and tilted by `pitch_deg` (negative looks down).
static func pose(target: Vector3, distance: float, yaw_deg: float, pitch_deg: float) -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	return Transform3D(basis, target + basis.z * distance)


## Ground metres under one screen pixel at the target, for a view `fov_deg`
## tall over `view_height_px`.
static func metres_per_pixel(distance: float, fov_deg: float, view_height_px: float) -> float:
	return 2.0 * distance * tan(deg_to_rad(fov_deg) * 0.5) / maxf(view_height_px, 1.0)


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
