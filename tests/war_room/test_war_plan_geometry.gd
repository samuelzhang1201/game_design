extends GutTest
## The staff's strokes' shapes (spec 2026-10-07-war-room-annotations-and-
## planning-pieces §2.3): smoothing, the curve through every control point,
## the axis arrow's band and head, the front's teeth, dashes, hits.


func test_simplify_keeps_the_ends_and_drops_collinear_points() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(5, 0.1), Vector2(10, 0), Vector2(10, 10)])
	var out := WarPlanGeometry.simplify(pts, 1.0, 16)
	assert_eq(out, PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]))


func test_simplify_coarsens_until_it_fits_the_cap() -> void:
	var pts := PackedVector2Array()
	for i in 200:
		pts.append(Vector2(i, sin(i * 0.3) * 20.0))
	var out := WarPlanGeometry.simplify(pts, 0.5, 8)
	assert_lte(out.size(), 8)
	assert_eq(out[0], pts[0])
	assert_eq(out[out.size() - 1], pts[pts.size() - 1])


func test_the_curve_passes_every_control_point() -> void:
	var ctrl := PackedVector2Array([Vector2(0, 0), Vector2(40, 30), Vector2(90, 10), Vector2(120, 60)])
	var c := WarPlanGeometry.curve(ctrl, 4.0)
	for p in ctrl:
		var best := INF
		for q in c:
			best = minf(best, q.distance_to(p))
		assert_almost_eq(best, 0.0, 0.001, str(p))
	assert_eq(c[0], ctrl[0])
	assert_eq(c[c.size() - 1], ctrl[ctrl.size() - 1])
	for i in range(1, c.size()):
		assert_lte(c[i - 1].distance_to(c[i]), 6.0, "samples about a step apart")


func test_two_points_make_a_straight_curve() -> void:
	var c := WarPlanGeometry.curve(PackedVector2Array([Vector2(0, 0), Vector2(20, 0)]), 5.0)
	for q in c:
		assert_almost_eq(q.y, 0.0, 0.0001)
	assert_almost_eq(WarPlanGeometry.length(c), 20.0, 0.0001)


func test_the_arrow_head_ends_at_the_last_point_on_the_last_tangent() -> void:
	var c := WarPlanGeometry.curve(PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), 2.0)
	var a := WarPlanGeometry.arrow(c, 4.0, 8.0, 14.0, 20.0)
	var head: PackedVector2Array = a["head"]
	var tip := Vector2(-INF, 0)
	for p in head:
		if p.x > tip.x:
			tip = p
	assert_almost_eq(tip.distance_to(Vector2(100, 0)), 0.0, 0.001, "the tip is the last point")
	var ys: Array = Array(head).map(func(p: Vector2) -> float: return p.y)
	assert_almost_eq(ys.max() - ys.min(), 20.0, 0.001, "the head is head_w across, square to the tangent")
	var band: PackedVector2Array = a["band"]
	var bx: Array = Array(band).map(func(p: Vector2) -> float: return p.x)
	assert_almost_eq(float(bx.max()), 86.0 + 0.0, 2.1, "the band runs to the head's base")
	# the band widens tail -> neck: 4 across at its tail, 8 at its neck
	var near_tail := Array(band).filter(func(p: Vector2) -> bool: return absf(p.x - 2.0) < 1.01 and p.y != 0.0)
	assert_almost_eq(absf(near_tail[0].y), 2.0, 0.2)


func test_a_short_arrow_keeps_a_head_in_proportion() -> void:
	var c := WarPlanGeometry.curve(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), 1.0)
	var a := WarPlanGeometry.arrow(c, 4.0, 8.0, 14.0, 20.0)
	assert_gt((a["band"] as PackedVector2Array).size(), 0, "a band still shows")


func test_teeth_stand_every_so_far_on_the_right_and_flip() -> void:
	var c := WarPlanGeometry.curve(PackedVector2Array([Vector2(0, 0), Vector2(60, 0)]), 1.0)
	var teeth := WarPlanGeometry.teeth(c, 10.0, 4.0, 3.0, 1)
	assert_eq(teeth.size(), 6, "floor(60 / 10)")
	for t: PackedVector2Array in teeth:
		var apex: Vector2 = t[1]
		assert_almost_eq(apex.y, 3.0, 0.001, "y-down: the drawer's right of an eastward line is south")
	var flipped := WarPlanGeometry.teeth(c, 10.0, 4.0, 3.0, -1)
	assert_almost_eq((flipped[0] as PackedVector2Array)[1].y, -3.0, 0.001)


func test_dashes() -> void:
	var c := PackedVector2Array([Vector2(0, 0), Vector2(20, 0)])
	var d := WarPlanGeometry.dashes(c, 5.0, 2.0)
	assert_eq(d.size(), 3, "dashes at 0-5, 7-12, 14-19")
	assert_almost_eq(WarPlanGeometry.length(d[1]), 5.0, 0.001)
	assert_almost_eq((d[1] as PackedVector2Array)[0].x, 7.0, 0.001)


func test_band_is_a_closed_outline_of_its_width() -> void:
	var b := WarPlanGeometry.band(PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), 4.0)
	var ys: Array = Array(b).map(func(p: Vector2) -> float: return p.y)
	assert_almost_eq(ys.max() - ys.min(), 4.0, 0.001)


func test_hits() -> void:
	var c := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	assert_almost_eq(WarPlanGeometry.hit(c, Vector2(5, 3)), 3.0, 0.001)
	assert_almost_eq(WarPlanGeometry.hit(c, Vector2(12, 5)), 2.0, 0.001)
	assert_almost_eq(WarPlanGeometry.ring_hit(Vector2.ZERO, 10.0, Vector2(13, 0)), 3.0, 0.001)


func test_the_curve_is_deterministic() -> void:
	var ctrl := PackedVector2Array([Vector2(0, 0), Vector2(3, 7), Vector2(11, 2)])
	assert_eq(WarPlanGeometry.curve(ctrl, 1.0), WarPlanGeometry.curve(ctrl, 1.0))


func test_clip_to_rect_cuts_at_the_edge() -> void:
	var runs := WarPlanGeometry.clip_to_rect(PackedVector2Array([Vector2(-10, 5), Vector2(10, 5)]), Rect2(0, 0, 20, 20))
	assert_eq(runs.size(), 1)
	assert_eq(runs[0], PackedVector2Array([Vector2(0, 5), Vector2(10, 5)]))


func test_a_road_that_leaves_and_returns_draws_two_runs() -> void:
	var pts := PackedVector2Array([Vector2(5, 5), Vector2(30, 5), Vector2(30, 15), Vector2(5, 15)])
	var runs := WarPlanGeometry.clip_to_rect(pts, Rect2(0, 0, 20, 20))
	assert_eq(runs.size(), 2)
	assert_eq(runs[0], PackedVector2Array([Vector2(5, 5), Vector2(20, 5)]))
	assert_eq(runs[1], PackedVector2Array([Vector2(20, 15), Vector2(5, 15)]))


func test_a_road_wholly_inside_is_one_run_unchanged() -> void:
	var pts := PackedVector2Array([Vector2(1, 1), Vector2(5, 9), Vector2(8, 2)])
	assert_eq(WarPlanGeometry.clip_to_rect(pts, Rect2(0, 0, 20, 20)), [pts])
