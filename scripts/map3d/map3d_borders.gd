class_name Map3DBorders
extends RefCounted
## The 3D map's kingdom borders and province seams (owner 2026-09-18), taken
## from the same LIVE outlines the 2D map draws (MapOwnership: a conquest or
## an annexed manor moves them with nothing rebuilt by hand), carried into
## world metres and laid on the ground as ribbons.
##
## A ribbon is two vertices per point at the SAME position, their NORMAL the
## ground-plane side (mitred at corners), one + and one −; border_line.gdshader
## pushes them apart by a width in SCREEN px and lifts them off the ground by
## the camera distance, so a line reads the same at every zoom. UV.x is the
## arc length in metres (the dash pattern), UV.y the side.


## Mesh arrays for `lines` (PackedVector2Array, world XZ), each a separate
## strip, lying on `height_fn(xz)` — or, where `heights` gives line i a
## PackedFloat32Array, on its value at each point that is not NAN (a road's
## bridge deck, Map3DBridges). [] when there is nothing to draw.
##
## `one_sided` (the realm band, spec 2026-09-19-map3d-border-look): both
## vertices of a point carry the SAME side, the line's own at UV.y 0 and the
## far one at UV.y 1, and border_line.gdshader's one_sided pushes only the far
## one, a full width — so the ribbon starts on the line and reaches one way
## (to the left of the line's heading; `inward` turns a ring so that is its
## inside). The side is never coded in NORMAL's length: Godot stores normals
## octahedrally, so a zero or doubled normal comes back unit-length.
## `colours`, when given, is a Color per line written on its vertices
## (ARRAY_COLOR), so one mesh carries every kingdom's band.
static func ribbon_arrays(lines: Array, height_fn: Callable, heights: Array = [],
		one_sided := false, colours: Array = []) -> Array:
	var verts := PackedVector3Array()
	var sides := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for li in lines.size():
		var line: PackedVector2Array = lines[li]
		var own: PackedFloat32Array = heights[li] if li < heights.size() else PackedFloat32Array()
		var col: Color = colours[li] if li < colours.size() else Color.WHITE
		var n := line.size()
		if n < 2:
			continue
		var base := verts.size()
		var arc := 0.0
		var prev_side := Vector2.ZERO
		for i in n:
			if i > 0:
				arc += line[i - 1].distance_to(line[i])
			var side := _side(line, i, prev_side)
			prev_side = side
			var y := own[i] if i < own.size() and not is_nan(own[i]) else float(height_fn.call(line[i]))
			var p := Vector3(line[i].x, y, line[i].y)
			verts.append(p)
			verts.append(p)
			sides.append(Vector3(side.x, 0.0, side.y))
			sides.append(Vector3(side.x, 0.0, side.y) if one_sided else Vector3(-side.x, 0.0, -side.y))
			uvs.append(Vector2(arc, 0.0))
			uvs.append(Vector2(arc, 1.0))
			if not colours.is_empty():
				cols.append(col)
				cols.append(col)
		for i in n - 1:
			var a := base + i * 2
			idx.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	if verts.is_empty():
		return []
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = sides
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	if not colours.is_empty():
		arrays[Mesh.ARRAY_COLOR] = cols
	return arrays


## A kingdom's rings (kingdom_lines) turned so a one-sided ribbon along each
## reaches into the KINGDOM: _side's (-d.y, d.x) is the left of the heading,
## the inside of a ring whose shoelace area over (x, z) is positive. An outer
## ring is turned to reach into itself; a HOLE — a ring inside an odd number of
## the kingdom's other rings (a lake, unheld land, an enclave: MapOwnership's
## merged loops return them as plain rings) — to reach out of itself, onto
## the land around it. Even-odd on one probe point of each ring.
static func inward_rings(rings: Array) -> Array:
	var out: Array = []
	for i in rings.size():
		var ring: PackedVector2Array = rings[i]
		var depth := 0
		if ring.size() >= 3:
			var probe := (ring[0] + ring[1]) * 0.5
			for j in rings.size():
				if j != i and (rings[j] as PackedVector2Array).size() >= 3 \
						and Geometry2D.is_point_in_polygon(probe, rings[j]):
					depth += 1
		out.append(oriented(ring, depth % 2 == 0))
	return out


## `line` turned so a one-sided ribbon along it reaches inside it (`inside`)
## or outside it, by the sign of its shoelace area over (x, z).
static func oriented(line: PackedVector2Array, inside: bool) -> PackedVector2Array:
	var area := 0.0
	var n := line.size()
	for i in n:
		var a := line[i]
		var b := line[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	if (area >= 0.0) == inside:
		return line
	var out := line.duplicate()
	out.reverse()
	return out


## The unit side at point i: perpendicular to the line there, the mitre of
## the two segments at a corner (the plain average — the shader's width is a
## few px, where a true mitre's spikes would only show as blots).
static func _side(line: PackedVector2Array, i: int, prev := Vector2.ZERO) -> Vector2:
	var n := line.size()
	var a := (line[i] - line[i - 1]).normalized() if i > 0 else Vector2.ZERO
	var b := (line[i + 1] - line[i]).normalized() if i < n - 1 else Vector2.ZERO
	# At a cusp the two directions cancel: keep the previous point's side
	# rather than swap the ribbon's sides (a twist, owner 2026-09-19).
	if a != Vector2.ZERO and b != Vector2.ZERO and a.dot(b) < -0.9 and prev != Vector2.ZERO:
		return prev
	var d := a + b
	if d.length_squared() < 1e-12:
		d = (line[mini(i + 1, n - 1)] - line[maxi(i - 1, 0)]).normalized()
	d = d.normalized()
	return Vector2(-d.y, d.x)


## Two-point segments joined into polylines through every point exactly two
## of them share; a point shared by one or by three or more ends a chain. A
## seam drawn as one strip has no overlapping caps at its joints and one
## unbroken dash (owner 2026-09-19).
static func chain_segments(segments: Array) -> Array:
	var at := {}  # point -> [segment indices]
	for i in segments.size():
		for p: Vector2 in segments[i]:
			if not at.has(p):
				at[p] = []
			(at[p] as Array).append(i)
	var used := PackedByteArray()
	used.resize(segments.size())
	var out: Array = []
	for s in segments.size():
		if used[s] == 1:
			continue
		used[s] = 1
		var seg: PackedVector2Array = segments[s]
		var chain := PackedVector2Array([seg[0], seg[1]])
		for dir in 2:  # forward from the end, then backward from the start
			while true:
				var tip: Vector2 = chain[chain.size() - 1] if dir == 0 else chain[0]
				var here: Array = at.get(tip, [])
				if here.size() != 2:
					break
				var next := -1
				for j: int in here:
					if used[j] == 0:
						next = j
				if next < 0:
					break
				used[next] = 1
				var ns: PackedVector2Array = segments[next]
				var far: Vector2 = ns[1] if ns[0] == tip else ns[0]
				if dir == 0:
					chain.append(far)
				else:
					chain.insert(0, far)
		out.append(chain)
	return out


## A kingdom's live outline rings in world metres, smoothed through the
## province corners exactly as the 2D border is (map_border_smoothing_steps),
## closed, and resampled to `step_m` so they drape over the relief.
static func kingdom_lines(repo: DataRepository, state: GameState, world: Dictionary,
		kingdom_code: String, step_m: float) -> Array:
	var steps := int(repo.bal("map_border_smoothing_steps"))
	var out: Array = []
	var loops := MapOwnership.outline_of(repo, state, kingdom_code)
	var pins := MapOwnership.outline_pins(repo, state, kingdom_code)
	for li in loops.size():
		var loop: PackedVector2Array = loops[li]
		if loop.size() < 3:
			continue
		var ring := MapGeometry.smooth_closed_through(loop, steps, pins[li])
		var pts := PackedVector2Array()
		for p in ring:
			pts.append(Map3DGeometry.pack_to_world(world, p))
		if pts[0] != pts[pts.size() - 1]:
			pts.append(pts[0])
		out.append(Map3DGeometry.resample(pts, step_m))
	return out


## Every kingdom's province seams in world metres, chained through their
## shared joints into as few polylines as possible (chain_segments) — one
## strip per seam, no overlapping caps at a junction and one unbroken dash —
## the province view is always on (owner 2026-09-13), so all of them.
static func seam_lines(repo: DataRepository, state: GameState, world: Dictionary,
		step_m: float) -> Array:
	var out: Array = []
	for code: String in repo.kingdoms:
		var segments: Array = MapOwnership.seams_of(repo, state, code)
		for chain: PackedVector2Array in chain_segments(segments):
			var pts := PackedVector2Array()
			for p in chain:
				pts.append(Map3DGeometry.pack_to_world(world, p))
			out.append(Map3DGeometry.resample(pts, step_m))
	return out


## The pack's routes of one `group` ("roads", "trails") in world metres,
## smoothed exactly as the 2D map smooths them (map_route_smoothing_steps)
## and resampled to `step_m` so they drape over the relief.
static func route_lines(repo: DataRepository, world: Dictionary, group: String,
		step_m: float) -> Array:
	var steps := int(repo.bal("map_route_smoothing_steps"))
	var out: Array = []
	for code: String in repo.routes:
		var r: Dictionary = repo.routes[code]
		if String(r["group"]) != group:
			continue
		var line := MapGeometry.smooth_open(r["polyline"], steps)
		if line.size() < 2:
			continue
		var pts := PackedVector2Array()
		for p in line:
			pts.append(Map3DGeometry.pack_to_world(world, p))
		out.append(Map3DGeometry.resample(pts, step_m))
	return out
