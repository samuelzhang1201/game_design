class_name Map3DMarchPhase
extends RefCounted
## A MARCH clip's distance-to-phase map (cavalry contract,
## docs/reviews/cluster-formations/cavalry-march-contact-prerequisite.md, "Concrete
## distance-map construction"): F(z) = floor(z) * S + f(frac(z)), f piecewise linear
## through the knots (phase, model metres) of army_art.csv `phase_map`, f(0) = 0,
## f(1) = S, strictly increasing. Where a constant stride_m slides a planted hoof
## (cavalry's 5.9: 8.03 world m a stance), the map plays each part of the clip at the
## travel its native hooves actually carry. Pure; no clock, no autoload.


## The knots of an army_art.csv row's `phase_map` ("phase:distance;…") as a flat
## float64 list [phase0, metres0, phase1, metres1, …] (a Vector2 is float32, which
## merges the atlas's nearest knots), or empty when it has none or is malformed (first
## knot not (0, 0), last not at phase 1, a phase or distance not strictly rising).
static func of_art(art: Dictionary) -> PackedFloat64Array:
	var text := String(art.get("phase_map", "")).strip_edges()
	if text == "":
		return PackedFloat64Array()
	var out := PackedFloat64Array()
	for pair in text.split(";"):
		var two := pair.split(":")
		if two.size() != 2 or not two[0].is_valid_float() or not two[1].is_valid_float():
			return PackedFloat64Array()
		out.append(two[0].to_float())
		out.append(two[1].to_float())
	return out if valid(out) else PackedFloat64Array()


## True when `knots` is a map: at least two, from (0, 0) to phase 1, both rising strictly.
static func valid(knots: PackedFloat64Array) -> bool:
	var n := knots.size()
	if n < 4 or n % 2 != 0 or knots[0] != 0.0 or knots[1] != 0.0 or knots[n - 2] != 1.0:
		return false
	for i in range(2, n, 2):
		if knots[i] <= knots[i - 2] or knots[i + 1] <= knots[i - 1]:
			return false
	return true


## Model metres one loop carries the piece (S).
static func loop_m(knots: PackedFloat64Array) -> float:
	return knots[knots.size() - 1]


## F(z): model metres from phase 0 of loop 0 to unwrapped phase z.
static func distance_at(knots: PackedFloat64Array, z: float) -> float:
	var loops := floorf(z)
	var p := z - loops
	var i := _segment(knots, p)
	return loops * loop_m(knots) + knots[i + 1] \
		+ (p - knots[i]) * (knots[i + 3] - knots[i + 1]) / (knots[i + 2] - knots[i])


## F^-1(F(z0) + d): the unwrapped phase reached `d` (>= 0) model metres on from z0.
static func phase_after(knots: PackedFloat64Array, z0: float, d: float) -> float:
	var s := loop_m(knots)
	var target := distance_at(knots, z0) + maxf(d, 0.0)
	var loops := floorf(target / s)
	var rest := target - loops * s
	var i := 0
	while i < knots.size() - 4 and knots[i + 3] <= rest:
		i += 2
	return loops + knots[i] + (rest - knots[i + 1]) * (knots[i + 2] - knots[i]) / (knots[i + 3] - knots[i + 1])


## The AnimationPlayer speed_scale that carries a figure now at clip phase `p` (0..1)
## over the next `dt` seconds through the phases `model_speed` (model m/s) walks it:
## the exact secant of the map over that step, so a frame crossing knots (or loops)
## keeps its hooves. `clip_s` is the clip's length. With no step (dt or speed 0) it
## is the map's slope at p.
static func rate(knots: PackedFloat64Array, p: float, model_speed: float, dt: float,
		clip_s: float) -> float:
	if model_speed <= 0.0:
		return 0.0
	if dt <= 0.0:
		var i := _segment(knots, p)
		return model_speed * clip_s * (knots[i + 2] - knots[i]) / (knots[i + 3] - knots[i + 1])
	return (phase_after(knots, p, model_speed * dt) - p) * clip_s / dt


## The flat index of the knot starting the segment holding phase p (half-open: a
## knot starts its segment).
static func _segment(knots: PackedFloat64Array, p: float) -> int:
	var i := 0
	while i < knots.size() - 4 and knots[i + 2] <= p:
		i += 2
	return i
