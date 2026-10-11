extends GutTest
## MapGeometry: pure helpers over the map pack's vector data (border loops,
## and later routes/rivers). Points are serialized in the CSVs as
## "x y|x y|..." in native Azgaar map coordinates.

func test_parse_points_reads_space_and_pipe_separated_pairs() -> void:
	var pts := MapGeometry.parse_points("1 2|3.5 4|720.62 69.16")
	assert_eq(pts.size(), 3)
	assert_eq(pts[0], Vector2(1, 2))
	assert_eq(pts[1], Vector2(3.5, 4))
	assert_almost_eq(pts[2].x, 720.62, 0.001)
	assert_almost_eq(pts[2].y, 69.16, 0.001)

func test_parse_points_of_empty_string_is_empty() -> void:
	assert_eq(MapGeometry.parse_points("").size(), 0)

func test_bounds_wraps_every_point() -> void:
	var r := MapGeometry.bounds(PackedVector2Array([Vector2(1, 2), Vector2(3, -1), Vector2(2, 0)]))
	assert_eq(r.position, Vector2(1, -1))
	assert_eq(r.end, Vector2(3, 2))

func test_bounds_of_nothing_is_empty() -> void:
	assert_eq(MapGeometry.bounds(PackedVector2Array()), Rect2())

## dash_polyline: the dash pattern is measured along the line's own length,
## so it survives a vertex instead of restarting there (draw_dashed_line
## restarts per call, which turned the smoothed borders into mush).

## nice_step: the 1-2-5 ladder a map's scale bar is allowed to land on, so
## the bar reads "200 km", never "187 km".

func test_nice_step_falls_to_the_ladder_below_the_raw_value() -> void:
	assert_almost_eq(MapGeometry.nice_step(1.0), 1.0, 0.0001)
	assert_almost_eq(MapGeometry.nice_step(1.9), 1.0, 0.0001)
	assert_almost_eq(MapGeometry.nice_step(3.7), 2.0, 0.0001)
	assert_almost_eq(MapGeometry.nice_step(9.9), 5.0, 0.0001)
	assert_almost_eq(MapGeometry.nice_step(10.0), 10.0, 0.0001)

func test_nice_step_holds_the_ladder_at_every_magnitude() -> void:
	assert_almost_eq(MapGeometry.nice_step(370.0), 200.0, 0.0001)
	assert_almost_eq(MapGeometry.nice_step(520.0), 500.0, 0.0001)
	assert_almost_eq(MapGeometry.nice_step(1000.0), 1000.0, 0.0001)
	assert_almost_eq(MapGeometry.nice_step(0.7), 0.5, 0.0001)
	assert_almost_eq(MapGeometry.nice_step(0.04), 0.02, 0.0001)

func test_nice_step_of_nothing_is_nothing() -> void:
	assert_eq(MapGeometry.nice_step(0.0), 0.0)
	assert_eq(MapGeometry.nice_step(-5.0), 0.0)

## smooth_open: the same uniform cubic B-spline as smooth_closed, for a line
## with two ends. The ends are clamped by repeating the endpoint, so the
## curve starts and finishes exactly on them — a river must still meet its
## coast after smoothing.

func test_smooth_open_keeps_both_endpoints() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	var out := MapGeometry.smooth_open(line, 1)
	assert_eq(out.size(), 5, "(n + 1) spans of one sample, plus the final point")
	assert_eq(out[0], Vector2(0, 0), "starts on the first point")
	assert_eq(out[out.size() - 1], Vector2(20, 0), "ends on the last")

func test_smooth_open_of_a_straight_line_stays_straight() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	var out := MapGeometry.smooth_open(line, 1)
	for p: Vector2 in out:
		assert_almost_eq(p.y, 0.0, 0.0001, "no wander off the axis")
	# Hand-computed from the B-spline basis at t = 0 over the clamped spans:
	# (p0 + 4p1 + p2) / 6 for each of [0,0,0,10], [0,0,10,20], [0,10,20,20],
	# [10,20,20,20], then the endpoint.
	assert_almost_eq(out[1].x, 10.0 / 6.0, 0.0001)
	assert_almost_eq(out[2].x, 10.0, 0.0001)
	assert_almost_eq(out[3].x, 110.0 / 6.0, 0.0001)

func test_smooth_open_rounds_a_corner_inward() -> void:
	# A right angle: the smoothed line must cut inside the corner, not touch it.
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var out := MapGeometry.smooth_open(line, 4)
	var nearest := INF
	for p: Vector2 in out:
		nearest = minf(nearest, p.distance_to(Vector2(10, 0)))
	assert_gt(nearest, 0.5, "the hard corner is gone")

func test_smooth_open_leaves_a_line_too_short_to_bend_alone() -> void:
	var two := PackedVector2Array([Vector2(0, 0), Vector2(5, 5)])
	assert_eq(MapGeometry.smooth_open(two, 3), two)
	var line := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(2, 0)])
	assert_eq(MapGeometry.smooth_open(line, 0), line, "no samples asked for")

## dash_runs: the same walk as dash_polyline but it hands back the gaps too,
## so a border can be drawn as a chequered ribbon — dark run, light run —
## instead of dash-and-nothing (owner request 2026-09-12, matching the
## alternating frame band of docs/references).

## ribbon: a polyline swollen into a filled band whose half-width varies from
## point to point — what draw_polyline cannot do, and what a drawn river
## needs: a hairline at the source widening to its mouth.

func test_ribbon_offsets_each_point_by_its_own_half_width() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	var tris := MapGeometry.ribbon(line, PackedFloat32Array([1.0, 2.0, 3.0]))
	assert_eq(tris.size(), 12, "two spans, two triangles each, three points each")
	# The band runs along the x axis, so every offset is purely vertical and
	# its size is that point's own half-width.
	var ys: Dictionary = {}
	for p: Vector2 in tris:
		ys["%.0f:%.1f" % [p.x, p.y]] = true
	assert_true(ys.has("0:1.0") and ys.has("0:-1.0"), "the source is 1 either side")
	assert_true(ys.has("20:3.0") and ys.has("20:-3.0"), "the mouth is 3")

func test_ribbon_turns_the_corner_on_the_bisector() -> void:
	# A right angle: the offset at the corner follows the average of the two
	# leg directions, so the band does not pinch or overshoot.
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var tris := MapGeometry.ribbon(line, PackedFloat32Array([1.0, 1.0, 1.0]))
	assert_eq(tris.size(), 12)
	for p: Vector2 in tris:
		assert_lte(p.distance_to(Vector2(10, 0)), 12.0, "nothing flies off at the bend")

func test_ribbon_of_a_mismatched_or_degenerate_line_is_empty() -> void:
	assert_eq(MapGeometry.ribbon(PackedVector2Array([Vector2(0, 0)]),
		PackedFloat32Array([1.0])).size(), 0)
	assert_eq(MapGeometry.ribbon(PackedVector2Array([Vector2(0, 0), Vector2(1, 0)]),
		PackedFloat32Array([1.0])).size(), 0, "one width per point or nothing")

## smooth_closed_through: a Catmull-Rom ring. smooth_closed uses a uniform
## cubic B-spline, which APPROXIMATES — it cuts every corner, so a kingdom's
## border drifted off the province boundary it is supposed to be (owner
## 2026-09-13). Catmull-Rom passes through every control point and is still
## smooth between them: the border hugs the real edge AND stops being angular.

func test_smooth_closed_through_keeps_every_control_point() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var out := MapGeometry.smooth_closed_through(square, 4)
	assert_eq(out.size(), 16, "four spans of four samples")
	for p: Vector2 in square:
		var hit := false
		for q: Vector2 in out:
			if q.distance_to(p) < 0.0001:
				hit = true
		assert_true(hit, "the curve runs through %s" % p)

func test_smooth_closed_through_of_a_degenerate_ring_is_itself() -> void:
	var two := PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
	assert_eq(MapGeometry.smooth_closed_through(two, 4), two)
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	assert_eq(MapGeometry.smooth_closed_through(sq, 0), sq, "no samples asked for")

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
	# Point 1 is at index 8, exactly (the j == 0 sample is forced to p1); the
	# tangent AT a pinned point is exact only in the limit (the reflected
	# neighbour makes p0, p1, p2 collinear, but the OTHER side of the curve
	# still leans on the real p3/p0 one segment away), so a finite step off
	# it is close to the edge, not exactly on it: unpinned this same corner
	# leaves at d.x ~= 0.55, pinned at steps=8 it is ~= 0.05 (10x closer, and
	# it keeps closing as steps grows) — a fixed, generous bound that still
	# catches a broken pin (which regresses toward the unpinned 0.55).
	var d := (out[9] - out[8]).normalized()
	assert_almost_eq(d.x, 0.0, 0.06, "leaves close to due south along 1->2")
	var back := (out[8] - out[7]).normalized()
	assert_almost_eq(back.y, 0.0, 0.06, "arrives close to due east along 0->1")

func test_a_duplicated_last_point_carries_its_pin_into_index_0() -> void:
	# A raw loop often repeats its first point at the end. Pinned only on
	# that trailing copy, the merge must fold the pin onto index 0 before
	# the duplicate is dropped, or the pin is silently lost. Same square as
	# the test above, rotated so the pinned corner (10, 0) sits at index 0
	# via a duplicate at the end instead of index 1.
	var ring := PackedVector2Array([Vector2(10, 0), Vector2(10, 10), Vector2(0, 10), Vector2(0, 0), Vector2(10, 0)])
	var pins := PackedByteArray([0, 0, 0, 0, 1])
	var out := MapGeometry.smooth_closed_through(ring, 8, pins)
	assert_eq(out.size(), 4 * 8, "the duplicated point is dropped")
	var d := (out[1] - out[0]).normalized()
	assert_almost_eq(d.x, 0.0, 0.06, "leaves close to due south along 0->1")
	var back := (out[0] - out[out.size() - 1]).normalized()
	assert_almost_eq(back.y, 0.0, 0.06, "arrives close to due east along 3->0")


## A broken supply line stops short of its column (owner 2026-10-11): an L of
## legs 10 (east) and 4 (south), 14 long. Short by 3: the last leg 4 -> 1, so
## the end is (10, 1). Short by 6: the last leg (4) goes and 2 more of the
## first, so the end is (8, 0). Short by 14 or more: nothing left.
func test_stop_short_takes_the_gap_off_the_end_along_the_line() -> void:
	var l := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 4)])
	assert_eq(MapGeometry.stop_short(l, 3.0), PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 1)]))
	assert_eq(MapGeometry.stop_short(l, 6.0), PackedVector2Array([Vector2(0, 0), Vector2(8, 0)]))
	assert_eq(MapGeometry.stop_short(l, 14.0), PackedVector2Array())
	assert_eq(MapGeometry.stop_short(l, 0.0), l, "no gap, the line as it was")
	assert_eq(MapGeometry.stop_short(PackedVector2Array([Vector2(1, 1)]), 1.0), PackedVector2Array())

## The break's tick: square to the last leg (east), half 2 each way of the end
## (10, 0): (10, 2) and (10, -2).
func test_tick_across_stands_square_to_the_last_leg() -> void:
	var t := MapGeometry.tick_across(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), 2.0)
	assert_eq(t.size(), 2)
	assert_true(t[0].is_equal_approx(Vector2(10, 2)), str(t[0]))
	assert_true(t[1].is_equal_approx(Vector2(10, -2)), str(t[1]))
	assert_eq(MapGeometry.tick_across(PackedVector2Array([Vector2(3, 3), Vector2(3, 3)]), 2.0), PackedVector2Array())
