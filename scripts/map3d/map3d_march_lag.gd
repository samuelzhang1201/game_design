class_name Map3DMarchLag
extends RefCounted
## A column does not march in lock-step (owner 2026-10-12, R5): each figure's
## gait starts at its own hashed phase of the clip, plays a little faster or
## slower, and trails its slot by a positional lag spring. All hashed from the
## regiment's id and the figure's index (String.hash is stable across runs; no
## RNG, no clock) and view-only: the simulation never sees it. Pure.


## A stable 0..1 (never 1) from a key. String.hash alone gives keys that differ
## only in their last character (figure 0, 1, 2 …) CONSECUTIVE hashes, so every
## figure drew the same share; murmur3's fmix32 spreads them over 0..1.
static func _unit(key: String) -> float:
	var h := key.hash() & 0xFFFFFFFF
	h ^= h >> 16
	h = (h * 0x85ebca6b) & 0xFFFFFFFF
	h ^= h >> 13
	h = (h * 0xc2b2ae35) & 0xFFFFFFFF
	h ^= h >> 16
	return float(h) / 4294967296.0


## The same stable 0..1 for any other view-only choice (Map3DClipChain).
static func unit(key: String) -> float:
	return _unit(key)


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


## A figure's stature, 1 +/- `spread` (owner 2026-10-14: 步伐要参差不齐): an
## exact-pace arm stands each figure at it and plays the piece's rate over it
## (Map3DUnitRig.keep_pace), so its cadence is its own and its feet still hold.
static func stature(code: String, index: int, spread: float) -> float:
	return 1.0 + (_unit("%s|stature|%d" % [code, index]) * 2.0 - 1.0) * spread


## One step of a figure's offset `o` from its slot (the piece's local metres)
## while the piece moves at local velocity `v`: a first-order lag, exactly
## o*e^(-dt/tau) - v*tau*(1 - e^(-dt/tau)) (steady state -v*tau, behind its
## slot), its length held to `cap`.
static func step(o: Vector3, v: Vector3, tau_s: float, dt: float, cap: float) -> Vector3:
	var e := exp(-dt / maxf(tau_s, 0.0001))
	var out := o * e - v * tau_s * (1.0 - e)
	return out.limit_length(cap)
