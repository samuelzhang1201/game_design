class_name Map3DCourierRide
extends RefCounted
## The pure maths of a courier's drawn ride, read by Map3DLayerCouriers: how
## far along his road the day's share puts him, and his FADE the moment he
## delivers (owner 2026-09-30: 信使送到信息后要立即淡化消失) — the engine keeps
## him to the day's end, the map does not. Pure but for `apply`, which only
## sets his meshes' transparency. Never the Game autoload.


## True once the drawn rider has done the whole of a ride that delivers:
## `ride` is the layer's day (CourierSystem.ride_ahead's `ends` and `share`),
## `done` the share of the day he has ridden.
static func delivered(ride: Dictionary, done: float) -> bool:
	return bool(ride.get("ends", false)) and done >= float(ride.get("share", 1.0))


## 1 before he delivered (`elapsed` < 0), falling to 0 over `fade_s` real seconds.
static func alpha(elapsed: float, fade_s: float) -> float:
	if elapsed < 0.0:
		return 1.0
	return clampf(1.0 - elapsed / fade_s, 0.0, 1.0) if fade_s > 0.0 else 0.0


## His meshes see-through by 1 - `a`, set only when it changed.
static func apply(piece: Dictionary, a: float) -> void:
	if is_equal_approx(float(piece.get("alpha", 1.0)), a):
		return
	piece["alpha"] = a
	for m: MeshInstance3D in Map3DUnits.meshes(piece["node"]):
		m.transparency = 1.0 - a


## `dist` along the points of `queue` from `now`, dropping each point reached.
static func walk_along(now: Vector2, queue: Array, dist: float) -> Vector2:
	var at := now
	var left := dist
	while not queue.is_empty():
		var to: Vector2 = queue[0]
		var d := at.distance_to(to)
		if d > left:
			return at + (to - at) / d * left
		left -= d
		at = to
		queue.pop_front()
	return at


static func length_along(now: Vector2, points: Array) -> float:
	var total := 0.0
	var at := now
	for p: Vector2 in points:
		total += at.distance_to(p)
		at = p
	return total
