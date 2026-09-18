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
## strip, lying on `height_fn(xz)`. [] when there is nothing to draw.
static func ribbon_arrays(lines: Array, height_fn: Callable) -> Array:
	var verts := PackedVector3Array()
	var sides := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for line: PackedVector2Array in lines:
		var n := line.size()
		if n < 2:
			continue
		var base := verts.size()
		var arc := 0.0
		for i in n:
			if i > 0:
				arc += line[i - 1].distance_to(line[i])
			var side := _side(line, i)
			var p := Vector3(line[i].x, float(height_fn.call(line[i])), line[i].y)
			verts.append(p)
			verts.append(p)
			sides.append(Vector3(side.x, 0.0, side.y))
			sides.append(Vector3(-side.x, 0.0, -side.y))
			uvs.append(Vector2(arc, 0.0))
			uvs.append(Vector2(arc, 1.0))
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
	return arrays


## The unit side at point i: perpendicular to the line there, the mitre of
## the two segments at a corner (the plain average — the shader's width is a
## few px, where a true mitre's spikes would only show as blots).
static func _side(line: PackedVector2Array, i: int) -> Vector2:
	var n := line.size()
	var d := Vector2.ZERO
	if i > 0:
		d += (line[i] - line[i - 1]).normalized()
	if i < n - 1:
		d += (line[i + 1] - line[i]).normalized()
	if d.length_squared() < 1e-12:
		d = (line[mini(i + 1, n - 1)] - line[maxi(i - 1, 0)]).normalized()
	d = d.normalized()
	return Vector2(-d.y, d.x)


## A kingdom's live outline rings in world metres, smoothed through the
## province corners exactly as the 2D border is (map_border_smoothing_steps),
## closed, and resampled to `step_m` so they drape over the relief.
static func kingdom_lines(repo: DataRepository, state: GameState, world: Dictionary,
		kingdom_code: String, step_m: float) -> Array:
	var steps := int(repo.bal("map_border_smoothing_steps"))
	var out: Array = []
	for loop: PackedVector2Array in MapOwnership.outline_of(repo, state, kingdom_code):
		if loop.size() < 3:
			continue
		var ring := MapGeometry.smooth_closed_through(loop, steps)
		var pts := PackedVector2Array()
		for p in ring:
			pts.append(Map3DGeometry.pack_to_world(world, p))
		if pts[0] != pts[pts.size() - 1]:
			pts.append(pts[0])
		out.append(Map3DGeometry.resample(pts, step_m))
	return out


## Every kingdom's province seams in world metres, one resampled line each —
## the province view is always on (owner 2026-09-13), so all of them.
static func seam_lines(repo: DataRepository, state: GameState, world: Dictionary,
		step_m: float) -> Array:
	var out: Array = []
	for code: String in repo.kingdoms:
		for seg: PackedVector2Array in MapOwnership.seams_of(repo, state, code):
			var pts := PackedVector2Array()
			for p in seg:
				pts.append(Map3DGeometry.pack_to_world(world, p))
			out.append(Map3DGeometry.resample(pts, step_m))
	return out
