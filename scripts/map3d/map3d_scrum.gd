class_name Map3DScrum
extends RefCounted
## The mixed fight's geometry (spec 2026-11-21-infantry-melee-scrum-design.md;
## owner: 双方兵人应该在战场上混在一起): one fighting area between two opposed
## fronts, a hashed target inside it per figure (Map3DMarchLag.unit), a bounded
## separation pass and greedy nearest pairing across it. Pure and view-only.


## The area between sides `a` and `b` (world XZ points): `across` runs from one
## side to the other (none: the line between their means), `along` the front;
## it spans both sides' extent along the front and `depth` across, centred
## between the two sides' means.
static func area(a: Array[Vector2], b: Array[Vector2], across: Vector2, depth: float) -> Dictionary:
	var mean := func(pts: Array[Vector2]) -> Vector2:
		var sum := Vector2.ZERO
		for p: Vector2 in pts:
			sum += p
		return sum / maxf(pts.size(), 1.0)
	var ma: Vector2 = mean.call(a)
	var mb: Vector2 = mean.call(b)
	var ac := across.normalized() if across != Vector2.ZERO else (mb - ma).normalized()
	if ac == Vector2.ZERO:
		ac = Vector2.DOWN
	var along := ac.orthogonal()
	var centre := (ma + mb) / 2.0
	var half_len := 0.0
	for p: Vector2 in a + b:
		half_len = maxf(half_len, absf((p - centre).dot(along)))
	return {"centre": centre, "along": along, "across": ac, "half_len": half_len, "half_depth": depth / 2.0}


## Figure `key`'s point inside `area`, the same every call.
static func target(key: String, area: Dictionary) -> Vector2:
	var u := Map3DMarchLag.unit(key + "|u") * 2.0 - 1.0
	var v := Map3DMarchLag.unit(key + "|v") * 2.0 - 1.0
	return area["centre"] + (area["along"] as Vector2) * u * float(area["half_len"]) \
		+ (area["across"] as Vector2) * v * float(area["half_depth"])


## One separation pass over `points` (key -> XZ): every two closer than `space`
## are pushed apart equally along their line (two on one spot along +X), each
## point's move at most `push_max`; keys taken in sorted order.
static func separate(points: Dictionary, space: float, push_max: float) -> Dictionary:
	var keys := points.keys()
	keys.sort()
	var move: Dictionary = {}
	for key: String in keys:
		move[key] = Vector2.ZERO
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var d: Vector2 = points[keys[j]] - points[keys[i]]
			var gap := d.length()
			if gap >= space:
				continue
			var dir := d / gap if gap > 0.0 else Vector2.RIGHT
			var half := (space - gap) / 2.0
			move[keys[i]] -= dir * half
			move[keys[j]] += dir * half
	var out: Dictionary = {}
	for key: String in keys:
		out[key] = (points[key] as Vector2) + (move[key] as Vector2).limit_length(push_max)
	return out


## Pairs of `a` and `b` figures ({key, xz}) nearest first (ties: by keys), each
## figure once, none farther apart than `reach`: [{a, b}] (keys).
static func pairs_nearest(a: Array, b: Array, reach: float) -> Array:
	var all: Array = []
	for fa: Dictionary in a:
		for fb: Dictionary in b:
			var d := (fa["xz"] as Vector2).distance_to(fb["xz"])
			if d <= reach:
				all.append([d, String(fa["key"]), String(fb["key"])])
	all.sort_custom(func(p: Array, q: Array) -> bool:
		return p[0] < q[0] if p[0] != q[0] else (p[1] < q[1] if p[1] != q[1] else p[2] < q[2]))
	var taken: Dictionary = {}
	var out: Array = []
	for row: Array in all:
		if not taken.has("a" + row[1]) and not taken.has("b" + row[2]):
			taken["a" + row[1]] = true
			taken["b" + row[2]] = true
			out.append({"a": row[1], "b": row[2]})
	return out
