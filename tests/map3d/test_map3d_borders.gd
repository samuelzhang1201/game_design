extends GutTest
## Map3DBorders: the 3D map's kingdom borders and province seams, from the
## same live outlines the 2D map draws (MapOwnership), laid on the ground as
## ribbons the border shader widens to a constant screen width.

const WORLD := {"m_per_px": 50.0, "pack_origin": [0.0, 0.0], "pack_px": [2560, 929]}


func test_a_ribbon_is_two_vertices_a_point_with_opposite_sides() -> void:
	# An L: east 10 m, then south 10 m, on ground at y = 7.
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var arrays := Map3DBorders.ribbon_arrays([line], func(_xz: Vector2) -> float: return 7.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var sides: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(verts.size(), 6, "two per point")
	assert_eq(verts[0], Vector3(0, 7, 0))
	assert_eq(verts[1], Vector3(0, 7, 0))
	assert_eq(idx.size(), 12, "two triangles per segment")
	# Heading east, the side is north/south; the pair points opposite ways.
	assert_almost_eq(absf(sides[0].z), 1.0, 0.0001)
	assert_almost_eq(sides[0].x, 0.0, 0.0001)
	assert_eq(sides[1], -sides[0])
	# The corner's side is the mitre of east and south, still unit-length.
	assert_almost_eq(sides[2].length(), 1.0, 0.0001)
	assert_almost_eq(absf(sides[2].x), absf(sides[2].z), 0.0001)
	# u is the arc length along the line, v the side.
	assert_almost_eq(uvs[4].x, 20.0, 0.0001)
	assert_eq(uvs[0].y, 0.0)
	assert_eq(uvs[1].y, 1.0)


func test_lines_are_separate_strips() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(5, 0)])
	var b := PackedVector2Array([Vector2(0, 9), Vector2(5, 9)])
	var arrays := Map3DBorders.ribbon_arrays([a, b], func(_xz: Vector2) -> float: return 0.0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(idx.size(), 12, "one segment each, none joining them")
	for i in range(6, 12):
		assert_true(idx[i] >= 4, "the second strip only indexes its own vertices")


func test_an_empty_set_makes_no_arrays() -> void:
	assert_true(Map3DBorders.ribbon_arrays([], func(_xz: Vector2) -> float: return 0.0).is_empty())


func test_kingdom_lines_follow_the_live_outline_in_world_metres() -> void:
	Game.start_campaign(42)
	var code := Game.data.resolve_realm("player_realm")
	var lines: Array = Map3DBorders.kingdom_lines(Game.data, Game.state, WORLD, code, 100.0)
	var loops: Array = MapOwnership.outline_of(Game.data, Game.state, code)
	assert_eq(lines.size(), loops.size(), "one line per ring")
	var ring: PackedVector2Array = lines[0]
	assert_eq(ring[0], ring[ring.size() - 1], "a ring is closed")
	for i in range(1, ring.size()):
		assert_true(ring[i - 1].distance_to(ring[i]) <= 100.0 + 0.001, "resampled to the step")
	# It lies on the pack outline scaled to metres (origin 0, 50 m per px).
	var first: PackedVector2Array = loops[0]
	var near := INF
	for p in ring:
		near = minf(near, p.distance_to(first[0] * 50.0))
	assert_lt(near, 1.0, "passes through the outline's own corner")


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


func test_seam_lines_cover_every_kingdoms_seams() -> void:
	Game.start_campaign(42)
	var lines := Map3DBorders.seam_lines(Game.data, Game.state, WORLD, 100.0)
	var m_per_px: float = WORLD["m_per_px"]
	for code: String in Game.data.kingdoms:
		for seg: PackedVector2Array in MapOwnership.seams_of(Game.data, Game.state, code):
			for end: Vector2 in seg:
				var target := end * m_per_px
				var near := INF
				for line: PackedVector2Array in lines:
					for p: Vector2 in line:
						near = minf(near, p.distance_to(target))
				assert_lt(near, 1.0, "%s's seam end %s lies on some chain" % [code, end])


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

## A shared border is ONE curve: each kingdom's copy of a shared
## kingdom-kingdom edge lies on the other's, once both sides are pinned and
## smoothed (MapOwnership.outline_pins).
##
## A blind "nearest point anywhere on the other ring" scan (the brief's first
## draft) ALSO flags ~150 points on the default pack that sit close to a
## properly-pinned junction but belong to a short, genuinely DIFFERENT edge
## leaving it in another direction — proximity to the junction, not a shared
## edge. The true matches are a clean, separate population: 5,200 pairs under
## 0.02 px, then a gap with NOTHING between 0.02 and 0.1 px before the ~150
## junction-adjacent false positives start (0.1 px up to the 3 px scan
## radius). So this matches the ACTUAL shared raw edge between two kingdoms'
## outlines (the same edge-key walk `MapOwnership._merge_loops` and the
## probe's own divergence check use) and compares that edge's two smoothed
## copies directly — 323 shared kingdom-kingdom edges on the default pack.
func test_shared_borders_draw_one_curve() -> void:
	var repo := DataRepository.load_all("res://data")
	var st := GameState.new_campaign(repo, 7)
	var steps := int(repo.bal("map_border_smoothing_steps"))
	# edge key (quantised endpoints, smaller first) -> Array of
	# {code, seg}: that edge's `steps + 1` smoothed points, oriented so the
	# edge's own smaller-endpoint-first direction always reads the same way
	# regardless of which kingdom's ring walked it forward or backward.
	var copies: Dictionary = {}
	for code: String in repo.kingdoms:
		var loops := MapOwnership.outline_of(repo, st, code)
		var pins := MapOwnership.outline_pins(repo, st, code)
		for li in loops.size():
			var loop: PackedVector2Array = loops[li]
			if loop.size() < 3:
				continue
			var curve := MapGeometry.smooth_closed_through(loop, steps, pins[li])
			var n := loop.size()
			for i in n:
				var a := loop[i]
				var b := loop[(i + 1) % n]
				var ak := Vector2i(roundi(a.x * 100.0), roundi(a.y * 100.0))
				var bk := Vector2i(roundi(b.x * 100.0), roundi(b.y * 100.0))
				if ak == bk:
					continue
				var fwd := ak.x < bk.x or (ak.x == bk.x and ak.y <= bk.y)
				var key: Array = [ak, bk] if fwd else [bk, ak]
				var seg := PackedVector2Array()
				for j in steps + 1:
					seg.append(curve[(i * steps + j) % curve.size()])
				if not fwd:
					seg.reverse()
				if not copies.has(key):
					copies[key] = []
				(copies[key] as Array).append({"code": code, "seg": seg})
	var worst := 0.0
	var checked := 0
	for key in copies:
		var c: Array = copies[key]
		if c.size() < 2:
			continue
		for oi in range(1, c.size()):
			if c[0]["code"] == c[oi]["code"]:
				continue
			var sa: PackedVector2Array = c[0]["seg"]
			var sb: PackedVector2Array = c[oi]["seg"]
			checked += 1
			for j in steps + 1:
				worst = maxf(worst, sa[j].distance_to(sb[j]))
	assert_gt(checked, 0, "found shared kingdom-kingdom edges to check")
	assert_lt(worst, 0.02)


## A one-sided ribbon (the realm band, spec 2026-09-19-map3d-border-look):
## both vertices carry the SAME unit side and UV.y says which is which — the
## line's own at 0 stays on the line, the other at 1 is pushed a full width
## one way by border_line.gdshader's one_sided. Not NORMAL's length: Godot
## stores normals octahedrally, so a zero or a doubled normal comes back unit
## (the round trip below pins it).
func test_a_one_sided_ribbon_keeps_the_line_and_reaches_one_way() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var arrays := Map3DBorders.ribbon_arrays([line], func(_xz: Vector2) -> float: return 0.0, [], true)
	var sides: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	assert_eq(sides[0], sides[1], "both vertices reach the same way")
	assert_almost_eq(sides[1].length(), 1.0, 0.0001)
	assert_eq(uvs[0].y, 0.0, "the line's own vertex")
	assert_eq(uvs[1].y, 1.0, "the far one")
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var back: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	assert_almost_eq(back[1].dot(sides[1]), 1.0, 0.001, "the side survives the mesh's encoding")


func test_inward_bands_reach_inside_the_ring() -> void:
	# A square ring, either winding: the band's side points to the centre.
	for ring: PackedVector2Array in [
			PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10), Vector2(0, 0)]),
			PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(10, 10), Vector2(10, 0), Vector2(0, 0)])]:
		var r := Map3DBorders.inward(ring)
		assert_eq(r.size(), ring.size())
		var sides: PackedVector3Array = Map3DBorders.ribbon_arrays([r],
			func(_xz: Vector2) -> float: return 0.0, [], true)[Mesh.ARRAY_NORMAL]
		for i in [1, 2, 3]:
			var p := r[i]
			var s := Vector2(sides[i * 2 + 1].x, sides[i * 2 + 1].z)
			assert_lt((p + s).distance_to(Vector2(5, 5)), p.distance_to(Vector2(5, 5)),
				"corner %d reaches inside" % i)


## One band mesh for every kingdom: a Color per line goes on both its
## vertices (ARRAY_COLOR), read by the shader under use_vertex_colour.
func test_line_colours_go_on_their_vertices() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(5, 0)])
	var b := PackedVector2Array([Vector2(0, 9), Vector2(5, 9)])
	var arrays := Map3DBorders.ribbon_arrays([a, b], func(_xz: Vector2) -> float: return 0.0,
		[], true, [Color.RED, Color.BLUE])
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(cols.size(), 8)
	assert_eq(cols[0], Color.RED)
	assert_eq(cols[3], Color.RED)
	assert_eq(cols[4], Color.BLUE)
	assert_null(Map3DBorders.ribbon_arrays([a], func(_xz: Vector2) -> float: return 0.0)[Mesh.ARRAY_COLOR],
		"no colours asked, none written")
