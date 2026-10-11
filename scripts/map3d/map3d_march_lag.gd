class_name Map3DMarchLag
extends RefCounted
## A column does not march in lock-step (owner 2026-10-12, R5): each figure's
## gait starts at its own hashed phase of the clip, plays a little faster or
## slower, and trails its slot by a positional lag spring. All hashed from the
## regiment's id and the figure's index (String.hash is stable across runs; no
## RNG, no clock) and view-only: the simulation never sees it. Pure.


## A stable 0..1 (never 1) from a key.
static func _unit(key: String) -> float:
	return float(key.hash() % 10007) / 10007.0


## Where in its MARCH clip figure `index` of `code` starts, as a share of the clip.
static func phase(code: String, index: int) -> float:
	return _unit("%s|phase|%d" % [code, index])


## The lag spring's time constant (seconds) of a figure: min_s..max_s.
static func tau(code: String, index: int, min_s: float, max_s: float) -> float:
	return min_s + _unit("%s|tau|%d" % [code, index]) * (max_s - min_s)


## A marching figure's playback rate: `base` x (1 +/- `spread`), clamped AFTER the
## jitter into lo..hi so the gait never outruns map3d_unit_anim_max.
static func pace(code: String, index: int, base: float, spread: float, lo: float, hi: float) -> float:
	var jitter := 1.0 + (_unit("%s|pace|%d" % [code, index]) * 2.0 - 1.0) * spread
	return clampf(base * jitter, lo, hi)


## One step of a figure's offset `o` from its slot (the piece's local metres)
## while the piece moves at local velocity `v`: a first-order lag, exactly
## o*e^(-dt/tau) - v*tau*(1 - e^(-dt/tau)) (steady state -v*tau, behind its
## slot), its length held to `cap`.
static func step(o: Vector3, v: Vector3, tau_s: float, dt: float, cap: float) -> Vector3:
	var e := exp(-dt / maxf(tau_s, 0.0001))
	var out := o * e - v * tau_s * (1.0 - e)
	return out.limit_length(cap)
