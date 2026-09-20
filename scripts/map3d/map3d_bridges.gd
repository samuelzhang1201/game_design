class_name Map3DBridges
extends RefCounted
## Stone bridges where a road crosses a river on the 3D map (owner
## 2026-09-19: "当道路穿越河流的时候，要显示为桥梁"). Pure and tested headless.
##
## `plan` walks each road line (world XZ, already resampled), finds where it
## crosses a river's centreline (Map3DRivers courses: pos.y the water line,
## a width per point) and, for each crossing, straightens the road over a
## SPAN — the river's width seen along the road, plus an abutment each side
## — and gives that stretch the bridge DECK's height: a gentle hump from the
## bank at one end to the bank at the other, its crown clear of the water.
## The roads are drawn over the deck (Map3DBorders.ribbon_arrays' heights);
## `mesh_arrays` builds the stone under them: spandrel walls pierced by
## arches, piers, the arches' soffits, the deck and a parapet each side.
##
## `rules` (balance.csv map3d_bridge_*): abut_m, clear_m, clear_per_width,
## hump_m, min_sin, merge_m, deck_step_m, deck_m, parapet_h_m, parapet_w_m,
## arch_max_m, pier_m, end_over_water_m.

## A river segment grid's cell, metres: a road point looks only at its own
## and the neighbouring cells.
const GRID_M := 500.0


## Every river's centreline segments bucketed by grid cell:
## {Vector2i: [[a: Vector2, b: Vector2, water_a, water_b, width_a, width_b, id]]}.
static func river_grid(courses: Array) -> Dictionary:
	var grid: Dictionary = {}
	var id := 0
	for c: Dictionary in courses:
		var pos: PackedVector3Array = c["pos"]
		var width: PackedFloat32Array = c["width"]
		for i in pos.size() - 1:
			var a := Vector2(pos[i].x, pos[i].z)
			var b := Vector2(pos[i + 1].x, pos[i + 1].z)
			var seg := [a, b, pos[i].y, pos[i + 1].y, width[i], width[i + 1], id]
			id += 1
			var lo := Vector2i(floori(minf(a.x, b.x) / GRID_M), floori(minf(a.y, b.y) / GRID_M))
			var hi := Vector2i(floori(maxf(a.x, b.x) / GRID_M), floori(maxf(a.y, b.y) / GRID_M))
			for gx in range(lo.x, hi.x + 1):
				for gy in range(lo.y, hi.y + 1):
					var key := Vector2i(gx, gy)
					if not grid.has(key):
						grid[key] = []
					(grid[key] as Array).append(seg)
	return grid


## Where `line` crosses a river: [{arc, at, water_y, width, river_dir}],
## by arc length along the line.
static func crossings(line: PackedVector2Array, grid: Dictionary) -> Array:
	var out: Array = []
	var arc := 0.0
	for i in line.size() - 1:
		var p := line[i]
		var q := line[i + 1]
		var seen: Dictionary = {}
		var lo := Vector2i(floori(minf(p.x, q.x) / GRID_M), floori(minf(p.y, q.y) / GRID_M))
		var hi := Vector2i(floori(maxf(p.x, q.x) / GRID_M), floori(maxf(p.y, q.y) / GRID_M))
		for gx in range(lo.x, hi.x + 1):
			for gy in range(lo.y, hi.y + 1):
				for seg: Array in grid.get(Vector2i(gx, gy), []):
					if seen.has(seg[6]):
						continue
					seen[seg[6]] = true
					var hit: Variant = Geometry2D.segment_intersects_segment(p, q, seg[0], seg[1])
					if hit == null:
						continue
					var at: Vector2 = hit
					var seg_len := (seg[0] as Vector2).distance_to(seg[1])
					var t := 0.0 if seg_len <= 0.0 else (seg[0] as Vector2).distance_to(at) / seg_len
					out.append({
						"arc": arc + p.distance_to(at), "at": at,
						"water_y": lerpf(seg[2], seg[3], t), "width": lerpf(seg[4], seg[5], t),
						"river_dir": ((seg[1] as Vector2) - (seg[0] as Vector2)).normalized(),
						"road_dir": (q - p).normalized()})
		arc += p.distance_to(q)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["arc"] < b["arc"])
	return out


## The bridges for `lines`: {lines: the roads with each span straightened,
## heights: per line a PackedFloat32Array, the deck's height on a span's
## points and NAN elsewhere, bridges: [{a, b, ya, yb, crown, water_y, width,
## foot}]} — foot the foundations' depth, under both banks and the water.
static func plan(lines: Array, courses: Array, height_fn: Callable, rules: Dictionary) -> Dictionary:
	var grid := river_grid(courses)
	var out_lines: Array = []
	var out_heights: Array = []
	var bridges: Array = []
	for line: PackedVector2Array in lines:
		var spans := _spans(line, crossings(line, grid), rules)
		if spans.is_empty():
			out_lines.append(line)
			out_heights.append(PackedFloat32Array())
			continue
		var res := _splice(line, spans, height_fn, rules)
		out_lines.append(res["line"])
		out_heights.append(res["heights"])
		bridges.append_array(res["bridges"])
	return {"lines": out_lines, "heights": out_heights, "bridges": bridges}


## Each crossing's span [from_arc, to_arc] on the line, overlapping spans
## (a road crossing a meander twice) merged into one bridge.
static func _spans(line: PackedVector2Array, hits: Array, rules: Dictionary) -> Array:
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	var spans: Array = []
	for h: Dictionary in hits:
		var sine := absf((h["road_dir"] as Vector2).cross(h["river_dir"]))
		var across := float(h["width"]) / maxf(sine, float(rules["min_sin"]))
		var half := 0.5 * across + float(rules["abut_m"])
		var from := maxf(float(h["arc"]) - half, 0.0)
		var to := minf(float(h["arc"]) + half, total)
		if to - from < 1.0:
			continue
		var last: Dictionary = spans.back() if not spans.is_empty() else {}
		if not last.is_empty() and from <= float(last["to"]) + float(rules["merge_m"]):
			last["to"] = maxf(float(last["to"]), to)
			last["water_y"] = minf(float(last["water_y"]), float(h["water_y"]))
			last["width"] = maxf(float(last["width"]), float(h["width"]))
			continue
		spans.append({"from": from, "to": to, "water_y": h["water_y"], "width": h["width"]})
	return spans


## The point `arc` metres along `line`.
static func point_at(line: PackedVector2Array, arc: float) -> Vector2:
	var run := 0.0
	for i in line.size() - 1:
		var d := line[i].distance_to(line[i + 1])
		if run + d >= arc:
			return line[i].lerp(line[i + 1], 0.0 if d <= 0.0 else (arc - run) / d)
		run += d
	return line[line.size() - 1]


## The deck's height `t` (0..1) of the way from end a to end b: the banks'
## line plus a hump that puts the middle at `crown`.
static func deck_y(ya: float, yb: float, crown: float, t: float) -> float:
	var base := lerpf(ya, yb, t)
	return base + (crown - lerpf(ya, yb, 0.5)) * 4.0 * t * (1.0 - t)


static func _splice(line: PackedVector2Array, spans: Array, height_fn: Callable,
		rules: Dictionary) -> Dictionary:
	var pts := PackedVector2Array()
	var hs := PackedFloat32Array()
	var bridges: Array = []
	var arcs := PackedFloat32Array([0.0])
	for i in range(1, line.size()):
		arcs.append(arcs[i - 1] + line[i - 1].distance_to(line[i]))
	var k := 0
	for s: Dictionary in spans:
		while k < line.size() and arcs[k] < float(s["from"]):
			pts.append(line[k])
			hs.append(NAN)
			k += 1
		var a := point_at(line, s["from"])
		var b := point_at(line, s["to"])
		var water := float(s["water_y"])
		var ga := float(height_fn.call(a))
		var gb := float(height_fn.call(b))
		# a deck end never lies under the water it crosses (the drawn water
		# line can stand over a carved bank)
		var ya := maxf(ga, water + float(rules["end_over_water_m"]))
		var yb := maxf(gb, water + float(rules["end_over_water_m"]))
		var clear := water + float(rules["clear_m"]) + float(rules["clear_per_width"]) * float(s["width"])
		var crown := maxf(maxf(ya, yb), clear) + float(rules["hump_m"])
		var n := maxi(2, ceili(a.distance_to(b) / float(rules["deck_step_m"])))
		for j in n + 1:
			var t := float(j) / float(n)
			pts.append(a.lerp(b, t))
			hs.append(deck_y(ya, yb, crown, t))
		bridges.append({"a": a, "b": b, "ya": ya, "yb": yb, "crown": crown,
			"water_y": water, "width": s["width"], "foot": minf(minf(ga, gb), water) - 2.0})
		while k < line.size() and arcs[k] <= float(s["to"]):
			k += 1
	while k < line.size():
		pts.append(line[k])
		hs.append(NAN)
		k += 1
	return {"line": pts, "heights": hs, "bridges": bridges}


## One mesh for every bridge in `bridges`, `deck_w` metres wide: UV in
## metres over `tile_m` (the stone texture's repeat), normals per face.
static func mesh_arrays(bridges: Array, deck_w: float, rules: Dictionary, tile_m: float) -> Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Dictionary in bridges:
		_bridge(st, b, deck_w, rules, tile_m)
	var arrays := st.commit_to_arrays()
	# With nothing committed SurfaceTool leaves ARRAY_VERTEX null, and `as`
	# on a null prints "Invalid cast": ask the variant, never cast it.
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return []
	var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
	if typeof(verts) != TYPE_PACKED_VECTOR3_ARRAY or (verts as PackedVector3Array).is_empty():
		return []
	return arrays


## The soffit's height (the underside) `t` of the way along one bridge: a
## solid abutment down to the bed over each bank (abut_m), and between them
## arches, each a segmental (parabolic) arch springing at the water, on piers of pier_m;
## never above the deck's underside.
static func soffit_y(b: Dictionary, rules: Dictionary, t: float, span: float) -> float:
	var water := float(b["water_y"])
	var under := deck_y(b["ya"], b["yb"], b["crown"], t) - float(rules["deck_m"])
	var bed := minf(float(b.get("foot", water - 2.0)), under)
	var ta := clampf(float(rules["abut_m"]) / span, 0.0, 0.45)
	if t <= ta or t >= 1.0 - ta:
		return bed
	var water_len := (1.0 - 2.0 * ta) * span
	var n := maxi(1, ceili(water_len / float(rules["arch_max_m"])))
	var cell := (1.0 - 2.0 * ta) / float(n)
	var local := t - ta
	var i := mini(int(local / cell), n - 1)
	var u := (local - float(i) * cell) / cell  # 0..1 across this arch's cell
	var half_pier := 0.5 * float(rules["pier_m"]) / (cell * span)
	var lo := half_pier if i > 0 else 0.0
	var hi := 1.0 - half_pier if i < n - 1 else 1.0
	if u < lo or u > hi:
		return bed
	# a segmental arch: a low parabola off the pier's face, never the
	# vertical springing of a half-ellipse (it drew a dark slab at each bank)
	var x := (u - lo) / maxf(hi - lo, 0.0001) * 2.0 - 1.0
	var spring := minf(water, under)
	var rise := maxf(under - spring - 0.3, 0.0)
	return minf(spring + rise * (1.0 - x * x), under)


static func _bridge(st: SurfaceTool, b: Dictionary, deck_w: float, rules: Dictionary,
		tile_m: float) -> void:
	var a: Vector2 = b["a"]
	var e: Vector2 = b["b"]
	var span := a.distance_to(e)
	if span < 1.0:
		return
	var along := (e - a) / span
	var side := Vector2(-along.y, along.x)
	var hw := 0.5 * deck_w
	var pw := float(rules["parapet_w_m"])
	var ph := float(rules["parapet_h_m"])
	var n := maxi(8, ceili(span / 1.5))
	var ts := PackedFloat32Array()
	for j in n + 1:
		ts.append(float(j) / float(n))
	var top := func(t: float) -> float: return deck_y(b["ya"], b["yb"], b["crown"], t)
	# the parapets die into the banks over the abutments, so an end is never
	# a slab standing on the road
	var ramp := clampf(float(rules["abut_m"]) / span, 0.01, 0.5)
	var under := func(t: float) -> float: return soffit_y(b, rules, t, span)
	var at := func(t: float, off: float, y: float) -> Vector3:
		var p := a.lerp(e, t) + side * off
		return Vector3(p.x, y, p.y)
	var s3 := Vector3(side.x, 0.0, side.y)
	for j in n:
		var t0 := ts[j]
		var t1 := ts[j + 1]
		var u0 := t0 * span / tile_m
		var u1 := t1 * span / tile_m
		var y0t: float = top.call(t0)
		var y1t: float = top.call(t1)
		var y0u: float = under.call(t0)
		var y1u: float = under.call(t1)
		var ph0 := ph * smoothstep(0.0, ramp, minf(t0, 1.0 - t0))
		var ph1 := ph * smoothstep(0.0, ramp, minf(t1, 1.0 - t1))
		for sgn: float in [1.0, -1.0]:
			var nrm := s3 * sgn
			# the outer wall, soffit to parapet top
			_quad(st, nrm,
				at.call(t0, sgn * hw, y0u), at.call(t1, sgn * hw, y1u),
				at.call(t1, sgn * hw, y1t + ph1), at.call(t0, sgn * hw, y0t + ph0),
				Vector2(u0, y0u / tile_m), Vector2(u1, y1u / tile_m),
				Vector2(u1, (y1t + ph1) / tile_m), Vector2(u0, (y0t + ph0) / tile_m))
			# the parapet's inner face and its coping
			var inner := sgn * (hw - pw)
			_quad(st, -nrm,
				at.call(t0, inner, y0t), at.call(t1, inner, y1t),
				at.call(t1, inner, y1t + ph1), at.call(t0, inner, y0t + ph0),
				Vector2(u0, y0t / tile_m), Vector2(u1, y1t / tile_m),
				Vector2(u1, (y1t + ph1) / tile_m), Vector2(u0, (y0t + ph0) / tile_m))
			_quad(st, Vector3.UP,
				at.call(t0, inner, y0t + ph0), at.call(t1, inner, y1t + ph1),
				at.call(t1, sgn * hw, y1t + ph1), at.call(t0, sgn * hw, y0t + ph0),
				Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, pw / tile_m), Vector2(u0, pw / tile_m))
		# the deck between the parapets, and the soffit under the whole width
		_quad(st, Vector3.UP,
			at.call(t0, -(hw - pw), y0t), at.call(t1, -(hw - pw), y1t),
			at.call(t1, hw - pw, y1t), at.call(t0, hw - pw, y0t),
			Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, deck_w / tile_m), Vector2(u0, deck_w / tile_m))
		_quad(st, Vector3.DOWN,
			at.call(t0, -hw, y0u), at.call(t1, -hw, y1u),
			at.call(t1, hw, y1u), at.call(t0, hw, y0u),
			Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, deck_w / tile_m), Vector2(u0, deck_w / tile_m))
	# the two ends, foundations to deck, so a bridge standing proud of a low
	# bank is never an open box
	for t: float in [0.0, 1.0]:
		var yt: float = top.call(t)
		var yu := minf(float(b.get("foot", yt - 3.0)), yt - 0.5)
		var out3 := Vector3(-along.x, 0.0, -along.y) if t == 0.0 else Vector3(along.x, 0.0, along.y)
		_quad(st, out3,
			at.call(t, -hw, yu), at.call(t, hw, yu), at.call(t, hw, yt), at.call(t, -hw, yt),
			Vector2(0.0, yu / tile_m), Vector2(deck_w / tile_m, yu / tile_m),
			Vector2(deck_w / tile_m, yt / tile_m), Vector2(0.0, yt / tile_m))


## One quad, its normal the face's own, turned to the side of `nrm` (a
## soffit rising steeply off a pier faces along the bridge, not down).
static func _quad(st: SurfaceTool, nrm: Vector3, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		uv0: Vector2, uv1: Vector2, uv2: Vector2, uv3: Vector2) -> void:
	var face := (p1 - p0).cross(p3 - p0)
	if face.length_squared() > 1e-8:
		face = face.normalized()
		nrm = face if face.dot(nrm) >= 0.0 else -face
	for pair: Array in [[p0, uv0], [p1, uv1], [p2, uv2], [p0, uv0], [p2, uv2], [p3, uv3]]:
		st.set_normal(nrm)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])
