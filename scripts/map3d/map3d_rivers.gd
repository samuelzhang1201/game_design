class_name Map3DRivers
extends RefCounted
## The 3D map's rivers as ONE ribbon mesh (pure, tested headless). The bake
## (tools/map3d/bake_world.py) carves each river's bed and writes its water
## line, source -> mouth, to rivers.json beside the built scene: per point
## [x_m, z_m, water_y_m, width_m, mouth 0..1] in world metres — a tributary's
## course now ends ON its main river's smoothed centreline (Task 6 fix round
## 3), and mouth is > 0 only on a course that truly ends at the sea. Each
## point becomes two vertices ON the centreline whose NORMAL is the side to
## grow toward — water_river.gdshader widens them to the river's width, or
## to a minimum screen width far away, as border_line.gdshader does for
## borders.

## A river leaving (or entering) a lake reads in the bake as the water line
## jumping tens of metres between two consecutive samples (Task 6 review;
## fix round 1: raised from 2.0, which also fired on ordinary bed rises —
## a river's own tributaries routinely climb a few metres between samples —
## to 10.0, which only the genuine lake jumps in the pack clear). Real
## callers always pass repo.bal("map3d_river_split_rise_m"); this default is
## for tests that don't carry a DataRepository.
const DEFAULT_SPLIT_RISE_M := 10.0
## Fallback for ribbon_arrays' end_fade_m, for the same reason. Real callers
## pass repo.bal("map3d_river_end_fade_m").
const DEFAULT_END_FADE_M := 80.0


## rivers.json text -> [{code, pos: PackedVector3Array, width, mouth:
## PackedFloat32Array, true_mouth: bool}, plus on a river's final strip that
## does not reach the sea joined_end: true and — when another river's
## course lies at its tip — end_fade_m, that river's local half-width (fix
## round 4, _fit_joined_ends)]; [] for anything unreadable.
##
## A course is split into separate strips wherever water_y rises by more
## than split_rise_m between consecutive points — a river leaving or
## entering a lake — so no vertical wall of water is drawn as one strip's
## geometry. Strips stay CONTINUOUS (fix round 1): the point where a rise
## crosses the threshold ends the strip before it AND starts the strip
## after it, so the two share that exact vertex — no point is ever dropped
## and no strip is ever shorter than 2 points, even with two rises back to
## back. `true_mouth` marks the strip that both carries the river's own
## final sample AND actually ends at the sea (the bake's own mouth field is
## > 0 there; fix round 3 — a tributary's course now also ends on its main
## river, with mouth == 0 throughout, and must NOT be read as a sea mouth:
## it has to fade out into the water it joins like any other cut end, not
## stay at full opacity as if it ran into the coast).
static func parse(text: String, split_rise_m: float = DEFAULT_SPLIT_RISE_M) -> Array:
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary) or not (data as Dictionary).has("rivers"):
		return []
	var out: Array = []
	for r: Variant in (data as Dictionary)["rivers"]:
		var pts: Array = (r as Dictionary).get("points", [])
		if pts.size() < 2:
			continue
		var code := String((r as Dictionary).get("code", ""))
		var last_idx := pts.size() - 1
		var start := 0
		var part := 1
		var prev_y := float((pts[0] as Array)[2])
		for i in range(1, pts.size()):
			var y := float((pts[i] as Array)[2])
			# Never split on the very last sample: that would hand the final
			# strip a single point (the true mouth) with nothing before it.
			if i < last_idx and y - prev_y > split_rise_m:
				out.append(_strip(pts, code, part, start, i, false))
				part += 1
				start = i
			prev_y = y
		var reaches_sea := float((pts[last_idx] as Array)[4]) > 0.0
		var last := _strip(pts, code, part, start, last_idx, reaches_sea)
		if not reaches_sea:
			last["joined_end"] = true
		out.append(last)
	_fit_joined_ends(out, data["rivers"])
	return out


## Fix round 4: a JOINED end — the river's own last sample, not a sea mouth
## and not a lake cut — lies ON another river's course (Task 6 fix round 3).
## Faded over the fixed end_fade_m (80 m) it stopped short of the main
## river's bank and left a band of wet dirt; left at full opacity (fix round
## 2) its tip ran on to the main river's centreline and drew a bright
## sliver inside the main water. So it fades over the main river's LOCAL
## half-width instead: full strength at the bank, gone at the centreline.
## Sets "end_fade_m" on each joined strip whose neighbour lies within twice
## that neighbour's width (else the caller's end_fade_m stands), and inserts
## a sample at that distance from the end when none is near, so the water
## is at full strength right AT the bank rather than ramping from the
## previous sample (the bake's samples are ~50-60 m apart).
static func _fit_joined_ends(strips: Array, rivers: Array) -> void:
	# Every river's course in the ground plane with its widths, and a box
	# grown by twice its widest point to skip far rivers cheaply.
	var courses: Array = []
	for r: Variant in rivers:
		var pts: Array = (r as Dictionary).get("points", [])
		var xz := PackedVector2Array()
		var w := PackedFloat32Array()
		var box := Rect2()
		var max_w := 0.0
		for i in pts.size():
			var p: Array = pts[i]
			var q := Vector2(float(p[0]), float(p[1]))
			xz.append(q)
			w.append(float(p[3]))
			max_w = maxf(max_w, float(p[3]))
			box = Rect2(q, Vector2.ZERO) if i == 0 else box.expand(q)
		courses.append({"code": String((r as Dictionary).get("code", "")), "xz": xz,
			"w": w, "box": box.grow(max_w * 2.0)})
	for s: Dictionary in strips:
		if not s.get("joined_end", false):
			continue
		var pos: PackedVector3Array = s["pos"]
		var tip := Vector2(pos[-1].x, pos[-1].z)
		var own := String(s["code"]).get_slice("#", 0)
		var best_d := INF
		var best_w := 0.0
		for c: Dictionary in courses:
			if c["code"] == own or not (c["box"] as Rect2).has_point(tip):
				continue
			var xz: PackedVector2Array = c["xz"]
			var w: PackedFloat32Array = c["w"]
			for i in range(1, xz.size()):
				var seg := xz[i] - xz[i - 1]
				var t := 0.0
				if seg.length_squared() > 0.0000001:
					t = clampf((tip - xz[i - 1]).dot(seg) / seg.length_squared(), 0.0, 1.0)
				var d := tip.distance_to(xz[i - 1] + seg * t)
				if d < best_d:
					best_d = d
					best_w = lerpf(w[i - 1], w[i], t)
		if best_w <= 0.0 or best_d > best_w * 2.0:
			continue
		var fade := best_w * 0.5
		s["end_fade_m"] = fade
		_insert_at_distance_from_end(s, fade)


## Inserts an interpolated sample `dist` metres of arc before the strip's
## end unless a sample already lies within a metre of that spot.
static func _insert_at_distance_from_end(s: Dictionary, dist: float) -> void:
	var pos: PackedVector3Array = s["pos"]
	var width: PackedFloat32Array = s["width"]
	var mouth: PackedFloat32Array = s["mouth"]
	var from_end := 0.0
	for i in range(pos.size() - 1, 0, -1):
		var seg := Vector2(pos[i].x - pos[i - 1].x, pos[i].z - pos[i - 1].z).length()
		if from_end + seg < dist - 1.0:
			from_end += seg
			continue
		if from_end + seg <= dist + 1.0 or dist - from_end <= 1.0:
			return
		var t := (dist - from_end) / seg  # measured back from pos[i]
		pos.insert(i, pos[i].lerp(pos[i - 1], t))
		width.insert(i, lerpf(width[i], width[i - 1], t))
		mouth.insert(i, lerpf(mouth[i], mouth[i - 1], t))
		s["pos"] = pos
		s["width"] = width
		s["mouth"] = mouth
		return


## pts[from_i..to_i] (inclusive, always >= 2 points) as one course dict.
static func _strip(pts: Array, code: String, part: int, from_i: int, to_i: int,
		true_mouth: bool) -> Dictionary:
	var pos := PackedVector3Array()
	var width := PackedFloat32Array()
	var mouth := PackedFloat32Array()
	for i in range(from_i, to_i + 1):
		var p: Array = pts[i]
		pos.append(Vector3(float(p[0]), float(p[2]), float(p[1])))
		width.append(float(p[3]))
		mouth.append(float(p[4]))
	return {"code": code if part == 1 else "%s#%d" % [code, part], "pos": pos,
		"width": width, "mouth": mouth, "true_mouth": true_mouth}


## The unit side at point i, left of the flow — shared by ribbon_arrays (to
## widen the ribbon) and clear_terrain (to sample the ground under each
## edge, not just the centreline).
static func _side_at(pos: PackedVector3Array, i: int) -> Vector2:
	var a := pos[maxi(i - 1, 0)]
	var b := pos[mini(i + 1, pos.size() - 1)]
	var tangent := Vector2(b.x - a.x, b.z - a.z)
	# A zero-length tangent (two coincident points, e.g. a duplicated split
	# vertex sitting next to its own copy) has no direction to widen toward;
	# fall back to a fixed side rather than let normalized() hand back a
	# degenerate zero vector and pinch the ribbon to nothing there.
	var dir := tangent.normalized() if tangent.length_squared() > 0.0000001 else Vector2.RIGHT
	return Vector2(dir.y, -dir.x)


## Raises a course's points so the water clears the REAL ground beneath it
## (fix round 3): the ribbon is built once, flat across its width, straight
## from the bake's own sparse samples, but the ground is not flat — on a
## steep, narrow-sampled tributary the terrain can rise above the water
## plane at one edge even where the centreline clears it comfortably
## (measured on knutshambe, the tributary joined to ashboury by Task 6 fix
## round 3: centre clearance +3.25m at one point, its own right edge -0.38m,
## i.e. the ground there pokes just above the water). Where that happens the
## carved riverbed's own ground material shows through instead of the water
## shader — flat, hard-edged, no ripple, beside a neighbouring stretch that
## clears cleanly and reads as normal water. height_fn(xz) -> ground height;
## `margin` on top of the highest of the centre/left/right samples. Courses
## are returned unchanged when height_fn is invalid (pure tests carry no
## Terrain3D); real callers pass Map3DView._height_at, at build time only.
static func clear_terrain(courses: Array, height_fn: Callable, margin: float) -> Array:
	if not height_fn.is_valid():
		return courses
	var out: Array = []
	for c: Dictionary in courses:
		var pos: PackedVector3Array = (c["pos"] as PackedVector3Array).duplicate()
		var width: PackedFloat32Array = c["width"]
		for i in pos.size():
			var side := _side_at(pos, i)
			var half_w := width[i] * 0.5
			var xz := Vector2(pos[i].x, pos[i].z)
			var centre_h: float = height_fn.call(xz)
			var left_h: float = height_fn.call(xz + side * half_w)
			var right_h: float = height_fn.call(xz - side * half_w)
			var need := maxf(centre_h, maxf(left_h, right_h)) + margin
			if need > pos[i].y:
				pos[i].y = need
		var lifted := c.duplicate()
		lifted["pos"] = pos
		out.append(lifted)
	return out


## Mesh arrays for every course, or [] when there is none. Every vertex
## carries its fade in COLOR.a: 0 at a cut (or the river's true source, which
## fades in the same way — a river starts from nothing) rising to 1 over
## end_fade_m of arc length; the true mouth is the one end that never fades,
## since it runs into the sea rather than being cut (a tributary's joined
## end is neither — fix round 3 — so it fades the same as any other cut,
## sliding under the river it joins instead of ending at full opacity).
## water_river.gdshader multiplies its ALPHA by this.
static func ribbon_arrays(courses: Array, end_fade_m: float = DEFAULT_END_FADE_M) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var index := PackedInt32Array()
	var fade_span := maxf(end_fade_m, 0.001)
	for c: Dictionary in courses:
		# A joined end fades over its main river's half-width (fix round 4).
		var tail_span := maxf(float(c.get("end_fade_m", end_fade_m)), 0.001)
		var pos: PackedVector3Array = c["pos"]
		var width: PackedFloat32Array = c["width"]
		var mouth: PackedFloat32Array = c["mouth"]
		var true_mouth: bool = bool(c.get("true_mouth", false))
		var arcs := PackedFloat32Array()
		arcs.resize(pos.size())
		var total := 0.0
		for i in pos.size():
			if i > 0:
				total += Vector2(pos[i].x - pos[i - 1].x, pos[i].z - pos[i - 1].z).length()
			arcs[i] = total
		for i in pos.size():
			var side2d := _side_at(pos, i)
			var side := Vector3(side2d.x, 0.0, side2d.y)
			var start_fade := clampf(arcs[i] / fade_span, 0.0, 1.0)
			var end_fade := 1.0 if true_mouth else clampf((total - arcs[i]) / tail_span, 0.0, 1.0)
			var fade := minf(start_fade, end_fade)
			var base := verts.size()
			for s: int in [0, 1]:
				verts.append(pos[i])
				normals.append(side * (1.0 if s == 0 else -1.0))
				uv.append(Vector2(float(s), arcs[i]))
				uv2.append(Vector2(width[i], mouth[i]))
				colors.append(Color(1.0, 1.0, 1.0, fade))
			if i > 0:
				index.append_array([base - 2, base - 1, base, base - 1, base + 1, base])
	if verts.is_empty():
		return []
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays
