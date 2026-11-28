class_name Map3DVolley
extends RefCounted
## The arrow rain's pure math (spec 2026-11-28-archer-arrow-rain-design.md;
## view-only): when a figure's clip crosses its release share, where its arrow
## lands among the target's figures (hashed, never an RNG draw) and the arc it
## flies. Shares are of the clip, 0..1.


## True when the clip went from `prev` to `now` past `share` (a wrap counts).
static func released(prev: float, now: float, share: float) -> bool:
	if now > prev:
		return share > prev and share <= now
	if now < prev:
		return share > prev or share <= now
	return false


## One of `targets` (stand points), hashed from the figure `key` and its release
## count `n`, plus an offset within `scatter_m` (uniform over the disc).
static func landing(key: String, n: int, targets: Array, scatter_m: float) -> Vector2:
	var k := "%s|%d" % [key, n]
	var pick := mini(int(Map3DMarchLag.unit(k + "|t") * targets.size()), targets.size() - 1)
	var r := sqrt(Map3DMarchLag.unit(k + "|r")) * scatter_m
	return (targets[pick] as Vector2) + Vector2.from_angle(Map3DMarchLag.unit(k + "|a") * TAU) * r


static func flight_s(dist: float, tune: Dictionary) -> float:
	return clampf(dist / float(tune["speed_m"]), float(tune["min_s"]), float(tune["max_s"]))


## The arrow's point at share `s` of its flight: the straight line plus a parabola `apex` high at its middle.
static func at(from: Vector3, to: Vector3, s: float, apex: float) -> Vector3:
	return from.lerp(to, s) + Vector3.UP * 4.0 * apex * s * (1.0 - s)


## The way it points at share `s` (the arc's tangent).
static func heading(from: Vector3, to: Vector3, s: float, apex: float) -> Vector3:
	return ((to - from) + Vector3.UP * 4.0 * apex * (1.0 - 2.0 * s)).normalized()
