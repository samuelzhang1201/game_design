class_name Map3DDeclutter
extends RefCounted
## Spread boxes so none covers another (owner 2026-10-07: 所有单位在地图上不要
## 重叠 … 数量marker也不要重叠; spec 2026-10-07-army-split-and-ground §5.2).
## Pure: boxes in any one plane (design px on the map's HUD, table metres in
## the war room), placed in the order given — the first never moves — each at
## the first offset of a fixed outward spiral that touches nothing placed and
## no obstacle. A HIDEABLE box (a headcount chip) with no clear offset within
## reach hides (null); any other (a counter) takes the least-covered offset
## of the spiral, so a unit is never lost from the map.

static var _spirals: Dictionary = {}   # Vector2(step, reach) -> the spiral's offsets


## Offsets on a grid of `step`, out to `reach` either way, nearest first
## (ties by angle from straight up, clockwise): ZERO first.
static func spiral(step: float, reach: float) -> Array:
	var key := Vector2(step, reach)
	if _spirals.has(key):
		return _spirals[key]
	var n := int(floor(reach / maxf(step, 0.000001)))
	var out: Array = []
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			out.append(Vector2(i * step, j * step))
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var la := a.length()
		var lb := b.length()
		if absf(la - lb) > step * 0.0001:
			return la < lb
		return fposmod(atan2(a.x, -a.y), TAU) < fposmod(atan2(b.x, -b.y), TAU))
	_spirals[key] = out
	return out


## One offset per box (Vector2), or null for a hideable box with no room.
static func place(boxes: Array, hideable: Array, obstacles: Array, step: float, reach: float) -> Array:
	var placed: Array[Rect2] = []
	placed.assign(obstacles)
	var out: Array = []
	var offs := spiral(step, reach)
	for i in boxes.size():
		var b: Rect2 = boxes[i]
		# only what lies within reach can be met: the rest is never tested
		var zone := b.grow(reach)
		var near: Array[Rect2] = []
		for p: Rect2 in placed:
			if zone.intersects(p):
				near.append(p)
		var at: Variant = _first_clear(b, near, offs)
		if at == null:
			if bool(hideable[i]):
				out.append(null)
				continue
			at = _least_covered(b, near, offs)
		out.append(at)
		placed.append(Rect2(b.position + (at as Vector2), b.size))
	return out


## The first offset of the spiral at which `b` touches nothing in `near`, or
## null. The rect that blocked the last offset is tried first: the spiral's
## next offset is beside it, so it usually blocks that one too (perf: the HUD
## cuts the counters every frame the camera moves).
static func _first_clear(b: Rect2, near: Array[Rect2], offs: Array) -> Variant:
	var last := 0
	var n := near.size()
	for off: Vector2 in offs:
		var r := Rect2(b.position + off, b.size)
		if n > 0 and r.intersects(near[last]):
			continue
		var clear := true
		for k in n:
			if r.intersects(near[k]):
				clear = false
				last = k
				break
		if clear:
			return off
	return null


## The offset of `offs` at which `b` is least covered by `near` (the first
## such): where a counter goes when no place within reach is clear.
static func _least_covered(b: Rect2, near: Array[Rect2], offs: Array) -> Vector2:
	var best := Vector2.ZERO
	var best_hit := INF
	for off: Vector2 in offs:
		var r := Rect2(b.position + off, b.size)
		var hit := 0.0
		for p: Rect2 in near:
			if r.intersects(p):
				hit += r.intersection(p).get_area()
		if hit < best_hit:
			best_hit = hit
			best = off
	return best
