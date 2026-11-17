class_name Map3DFall
extends RefCounted
## A lost group falls IN THE DUEL (spec 2026-11-16-infantry-duel-animation-design.md;
## owner: 前排倒，后排补位). The engine trims a unit's losses from the tail of its
## saved rows, a flank figure; the view shows the fall on a duelling front
## figure instead and walks the removed figure up into its place, so the falls
## equal the removed groups and, the walk done, every saved row has its figure.
## Pure and hashed (Map3DMarchLag.unit); view-only.


## One {removed, faller} per slot in `removed` (in order): `faller` a distinct
## slot of `paired` still in `kept`, picked by hash; a removed slot that is
## itself paired, or none left, falls where it stands (`faller` == `removed`). `n` counts this unit's
## earlier losses, so successive losses pick afresh.
static func plan(code: String, removed: Array, paired: Array, kept: Array, n: int) -> Array:
	var free: Array = paired.filter(func(slot: int) -> bool: return slot in kept)
	free.sort()
	var out: Array = []
	for slot: int in removed:
		var faller := slot  # a removed duellist is already in the duel: it falls as itself
		if not slot in paired and not free.is_empty():
			var k := mini(int(Map3DMarchLag.unit("%s|fall|%d|%d" % [code, slot, n]) * free.size()), free.size() - 1)
			faller = int(free[k])
			free.remove_at(k)
		out.append({"removed": slot, "faller": faller})
	return out


## A fallen body's opacity: whole for `hold_s`, then gone linearly over `fade_s`.
static func alpha(elapsed: float, hold_s: float, fade_s: float) -> float:
	return Map3DCourierRide.alpha(elapsed - hold_s, fade_s)
