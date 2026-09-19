# Borders Without Curls, and a Better Kingdom Border — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the small loops at corners of the kingdom borders and province seams, and replace the thin solid black kingdom border with a realm band + pale halo + warm ink line.

**Architecture:** The loops are made by uniform Catmull-Rom smoothing (`MapGeometry.smooth_closed_through`); switch it to centripetal, pin the tangent at junctions so shared borders draw one curve, chain seams into polylines, and keep the ribbon's side at cusps. The look is three ribbons through the existing `border_line.gdshader`, with a new one-sided ribbon mode and an across-fade.

**Tech Stack:** Godot 4.7 typed GDScript, GUT, spatial shaders (GL Compatibility).

**Spec:** `docs/superpowers/specs/2026-09-19-map3d-border-look-design.md`

## Global Constraints

- Typed GDScript; design values in `data/*.csv` (`balance.csv`, `political_palette.csv`), never hardcoded.
- The smoothed curve must still pass through every (deduplicated) input point.
- The 2D map's calls (`world_map_view.gd:777, 861`) keep working with the default (no pins) signature.
- Tests: single file `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/<path>.gd -gexit`; suite `./run_tests.sh` ("Errors 2" expected). Known pre-existing failure, not yours: `test_ui_rework.gd::test_campaign_opens_with_nameless_background_narration`.
- Stage only the task's files; commit messages end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- Look values: ink `#2A1E16`, halo `#EFE6D2` alpha 0.7 width 3.6 px, ink width 1.8 px, band 9 px alpha 0.55 — starting values the visual review may tune.

---

### Task 1: Centripetal smoothing with junction pins

**Files:**
- Modify: `scripts/engine/map_geometry.gd:221-253` (`smooth_closed_through`)
- Modify: `scripts/engine/map_ownership.gd` (new `outline_pins`, cached with the outlines)
- Modify: `scripts/map3d/map3d_borders.gd:78-93` (`kingdom_lines` passes the pins)
- Test: `tests/engine/test_map_geometry.gd`, `tests/map3d/test_map3d_borders.gd`

**Interfaces:**
- Produces: `MapGeometry.smooth_closed_through(pts: PackedVector2Array, steps: int, pinned := PackedByteArray()) -> PackedVector2Array` (pinned[i] == 1 pins point i; empty = none); `MapOwnership.outline_pins(data, state, kingdom_code) -> Array` of `PackedByteArray`, one per loop of `outline_of`, same order and length.

- [ ] **Step 1: Failing tests** — append to `tests/engine/test_map_geometry.gd`:

```gdscript
## The curls (owner 2026-09-19): a uniform Catmull-Rom overshoots a short
## edge between long ones into a cusp or loop; centripetal cannot.
func _turns_back(pts: PackedVector2Array) -> int:
	var n := pts.size()
	var count := 0
	for i in n:
		var a := (pts[i] - pts[(i - 1 + n) % n])
		var b := (pts[(i + 1) % n] - pts[i])
		if a.length() < 1e-6 or b.length() < 1e-6:
			continue
		if a.normalized().dot(b.normalized()) < cos(deg_to_rad(150.0)):
			count += 1
	return count

func _crossings(pts: PackedVector2Array, window: int) -> int:
	var n := pts.size()
	var count := 0
	for i in n:
		for k in range(2, window):
			var j := (i + k) % n
			if (j + 1) % n == i:
				continue
			if Geometry2D.segment_intersects_segment(pts[i], pts[(i + 1) % n], pts[j], pts[(j + 1) % n]) != null:
				count += 1
	return count

func test_a_short_edge_between_long_ones_makes_no_curl() -> void:
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10.05, 0.02),
		Vector2(10.05, 10), Vector2(0, 10)])
	var out := MapGeometry.smooth_closed_through(ring, 8)
	assert_eq(_turns_back(out), 0)
	assert_eq(_crossings(out, 24), 0)
	for p in ring:
		assert_true(out.has(p), "still through %s" % p)

func test_near_duplicate_points_are_dropped_first() -> void:
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10.0005, 0), Vector2(10, 10), Vector2(0, 10)])
	var out := MapGeometry.smooth_closed_through(ring, 4)
	assert_eq(out.size(), 4 * 4, "the near-duplicate went")

func test_a_pinned_point_leaves_along_its_own_edge() -> void:
	var ring := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var pins := PackedByteArray([0, 1, 0, 0])
	var out := MapGeometry.smooth_closed_through(ring, 8, pins)
	# Point 1 is at index 8; the next sample heads straight toward point 2.
	var d := (out[9] - out[8]).normalized()
	assert_almost_eq(d.x, 0.0, 0.0001, "leaves due south along 1->2")
	var back := (out[8] - out[7]).normalized()
	assert_almost_eq(back.y, 0.0, 0.0001, "arrives due east along 0->1")
```

Append to `tests/map3d/test_map3d_borders.gd`:

```gdscript
## No kingdom ring curls (owner 2026-09-19).
func test_kingdom_lines_do_not_curl() -> void:
	var repo := DataRepository.load_all("res://data")
	var st := GameState.new_campaign(repo, 7)
	for code: String in repo.kingdoms:
		for line: PackedVector2Array in Map3DBorders.kingdom_lines(repo, st, WORLD, code, 150.0):
			var n := line.size()
			for i in range(1, n - 1):
				var a := line[i] - line[i - 1]
				var b := line[i + 1] - line[i]
				if a.length() < 1e-3 or b.length() < 1e-3:
					continue
				assert_gt(a.normalized().dot(b.normalized()), cos(deg_to_rad(150.0)),
					"%s turns back at %s" % [code, line[i]])

## A shared border is ONE curve: each kingdom's copy lies on the other's.
func test_shared_borders_draw_one_curve() -> void:
	var repo := DataRepository.load_all("res://data")
	var st := GameState.new_campaign(repo, 7)
	var steps := int(repo.bal("map_border_smoothing_steps"))
	var all: Array = []
	for code: String in repo.kingdoms:
		var loops := MapOwnership.outline_of(repo, st, code)
		var pins := MapOwnership.outline_pins(repo, st, code)
		for i in loops.size():
			all.append(MapGeometry.smooth_closed_through(loops[i], steps, pins[i]))
	# Every sample of each ring that lies within 3 px of another ring must lie
	# within 0.02 px (1 m) of that ring's own samples.
	var worst := 0.0
	for a in all.size():
		for b in all.size():
			if a == b:
				continue
			var rb: PackedVector2Array = all[b]
			for p: Vector2 in all[a]:
				var d := INF
				for q: Vector2 in rb:
					d = minf(d, p.distance_to(q))
				if d < 3.0:
					worst = maxf(worst, d)
	assert_lt(worst, 0.02)
```

(The pair loop is O(n²) per ring pair; if the test takes more than ~20 s, prefilter by each ring's bounding box with `MapGeometry.bounds` and a grid hash of `rb` at 3 px cells.)

- [ ] **Step 2: Run to verify they fail** (the curl and one-curve tests fail today; the pin test fails for the missing parameter).

- [ ] **Step 3: Implement `smooth_closed_through`**

Replace the function (keep its doc comment, add a paragraph on centripetal and pins):

```gdscript
static func smooth_closed_through(pts: PackedVector2Array, steps: int,
		pinned := PackedByteArray()) -> PackedVector2Array:
	# Drop near-duplicates first (a 0.0005 px Voronoi edge would make a knot
	# of zero length), carrying each kept point's pin.
	var p := PackedVector2Array()
	var pin := PackedByteArray()
	for i in pts.size():
		if p.size() > 0 and pts[i].distance_to(p[p.size() - 1]) < 1e-3:
			if i < pinned.size() and pinned[i] == 1:
				pin[pin.size() - 1] = 1
			continue
		p.append(pts[i])
		pin.append(1 if i < pinned.size() and pinned[i] == 1 else 0)
	if p.size() > 1 and p[0].distance_to(p[p.size() - 1]) < 1e-3:
		p.remove_at(p.size() - 1)
		pin.remove_at(pin.size() - 1)
	var n := p.size()
	if n < 3 or steps < 1:
		return p
	var out := PackedVector2Array()
	out.resize(n * steps)
	var k := 0
	for i in n:
		var p1: Vector2 = p[i]
		var p2: Vector2 = p[(i + 1) % n]
		# A pinned end reflects its own segment, so the curve leaves (or
		# reaches) a junction along the edge itself and both kingdoms that
		# share the edge draw the same curve.
		var p0: Vector2 = 2.0 * p1 - p2 if pin[i] == 1 else p[(i - 1 + n) % n]
		var p3: Vector2 = 2.0 * p2 - p1 if pin[(i + 1) % n] == 1 else p[(i + 2) % n]
		# Centripetal knots (alpha 0.5, Barry-Goldman): a short edge between
		# long ones can neither cusp nor loop (the uniform form made 108 curls
		# on the default pack, owner 2026-09-19).
		var t1 := maxf(sqrt(p0.distance_to(p1)), 1e-4)
		var t2 := t1 + maxf(sqrt(p1.distance_to(p2)), 1e-4)
		var t3 := t2 + maxf(sqrt(p2.distance_to(p3)), 1e-4)
		for j in steps:
			var t := lerpf(t1, t2, float(j) / float(steps))
			var a1 := p0.lerp(p1, t / t1)
			var a2 := p1.lerp(p2, (t - t1) / (t2 - t1))
			var a3 := p2.lerp(p3, (t - t2) / (t3 - t2))
			var b1 := a1.lerp(a2, t / t2)
			var b2 := a2.lerp(a3, (t - t1) / (t3 - t1))
			out[k] = b1.lerp(b2, (t - t1) / (t2 - t1))
			k += 1
	return out
```

Note: at j == 0, t == t1 and the formula yields exactly p1 (check `test_smooth_closed_through_keeps_every_control_point` still passes; if floating error breaks `out.has(p)`, set `out[k] = p1` when `j == 0`).

- [ ] **Step 4: Implement `MapOwnership.outline_pins`**

A vertex is a JUNCTION when the set of kingdoms whose live outline passes through it differs between its two ring neighbours, or when three or more kingdoms meet at it:

```gdscript
static var _pin_cache: Dictionary = {}

## Per loop of outline_of, 1 where the ring meets a junction: three or more
## kingdoms meet there, or the kingdoms along the ring change there (a border
## reaching the coast, or a third realm). Pinning these makes both kingdoms
## that share an edge smooth it the same way (MapGeometry.smooth_closed_through).
static func outline_pins(data: DataRepository, state: GameState, kingdom_code: String) -> Array:
	_refresh_caches(state)
	if _pin_cache.has(kingdom_code):
		return _pin_cache[kingdom_code]
	var owners := {}  # _key(point) -> {kingdom: true}
	for code: String in data.kingdoms:
		for loop: PackedVector2Array in outline_of(data, state, code):
			for pt in loop:
				var key := _key(pt)
				if not owners.has(key):
					owners[key] = {}
				owners[key][code] = true
	var out: Array = []
	for loop: PackedVector2Array in outline_of(data, state, kingdom_code):
		var n := loop.size()
		var pins := PackedByteArray()
		pins.resize(n)
		for i in n:
			var here: Dictionary = owners.get(_key(loop[i]), {})
			var before: Dictionary = owners.get(_key(loop[(i - 1 + n) % n]), {})
			var after: Dictionary = owners.get(_key(loop[(i + 1) % n]), {})
			var edge_in := _shared(here, before)
			var edge_out := _shared(here, after)
			pins[i] = 1 if here.size() >= 3 or edge_in != edge_out else 0
		out.append(pins)
	_pin_cache[kingdom_code] = out
	return out


## The kingdoms two neighbouring points of a ring have in common, sorted.
static func _shared(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in a:
		if b.has(k):
			out.append(k)
	out.sort()
	return out
```

Clear `_pin_cache` in `_refresh_caches` beside `_outline_cache` and in `invalidate()`. (Read `_key` at line 259 — it snaps a point to a grid; use it as is.)

- [ ] **Step 5: `kingdom_lines` passes the pins**

```gdscript
	var loops := MapOwnership.outline_of(repo, state, kingdom_code)
	var pins := MapOwnership.outline_pins(repo, state, kingdom_code)
	for li in loops.size():
		var loop: PackedVector2Array = loops[li]
		if loop.size() < 3:
			continue
		var ring := MapGeometry.smooth_closed_through(loop, steps, pins[li])
```

(and the rest as before). Also pass pins in `WorldMapView` at line 777 if the loop there comes from `outline_of` with an index at hand; if not, leave it — the centripetal change alone fixes its curls.

- [ ] **Step 6: Run** `test_map_geometry.gd`, `test_map3d_borders.gd`, `tests/engine/test_map_ownership.gd` (if present), `tests/ui/test_world_map_view.gd`; then `./run_tests.sh`.

- [ ] **Step 7: Commit** `fix(map): borders without curls — centripetal smoothing, one curve per shared border`

---

### Task 2: Seams as chains, and a ribbon that keeps its side

**Files:**
- Modify: `scripts/map3d/map3d_borders.gd` (`seam_lines`, `_side`)
- Test: `tests/map3d/test_map3d_borders.gd`

**Interfaces:**
- Produces: `Map3DBorders.chain_segments(segments: Array) -> Array` (pure: two-point `PackedVector2Array` segments in, polylines out, joined through points shared by exactly two segments, in a deterministic order: start from the lowest-index unused segment, walk forward then backward).

- [ ] **Step 1: Failing tests**

```gdscript
func test_segments_chain_through_their_joints() -> void:
	var segs := [PackedVector2Array([Vector2(0, 0), Vector2(1, 0)]),
		PackedVector2Array([Vector2(2, 0), Vector2(1, 0)]),
		PackedVector2Array([Vector2(2, 0), Vector2(3, 1)]),
		PackedVector2Array([Vector2(9, 9), Vector2(8, 8)])]
	var chains := Map3DBorders.chain_segments(segs)
	assert_eq(chains.size(), 2)
	assert_eq(Array(chains[0]), [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 1)])

func test_a_three_way_joint_ends_the_chains() -> void:
	var segs := [PackedVector2Array([Vector2(0, 0), Vector2(1, 0)]),
		PackedVector2Array([Vector2(1, 0), Vector2(2, 0)]),
		PackedVector2Array([Vector2(1, 0), Vector2(1, 1)])]
	assert_eq(Map3DBorders.chain_segments(segs).size(), 3)

func test_seam_lines_are_fewer_chains_than_segments() -> void:
	var repo := DataRepository.load_all("res://data")
	var st := GameState.new_campaign(repo, 7)
	var segments := 0
	for code: String in repo.kingdoms:
		segments += MapOwnership.seams_of(repo, st, code).size()
	var lines := Map3DBorders.seam_lines(repo, st, WORLD, 150.0)
	assert_lt(lines.size(), segments)

func test_a_cusp_keeps_the_ribbons_side() -> void:
	# Out and straight back: the two directions cancel at the tip.
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(0, 0.01)])
	var sides: PackedVector3Array = Map3DBorders.ribbon_arrays([line],
		func(_xz: Vector2) -> float: return 0.0)[Mesh.ARRAY_NORMAL]
	assert_gt(sides[0].dot(sides[2]), 0.0, "the tip keeps the first point's side")
```

Update `test_seam_lines_cover_every_kingdoms_seams` (line 66) if it counts one line per segment: it should now check that every seam segment's two ends lie on some chain (a point of the resampled chains within 1 m of each end).

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

```gdscript
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
```

`seam_lines` becomes: collect every kingdom's `seams_of` into one array per kingdom, `chain_segments` it, then convert to world and resample each chain.

`_side` — carry the previous side: change `ribbon_arrays` to track `var prev_side := Vector2.ZERO` per line and call `_side(line, i, prev_side)`:

```gdscript
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
```

- [ ] **Step 4: Run** `test_map3d_borders.gd`, then `./run_tests.sh`.

- [ ] **Step 5: Commit** `fix(map3d): seams as chains; the ribbon keeps its side at a cusp`

---

### Task 3: The kingdom border's look — realm band, halo, warm ink

**Files:**
- Modify: `scripts/map3d/map3d_borders.gd` (`ribbon_arrays` gains `one_sided`; `kingdom_bands` producing inward rings per kingdom)
- Modify: `scripts/map3d/border_line.gdshader` (`fade_across`)
- Modify: `scripts/map3d/map3d_view.gd` (~line 828-838: three ribbons; `_set_lines` gains a `one_sided`/`fade_across` pass-through)
- Modify: `data/balance.csv`, `data/political_palette.csv`
- Test: `tests/map3d/test_map3d_borders.gd`, `tests/map3d/test_map3d_view.gd` (the view builds `Kingdoms`, `KingdomHalo`, `KingdomBand` nodes)

**Interfaces:**
- Produces: `Map3DBorders.ribbon_arrays(lines, height_fn, heights := [], one_sided := false)` — one-sided: the line's vertex keeps offset 0 (NORMAL zero, UV.y 0) and the other carries `2 × side` (UV.y 1), so the shader's `0.5 × width` puts it a full width off the line; `Map3DBorders.inward(line: PackedVector2Array) -> PackedVector2Array` returns the ring oriented so the LEFT-hand side of `_side` points inside (reverse it when its signed area says otherwise — check which sign `_side`'s `(-d.y, d.x)` gives in XZ and pin it by test).

- [ ] **Step 1: Failing tests**

```gdscript
func test_a_one_sided_ribbon_keeps_the_line_and_reaches_one_way() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var arrays := Map3DBorders.ribbon_arrays([line], func(_xz: Vector2) -> float: return 0.0, [], true)
	var sides: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(sides[0], Vector3.ZERO, "the line's own vertex stays on it")
	assert_almost_eq(sides[1].length(), 2.0, 0.0001, "the other a full width off")

func test_inward_bands_reach_inside_the_ring() -> void:
	# A square ring, either winding: the band's side points to the centre.
	for ring in [PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10), Vector2(0, 0)]),
			PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(10, 10), Vector2(10, 0), Vector2(0, 0)])]:
		var r := Map3DBorders.inward(ring)
		var sides: PackedVector3Array = Map3DBorders.ribbon_arrays([r],
			func(_xz: Vector2) -> float: return 0.0, [], true)[Mesh.ARRAY_NORMAL]
		var p := Vector2(r[1].x, r[1].y)  # a corner
		var s := Vector2(sides[3].x, sides[3].z)
		assert_lt((p + s).distance_to(Vector2(5, 5)), p.distance_to(Vector2(5, 5)))
```

In the view test (read `test_map3d_view.gd` for how it builds a view on the fixture): after activation, `KingdomBand`, `KingdomHalo` and `Kingdoms` exist under the lines node, and `KingdomBand`'s material has `fade_across` 1.

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Shader** — add `uniform float fade_across = 0.0;` and at the end of `fragment()`:

```glsl
	if (fade_across > 0.0) {
		ALPHA *= 1.0 - fade_across * UV.y;
	}
```

Update the header comment (one-sided bands fade inward).

- [ ] **Step 4: `ribbon_arrays` one-sided and `inward`**

In the per-point loop, when `one_sided`: first vertex `sides.append(Vector3.ZERO)`, second `sides.append(Vector3(side.x, 0, side.y) * 2.0)`; UVs unchanged (0 and 1). `inward`: compute the signed area (shoelace) of the ring; return it as is or reversed so `_side`'s left-hand normal points inside, whichever the test pins.

- [ ] **Step 5: The view** — replace the kingdom block (~828-834) with, per kingdom, its rings once (`Map3DBorders.kingdom_lines`), then:

```gdscript
	# The kingdom border (owner 2026-09-19, spec 2026-09-19-map3d-border-look):
	# a band in the realm's own colour inside each outline, a pale halo, and
	# the warm ink line over it.
	var rings: Array = []
	var bands: Dictionary = {}  # colour -> inward rings
	for code: String in _repo.kingdoms:
		var own := Map3DBorders.kingdom_lines(_repo, st, _meta, code, step)
		rings.append_array(own)
		var c := MapPalette.color_of(_repo, st, code)
		if not bands.has(c):
			bands[c] = []
		for r: PackedVector2Array in own:
			(bands[c] as Array).append(Map3DBorders.inward(r))
```

Each band colour is its own `_set_lines("KingdomBand_%d" % i, ...)` node with `one_sided = true`, `fade_across = 1.0`, colour alpha `map3d_border_band_alpha`, width `map3d_border_band_px`, priority `PRIORITY_KINGDOMS - 2`; the halo `_set_lines("KingdomHalo", rings, halo, halo, "map3d_border_halo_px", "", "", PRIORITY_KINGDOMS - 1, map3d_border_halo_soft)`; the ink as before. (Check `MapPalette.color_of`'s real signature; realm colours number ~20, so ~20 band nodes — or, better, ONE band mesh with the colour as a vertex COLOR: add `ARRAY_COLOR` to `ribbon_arrays` via an optional `colours: Array` (one `Color` per line) and read `COLOR` in the shader when a `use_vertex_colour` uniform is set. Do the one-mesh version.) Old `KingdomBand*` nodes must be removed on rebuild like the others. Check the priority constants' values so the band sits under the seams, the halo under the ink, and the hover/selection over all.

Data — `balance.csv`:

```csv
map3d_border_band_px,9,"3D MAP borders (owner 2026-09-19, spec 2026-09-19-map3d-border-look): the realm band inside each kingdom's outline, screen px — the kingdom's own colour, fading inward"
map3d_border_band_alpha,0.55,"3D MAP borders: the realm band's opacity at the line"
map3d_border_halo_px,3.6,"3D MAP borders: the pale halo under the ink line, screen px"
map3d_border_halo_alpha,0.7,"3D MAP borders: the halo's opacity"
map3d_border_halo_soft,0.6,"3D MAP borders: the halo's soft edge (border_line.gdshader edge_soft)"
```

and set `map3d_border_width_px` to 1.8 (update its note: the ink over a halo and a realm band, 2026-09-19). `political_palette.csv`: `map3d_border` → `#2A1E16` (note updated), add `map3d_border_halo,#EFE6D2`.

- [ ] **Step 6: Run** the map3d tests, then `./run_tests.sh`.

- [ ] **Step 7: Visual review** — follow `.claude/skills/visual-review/SKILL.md`: shoot the 3D map far / mid / near (`tools/snapshot_screen.gd`, see its header for the 3D flags; the investigator found `--at3d` rendered 2D in one environment — check `--map2d` is NOT set and a built scene exists under `assets/map3d/<pack>/world.tscn`; if no built scene exists, record that the visual check could not run). Compare with the previous look, bracket band alpha/width, get an independent critic's read, tune by data only. Run `tools/map3d/bench.gd` — within its 8 ms budget.

- [ ] **Step 8: Commit** `feat(map3d): the kingdom border — realm band, halo and warm ink`; update CLAUDE.md's Borders sentence (thin solid black → band + halo + warm ink, centripetal smoothing, pinned junctions, chained seams) in the same commit, and add a ruling line to `.claude/skills/visual-review/taste.md` only if the review settled something worth keeping.
