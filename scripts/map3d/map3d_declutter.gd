class_name Map3DDeclutter
extends RefCounted
## Spread boxes so none covers another (owner 2026-10-07: 所有单位在地图上不要
## 重叠 … 数量marker也不要重叠; spec 2026-10-07-army-split-and-ground §5.2).
## Pure: boxes in any one plane (design px on the map's HUD, table metres in
## the war room), placed in the order given — the first never moves — each at
## the first offset of a fixed outward spiral that touches nothing placed and
## no obstacle. A HIDEABLE box (a headcount chip) with no clear offset within
## reach hides (null); any other (a counter) takes the least-covered offset
## of the spiral, so a unit is never lost from the map. An optional `allowed`
## (the box's centre -> bool; the HUD's: on land) is asked only of clear
## offsets off the box's home (its unit stands there): the first clear AND
## allowed one wins, else the first clear one (owner 2026-10-08: counters off
## the sea where they can be). A box whose `any_ground` is true (a fleet) is
## never asked.

static var _spirals: Dictionary = {}   # Vector2(step, reach) -> the spiral's offsets
static var _grids: Dictionary = {}


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
static func place(boxes: Array, hideable: Array, obstacles: Array, step: float, reach: float,
		allowed: Callable = Callable(), any_ground: Array = []) -> Array:
	var placed: Array[Rect2] = []
	placed.assign(obstacles)
	var out: Array = []
	var offs := spiral(step, reach)
	var grid_key := Vector2(step, reach)
	if not _grids.has(grid_key): _grids[grid_key] = _grid_of(offs)
	var grid: Dictionary = _grids[grid_key]
	for i in boxes.size():
		var b: Rect2 = boxes[i]
		# only what lies within reach can be met: the rest is never tested
		var zone := b.grow(reach)
		var near: Array[Rect2] = []
		for p: Rect2 in placed:
			if zone.intersects(p):
				near.append(p)
		var ask := allowed.is_valid() and not (i < any_ground.size() and bool(any_ground[i]))
		var at: Variant = _first_clear(b, near, offs, allowed if ask else Callable(), grid)
		if at == null:
			if bool(hideable[i]):
				out.append(null)
				continue
			at = _least_covered(b, near, offs, grid)
		out.append(at)
		placed.append(Rect2(b.position + (at as Vector2), b.size))
	return out


## The first offset of the spiral at which `b` touches nothing in `near`
## and `allowed` (when valid) takes its centre — ZERO, the home, always
## does — else the first clear one;
## null for none. Native image fills mark every blocked lattice cell; scanning
## those cells retains the original spiral order without repeating rect tests.
static func _first_clear(b: Rect2, near: Array[Rect2], offs: Array, allowed: Callable,
		grid: Dictionary = {}) -> Variant:
	if offs.is_empty(): return null
	if not near.any(func(p: Rect2) -> bool: return b.intersects(p)): return Vector2.ZERO
	var lattice := _grid_of(offs) if grid.is_empty() else grid
	var axis: Array[float] = lattice["axis"]
	var cells: PackedInt32Array = lattice["cells"]
	var bounds := _box_axes(b, axis)
	var lefts: PackedFloat64Array = bounds[0]
	var rights: PackedFloat64Array = bounds[1]
	var tops: PackedFloat64Array = bounds[2]
	var bottoms: PackedFloat64Array = bounds[3]
	var mask := Image.create(axis.size(), axis.size(), false, Image.FORMAT_R8)
	mask.fill(Color.BLACK)
	for p: Rect2 in near:
		var end := p.end
		var xs := Vector2i(rights.bsearch(p.position.x, false), lefts.bsearch(end.x))
		var ys := Vector2i(bottoms.bsearch(p.position.y, false), tops.bsearch(end.y))
		if xs.x >= xs.y or ys.x >= ys.y: continue
		mask.fill_rect(Rect2i(xs.x, ys.x, xs.y - xs.x, ys.y - ys.x), Color.WHITE)
	var blocked := mask.get_data()
	if not blocked.has(0): return null
	var fallback: Variant = null
	for i: int in offs.size():
		if blocked[cells[i]] != 0: continue
		var off: Vector2 = offs[i]
		var r := Rect2(b.position + off, b.size)
		if not allowed.is_valid() or off == Vector2.ZERO or bool(allowed.call(r.get_center())):
			return off
		if fallback == null:
			fallback = off
	return fallback


## The offset of `offs` at which `b` is least covered by `near` (the first
## such): where a counter goes when no place within reach is clear.
static func _least_covered(b: Rect2, near: Array[Rect2], offs: Array,
		grid: Dictionary = {}) -> Vector2:
	if offs.is_empty(): return Vector2.ZERO
	var lattice := _grid_of(offs) if grid.is_empty() else grid
	var axis: Array[float] = lattice["axis"]
	var cells: PackedInt32Array = lattice["cells"]
	var bounds := _box_axes(b, axis)
	var lefts: PackedFloat64Array = bounds[0]
	var rights: PackedFloat64Array = bounds[1]
	var tops: PackedFloat64Array = bounds[2]
	var bottoms: PackedFloat64Array = bounds[3]
	var scores := PackedFloat64Array()
	scores.resize(axis.size() * axis.size())
	for p: Rect2 in near:
		var end := p.end
		var xs := Vector2i(rights.bsearch(p.position.x, false), lefts.bsearch(end.x))
		var ys := Vector2i(bottoms.bsearch(p.position.y, false), tops.bsearch(end.y))
		if xs.x >= xs.y or ys.x >= ys.y: continue
		var widths := PackedFloat64Array()
		for x: int in range(xs.x, xs.y):
			var r := Rect2(b.position + Vector2(axis[x], axis[ys.x]), b.size)
			widths.append(r.intersection(p).size.x)
		for y: int in range(ys.x, ys.y):
			var r := Rect2(b.position + Vector2(axis[xs.x], axis[y]), b.size)
			var height := r.intersection(p).size.y
			for x: int in range(xs.x, xs.y):
				# Native area multiplication retains Rect2 rounding after separating its two axes.
				scores[y * axis.size() + x] += Rect2(0, 0, widths[x - xs.x], height).get_area()
	var best := Vector2.ZERO
	var best_hit := INF
	for i: int in offs.size():
		var hit := scores[cells[i]]
		if hit < best_hit:
			best_hit = hit
			best = offs[i]
	return best


static func _grid_of(offs: Array) -> Dictionary:
	var axis: Array[float] = []
	for off: Vector2 in offs:
		if off.y == 0.0: axis.append(off.x)
	axis.sort()
	var indices: Dictionary[float, int] = {}
	for i: int in axis.size(): indices[axis[i]] = i
	var cells := PackedInt32Array()
	for off: Vector2 in offs: cells.append(indices[off.y] * axis.size() + indices[off.x])
	return {"axis": axis, "cells": cells}


static func _box_axes(b: Rect2, axis: Array[float]) -> Array:
	var lefts := PackedFloat64Array()
	var rights := PackedFloat64Array()
	var tops := PackedFloat64Array()
	var bottoms := PackedFloat64Array()
	# Use native Rect2 rounding before the searches, preserving subpixel gaps and ties exactly.
	for shift: float in axis:
		var r := Rect2(b.position + Vector2(shift, shift), b.size)
		var end := r.end
		lefts.append(r.position.x); rights.append(end.x)
		tops.append(r.position.y); bottoms.append(end.y)
	return [lefts, rights, tops, bottoms]
